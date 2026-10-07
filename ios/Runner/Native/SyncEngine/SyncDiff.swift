import Foundation

/// A local file's size and modification time (ms), the pair sync compares
/// against what it recorded.
struct LocalStat: Equatable {
  let size: Int64
  let mtimeMs: Int64
}

enum LocalFS {
  /// nil if [url] doesn't exist.
  static func stat(_ url: URL) -> LocalStat? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    let mtime = (attrs[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
    return LocalStat(size: size, mtimeMs: mtime)
  }

  static func relative(_ path: String) -> String {
    path.hasPrefix("/") ? String(path.dropFirst()) : path
  }

  static func trimTrailingSlashes(_ path: String) -> String {
    var p = path
    while p.hasSuffix("/") { p.removeLast() }
    return p
  }

  /// [rel] under [root], or nil if it isn't safely inside it: empty, with a
  /// `.`/`..` component, or resolving outside [root]. Every path that came
  /// from the server goes through this before anything is read, written or
  /// deleted, so a hostile or buggy server can't point sync at other files.
  static func resolve(_ rel: String, in root: URL) -> URL? {
    let parts = rel.split(separator: "/", omittingEmptySubsequences: true)
    guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
    let url = root.appendingPathComponent(rel)
    let rootPath = root.standardizedFileURL.path
    guard url.standardizedFileURL.path.hasPrefix(rootPath + "/") else { return nil }
    return url
  }
}

/// The decisions of a sync pass, kept free of networking so they can be
/// unit-tested. A direct port of Android's `SyncEngine.diffFolder` and its
/// helpers - the same rules, so a device behaves the same on either platform.
enum SyncDiff {
  /// Diffs one synced path's remote manifest against the recorded state.
  /// Callers own actually doing the GET/PUT/delete and updating state.
  ///
  /// - A file with no recorded state is simply pulled.
  /// - Server changed and device changed -> conflict (never silently overwrite).
  /// - Only the server changed -> download. Only the device changed -> upload.
  /// - Recorded but missing on the device -> pull it back (it's inside a path
  ///   the user asked to sync, so a vanished copy is repaired, not propagated).
  /// - Recorded for this path but absent from a *successful* listing ->
  ///   deleted on the server, so the local copy goes too. (An unreachable
  ///   server never gets here - the caller skips the path instead.)
  static func diffFolder(
    entries: [SyncRemoteEntry],
    state: [String: SyncFileState],
    priorFolderFileIds: Set<String>,
    syncRoot: URL
  ) -> [SyncAction] {
    var actions: [SyncAction] = []
    var seen = Set<String>()

    for entry in entries where !entry.isFolder {
      seen.insert(entry.fileId)
      let rel = LocalFS.relative(entry.path)
      let local = LocalFS.stat(syncRoot.appendingPathComponent(rel))

      guard let prior = state[entry.fileId] else {
        actions.append(.download(entry))
        continue
      }
      let serverChanged = entry.etag != prior.etag
      let localChanged = local.map { $0.mtimeMs != prior.localMTime || $0.size != prior.size } ?? false

      if local == nil {
        actions.append(.download(entry))
      } else if serverChanged && localChanged {
        actions.append(.conflict(entry, relPath: rel))
      } else if serverChanged {
        actions.append(.download(entry))
      } else if localChanged {
        actions.append(.upload(relPath: rel, fileId: entry.fileId))
      }
    }

    for fileId in priorFolderFileIds where !seen.contains(fileId) {
      guard let prior = state[fileId] else { continue }
      // Deleted on the server. If it was also edited here since the last sync
      // that edit is the only copy left - keep it (untracked) instead of
      // deleting it along with the rest.
      if let local = LocalFS.stat(syncRoot.appendingPathComponent(prior.relPath)),
        local.mtimeMs != prior.localMTime || local.size != prior.size
      {
        actions.append(.orphan(relPath: prior.relPath, fileId: fileId))
      } else {
        actions.append(.delete(relPath: prior.relPath, fileId: fileId))
      }
    }
    return actions
  }

  /// The recorded files that belong to the synced [path]: everything for the
  /// root ("/"), else the file itself or anything under it - matched on a
  /// path-component boundary, so "/Docs" never claims "/Docs2" or
  /// "/Documents".
  static func priorFileIds(state: [String: SyncFileState], path: String) -> Set<String> {
    let rootRel = LocalFS.relative(LocalFS.trimTrailingSlashes(path))
    return Set(
      state.filter {
        rootRel.isEmpty || $0.value.relPath == rootRel || $0.value.relPath.hasPrefix(rootRel + "/")
      }.keys)
  }

  /// Local paths (as spelled by the server) that more than one remote entry
  /// would land on: "a.txt" and "A.txt" on a case-insensitive volume, or two
  /// canonically-equivalent Unicode spellings. Downloading either would
  /// overwrite the other, so callers skip them.
  static func collidingRelPaths(_ entries: [SyncRemoteEntry]) -> Set<String> {
    var byKey: [String: [String]] = [:]
    for entry in entries {
      let rel = LocalFS.relative(entry.path)
      byKey[rel.precomposedStringWithCanonicalMapping.lowercased(), default: []].append(rel)
    }
    // Compared as raw bytes: Swift's own `String` equality already treats
    // canonically equivalent spellings as the same string, which is exactly
    // the distinction the server preserves and the disk may not.
    return Set(byKey.values.filter { Set($0.map { Array($0.utf8) }).count > 1 }.flatMap { $0 })
  }

  /// True if every file in [fileIds] is still on disk exactly as recorded
  /// (same size and mtime): nothing local to upload and nothing missing to
  /// re-download. Pure local stat calls, no network.
  static func localMatchesState(
    state: [String: SyncFileState], fileIds: Set<String>, syncRoot: URL
  ) -> Bool {
    fileIds.allSatisfy { id in
      guard let s = state[id], let local = LocalFS.stat(syncRoot.appendingPathComponent(s.relPath)) else {
        return false
      }
      return local.size == s.size && local.mtimeMs == s.localMTime
    }
  }

  /// Creates a local directory for every remote folder, so empty folders
  /// exist on the device too.
  static func mirrorFolders(
    entries: [SyncRemoteEntry], syncRoot: URL, rootRel: String, collisions: Set<String> = []
  ) {
    let fm = FileManager.default
    if !rootRel.isEmpty, let dir = LocalFS.resolve(rootRel, in: syncRoot) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    for entry in entries where entry.isFolder {
      let rel = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      // Skip anything unsafe or that would share a local folder with another
      // remote folder (a/A on a case-insensitive volume).
      guard !collisions.contains(rel), let dir = LocalFS.resolve(rel, in: syncRoot) else { continue }
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  /// Removes local directories under [rootRel] that no longer exist on the
  /// server ([remoteFolders], relative paths). Only *empty* directories go:
  /// by the time this runs the diff has already deleted the files that were
  /// inside a deleted server folder, while a directory that still holds
  /// something (a file this device created that hasn't synced) is left alone.
  /// Never removes the sync root itself.
  static func pruneRemovedFolders(syncRoot: URL, rootRel: String, remoteFolders: Set<String>) {
    let fm = FileManager.default
    let top = rootRel.isEmpty ? syncRoot : syncRoot.appendingPathComponent(rootRel)
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: top.path, isDirectory: &isDir), isDir.boolValue else { return }

    func prune(_ dir: URL, rel: String) {
      let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
      for child in children {
        let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if childIsDir {
          prune(child, rel: rel.isEmpty ? child.lastPathComponent : rel + "/" + child.lastPathComponent)
        }
      }
      guard !rel.isEmpty, !remoteFolders.contains(rel),
        let remaining = try? fm.contentsOfDirectory(atPath: dir.path), remaining.isEmpty
      else { return }
      // rmdir, not removeItem: it refuses a directory that isn't empty, so a
      // file that appeared since the check survives.
      rmdir(dir.path)
    }
    prune(top, rel: rootRel)
  }
}
