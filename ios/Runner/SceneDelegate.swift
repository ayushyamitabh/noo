import Flutter
import UIKit
import os
import UniformTypeIdentifiers

class SceneDelegate: FlutterSceneDelegate, UIContextMenuInteractionDelegate, UIDropInteractionDelegate {
  private var incomingDrop: UIDropInteraction?
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
    if incomingDrop == nil {
      let interaction = UIDropInteraction(delegate: self)
      controller.view.addInteraction(interaction)
      incomingDrop = interaction
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

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    NativeServices.canReceiveDrop && session.items.allSatisfy {
      $0.itemProvider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
    }
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession)
    -> UIDropProposal {
    UIDropProposal(operation: NativeServices.canReceiveDrop ? .copy : .cancel)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    guard NativeServices.canReceiveDrop, let root = AppGroup.containerURL,
      let batch = try? SharedInbox.makeBatchDirectory(in: root) else { return }
    NativeServices.prepareDrop(session.items.count)
    let fileCount = session.items.count
    let group = DispatchGroup()
    let lock = NSLock()
    var received: [(Int, SharedItem)] = []
    var failed = false
    for (index, item) in session.items.enumerated() {
      let provider = item.itemProvider
      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, error in
        defer { group.leave() }
        do {
          guard let url else { throw error ?? TransferError(message: "Could not read dropped file.") }
          let values = try url.resourceValues(forKeys: [.isRegularFileKey])
          guard values.isRegularFile == true else {
            throw TransferError(message: "Drop files, rather than folders.")
          }
          var name = URL(fileURLWithPath: provider.suggestedName ?? url.lastPathComponent).lastPathComponent
          if URL(fileURLWithPath: name).pathExtension.isEmpty && !url.pathExtension.isEmpty {
            name += "." + url.pathExtension
          }
          let target = batch.appendingPathComponent("\(index)-\(name)")
          // The provider's URL expires when this callback returns.
          try FileManager.default.copyItem(at: url, to: target)
          let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          lock.lock()
          received.append((index, SharedItem(path: target.path, name: name, mimeType: nil, size: Int64(size))))
          lock.unlock()
        } catch {
          lock.lock(); failed = true; lock.unlock()
        }
      }
    }
    group.notify(queue: .main) {
      defer { NativeServices.finishDrop(fileCount) }
      if failed {
        try? FileManager.default.removeItem(at: batch)
        let alert = UIAlertController(title: "Could not read dropped files",
          message: "Try dropping the files again. Folders aren't supported yet.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.flutterController(in: interaction.view?.window?.rootViewController)?.present(alert, animated: true)
      } else {
        NativeServices.receiveDroppedFiles(received.sorted { $0.0 < $1.0 }.map { $0.1 })
      }
    }
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
