import Flutter
import Foundation
import UIKit

/// Holds the one native-side listener of an `EventChannel` so Swift code can
/// push events to Dart whenever they happen.
final class SinkStreamHandler: NSObject, FlutterStreamHandler {
  var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

/// The iOS side of the `dev.ayushya.noo/*` channels `lib/services/` talks to
/// (Android's lives in `MainActivity.kt`). Upload, download and share (the
/// receiving half of the Share Extension) are implemented so far; the rest
/// still throw `MissingPluginException`, which the Dart side treats as
/// "unavailable" (`lib/services/native_channel.dart`).
enum NativeServices {
  private static let uploadStatus = SinkStreamHandler()

  static func register(messenger: FlutterBinaryMessenger) {
    // iPhone vs iPad, for the tablet layout's fold split (Dart's DeviceIdiom):
    // Flutter has no fold API on iOS, but only an unfolded foldable iPhone
    // gets a tablet-class window.
    FlutterMethodChannel(name: "dev.ayushya.noo/device", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "isPhone" else { return result(FlutterMethodNotImplemented) }
        result(UIDevice.current.userInterfaceIdiom == .phone)
      }
    FlutterMethodChannel(name: "dev.ayushya.noo/upload_service", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "startUpload" else { return result(FlutterMethodNotImplemented) }
        handle(call, result) { args in
          let files = try parseJSONList(args["files"])
          try TransferManager.shared.startUpload(
            serverUrl: try string(args, "serverUrl"),
            username: try string(args, "username"),
            authHeader: try string(args, "authHeader"),
            files: files.compactMap { entry in
              guard let uri = entry["uri"] as? String, let name = entry["name"] as? String else {
                return nil
              }
              return UploadFile(uri: uri, name: name)
            },
            remoteFolder: (args["remoteFolder"] as? String) ?? "/"
          )
        }
      }

    FlutterMethodChannel(name: "dev.ayushya.noo/download_service", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "startDownload" else { return result(FlutterMethodNotImplemented) }
        handle(call, result) { args in
          let items = try parseJSONList(args["files"])
          try TransferManager.shared.startDownload(
            serverUrl: try string(args, "serverUrl"),
            username: try string(args, "username"),
            authHeader: try string(args, "authHeader"),
            items: items.compactMap { entry in
              guard let path = entry["path"] as? String, let name = entry["name"] as? String else {
                return nil
              }
              return (path: path, name: name)
            }
          )
        }
      }

    FlutterEventChannel(name: "dev.ayushya.noo/upload_service/status", binaryMessenger: messenger)
      .setStreamHandler(uploadStatus)
    TransferManager.shared.onUploadBatchFinished = { folder, succeeded, failed in
      uploadStatus.sink?(["remoteFolder": folder, "succeeded": succeeded, "failed": failed])
    }
    TransferManager.shared.reconnect()
    registerShare(messenger: messenger)
    registerShareAccount(messenger: messenger)
    registerSync(messenger: messenger)
  }

  // MARK: - Device sync

  /// Sends the current sync status the moment Dart starts listening, then
  /// every change - same as Android's `SyncStatusBus.subscribe`.
  private final class SyncStatusStream: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
      -> FlutterError?
    {
      sink = events
      let coordinator = SyncCoordinator.shared
      events(coordinator.statusMap(coordinator.bus.snapshot()))
      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      sink = nil
      return nil
    }
  }

  private static let syncStatusStream = SyncStatusStream()
  /// Serial, so status events reach Dart in the order they happened even
  /// though building each one reads the state from disk.
  private static let syncStatusQueue = DispatchQueue(label: "dev.ayushya.noo.sync-status", qos: .utility)

  /// `sync_service`: the same methods Android's `MainActivity.kt` serves,
  /// backed by `SyncCoordinator`/`SyncRunner`.
  private static func registerSync(messenger: FlutterBinaryMessenger) {
    let coordinator = SyncCoordinator.shared

    FlutterMethodChannel(name: "dev.ayushya.noo/sync_service", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "reschedule":
          handle(call, result) { _ in coordinator.reschedule(try syncConfig(args)) }
        case "cancel":
          // `forget` (default true) = signed out / removed; false = only the
          // background job is off - credentials stay for manual runs and
          // conflict actions.
          handle(call, result) { _ in
            coordinator.cancel(
              accountId: try string(args, "accountId"), forget: args["forget"] as? Bool ?? true)
          }
        case "syncNow":
          handle(call, result) { _ in
            let force = args["force"] as? Bool ?? true
            coordinator.syncNow(try syncConfig(args), force: force, wifiOnly: args["wifiOnly"] as? Bool)
          }
        case "getSyncStatus":
          let accountId = args["accountId"] as? String
          syncStatusQueue.async {
            let map = coordinator.statusMap(coordinator.bus.snapshot(), accountIdOverride: accountId)
            DispatchQueue.main.async { result(map) }
          }
        case "resolveConflict":
          handle(call, result) { _ in
            let conflict = SyncConflict(
              accountId: try string(args, "accountId"), fileId: try string(args, "fileId"),
              remotePath: try string(args, "remotePath"), relPath: try string(args, "relPath"),
              name: ((args["relPath"] as? String ?? "") as NSString).lastPathComponent)
            let creds = SyncCredentials(
              serverUrl: try string(args, "serverUrl"), username: try string(args, "username"),
              authHeader: try string(args, "authHeader"))
            let resolution = try string(args, "resolution")
            // Fire and forget, like Android: the status stream reports the result.
            Task { _ = await coordinator.resolveConflict(conflict, resolution: resolution, creds: creds) }
          }
        case "removeAccountData":
          guard let accountId = args["accountId"] as? String else {
            return result(FlutterError(code: "bad_args", message: "Missing accountId", details: nil))
          }
          Task {
            do {
              try await coordinator.removeAccountData(accountId: accountId)
              await MainActor.run { result(nil) }
            } catch {
              await MainActor.run { result(FlutterError(code: "cleanup_failed", message: error.localizedDescription, details: nil)) }
            }
          }
        case "removeLocalSync":
          guard let accountId = args["accountId"] as? String, let path = args["path"] as? String else {
            return result(FlutterError(code: "bad_args", message: "Missing required arguments", details: nil))
          }
          Task {
            await coordinator.removeLocalSync(accountId: accountId, path: path)
            await MainActor.run { result(nil) }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterEventChannel(name: "dev.ayushya.noo/sync_service/status", binaryMessenger: messenger)
      .setStreamHandler(syncStatusStream)
    coordinator.bus.onChange = { status in
      syncStatusQueue.async {
        let map = coordinator.statusMap(status)
        DispatchQueue.main.async { syncStatusStream.sink?(map) }
      }
    }
  }

  /// The account credentials + settings every sync call carries, as a config.
  private static func syncConfig(_ args: [String: Any]) throws -> SyncAccountConfig {
    var folders: [String] = []
    if let json = args["folders"] as? String, let data = json.data(using: .utf8),
      let list = try? JSONSerialization.jsonObject(with: data) as? [String]
    {
      folders = list
    }
    return SyncAccountConfig(
      accountId: try string(args, "accountId"), serverUrl: try string(args, "serverUrl"),
      username: try string(args, "username"), authHeader: try string(args, "authHeader"),
      folders: folders, wifiOnly: args["wifiOnly"] as? Bool ?? true,
      intervalMinutes: args["intervalMinutes"] as? Int, notify: args["notify"] as? Bool ?? true)
  }

  // MARK: - Account for the Share Extension

  /// `share_account`: Dart hands native every account that can upload, which
  /// one is active, and the app-lock settings, so the Share Extension - a
  /// separate process with no Flutter engine - can list folders and upload as
  /// them. Stored in the shared Keychain group.
  private static func registerShareAccount(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "dev.ayushya.noo/share_account", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "setAccounts":
          handle(call, result) { args in
            guard let json = args["accounts"] as? String,
              let data = json.data(using: .utf8),
              let accounts = try? JSONDecoder().decode(SharedAccounts.self, from: data)
            else { throw TransferError(message: "Bad accounts payload.") }
            try SharedAccountStore.save(accounts)
            NSLog("[ShareAccounts] saved %d account(s), active=%@", accounts.accounts.count, accounts.activeId ?? "none")
          }
        case "clearAccount":
          SharedAccountStore.clear()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  // MARK: - Share Extension inbox

  private static let shareEvents = SinkStreamHandler()

  /// `share_intent`: files the Share Extension left in the App Group inbox.
  /// Cold start asks once (`getInitialShare`); a share that arrives while the
  /// app is running is pushed when it next becomes active (the extension
  /// can't signal the app any other way).
  private static func registerShare(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "dev.ayushya.noo/share_intent", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "getInitialShare" else { return result(FlutterMethodNotImplemented) }
        result(consumeShared().map(encode))
      }
    FlutterEventChannel(name: "dev.ayushya.noo/share_intent/new", binaryMessenger: messenger)
      .setStreamHandler(shareEvents)
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      TransferManager.shared.deliverExtensionUploads()
      guard let sink = shareEvents.sink else { return }
      let items = consumeShared()
      if !items.isEmpty { sink(items.map(encode)) }
    }
  }

  private static func consumeShared() -> [SharedItem] {
    guard let root = AppGroup.containerURL else { return [] }
    return SharedInbox.consume(in: root)
  }

  private static func encode(_ item: SharedItem) -> [String: Any] {
    [
      "uri": URL(fileURLWithPath: item.path).absoluteString,
      "name": item.name,
      "mimeType": item.mimeType ?? NSNull(),
      "size": item.size,
    ]
  }

  // MARK: - Argument helpers

  /// Runs [work] with the call's argument map, turning a thrown error into
  /// the `FlutterError` Dart's `catch` shows the user.
  private static func handle(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult,
    work: ([String: Any]) throws -> Void
  ) {
    guard let args = call.arguments as? [String: Any] else {
      return result(FlutterError(code: "bad_args", message: "Missing arguments.", details: nil))
    }
    do {
      try work(args)
      result(nil)
    } catch {
      result(FlutterError(code: "transfer_failed", message: error.localizedDescription, details: nil))
    }
  }

  private static func string(_ args: [String: Any], _ key: String) throws -> String {
    guard let value = args[key] as? String, !value.isEmpty else {
      throw TransferError(message: "Missing \(key).")
    }
    return value
  }

  /// The Dart services pass their file list as one JSON string.
  private static func parseJSONList(_ value: Any?) throws -> [[String: Any]] {
    guard let json = value as? String,
      let data = json.data(using: .utf8),
      let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      throw TransferError(message: "Missing file list.")
    }
    return list
  }
}
