import Foundation

/// Starts the Share Extension's uploads on a background `URLSession` that
/// outlives the extension. The extension process is torn down as soon as its
/// sheet closes; because the session has a `sharedContainerIdentifier` and
/// the same identifier is recreated by the app at launch
/// (`TransferManager.reconnect`), the *app* is what gets relaunched to
/// receive the results, post the summary notification and clean up.
/// Compiled into both targets.
enum ShareUpload {
  static let sessionIdentifier = "dev.ayushya.noo.transfers.share"

  static func configuration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
    config.sharedContainerIdentifier = AppGroup.identifier
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.waitsForConnectivity = true
    // Authenticate by the request's own header only (see DavClient.session).
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.urlCredentialStorage = nil
    return config
  }

  /// A `PUT` for [item] into [remoteFolder] - shared by the extension's
  /// [enqueue] and the app's own uploads so both build requests identically.
  static func uploadRequest(for item: SharedItem, account: SharedAccount, remoteFolder: String) -> URLRequest? {
    guard
      let url = WebDAV.fileURL(
        serverUrl: account.serverUrl,
        username: account.username,
        remotePath: WebDAV.join(remoteFolder, item.name)
      )
    else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(account.authHeader, forHTTPHeaderField: "Authorization")
    if let modified = (try? FileManager.default.attributesOfItem(atPath: item.path))?[.modificationDate] as? Date {
      request.setValue(String(Int(modified.timeIntervalSince1970)), forHTTPHeaderField: "X-OC-Mtime")
    }
    return request
  }

  /// Queues every item (already copied into the App Group by the extension)
  /// and returns once the system has accepted them.
  static func enqueue(items: [SharedItem], account: SharedAccount, remoteFolder: String) throws {
    guard !items.isEmpty else { return }
    let batch = UUID().uuidString
    // Small files can finish while the extension is still on screen; for
    // those this delegate counts them. Whatever outlives the extension is
    // reported to the app instead (see `TransferManager`).
    let session = URLSession(configuration: configuration(), delegate: ShareUploadDelegate(), delegateQueue: nil)

    var tasks: [URLSessionUploadTask] = []
    for item in items {
      guard let request = uploadRequest(for: item, account: account, remoteFolder: remoteFolder) else {
        throw TransferError(message: "Invalid server address.")
      }
      let task = session.uploadTask(with: request, fromFile: URL(fileURLWithPath: item.path))
      task.taskDescription =
        (try? JSONEncoder().encode(
          TransferTaskInfo(
            kind: .upload, batch: batch, name: item.name, remoteFolder: remoteFolder, stagedPath: item.path)
        )).flatMap { String(data: $0, encoding: .utf8) }
      tasks.append(task)
    }
    TransferBatchStore.save(
      TransferBatch(kind: .upload, remoteFolder: remoteFolder, total: tasks.count, succeeded: 0, failed: 0),
      id: batch)
    TransferNotifications.started(kind: .upload, batch: batch, count: tasks.count)
    tasks.forEach { $0.resume() }
    session.finishTasksAndInvalidate()
  }
}

struct TransferError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
