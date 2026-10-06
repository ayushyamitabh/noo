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
