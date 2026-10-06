import Foundation

/// What a background upload/download task is, stored in the task's
/// `taskDescription` so it's still known if the app was relaunched by the
/// system to deliver the result - possibly for a task the Share Extension
/// started. Compiled into both targets.
struct TransferTaskInfo: Codable {
  enum Kind: String, Codable { case upload, download }

  let kind: Kind
  let batch: String
  let name: String
  let remoteFolder: String?
  /// A file to delete once the task ends (the upload's staged copy).
  let stagedPath: String?
}

/// Running totals for one "upload these 3 files" / "download these 2 files"
/// request, so the one summary notification (and the Dart-side "folder
/// changed" event) fires exactly once, on the last file.
struct TransferBatch: Codable {
  let kind: TransferTaskInfo.Kind
  let remoteFolder: String?
  let total: Int
  var succeeded: Int
  var failed: Int

  var finished: Int { succeeded + failed }
}

/// Persists [TransferBatch]es in the App Group's `UserDefaults`, not the
/// process's own: the Share Extension starts an upload batch, and the app -
/// a different process, possibly relaunched in the background - finishes
/// counting it.
enum TransferBatchStore {
  private static let lock = NSLock()

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: AppGroup.identifier) ?? .standard
  }

  private static func key(_ id: String) -> String { "transfer.batch.\(id)" }

  static func save(_ batch: TransferBatch, id: String) {
    lock.lock()
    defer { lock.unlock() }
    if let data = try? JSONEncoder().encode(batch) { defaults.set(data, forKey: key(id)) }
  }

  private static let finishedFoldersKey = "transfer.finishedUploadFolders"

  /// The Share Extension finished an upload into [folder] while the app
  /// wasn't running; the app reads this on its next activation so its file
  /// list can refresh.
  static func noteFinishedUpload(folder: String) {
    lock.lock()
    defer { lock.unlock() }
    var folders = defaults.stringArray(forKey: finishedFoldersKey) ?? []
    if !folders.contains(folder) { folders.append(folder) }
    defaults.set(folders, forKey: finishedFoldersKey)
  }

  static func consumeFinishedUploadFolders() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    let folders = defaults.stringArray(forKey: finishedFoldersKey) ?? []
    defaults.removeObject(forKey: finishedFoldersKey)
    return folders
  }

  /// Counts one file's outcome. Returns the batch when that was its last
  /// file (and forgets it), nil while others are still running.
  static func record(_ info: TransferTaskInfo, success: Bool) -> TransferBatch? {
    lock.lock()
    defer { lock.unlock() }
    let storageKey = key(info.batch)
    var batch =
      defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(TransferBatch.self, from: $0) }
      ?? TransferBatch(kind: info.kind, remoteFolder: info.remoteFolder, total: 1, succeeded: 0, failed: 0)
    if success { batch.succeeded += 1 } else { batch.failed += 1 }
    if batch.finished >= batch.total {
      defaults.removeObject(forKey: storageKey)
      return batch
    }
    if let data = try? JSONEncoder().encode(batch) { defaults.set(data, forKey: storageKey) }
    return nil
  }
}
