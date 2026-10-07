import BackgroundTasks
import Network
import UIKit
import UserNotifications

/// Whether the network currently allows a sync run: any connection normally,
/// but with "Wi-Fi only" nothing metered (cellular, a phone's hotspot) -
/// iOS's equivalent of Android's `NetworkType.UNMETERED` work constraint,
/// which a `BGTask` doesn't offer.
enum NetworkGate {
  static func allows(wifiOnly: Bool) async -> Bool {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "dev.ayushya.noo.network-gate")
    return await withCheckedContinuation { continuation in
      var answered = false  // only touched on `queue`
      monitor.pathUpdateHandler = { path in
        guard !answered else { return }
        answered = true
        monitor.cancel()
        let connected = path.status == .satisfied
        continuation.resume(returning: connected && (!wifiOnly || !path.isExpensive))
      }
      monitor.start(queue: queue)
    }
  }
}

/// Runs an action at most once - for completing a `BGTask`, which must be
/// told it's done exactly one time whether the work finished or the system's
/// time ran out first.
final class OnceGate {
  private let lock = NSLock()
  private var done = false
  private let action: (Bool) -> Void

  init(_ action: @escaping (Bool) -> Void) {
    self.action = action
  }

  func finish(_ success: Bool) {
    lock.lock()
    if done {
      lock.unlock()
      return
    }
    done = true
    lock.unlock()
    action(success)
  }
}

/// Runs sync for the app: the "Sync now" / in-app refresh runs the Dart side
/// asks for, the periodic background runs iOS grants through
/// `BGTaskScheduler`, conflict resolution, and the notifications around them.
/// The iOS counterpart of Android's `SyncWorker` scheduling + `MainActivity`'s
/// `sync_service` handlers; the actual walk/diff/transfer is `SyncRunner`.
///
/// Every run - foreground or background - goes through `startRun`, so one
/// per-account record knows what's running, "Sync now" can supersede it and a
/// quiet check can leave it alone, and signing out or removing a path can
/// cancel it. Runs are also serialised against each other (and against
/// removal) by one mutex, and carry the account's *generation*: cancelling or
/// removing bumps it, so a run that was only queued behind another never
/// starts for an account that's gone in the meantime.
///
/// iOS decides *when* background work runs (typically while charging, on
/// Wi-Fi, learned from how you use the phone) - `intervalMinutes` is only the
/// earliest it may start, not a schedule, and a run is cut off when the
/// system's time budget ends (the runner saves its state as it goes).
final class SyncCoordinator {
  static let shared = SyncCoordinator()

  static let refreshTaskId = "dev.ayushya.noo.sync.refresh"
  static let processingTaskId = "dev.ayushya.noo.sync.processing"

  static let conflictCategory = "dev.ayushya.noo.sync.conflict"
  static let keepLocalAction = "dev.ayushya.noo.sync.keepLocal"
  static let useServerAction = "dev.ayushya.noo.sync.useServer"

  let store: SyncStore
  let bus: SyncStatusBus
  let configs: SyncConfigStore
  private let runner: SyncRunner

  /// One run at a time, app-wide (see `AsyncMutex`).
  private let mutex = AsyncMutex()
  private let lock = NSLock()
  private var running: [String: (token: UUID, task: Task<Void, Never>)] = [:]
  private var generations: [String: Int] = [:]

  init(
    store: SyncStore = .shared, bus: SyncStatusBus = SyncStatusBus(),
    configs: SyncConfigStore = SyncConfigStore(), client: DavSyncClient = DavSyncClient()
  ) {
    self.store = store
    self.bus = bus
    self.configs = configs
    self.runner = SyncRunner(client: client, store: store, bus: bus)
  }

  // MARK: - Settings from Dart

  /// Brings the background job in line with [config] (called whenever the
  /// synced paths, account or network setting changes). A config with no
  /// folders means this account has nothing to sync.
  func reschedule(_ config: SyncAccountConfig) {
    if config.folders.isEmpty {
      cancel(accountId: config.accountId, forget: true)
      return
    }
    configs.upsert(config)
    scheduleBackgroundWork()
  }

  /// [forget] true: the account was removed or signed out - stop its run and
  /// drop its settings and credentials. [forget] false: only background sync
  /// was turned off (manual refresh is still possible) - the credentials stay,
  /// since a conflict notification's actions and the next "Sync now" need
  /// them, and a run in progress is left to finish.
  func cancel(accountId: String, forget: Bool = true) {
    if forget {
      cancelRun(accountId: accountId, invalidateQueued: true)
      configs.remove(accountId: accountId)
    } else if var config = configs.config(for: accountId) {
      config.intervalMinutes = nil
      configs.upsert(config)
    }
    scheduleBackgroundWork()
  }

  /// A one-off run. [force] is an explicit "Sync now" / newly added path:
  /// a full walk, a summary notification, and it supersedes any run already
  /// going for this account; without it (pull-to-refresh, foreground timer,
  /// app resume) it's a quiet check that never interrupts a run in progress.
  /// [wifiOnly] non-nil means "respect the Wi-Fi-only setting".
  func syncNow(_ config: SyncAccountConfig, force: Bool, wifiOnly: Bool?) {
    if config.folders.isEmpty { return }
    // Keep the background settings this call doesn't carry.
    var stored = config
    if let existing = configs.config(for: config.accountId) {
      stored.intervalMinutes = existing.intervalMinutes
      stored.wifiOnly = existing.wifiOnly
    }
    configs.upsert(stored)
    startRun(stored.withNotify(config.notify), force: force, wifiOnly: wifiOnly)
  }

  /// Stops [accountId]'s run, if any. [invalidateQueued] also stops runs that
  /// are only waiting their turn from ever starting.
  private func cancelRun(accountId: String, invalidateQueued: Bool) {
    lock.lock()
    if invalidateQueued { generations[accountId, default: 0] += 1 }
    running[accountId]?.task.cancel()
    lock.unlock()
  }

  private func generation(of accountId: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return generations[accountId] ?? 0
  }

  /// Starts a tracked run, or - for a non-forced one when this account is
  /// already running - returns nil and leaves the current run alone.
  @discardableResult
  private func startRun(_ config: SyncAccountConfig, force: Bool, wifiOnly: Bool?) -> Task<Void, Never>? {
    lock.lock()
    if let existing = running[config.accountId] {
      if force {
        existing.task.cancel()
      } else {
        lock.unlock()
        return nil
      }
    }
    let token = UUID()
    let generation = generations[config.accountId] ?? 0
    let task = Task { [weak self] in
      await self?.execute(config, force: force, wifiOnly: wifiOnly, generation: generation)
      self?.finished(accountId: config.accountId, token: token)
    }
    running[config.accountId] = (token, task)
    lock.unlock()
    return task
  }

  private func finished(accountId: String, token: UUID) {
    lock.lock()
    if running[accountId]?.token == token { running[accountId] = nil }
    lock.unlock()
  }

  /// Turning sync off for [path]: stop this account's run first and do the
  /// removal under the same mutex as runs - a run still holding the old
  /// state would otherwise write it back over the removal (and a transfer
  /// finishing after it would leave a file the state doesn't know about).
  func removeLocalSync(accountId: String, path: String) async {
    cancelRun(accountId: accountId, invalidateQueued: true)
    _ = try? await mutex.withLock {
      store.removeLocalSync(accountId: accountId, path: path)
    }
  }

  /// The map Dart's `SyncStatusSnapshot.fromMap` reads. [accountIdOverride]
  /// is the account Dart is asking about: the bus only learns an account once
  /// a run has happened in this process, so on a fresh start the durable
  /// per-file synced state would otherwise be reported as empty.
  func statusMap(_ status: SyncStatusBus.Status, accountIdOverride: String? = nil) -> [String: Any] {
    let accountId = accountIdOverride ?? status.accountId
    // Live syncing state belongs to whichever account last synced.
    let busMatches = status.accountId == nil || status.accountId == accountId
    let synced = accountId.map { Array(((try? store.loadState(accountId: $0)) ?? [:]).keys) } ?? []
    let missing = accountId.map { Array(store.loadMissingRoots(accountId: $0)) } ?? []
    return [
      "accountId": accountId as Any,
      "syncing": busMatches && status.syncing,
      "syncingFileIds": busMatches ? Array(status.syncingFileIds) : [],
      "syncedFileIds": synced,
      "missingRoots": missing,
      // Conflicts are per account (a file id is only unique within one).
      "conflicts": status.conflicts.filter { $0.accountId == accountId }.map {
        [
          "accountId": $0.accountId, "fileId": $0.fileId, "remotePath": $0.remotePath,
          "relPath": $0.relPath, "name": $0.name,
        ]
      },
    ]
  }

  // MARK: - Running

  /// One account's pass, serialised against every other run.
  private func execute(
    _ config: SyncAccountConfig, force: Bool, wifiOnly: Bool?, generation: Int
  ) async {
    // A few extra seconds if the app is backgrounded mid-run; if even those
    // run out, stop this account's run so it saves and ends cleanly.
    let box = BackgroundTaskBox()
    box.id = await MainActor.run {
      UIApplication.shared.beginBackgroundTask(withName: "noo.sync") { [weak self] in
        self?.cancelRun(accountId: config.accountId, invalidateQueued: false)
        UIApplication.shared.endBackgroundTask(box.id)
      }
    }
    defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(box.id) } }

    do {
      try await mutex.withLock {
        try Task.checkCancellation()
        // Gone (signed out / removed) while this was queued?
        guard self.generation(of: config.accountId) == generation,
          self.configs.config(for: config.accountId) != nil
        else { return }
        if let wifiOnly, await !NetworkGate.allows(wifiOnly: wifiOnly) { return }
        let summary = await runner.run(config, force: force)
        if summary.changedAnything && (force || config.notify) {
          SyncNotifications.summary(summary, username: config.username, accountId: config.accountId)
        }
        SyncNotifications.conflicts(summary.conflicts, username: config.username)
      }
    } catch {
      // Cancelled while waiting for its turn - nothing ran.
    }
  }

  /// Resolves a conflict from a notification action, using the stored
  /// credentials for its account.
  func resolveConflict(_ conflict: SyncConflict, resolution: String, creds: SyncCredentials) async -> Bool {
    (try? await mutex.withLock {
      await runner.resolveConflict(conflict, resolution: resolution, creds: creds)
    }) ?? false
  }

  // MARK: - Background tasks

  /// Registers the two `BGTask` handlers. Must run before the app finishes
  /// launching (see `AppDelegate`).
  func registerBackgroundTasks() {
    for id in [Self.refreshTaskId, Self.processingTaskId] {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { [weak self] task in
        self?.handleBackground(task)
      }
    }
  }

  /// Asks iOS for the next background run: a short app-refresh slot and a
  /// longer processing slot (the system picks when, e.g. overnight on power).
  /// Nothing is requested when no account has background sync turned on.
  func scheduleBackgroundWork() {
    let scheduler = BGTaskScheduler.shared
    let due = backgroundConfigs()
    guard let minutes = due.compactMap(\.intervalMinutes).min() else {
      scheduler.cancel(taskRequestWithIdentifier: Self.refreshTaskId)
      scheduler.cancel(taskRequestWithIdentifier: Self.processingTaskId)
      return
    }
    // Same floor as Android's periodic work.
    let earliest = Date(timeIntervalSinceNow: TimeInterval(max(minutes, 15) * 60))

    let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
    refresh.earliestBeginDate = earliest
    let processing = BGProcessingTaskRequest(identifier: Self.processingTaskId)
    processing.earliestBeginDate = earliest
    processing.requiresNetworkConnectivity = true
    processing.requiresExternalPower = false
    for request in [refresh, processing] as [BGTaskRequest] {
      do { try scheduler.submit(request) } catch {
        NSLog("[Sync] couldn't schedule %@: %@", request.identifier, String(describing: error))
      }
    }
  }

  private func backgroundConfigs() -> [SyncAccountConfig] {
    configs.all().filter { $0.intervalMinutes != nil && !$0.folders.isEmpty }
  }

  /// A background slot: runs every account that has background sync on, each
  /// through the normal tracked path (so it can be cancelled by sign-out, and
  /// a run already going is left alone). The task is reported complete
  /// exactly once - when the work ends or when the system's time does.
  private func handleBackground(_ task: BGTask) {
    scheduleBackgroundWork()  // line up the next one before this one runs
    let gate = OnceGate { task.setTaskCompleted(success: $0) }
    let accountIds = backgroundConfigs().map(\.accountId)
    let work = Task { [weak self] in
      guard let self else { return gate.finish(false) }
      for config in self.backgroundConfigs() {
        if Task.isCancelled { break }
        await self.startRun(config, force: false, wifiOnly: config.wifiOnly)?.value
      }
      gate.finish(!Task.isCancelled)
    }
    // The system's time is up: stop the work and the runs it started (each
    // saves what it has) and report.
    task.expirationHandler = { [weak self] in
      work.cancel()
      for id in accountIds { self?.cancelRun(accountId: id, invalidateQueued: false) }
      gate.finish(false)
    }
  }

  // MARK: - Notifications

  /// Registers the conflict notification's actions. Call once at launch.
  func registerNotificationCategories() {
    let keep = UNNotificationAction(identifier: Self.keepLocalAction, title: "Keep local", options: [])
    let server = UNNotificationAction(identifier: Self.useServerAction, title: "Use server", options: [])
    let category = UNNotificationCategory(
      identifier: Self.conflictCategory, actions: [keep, server], intentIdentifiers: [], options: [])
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  /// Handles a tap on a conflict notification's action. Returns whether the
  /// response was ours (so `AppDelegate` knows not to pass it on).
  @MainActor
  func handleNotificationResponse(
    _ response: UNNotificationResponse, completion: @escaping () -> Void
  ) -> Bool {
    let content = response.notification.request.content
    guard content.categoryIdentifier == Self.conflictCategory else { return false }
    let resolution: String
    switch response.actionIdentifier {
    case Self.keepLocalAction: resolution = "local"
    case Self.useServerAction: resolution = "server"
    default:
      completion()  // plain tap: just opens the app
      return true
    }
    let info = content.userInfo
    guard let accountId = info["accountId"] as? String,
      let fileId = info["fileId"] as? String,
      let remotePath = info["remotePath"] as? String,
      let relPath = info["relPath"] as? String,
      let config = configs.config(for: accountId)
    else {
      completion()
      return true
    }
    let conflict = SyncConflict(
      accountId: accountId, fileId: fileId, remotePath: remotePath, relPath: relPath,
      name: (relPath as NSString).lastPathComponent)
    let creds = SyncCredentials(serverUrl: config.serverUrl, username: config.username, authHeader: config.authHeader)
    let box = BackgroundTaskBox()
    box.id = UIApplication.shared.beginBackgroundTask(withName: "noo.sync.resolve") {
      completion()
      UIApplication.shared.endBackgroundTask(box.id)
    }
    Task {
      let ok = await self.resolveConflict(conflict, resolution: resolution, creds: creds)
      if ok {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
          withIdentifiers: [response.notification.request.identifier])
      }
      completion()
      await MainActor.run { UIApplication.shared.endBackgroundTask(box.id) }
    }
    return true
  }
}

/// Holds a `UIBackgroundTaskIdentifier` so an expiration handler (created
/// before the identifier exists) can end the task it belongs to.
final class BackgroundTaskBox {
  var id: UIBackgroundTaskIdentifier = .invalid
}

extension SyncAccountConfig {
  func withNotify(_ notify: Bool) -> SyncAccountConfig {
    var copy = self
    copy.notify = notify
    return copy
  }
}

/// The local notifications sync posts: a summary of what changed, and one per
/// conflict (which always posts - it needs a decision) with Keep local / Use
/// server actions.
enum SyncNotifications {
  static func summary(_ summary: SyncRunSummary, username: String, accountId: String) {
    var parts: [String] = []
    if summary.downloaded > 0 { parts.append("\(summary.downloaded) updated") }
    if summary.uploaded > 0 { parts.append("\(summary.uploaded) uploaded") }
    if summary.deleted > 0 { parts.append("\(summary.deleted) removed") }
    let content = UNMutableNotificationContent()
    content.title = "Noo sync · \(username)"
    content.body = parts.joined(separator: ", ")
    // One per account, so a newer summary replaces an older one in place.
    post(content, id: "sync.summary.\(accountId)")
  }

  static func conflicts(_ conflicts: [SyncConflict], username: String) {
    for conflict in conflicts {
      let content = UNMutableNotificationContent()
      content.title = "Sync conflict: \(conflict.name)"
      content.body = "\(username) - changed both on this device and on the server."
      content.categoryIdentifier = SyncCoordinator.conflictCategory
      content.userInfo = [
        "accountId": conflict.accountId, "fileId": conflict.fileId,
        "remotePath": conflict.remotePath, "relPath": conflict.relPath,
      ]
      post(content, id: "sync.conflict.\(conflict.accountId).\(conflict.relPath)")
    }
  }

  private static func post(_ content: UNMutableNotificationContent, id: String) {
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }
}
