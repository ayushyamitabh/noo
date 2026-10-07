import Foundation

/// A mutex for `async` code: one holder at a time, waiters resume in order.
/// (An `actor` isn't enough - it lets other calls in at every `await`.) Held
/// for the whole of any run that reads-then-rewrites a sync state map, which
/// is also what keeps `SyncStatusBus` - it tracks one account at a time -
/// coherent when several accounts are due.
///
/// Waiting is cancellable: a task that's cancelled while queued (a background
/// run whose time budget expired, a superseded "Sync now") leaves the queue
/// at once with `CancellationError` instead of sitting behind a long run.
final class AsyncMutex {
  private let lock = NSLock()
  private var locked = false
  private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

  func withLock<T>(_ body: () async throws -> T) async throws -> T {
    try await acquire()
    defer { release() }
    return try await body()
  }

  private func acquire() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        lock.lock()
        if Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
        } else if !locked {
          locked = true
          lock.unlock()
          continuation.resume()
        } else {
          waiters.append((id, continuation))
          lock.unlock()
        }
      }
    } onCancel: {
      lock.lock()
      if let index = waiters.firstIndex(where: { $0.id == id }) {
        let waiter = waiters.remove(at: index)
        lock.unlock()
        waiter.continuation.resume(throwing: CancellationError())
      } else {
        lock.unlock()
      }
    }
  }

  private func release() {
    lock.lock()
    if waiters.isEmpty {
      locked = false
      lock.unlock()
    } else {
      let next = waiters.removeFirst()
      lock.unlock()
      next.continuation.resume()
    }
  }
}

/// Live sync status for the app: whether a run is going, which files are
/// transferring, and unresolved conflicts. In-memory only - what actually
/// answers "is this file synced" is the on-disk state; this carries just the
/// transient parts. The iOS twin of Android's `SyncStatusBus`, except that
/// conflicts are kept per account (a file id is only unique within one).
final class SyncStatusBus {
  struct Status: Equatable {
    var accountId: String?
    var syncing = false
    var syncingFileIds: Set<String> = []
    /// Every account's unresolved conflicts - readers filter by account.
    var conflicts: [SyncConflict] = []
  }

  private let lock = NSLock()
  private var current = Status()

  /// Called (on whatever thread changed it) after every update.
  var onChange: ((Status) -> Void)?

  func snapshot() -> Status {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  func setSyncing(accountId: String, _ syncing: Bool) {
    update {
      $0.accountId = accountId
      $0.syncing = syncing
      if !syncing { $0.syncingFileIds = [] }
    }
  }

  func markFileSyncing(accountId: String, fileId: String, _ syncing: Bool) {
    update {
      $0.accountId = accountId
      if syncing { $0.syncingFileIds.insert(fileId) } else { $0.syncingFileIds.remove(fileId) }
    }
  }

  func addConflicts(accountId: String, _ new: [SyncConflict]) {
    guard !new.isEmpty else { return }
    update {
      $0.accountId = accountId
      for conflict in new
      where !$0.conflicts.contains(where: { $0.accountId == conflict.accountId && $0.fileId == conflict.fileId }) {
        $0.conflicts.append(conflict)
      }
    }
  }

  func removeConflict(accountId: String, fileId: String) {
    update {
      $0.accountId = accountId
      $0.conflicts.removeAll { $0.accountId == accountId && $0.fileId == fileId }
    }
  }

  private func update(_ mutate: (inout Status) -> Void) {
    lock.lock()
    mutate(&current)
    let snapshot = current
    lock.unlock()
    onChange?(snapshot)
  }
}

/// One account's sync pass: walk each configured path, diff it against the
/// recorded state, transfer, and record the result. The iOS port of Android's
/// `SyncWorker.performSync` (and `ConflictResolveWorker`), with the same
/// safeguards - and a few more, found in review:
///
/// - If the server can't be reached for a path - or answers with something
///   that isn't a complete, plausible listing - that path is skipped for this
///   run, never diffed against an empty or partial listing, which would look
///   like files were deleted and wipe the local copies.
/// - If the recorded state can't be read the run does nothing at all (it
///   would otherwise treat every local file as untracked and overwrite local
///   edits with the server's copies).
/// - Paths the server sends are checked to stay inside the mirror, and two
///   remote files that would land on the same local file are both skipped.
/// - A file deleted on the server but edited here is kept, not deleted.
/// - A root's etag is only remembered once its whole path synced cleanly, and
///   only if the state it relies on was actually saved.
struct SyncRunner {
  let client: DavSyncClient
  let store: SyncStore
  let bus: SyncStatusBus
  var now: () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }

  /// Even when a root's etag hasn't changed, walk it in full at least this
  /// often: etag propagation isn't reliable everywhere (external storage
  /// mounts in particular), so this bounds how stale a mirror can get.
  static let fullWalkMaxAgeMs: Int64 = 6 * 60 * 60 * 1000

  /// State is flushed to disk after this many transfers.
  static let saveEvery = 20

  /// [force] is an explicit "Sync now" / newly added path: always a full
  /// walk, never trusting the root-etag shortcut.
  func run(_ config: SyncAccountConfig, force: Bool) async -> SyncRunSummary {
    var summary = SyncRunSummary()
    guard !config.folders.isEmpty else { return summary }
    let accountId = config.accountId
    let creds = SyncCredentials(serverUrl: config.serverUrl, username: config.username, authHeader: config.authHeader)
    let syncRoot = store.syncRoot(accountId: accountId)

    var state: [String: SyncFileState]
    do {
      state = try store.loadState(accountId: accountId)
    } catch {
      NSLog("[Sync] %@ - skipping this run", String(describing: error))
      return summary
    }
    var markers = store.loadRootMarkers(accountId: accountId)
    var sinceSave = 0

    bus.setSyncing(accountId: accountId, true)
    defer {
      // State first, then the markers that depend on it, then announce.
      if store.saveState(accountId: accountId, state) {
        markers = markers.filter { config.folders.contains($0.key) }
        store.saveRootMarkers(accountId: accountId, markers)
      } else {
        NSLog("[Sync] couldn't save state for %@; not recording this run's markers", accountId)
      }
      bus.setSyncing(accountId: accountId, false)
    }

    func transferred() {
      sinceSave += 1
      if sinceSave >= Self.saveEvery {
        if !store.saveState(accountId: accountId, state) { NSLog("[Sync] periodic state save failed") }
        sinceSave = 0
      }
    }

    for path in config.folders {
      if Task.isCancelled { break }
      do {
        // A configured path can be a file or a folder - check which before
        // deciding whether to walk it or just diff the single item.
        let selfEntry = try await client.propfindSelf(creds, path: path)
        let priorIds = SyncDiff.priorFileIds(state: state, path: path)

        // Cheap "did anything change?" check: an unchanged root etag means
        // nothing beneath it changed on the server, and if every local file
        // is also still as recorded there's nothing to upload or re-download
        // either - skip the walk (one Depth-0 PROPFIND instead of one per
        // subfolder).
        if !force, let root = selfEntry, root.isFolder, let marker = markers[path],
          marker.etag == root.etag,
          now() - marker.fullWalkAt < Self.fullWalkMaxAgeMs,
          !priorIds.isEmpty,
          SyncDiff.localMatchesState(state: state, fileIds: priorIds, syncRoot: syncRoot)
        {
          continue
        }

        // The server says this synced path no longer exists (a clean 404, not
        // a network error): flag it so the app drops it from its synced list.
        store.setRootMissing(accountId: accountId, path: path, missing: selfEntry == nil)

        var entries: [SyncRemoteEntry] = []
        if let root = selfEntry {
          if root.isFolder {
            entries = try await client.walk(creds, root: path)
          } else {
            entries = [root]
          }
        }
        var pathClean = true
        let collisions = SyncDiff.collidingRelPaths(entries)

        let actions = SyncDiff.diffFolder(
          entries: entries, state: state, priorFolderFileIds: priorIds, syncRoot: syncRoot)
        for action in actions {
          try Task.checkCancellation()
          switch action {
          case .download(let entry):
            let rel = LocalFS.relative(entry.path)
            guard !collisions.contains(rel), let dest = LocalFS.resolve(rel, in: syncRoot) else {
              NSLog("[Sync] not downloading %@: unsafe or colliding local path", rel)
              pathClean = false
              continue
            }
            bus.markFileSyncing(accountId: accountId, fileId: entry.fileId, true)
            let ok = try await client.download(creds, remotePath: entry.path, to: dest)
            bus.markFileSyncing(accountId: accountId, fileId: entry.fileId, false)
            if ok {
              let local = LocalFS.stat(dest)
              state[entry.fileId] = SyncFileState(
                relPath: rel, etag: entry.etag, lastModified: entry.lastModified,
                size: local?.size ?? entry.size, localMTime: local?.mtimeMs ?? 0)
              summary.downloaded += 1
              transferred()
            } else {
              pathClean = false
            }

          case .upload(let rel, let fileId):
            guard let local = LocalFS.resolve(rel, in: syncRoot) else {
              pathClean = false
              continue
            }
            bus.markFileSyncing(accountId: accountId, fileId: fileId, true)
            var ok = false
            if FileManager.default.fileExists(atPath: local.path) {
              ok = try await client.upload(creds, remotePath: "/" + rel, from: local)
            }
            bus.markFileSyncing(accountId: accountId, fileId: fileId, false)
            if ok, let stat = LocalFS.stat(local) {
              // Our own PUT changed the file's etag; record the new one, or
              // the next pass would see "server changed" and re-download it.
              // If it can't be read back, keep the old one and let the root
              // be walked for real next time.
              let fresh = (try? await client.propfindSelf(creds, path: "/" + rel)) ?? nil
              if fresh == nil { pathClean = false }
              state[fileId] = SyncFileState(
                relPath: rel, etag: fresh?.etag ?? state[fileId]?.etag ?? "",
                lastModified: stat.mtimeMs, size: stat.size, localMTime: stat.mtimeMs)
              summary.uploaded += 1
              transferred()
            } else {
              pathClean = false
            }

          case .delete(let rel, let fileId):
            // Only counts as a removal if a local copy existed and went;
            // dropping stale state for a file never on disk isn't news.
            if let local = LocalFS.resolve(rel, in: syncRoot),
              FileManager.default.fileExists(atPath: local.path),
              (try? FileManager.default.removeItem(at: local)) != nil
            {
              summary.deleted += 1
            }
            state[fileId] = nil

          case .orphan(_, let fileId):
            // Deleted on the server but edited here: the edit stays on the
            // device, no longer tracked.
            state[fileId] = nil

          case .conflict(let entry, let rel):
            summary.conflicts.append(
              SyncConflict(
                accountId: accountId, fileId: entry.fileId, remotePath: entry.path, relPath: rel,
                name: (rel as NSString).lastPathComponent))
            pathClean = false
          }
        }

        // Mirror the folder structure itself: empty folders created on the
        // server appear on the device, and folders deleted on the server
        // (whose files the diff has already removed) don't linger.
        if selfEntry == nil || selfEntry?.isFolder == true {
          let rootRel = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          if selfEntry != nil {
            SyncDiff.mirrorFolders(entries: entries, syncRoot: syncRoot, rootRel: rootRel, collisions: collisions)
          }
          var remoteFolders = Set(
            entries.filter(\.isFolder).map { $0.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) })
          if selfEntry != nil { remoteFolders.insert(rootRel) }
          SyncDiff.pruneRemovedFolders(syncRoot: syncRoot, rootRel: rootRel, remoteFolders: remoteFolders)
        }

        if let root = selfEntry, root.isFolder, pathClean {
          markers[path] = SyncRootMarker(etag: root.etag, fullWalkAt: now())
        } else {
          markers[path] = nil
        }
      } catch is CancellationError {
        markers[path] = nil  // cut short: make the next run walk it for real
        break
      } catch {
        // Couldn't reach the server for this path (or it answered with
        // nothing usable): leave its state and marker alone and try again
        // next run.
        NSLog("[Sync] skipping %@ this run: %@", path, String(describing: error))
      }
    }

    if !summary.conflicts.isEmpty {
      bus.addConflicts(accountId: accountId, summary.conflicts)
    }
    return summary
  }

  /// Applies the user's choice for one conflicted file - `local` uploads the
  /// device's copy over the server's, `server` downloads the server's over
  /// the device's - then refreshes the recorded etag so the next pass doesn't
  /// immediately re-flag it. Returns whether it worked.
  func resolveConflict(
    _ conflict: SyncConflict, resolution: String, creds: SyncCredentials
  ) async -> Bool {
    // An unreadable baseline must not be overwritten with a one-file one.
    guard var state = try? store.loadState(accountId: conflict.accountId),
      let local = LocalFS.resolve(conflict.relPath, in: store.syncRoot(accountId: conflict.accountId))
    else { return false }

    var ok = false
    do {
      switch resolution {
      case "local":
        if FileManager.default.fileExists(atPath: local.path) {
          ok = try await client.upload(creds, remotePath: conflict.remotePath, from: local)
        }
      case "server":
        ok = try await client.download(creds, remotePath: conflict.remotePath, to: local)
      default:
        break
      }
    } catch {
      return false
    }
    guard ok else { return false }

    let fresh = (try? await client.propfindSelf(creds, path: conflict.remotePath)) ?? nil
    let stat = LocalFS.stat(local)
    state[conflict.fileId] = SyncFileState(
      relPath: conflict.relPath, etag: fresh?.etag ?? "", lastModified: fresh?.lastModified ?? 0,
      size: stat?.size ?? 0, localMTime: stat?.mtimeMs ?? 0)
    store.saveState(accountId: conflict.accountId, state)
    bus.removeConflict(accountId: conflict.accountId, fileId: conflict.fileId)
    return true
  }
}
