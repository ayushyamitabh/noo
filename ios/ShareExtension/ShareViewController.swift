import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Share to Noo". Like Reminders' or Notes' share sheet, the destination is
/// chosen *inside* the sheet - an extension can't open its host app - so this
/// shows a folder picker, then starts a background upload and closes:
///
/// 1. Copies whatever was shared into the App Group (`SharedInbox`).
/// 2. Reads the accounts the app left in the shared Keychain
///    (`SharedAccountStore`) - asking which one first if there are several -
///    and lists folders over WebDAV (`DavClient`), honouring the app's
///    hidden-files filter and its unlock settings (`ShareModel`).
/// 3. "Upload" queues the files on a background session that outlives this
///    process (`ShareUpload`); the app is relaunched to finish and notify.
///
/// With no account, or if the user prefers, the files are instead left in the
/// inbox for the app to offer its own destination picker next time it opens
/// (with a notification saying so).
final class ShareViewController: UIViewController {
  private var model: ShareModel!
  private var batchDirectory: URL?

  override func viewDidLoad() {
    super.viewDidLoad()
    model = ShareModel(shared: SharedAccountStore.load())
    model.onUpload = { [weak self] in self?.upload() }
    model.onSaveForLater = { [weak self] in self?.saveForLater() }
    model.onCancel = { [weak self] in self?.cancel() }

    let host = UIHostingController(rootView: SharePickerView(model: model))
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    host.didMove(toParent: self)

    Task { await prepare() }
  }

  // MARK: - Importing

  @MainActor
  private func prepare() async {
    guard let root = AppGroup.containerURL else {
      model.stage = .failed("Noo isn't set up to receive files yet.")
      return
    }
    let providers =
      (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []

    do {
      let batch = try SharedInbox.makeBatchDirectory(in: root)
      batchDirectory = batch
      for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
        if let item = try? await copy(provider, into: batch) { model.items.append(item) }
      }
    } catch {
      model.stage = .failed("Couldn't save to Noo: \(error.localizedDescription)")
      return
    }

    guard !model.items.isEmpty else {
      model.stage = .failed("Noo can only receive files and photos.")
      return
    }
    await model.start()
  }

  /// `loadFileRepresentation`'s URL only lives for the duration of its
  /// callback, so the copy happens inside it.
  private func copy(_ provider: NSItemProvider, into directory: URL) async throws -> SharedItem {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
        guard let url else {
          return continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
        }
        do {
          let destination = LocalFiles.uniqueURL(in: directory, name: url.lastPathComponent)
          try FileManager.default.copyItem(at: url, to: destination)
          let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int64 ?? 0
          let mime = UTType(filenameExtension: destination.pathExtension)?.preferredMIMEType
          continuation.resume(
            returning: SharedItem(
              path: destination.path, name: destination.lastPathComponent, mimeType: mime, size: size))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: - Actions

  private func upload() {
    guard let account = model.selected else { return }
    do {
      try ShareUpload.enqueue(items: model.items, account: account, remoteFolder: model.path)
      model.stage = .uploading
      complete(after: 1.2)
    } catch {
      model.stage = .failed("Couldn't start the upload: \(error.localizedDescription)")
    }
  }

  private func saveForLater() {
    guard let root = AppGroup.containerURL else { return cancel() }
    do {
      try SharedInbox.append(model.items, in: root)
      notifyOpenNoo(count: model.items.count)
      complete(after: 0)
    } catch {
      model.stage = .failed("Couldn't save to Noo: \(error.localizedDescription)")
    }
  }

  private func cancel() {
    if let batchDirectory { try? FileManager.default.removeItem(at: batchDirectory) }
    extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
  }

  private func complete(after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      self.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func notifyOpenNoo(count: Int) {
    let content = UNMutableNotificationContent()
    content.title = "Noo"
    content.body =
      count == 1
      ? "Open Noo to choose where to upload 1 file."
      : "Open Noo to choose where to upload \(count) files."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }
}
