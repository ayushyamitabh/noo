import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    TransferManager.shared.reconnect()
    // BGTask handlers have to be registered before launch finishes.
    SyncCoordinator.shared.registerBackgroundTasks()
    SyncCoordinator.shared.registerNotificationCategories()
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    SyncCoordinator.shared.scheduleBackgroundWork()
    return launched
  }

  /// Taps on a sync-conflict notification's "Keep local" / "Use server".
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if SyncCoordinator.shared.handleNotificationResponse(response, completion: completionHandler) { return }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  /// A transfer summary ("Downloaded 1 file") usually finishes while the app
  /// is open; without this iOS delivers it silently to Notification Center
  /// instead of showing the banner.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == TransferManager.sessionIdentifier || identifier == ShareUpload.sessionIdentifier {
      TransferManager.shared.backgroundCompletionHandler = completionHandler
    } else {
      super.application(
        application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    NativeServices.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
