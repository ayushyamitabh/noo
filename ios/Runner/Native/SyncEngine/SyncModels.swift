import Foundation

// The iOS port of Android's `SyncEngine.kt`/`SyncWorker.kt` data model. Times
// are milliseconds since the epoch, like the Kotlin side, so the persisted
// state means the same thing on both platforms.

/// One file or folder the server reported in a PROPFIND.
struct SyncRemoteEntry: Equatable {
  /// Path relative to the user's files root, no trailing slash ("/Docs/a.txt").
  let path: String
  let fileId: String
  let etag: String
  let lastModified: Int64
  let size: Int64
  let isFolder: Bool
}

/// What the last successful sync recorded for a file - the baseline a later
/// pass diffs the server and the device against.
struct SyncFileState: Codable, Equatable {
  let relPath: String
  let etag: String
  let lastModified: Int64
  let size: Int64
  let localMTime: Int64
}

/// A configured sync root's etag at the end of its last clean, complete walk.
/// Nextcloud propagates a change to any descendant up through every ancestor's
/// etag, so an unchanged root etag means nothing beneath it changed.
struct SyncRootMarker: Codable, Equatable {
  let etag: String
  let fullWalkAt: Int64
}

enum SyncAction: Equatable {
  case download(SyncRemoteEntry)
  case upload(relPath: String, fileId: String)
  case delete(relPath: String, fileId: String)
  case conflict(SyncRemoteEntry, relPath: String)
}

/// A file changed both on the device and on the server since the last sync.
struct SyncConflict: Codable, Equatable {
  let accountId: String
  let fileId: String
  let remotePath: String
  let relPath: String
  let name: String
}

/// Everything a sync run (foreground or background) needs for one account.
/// Persisted in the Keychain - it carries the auth header.
struct SyncAccountConfig: Codable, Equatable {
  let accountId: String
  let serverUrl: String
  let username: String
  let authHeader: String
  /// Remote paths (files or folders) to mirror.
  var folders: [String]
  var wifiOnly: Bool
  /// Minutes between background syncs; nil = no background sync (manual and
  /// in-app refresh only).
  var intervalMinutes: Int?
  /// Whether automatic runs may post a summary notification.
  var notify: Bool
}

struct SyncRunSummary: Equatable {
  var downloaded = 0
  var uploaded = 0
  var deleted = 0
  var conflicts: [SyncConflict] = []

  var changedAnything: Bool { downloaded > 0 || uploaded > 0 || deleted > 0 }
}

/// The server couldn't be reached or answered with an error (anything but a
/// clean 404). Distinct from "the path is genuinely gone": treating a network
/// blip as an empty listing made every previously synced file look deleted
/// server-side, and the diff then deleted the local copies. Callers skip the
/// affected path for this run instead.
struct SyncRemoteUnavailable: Error, CustomStringConvertible {
  let message: String
  var description: String { message }
}

/// The recorded sync state exists but couldn't be read (corrupt, or an I/O
/// error). Treating that as "nothing recorded yet" would make every local
/// file look untracked and overwrite local edits with the server's copy, so
/// a run that hits it does nothing at all.
struct SyncStateUnreadable: Error, CustomStringConvertible {
  let accountId: String
  var description: String { "Sync state for \(accountId) is unreadable" }
}
