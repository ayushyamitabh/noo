import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Share to Noo": copies whatever was shared into the App Group container
/// (`SharedInbox`) and finishes. The extension can't pick a destination or
/// upload - it has no session and a tight memory/time budget - so the app
/// does that when it next opens, through its existing destination picker. A
/// notification tells the user to open it, because an extension can't launch
/// its host app.
final class ShareViewController: UIViewController {
  private let label = UILabel()
  private let spinner = UIActivityIndicatorView(style: .large)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    label.text = "Saving to Noo…"
    label.font = .preferredFont(forTextStyle: .headline)
    label.textAlignment = .center
    label.numberOfLines = 0
    spinner.startAnimating()

    let stack = UIStackView(arrangedSubviews: [spinner, label])
    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])

    Task { await importSharedItems() }
  }

  private func importSharedItems() async {
    guard let root = AppGroup.containerURL else {
      return finish(message: "Noo isn't set up to receive files yet.", saved: 0)
    }
    let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
      .flatMap { $0.attachments ?? [] } ?? []

    var saved: [SharedItem] = []
    do {
      let batch = try SharedInbox.makeBatchDirectory(in: root)
      for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
        if let item = try? await copy(provider, into: batch) { saved.append(item) }
      }
      try SharedInbox.append(saved, in: root)
    } catch {
      return finish(message: "Couldn't save to Noo: \(error.localizedDescription)", saved: 0)
    }

    if saved.isEmpty {
      finish(message: "Noo can only receive files and photos.", saved: 0)
    } else {
      notify(count: saved.count)
      finish(message: saved.count == 1 ? "Saved 1 file to Noo" : "Saved \(saved.count) files to Noo", saved: saved.count)
    }
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
          let destination = Self.uniqueURL(in: directory, name: url.lastPathComponent)
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

  private static func uniqueURL(in directory: URL, name: String) -> URL {
    var candidate = directory.appendingPathComponent(name)
    var index = 1
    while FileManager.default.fileExists(atPath: candidate.path) {
      let ext = (name as NSString).pathExtension
      let stem = (name as NSString).deletingPathExtension
      candidate = directory.appendingPathComponent(ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)")
      index += 1
    }
    return candidate
  }

  private func notify(count: Int) {
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

  private func finish(message: String, saved: Int) {
    DispatchQueue.main.async {
      self.spinner.stopAnimating()
      self.label.text = message
      DispatchQueue.main.asyncAfter(deadline: .now() + (saved > 0 ? 1.2 : 2.5)) {
        self.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }
}
