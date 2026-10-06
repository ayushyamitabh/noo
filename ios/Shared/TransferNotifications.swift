import Foundation
import UserNotifications

/// The local notifications for an upload/download batch - one "Uploading 3
/// files…" when it starts, replaced in place by "Uploaded 3 files" when it
/// ends (both use the batch's id as the request identifier, so the second
/// *replaces* the first instead of stacking). Posted from whichever process
/// sees the event - the app, or the Share Extension while it's still alive.
/// iOS can't update a notification with live byte progress from a background
/// session, so start/finish is as much as a notification can say.
/// Compiled into both targets.
enum TransferNotifications {
  static func started(kind: TransferTaskInfo.Kind, batch: String, count: Int) {
    let verb = kind == .upload ? "Uploading" : "Downloading"
    post(id: batch, body: "\(verb) \(files(count))…", sound: false)
  }

  static func finished(_ batch: TransferBatch, id: String) {
    let verb = batch.kind == .upload ? "upload" : "download"
    let past = batch.kind == .upload ? "Uploaded" : "Downloaded"
    let body: String
    if batch.failed == 0 {
      body = "\(past) \(files(batch.succeeded))"
    } else if batch.succeeded == 0 {
      body = "Couldn't \(verb) \(files(batch.failed))"
    } else {
      body = "\(past) \(files(batch.succeeded)), \(batch.failed) failed"
    }
    post(id: id, body: body, sound: true)
  }

  static func files(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(count) files"
  }

  private static func post(id: String, body: String, sound: Bool) {
    let content = UNMutableNotificationContent()
    content.title = "Noo"
    content.body = body
    if sound { content.sound = .default }
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: "transfer.\(id)", content: content, trigger: nil))
  }
}

/// Counting one finished upload task - shared so the result is handled the
/// same way whether the Share Extension (still alive) or the app (relaunched
/// later) receives it.
enum UploadResults {
  /// Deletes the task's staged copy, records its outcome, and - if it was the
  /// last file of its batch - posts the summary notification and returns the
  /// finished batch.
  static func handle(_ task: URLSessionTask, error: Error?) -> (info: TransferTaskInfo, batch: TransferBatch?)? {
    guard let info = task.taskDescription
      .flatMap({ $0.data(using: .utf8) })
      .flatMap({ try? JSONDecoder().decode(TransferTaskInfo.self, from: $0) }),
      info.kind == .upload
    else { return nil }
    if let staged = info.stagedPath { try? FileManager.default.removeItem(atPath: staged) }
    let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
    let ok = error == nil && (200..<300).contains(status)
    let batch = TransferBatchStore.record(info, success: ok)
    if let batch { TransferNotifications.finished(batch, id: info.batch) }
    return (info, batch)
  }
}

/// Delegate for the Share Extension's upload session while the extension is
/// still alive: files that finish before it closes are counted here, the
/// rest by the app (`TransferManager`) once the system relaunches it.
final class ShareUploadDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let result = UploadResults.handle(task, error: error) else { return }
    // The app wasn't running to hear about this, so leave a note for it to
    // refresh that folder next time it's active.
    if let batch = result.batch, batch.succeeded > 0, let folder = batch.remoteFolder {
      TransferBatchStore.noteFinishedUpload(folder: folder)
    }
  }
}
