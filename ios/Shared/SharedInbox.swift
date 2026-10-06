import Foundation

/// The App Group both the app and its Share Extension belong to - the one
/// place they can exchange files.
enum AppGroup {
  static let identifier = "group.dev.ayushya.noo"

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }
}

/// One file the Share Extension copied into the group container.
struct SharedItem: Codable, Equatable {
  let path: String
  let name: String
  let mimeType: String?
  let size: Int64
}

/// Files the Share Extension received, waiting for the app to ask the user
/// where to upload them. The extension appends; the app consumes (reads and
/// clears) when it launches or becomes active. Compiled into both targets.
///
/// Layout under `<root>/SharedInbox/`: `pending.json` (the manifest) and one
/// `<batch-id>/` folder per share holding the copied files.
enum SharedInbox {
  static let folderName = "SharedInbox"
  private static let manifestName = "pending.json"

  static func directory(in root: URL) -> URL {
    root.appendingPathComponent(folderName, isDirectory: true)
  }

  /// A fresh folder for one share's files.
  static func makeBatchDirectory(in root: URL) throws -> URL {
    let dir = directory(in: root).appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func append(_ items: [SharedItem], in root: URL) throws {
    guard !items.isEmpty else { return }
    try withManifestLock(in: root) {
      let existing = (try? readManifest(in: root)) ?? []
      try writeManifest(existing + items, in: root)
    }
  }

  /// Everything pending, dropping entries whose file has gone missing, and
  /// clears the manifest so each share is delivered once.
  static func consume(in root: URL) -> [SharedItem] {
    var items: [SharedItem] = []
    try? withManifestLock(in: root) {
      items = ((try? readManifest(in: root)) ?? []).filter {
        FileManager.default.fileExists(atPath: $0.path)
      }
      try? FileManager.default.removeItem(at: manifestURL(in: root))
    }
    return items
  }

  private static func manifestURL(in root: URL) -> URL {
    directory(in: root).appendingPathComponent(manifestName)
  }

  private static func readManifest(in root: URL) throws -> [SharedItem] {
    let data = try Data(contentsOf: manifestURL(in: root))
    return try JSONDecoder().decode([SharedItem].self, from: data)
  }

  private static func writeManifest(_ items: [SharedItem], in root: URL) throws {
    try FileManager.default.createDirectory(
      at: directory(in: root), withIntermediateDirectories: true)
    try JSONEncoder().encode(items).write(to: manifestURL(in: root), options: .atomic)
  }

  /// The extension and the app are separate processes that can both touch the
  /// manifest, so read-modify-write goes through a file coordinator.
  private static func withManifestLock(in root: URL, _ body: () throws -> Void) throws {
    try FileManager.default.createDirectory(
      at: directory(in: root), withIntermediateDirectories: true)
    var coordinationError: NSError?
    var thrown: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: directory(in: root), options: [], error: &coordinationError
    ) { _ in
      do { try body() } catch { thrown = error }
    }
    if let error = coordinationError ?? thrown.map({ $0 as NSError }) { throw error }
  }
}
