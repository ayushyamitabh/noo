import Flutter
import UIKit
import os

class SceneDelegate: FlutterSceneDelegate, UIContextMenuInteractionDelegate {
  private var hingeInteraction: AnyObject?
  private var hingeChannel: FlutterMethodChannel?
  private var hingePartiallyOpen = false
  private var secondaryClick: UIContextMenuInteraction?
  private var secondaryClickChannel: FlutterMethodChannel?
  private let clickLog = Logger(subsystem: "dev.ayushya.noo", category: "secondary-click")

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    guard let windowScene = scene as? UIWindowScene else { return }
    let controller = windowScene.windows.compactMap { flutterController(in: $0.rootViewController) }.first
    guard let controller else {
      clickLog.error("No Flutter controller found for Mac context-menu bridge")
      return
    }
    if #available(iOS 27.1, *), hingeInteraction == nil {
      let channel = FlutterMethodChannel(
        name: "dev.ayushya.noo/hinge", binaryMessenger: controller.binaryMessenger)
      hingeChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "isPartiallyOpen" {
          result(self?.hingePartiallyOpen ?? false)
        } else { result(FlutterMethodNotImplemented) }
      }
      let interaction = UIHingeInteraction { [weak self] _, update in
        let partiallyOpen = update.hinge?.status == .partiallyOpen
        guard let self, partiallyOpen != self.hingePartiallyOpen else { return }
        self.hingePartiallyOpen = partiallyOpen
        channel.invokeMethod("postureChanged", arguments: partiallyOpen)
      }
      hingeInteraction = interaction
      controller.view.addInteraction(interaction)
    }
    guard #available(iOS 14.0, *), ProcessInfo.processInfo.isiOSAppOnMac,
      secondaryClick == nil else { return }
    secondaryClickChannel = FlutterMethodChannel(
      name: "dev.ayushya.noo/secondary_click", binaryMessenger: controller.binaryMessenger)
    // iOS-on-Mac delivers right-click through UIKit context-menu interactions,
    // rather than the secondary tap recognizer used by Flutter.
    let interaction = UIContextMenuInteraction(delegate: self)
    controller.view.addInteraction(interaction)
    secondaryClick = interaction
    clickLog.notice("Mac context-menu bridge installed")
  }

  private func flutterController(in controller: UIViewController?) -> FlutterViewController? {
    guard let controller else { return nil }
    if let flutter = controller as? FlutterViewController { return flutter }
    for child in controller.children {
      if let flutter = flutterController(in: child) { return flutter }
    }
    return nil
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    clickLog.notice("Mac context-menu click received")
    // Return no UIKit menu: the existing Flutter overflow sheet owns the UI.
    DispatchQueue.main.async { [weak self] in
      self?.secondaryClickChannel?.invokeMethod(
        "secondaryClick", arguments: ["x": location.x, "y": location.y])
    }
    return nil
  }
}
