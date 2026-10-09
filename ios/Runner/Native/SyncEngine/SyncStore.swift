import Foundation

/// The on-device side of sync: the mirrored files and the per-account sync
/// state. Laid out under one base directory (Application Support, which is
/// also where Dart's `SyncService.baseDirectory()` looks for the mirror):
///
///     <base>/sync/<accountId>/...          the mirrored files
///     <base>/sync-state/<accountId>/*.json  state, root markers, missing roots
///
/// Plain JSON files rather than `UserDefaults`: the state map grows with the
/// number of synced files. Not thread-safe by itself - the sync runner holds
/// one lock around anything that reads-then-rewrites it (see `AsyncMutex`).
final class SyncStore {
  /// Bumped whenever a walk starts doing something new (e.g. mirroring empty
  /// folders) so markers recorded by an older version - which would make the
  /// next run skip the walk - are ignored once. Same value as Android.
  static let rootsVersion = 2

  static let shared = SyncStore(base: defaultBase)

  static var defaultBase: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  }

  let base: URL
  private let fileManager = FileManager.default

  init(base: URL) {
    self.base = base
  }

  // MARK: - Locations

  /// The account's mirror folder, created on demand. Marked excluded from
  /// iCloud/device backups: it's a re-downloadable copy of server data.
  func syncRoot(accountId: String) -> URL {
    let top = base.appendingPathComponent("sync", isDirectory: true)
    let root = top.appendingPathComponent(accountId, isDirectory: true)
    try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var topMutable = top
    try? topMutable.setResourceValues(values)
    return root
  }

  private func stateDirectory(accountId: String) -> URL {
    let dir = base.appendingPathComponent("sync-state", isDirectory: true)
      .appendingPathComponent(accountId, isDirectory: true)
    try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func file(_ accountId: String, _ name: String) -> URL {
    stateDirectory(accountId: accountId).appendingPathComponent(name)
  }

  // MARK: - Per-file state

  /// The recorded baseline - empty if nothing has been recorded yet, and
  /// *throws* if there is a file that can't be read or decoded (see
  /// `SyncStateUnreadable`).
  func loadState(accountId: String) throws -> [String: SyncFileState] {
    let url = file(accountId, "state.json")
    guard fileManager.fileExists(atPath: url.path) else { return [:] }
    do {
      return try JSONDecoder().decode([String: SyncFileState].self, from: Data(contentsOf: url))
    } catch {
      throw SyncStateUnreadable(accountId: accountId)
    }
  }

  /// False if the state couldn't be written - callers must not then record
  /// anything that assumes it was.
  @discardableResult
  func saveState(accountId: String, _ state: [String: SyncFileState]) -> Bool {
    write(state, to: file(accountId, "state.json"))
  }

  // MARK: - Root markers

  private struct MarkersFile: Codable {
    let version: Int
    let markers: [String: SyncRootMarker]
  }

  func loadRootMarkers(accountId: String) -> [String: SyncRootMarker] {
    guard let stored = read(MarkersFile.self, from: file(accountId, "roots.json")),
      stored.version == Self.rootsVersion
    else { return [:] }
    return stored.markers
  }

  @discardableResult
  func saveRootMarkers(accountId: String, _ markers: [String: SyncRootMarker]) -> Bool {
    write(MarkersFile(version: Self.rootsVersion, markers: markers), to: file(accountId, "roots.json"))
  }

  // MARK: - Roots the server says are gone

  func loadMissingRoots(accountId: String) -> Set<String> {
    Set(read([String].self, from: file(accountId, "missing.json")) ?? [])
  }

  func setRootMissing(accountId: String, path: String, missing: Bool) {
    var current = loadMissingRoots(accountId: accountId)
    let changed = missing ? current.insert(path).inserted : (current.remove(path) != nil)
    if changed { _ = write(Array(current).sorted(), to: file(accountId, "missing.json")) }
  }

  func removeAccountData(accountId: String) throws {
    for directory in ["sync", "sync-state"] {
      let url = base.appendingPathComponent(directory).appendingPathComponent(accountId)
      if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }
  }

  // MARK: - Removing a path's mirror

  /// Deletes [path]'s local mirror (a file, or a whole folder's worth) and
  /// forgets its entries - called when the user turns sync off for that path.
  /// Without clearing the state too, a later re-add would see the (now
  /// missing) local file as "deleted, server unchanged" and not pull it back.
  func removeLocalSync(accountId: String, path: String) {
    var cleanPath = path.trimmingCharacters(in: .whitespaces)
    if cleanPath.hasPrefix("/") { cleanPath.removeFirst() }
    while cleanPath.hasSuffix("/") { cleanPath.removeLast() }
    let prefix = cleanPath.isEmpty ? "" : cleanPath + "/"

    // An unreadable baseline is left alone rather than overwritten with a
    // partial one; the next run reports it and does nothing.
    if var state = try? loadState(accountId: accountId) {
      // The sync root itself ("/") covers every recorded file.
      for (fileId, entry) in state
      where cleanPath.isEmpty || entry.relPath == cleanPath || entry.relPath.hasPrefix(prefix) {
        state[fileId] = nil
      }
      saveState(accountId: accountId, state)
    }

    setRootMissing(accountId: accountId, path: "/" + cleanPath, missing: false)
    setRootMissing(accountId: accountId, path: cleanPath, missing: false)

    // A root marker for this path (or an ancestor/descendant that also covers
    // some of what was just deleted) would make the next background pass
    // think nothing changed and skip re-downloading.
    let removedPath = "/" + cleanPath
    var markers = loadRootMarkers(accountId: accountId)
    let stale = markers.keys.filter { key in
      var k = key
      while k.hasSuffix("/") { k.removeLast() }
      return k.isEmpty || removedPath == "/" || k == removedPath || k.hasPrefix(removedPath + "/")
        || removedPath.hasPrefix(k + "/")
    }
    if !stale.isEmpty {
      stale.forEach { markers[$0] = nil }
      saveRootMarkers(accountId: accountId, markers)
    }

    let root = syncRoot(accountId: accountId)
    let target = cleanPath.isEmpty ? root : root.appendingPathComponent(cleanPath)
    if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
    if cleanPath.isEmpty { _ = syncRoot(accountId: accountId) }
  }

  // MARK: - Helpers

  private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  private func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
    guard let data = try? JSONEncoder().encode(value) else { return false }
    do {
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      return false
    }
  }
}
