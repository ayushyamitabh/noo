import Foundation
import UserNotifications

struct UploadFile {
  let uri: String
  let name: String
}

/// Uploads and downloads on a background `URLSession`, so a transfer keeps
/// going - and finishes - after the app is suspended or closed. The iOS
/// counterpart of Android's `ShareUploadService`/`DownloadService`
/// foreground services, behind the same Dart channels (`NativeServices`).
///
/// Uploads are one `PUT` per file straight to the account's WebDAV root
/// (no chunking), from a staged copy in Caches - a background upload task
/// needs a file that stays put, and the picker's temp file may not. Downloads
/// land in `Documents/Downloads`, which is visible in the Files app
/// (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`).
final class TransferManager: NSObject {
  static let shared = TransferManager()
  static let sessionIdentifier = "dev.ayushya.noo.transfers"

  /// Called on the main thread when an upload batch ends with at least one
  /// file uploaded: (remote folder, succeeded, failed).
  var onUploadBatchFinished: ((String, Int, Int) -> Void)?

  /// The system's completion handler from
  /// `application(_:handleEventsForBackgroundURLSession:)`, called once the
  /// session has delivered every pending event.
  var backgroundCompletionHandler: (() -> Void)?

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.waitsForConnectivity = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  /// The session the Share Extension's uploads run on (see `ShareUpload`).
  /// The extension is gone by the time they finish, so the app recreates it -
  /// same identifier and shared container - to receive the results.
  private lazy var shareSession = URLSession(
    configuration: ShareUpload.configuration(), delegate: self, delegateQueue: nil)

  /// Touch both sessions at launch so a system relaunch for finished
  /// background transfers reconnects to them.
  func reconnect() {
    _ = session
    _ = shareSession
  }

  // MARK: - Starting transfers

  func startUpload(
    serverUrl: String,
    username: String,
    authHeader: String,
    files: [UploadFile],
    remoteFolder: String
  ) throws {
    guard !files.isEmpty else { throw TransferError(message: "No files to upload.") }
    let batch = UUID().uuidString
    let stageDir = try Self.stagingDirectory().appendingPathComponent(batch, isDirectory: true)
    try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

    var tasks: [URLSessionUploadTask] = []
    for (index, file) in files.enumerated() {
      guard let source = URL(string: file.uri), source.isFileURL else {
        throw TransferError(message: "Can't read \(file.name).")
      }
      let staged = stageDir.appendingPathComponent("\(index)-\(file.name)")
      do {
        try FileManager.default.copyItem(at: source, to: staged)
        // A file the Share Extension left in the App Group is ours to clean
        // up once it's staged; a picker's temp file isn't.
        if source.path.contains("/\(SharedInbox.folderName)/") {
          try? FileManager.default.removeItem(at: source)
        }
      } catch {
        throw TransferError(message: "Can't read \(file.name): \(error.localizedDescription)")
      }
      guard let url = WebDAV.fileURL(
        serverUrl: serverUrl,
        username: username,
        remotePath: WebDAV.join(remoteFolder, file.name)
      ) else {
        throw TransferError(message: "Invalid server address.")
      }
      var request = URLRequest(url: url)
      request.httpMethod = "PUT"
      request.setValue(authHeader, forHTTPHeaderField: "Authorization")
      if let modified = (try? FileManager.default.attributesOfItem(atPath: staged.path))?[.modificationDate] as? Date {
        request.setValue(String(Int(modified.timeIntervalSince1970)), forHTTPHeaderField: "X-OC-Mtime")
      }
      let task = session.uploadTask(with: request, fromFile: staged)
      task.taskDescription = Self.encode(
        TransferTaskInfo(
          kind: .upload, batch: batch, name: file.name,
          remoteFolder: remoteFolder, stagedPath: staged.path
        )
      )
      tasks.append(task)
    }
    TransferBatchStore.save(
      TransferBatch(kind: .upload, remoteFolder: remoteFolder, total: tasks.count, succeeded: 0, failed: 0),
      id: batch
    )
    TransferNotifications.started(kind: .upload, batch: batch, count: tasks.count)
    tasks.forEach { $0.resume() }
  }

  func startDownload(
    serverUrl: String,
    username: String,
    authHeader: String,
    items: [(path: String, name: String)]
  ) throws {
    guard !items.isEmpty else { throw TransferError(message: "No files to download.") }
    let batch = UUID().uuidString
    var tasks: [URLSessionDownloadTask] = []
    for item in items {
      guard let url = WebDAV.fileURL(serverUrl: serverUrl, username: username, remotePath: item.path) else {
        throw TransferError(message: "Invalid server address.")
      }
      var request = URLRequest(url: url)
      request.setValue(authHeader, forHTTPHeaderField: "Authorization")
      let task = session.downloadTask(with: request)
      task.taskDescription = Self.encode(
        TransferTaskInfo(kind: .download, batch: batch, name: item.name, remoteFolder: nil, stagedPath: nil)
      )
      tasks.append(task)
    }
    TransferBatchStore.save(
      TransferBatch(kind: .download, remoteFolder: nil, total: tasks.count, succeeded: 0, failed: 0),
      id: batch
    )
    TransferNotifications.started(kind: .download, batch: batch, count: tasks.count)
    tasks.forEach { $0.resume() }
  }

  // MARK: - Locations

  private static func stagingDirectory() throws -> URL {
    let caches = try FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    return caches.appendingPathComponent("uploads", isDirectory: true)
  }

  static func downloadsDirectory() throws -> URL {
    let documents = try FileManager.default.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    let dir = documents.appendingPathComponent("Downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - Batch bookkeeping

  private static func encode(_ info: TransferTaskInfo) -> String? {
    (try? JSONEncoder().encode(info)).flatMap { String(data: $0, encoding: .utf8) }
  }

  private static func info(for task: URLSessionTask) -> TransferTaskInfo? {
    task.taskDescription
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONDecoder().decode(TransferTaskInfo.self, from: $0) }
  }

  /// Counts one file's outcome; fires the batch summary when it was the last.
  private func record(_ info: TransferTaskInfo, success: Bool) {
    if let batch = TransferBatchStore.record(info, success: success) { finish(batch, id: info.batch) }
  }

  private func finish(_ batch: TransferBatch, id: String) {
    TransferNotifications.finished(batch, id: id)
    reportToDart(batch)
  }

  /// Tells Dart (so `FilesController` can refresh the folder) once an upload
  /// batch has landed at least one file.
  private func reportToDart(_ batch: TransferBatch) {
    if batch.kind == .upload, batch.succeeded > 0, let folder = batch.remoteFolder {
      DispatchQueue.main.async { self.onUploadBatchFinished?(folder, batch.succeeded, batch.failed) }
    }
  }

  /// Folders the Share Extension finished uploading into while the app wasn't
  /// running - call when the app becomes active.
  func deliverExtensionUploads() {
    for folder in TransferBatchStore.consumeFinishedUploadFolders() {
      DispatchQueue.main.async { self.onUploadBatchFinished?(folder, 1, 0) }
    }
  }
}

// MARK: - URLSession delegates

extension TransferManager: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
  ) {
    guard let info = Self.info(for: downloadTask) else { return }
    let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      record(info, success: false)
      return
    }
    do {
      let destination = LocalFiles.uniqueURL(in: try Self.downloadsDirectory(), name: info.name)
      try FileManager.default.moveItem(at: location, to: destination)
      record(info, success: true)
    } catch {
      record(info, success: false)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let info = Self.info(for: task) else { return }
    switch info.kind {
    case .upload:
      if let result = UploadResults.handle(task, error: error), let batch = result.batch {
        reportToDart(batch)
      }
    case .download:
      // A finished download was already counted in didFinishDownloadingTo;
      // only a transport failure arrives here.
      if error != nil { record(info, success: false) }
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletionHandler?()
      self.backgroundCompletionHandler = nil
    }
  }
}
