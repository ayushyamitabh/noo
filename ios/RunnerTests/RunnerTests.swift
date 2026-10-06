import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testFileURLEncodesEachSegment() {
    let url = WebDAV.fileURL(
      serverUrl: "https://cloud.example.com", username: "alice",
      remotePath: "/Tax Forms/2026 #1/a&b.pdf")
    XCTAssertEqual(
      url?.absoluteString,
      "https://cloud.example.com/remote.php/dav/files/alice/Tax%20Forms/2026%20%231/a&b.pdf")
  }

  func testFileURLKeepsServerSubPathAndDropsTrailingSlash() {
    let url = WebDAV.fileURL(
      serverUrl: "https://example.com/nextcloud/", username: "bob@home", remotePath: "docs/x.txt")
    XCTAssertEqual(
      url?.absoluteString,
      "https://example.com/nextcloud/remote.php/dav/files/bob@home/docs/x.txt")
  }

  func testFileURLForRoot() {
    XCTAssertEqual(
      WebDAV.fileURL(serverUrl: "https://c.io", username: "u", remotePath: "/")?.absoluteString,
      "https://c.io/remote.php/dav/files/u")
  }

  func testJoinUsesOneSlash() {
    XCTAssertEqual(WebDAV.join("/", "a.txt"), "/a.txt")
    XCTAssertEqual(WebDAV.join("/docs", "a.txt"), "/docs/a.txt")
    XCTAssertEqual(WebDAV.join("/docs/", "a.txt"), "/docs/a.txt")
  }

  func testUniqueURLNumbersCollisions() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("noo-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    XCTAssertEqual(LocalFiles.uniqueURL(in: dir, name: "a.txt").lastPathComponent, "a.txt")
    FileManager.default.createFile(atPath: dir.appendingPathComponent("a.txt").path, contents: nil)
    XCTAssertEqual(LocalFiles.uniqueURL(in: dir, name: "a.txt").lastPathComponent, "a (1).txt")
    FileManager.default.createFile(atPath: dir.appendingPathComponent("a (1).txt").path, contents: nil)
    XCTAssertEqual(LocalFiles.uniqueURL(in: dir, name: "a.txt").lastPathComponent, "a (2).txt")
    FileManager.default.createFile(atPath: dir.appendingPathComponent("README").path, contents: nil)
    XCTAssertEqual(LocalFiles.uniqueURL(in: dir, name: "README").lastPathComponent, "README (1)")
  }

  // MARK: - SharedInbox (Share Extension hand-off)

  private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("noo-inbox-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return root
  }

  private func makeSharedFile(in root: URL, name: String, contents: String = "hi") throws -> SharedItem {
    let batch = try SharedInbox.makeBatchDirectory(in: root)
    let file = batch.appendingPathComponent(name)
    try contents.write(to: file, atomically: true, encoding: .utf8)
    return SharedItem(path: file.path, name: name, mimeType: "text/plain", size: Int64(contents.utf8.count))
  }

  func testInboxConsumeReturnsAppendedItemsOnceThenNothing() throws {
    let root = try makeRoot()
    let a = try makeSharedFile(in: root, name: "a.txt")
    let b = try makeSharedFile(in: root, name: "b.txt")
    try SharedInbox.append([a], in: root)
    try SharedInbox.append([b], in: root)

    XCTAssertEqual(SharedInbox.consume(in: root), [a, b])
    XCTAssertEqual(SharedInbox.consume(in: root), [], "each share is delivered once")
  }

  func testInboxConsumeDropsFilesThatNoLongerExist() throws {
    let root = try makeRoot()
    let kept = try makeSharedFile(in: root, name: "kept.txt")
    let gone = try makeSharedFile(in: root, name: "gone.txt")
    try SharedInbox.append([kept, gone], in: root)
    try FileManager.default.removeItem(atPath: gone.path)

    XCTAssertEqual(SharedInbox.consume(in: root), [kept])
  }

  func testInboxConsumeWithNothingPendingIsEmpty() throws {
    XCTAssertEqual(SharedInbox.consume(in: try makeRoot()), [])
  }

  func testInboxAppendOfNothingCreatesNoManifest() throws {
    let root = try makeRoot()
    try SharedInbox.append([], in: root)
    XCTAssertEqual(SharedInbox.consume(in: root), [])
  }

  // MARK: - DavFolderParser (Share Extension folder picker)

  private func multistatus(_ responses: [(href: String, collection: Bool)]) -> Data {
    let body = responses.map { r in
      """
      <d:response><d:href>\(r.href)</d:href><d:propstat><d:prop>\
      <d:resourcetype>\(r.collection ? "<d:collection/>" : "")</d:resourcetype>\
      </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
      """
    }.joined()
    return Data(
      "<?xml version=\"1.0\"?><d:multistatus xmlns:d=\"DAV:\">\(body)</d:multistatus>".utf8)
  }

  func testFoldersListsOnlyChildFoldersSortedWithoutHidden() {
    let xml = multistatus([
      ("/remote.php/dav/files/alice/Docs/", true),
      ("/remote.php/dav/files/alice/Docs/zeta/", true),
      ("/remote.php/dav/files/alice/Docs/Tax%20Forms/", true),
      ("/remote.php/dav/files/alice/Docs/note.txt", false),
      ("/remote.php/dav/files/alice/Docs/.git/", true),
    ])
    XCTAssertEqual(
      DavFolderParser.folders(from: xml, excluding: "/Docs"),
      [DavFolder(name: "Tax Forms", path: "/Docs/Tax Forms"), DavFolder(name: "zeta", path: "/Docs/zeta")])
    XCTAssertEqual(
      DavFolderParser.folders(from: xml, excluding: "/Docs", includeHidden: true).map(\.name),
      [".git", "Tax Forms", "zeta"])
  }

  func testFoldersAtRootAndUnderServerSubPath() {
    let xml = multistatus([
      ("/nextcloud/remote.php/dav/files/bob/", true),
      ("/nextcloud/remote.php/dav/files/bob/Photos/", true),
    ])
    XCTAssertEqual(
      DavFolderParser.folders(from: xml, excluding: "/"),
      [DavFolder(name: "Photos", path: "/Photos")])
  }

  func testRelativePath() {
    XCTAssertEqual(DavFolderParser.relativePath(fromHref: "/remote.php/dav/files/a/B%20C/D/"), "/B C/D")
    XCTAssertEqual(DavFolderParser.relativePath(fromHref: "/remote.php/dav/files/a/"), "/")
    XCTAssertNil(DavFolderParser.relativePath(fromHref: "/somewhere/else"))
  }

  func testFoldersIgnoresGarbage() {
    XCTAssertEqual(DavFolderParser.folders(from: Data("not xml".utf8), excluding: "/"), [])
  }

  // MARK: - Shared account (Keychain group shared with the extension)

  func testSharedAccountRoundTripsThroughTheKeychain() throws {
    let account = SharedAccount(
      serverUrl: "https://cloud.example.com", username: "alice",
      authHeader: "Basic YWxpY2U6c2VjcmV0", displayName: "alice@cloud.example.com")
    addTeardownBlock { SharedAccountStore.clear() }

    SharedAccountStore.clear()
    XCTAssertNil(SharedAccountStore.load())
    try SharedAccountStore.save(account)
    XCTAssertEqual(SharedAccountStore.load(), account)

    let replacement = SharedAccount(
      serverUrl: "https://other.example.org", username: "bob", authHeader: "Basic Ym9i", displayName: "bob")
    try SharedAccountStore.save(replacement)
    XCTAssertEqual(SharedAccountStore.load(), replacement, "saving replaces, never duplicates")

    SharedAccountStore.clear()
    XCTAssertNil(SharedAccountStore.load())
  }

  // MARK: - TransferBatchStore

  func testBatchSummaryFiresOnlyOnTheLastFile() {
    let batchId = UUID().uuidString
    TransferBatchStore.save(
      TransferBatch(kind: .upload, remoteFolder: "/Docs", total: 3, succeeded: 0, failed: 0), id: batchId)
    let info = TransferTaskInfo(kind: .upload, batch: batchId, name: "a", remoteFolder: "/Docs", stagedPath: nil)

    XCTAssertNil(TransferBatchStore.record(info, success: true))
    XCTAssertNil(TransferBatchStore.record(info, success: false))
    let finished = TransferBatchStore.record(info, success: true)
    XCTAssertEqual(finished?.succeeded, 2)
    XCTAssertEqual(finished?.failed, 1)
    XCTAssertEqual(finished?.remoteFolder, "/Docs")
  }
}
