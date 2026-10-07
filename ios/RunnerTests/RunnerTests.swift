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
      DavFolderParser.folders(from: xml, excluding: "/Docs", hidden: .include).map(\.name),
      [".git", "Tax Forms", "zeta"])
    XCTAssertEqual(
      DavFolderParser.folders(from: xml, excluding: "/Docs", hidden: .only).map(\.name),
      [".git"])
  }

  func testHiddenFilterTreatsAnyDotSegmentAsHidden() {
    XCTAssertTrue(HiddenFilter.isHidden(path: "/.cache"))
    XCTAssertTrue(HiddenFilter.isHidden(path: "/.cache/inside/deeper"), "children of a hidden folder are hidden")
    XCTAssertFalse(HiddenFilter.isHidden(path: "/Docs/Tax Forms"))
    XCTAssertTrue(HiddenFilter.hide.shows(path: "/Docs"))
    XCTAssertFalse(HiddenFilter.hide.shows(path: "/.git"))
    XCTAssertTrue(HiddenFilter.only.shows(path: "/.git/hooks"))
    XCTAssertFalse(HiddenFilter.only.shows(path: "/Docs"))
    XCTAssertTrue(HiddenFilter.include.shows(path: "/Docs"))
    XCTAssertEqual(HiddenFilter(raw: "include"), .include)
    XCTAssertEqual(HiddenFilter(raw: "nonsense"), .hide, "unknown values fall back to hiding")
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

  private func account(_ id: String, hidden: String = "hide") -> SharedAccount {
    SharedAccount(
      id: id, serverUrl: "https://\(id).example.com", username: id,
      authHeader: "Basic \(id)", displayName: "\(id)@\(id).example.com", hiddenFilter: hidden)
  }

  func testSharedAccountsRoundTripThroughTheKeychain() throws {
    let accounts = SharedAccounts(
      accounts: [account("alice", hidden: "include"), account("bob")], activeId: "bob",
      loginLockEnabled: true, lockAccountSwitching: true, lockHiddenFiles: false)
    addTeardownBlock { SharedAccountStore.clear() }

    SharedAccountStore.clear()
    XCTAssertNil(SharedAccountStore.load())
    try SharedAccountStore.save(accounts)
    XCTAssertEqual(SharedAccountStore.load(), accounts)

    let replacement = SharedAccounts(
      accounts: [account("carol")], activeId: "carol",
      loginLockEnabled: false, lockAccountSwitching: false, lockHiddenFiles: false)
    try SharedAccountStore.save(replacement)
    XCTAssertEqual(SharedAccountStore.load(), replacement, "saving replaces, never duplicates")

    SharedAccountStore.clear()
    XCTAssertNil(SharedAccountStore.load())
  }

  func testSharedAccountsActiveFallsBackToTheFirstAccount() {
    var shared = SharedAccounts(
      accounts: [account("alice"), account("bob")], activeId: "bob",
      loginLockEnabled: false, lockAccountSwitching: false, lockHiddenFiles: false)
    XCTAssertEqual(shared.active?.id, "bob")
    shared.activeId = "gone"
    XCTAssertEqual(shared.active?.id, "alice")
    shared.activeId = nil
    XCTAssertEqual(shared.active?.id, "alice")
  }

  func testUnlockRulesAreIndependentOfLoginLock() {
    func rules(master: Bool, switching: Bool, hidden: Bool) -> (Bool, Bool) {
      let shared = SharedAccounts(
        accounts: [account("a")], activeId: "a",
        loginLockEnabled: master, lockAccountSwitching: switching, lockHiddenFiles: hidden)
      return (shared.needsUnlockToSwitchAccount, shared.needsUnlockForHidden)
    }
    XCTAssertTrue(rules(master: false, switching: true, hidden: false) == (true, false))
    XCTAssertTrue(rules(master: false, switching: false, hidden: true) == (false, true))
    XCTAssertTrue(rules(master: true, switching: false, hidden: false) == (false, false))
    XCTAssertTrue(rules(master: true, switching: true, hidden: true) == (true, true))
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

  func testFinishedUploadFoldersAreNotedOnceAndConsumed() {
    _ = TransferBatchStore.consumeFinishedUploadFolders()  // start clean
    TransferBatchStore.noteFinishedUpload(folder: "/Docs")
    TransferBatchStore.noteFinishedUpload(folder: "/Docs")
    TransferBatchStore.noteFinishedUpload(folder: "/Photos")

    XCTAssertEqual(TransferBatchStore.consumeFinishedUploadFolders(), ["/Docs", "/Photos"])
    XCTAssertEqual(TransferBatchStore.consumeFinishedUploadFolders(), [])
  }

  func testNotificationFileCountWording() {
    XCTAssertEqual(TransferNotifications.files(1), "1 file")
    XCTAssertEqual(TransferNotifications.files(3), "3 files")
  }

  // MARK: - External storage + tolerant decoding

  func testFoldersFlagExternalMountsAndStorageFilterAppliesToThem() {
    let xml = Data(
      """
      <?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:nc="http://nextcloud.org/ns">
      <d:response><d:href>/remote.php/dav/files/a/</d:href><d:propstat><d:prop>
        <d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
      <d:response><d:href>/remote.php/dav/files/a/NAS/</d:href><d:propstat><d:prop>
        <d:resourcetype><d:collection/></d:resourcetype><nc:mount-type>external</nc:mount-type>
        </d:prop></d:propstat></d:response>
      <d:response><d:href>/remote.php/dav/files/a/Docs/</d:href><d:propstat><d:prop>
        <d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
      <d:response><d:href>/remote.php/dav/files/a/Shared/</d:href><d:propstat><d:prop>
        <d:resourcetype><d:collection/></d:resourcetype><nc:mount-type>shared</nc:mount-type>
        </d:prop></d:propstat></d:response>
      </d:multistatus>
      """.utf8)
    let folders = DavFolderParser.folders(from: xml, excluding: "/")
    XCTAssertEqual(folders.map(\.name), ["Docs", "NAS", "Shared"])
    XCTAssertEqual(folders.map(\.isExternal), [false, true, false], "only mount-type=external counts")

    XCTAssertTrue(StorageFilter.cloud.shows(isExternal: false))
    XCTAssertFalse(StorageFilter.cloud.shows(isExternal: true))
    XCTAssertTrue(StorageFilter.external.shows(isExternal: true))
    XCTAssertFalse(StorageFilter.external.shows(isExternal: false))
    XCTAssertTrue(StorageFilter.all.shows(isExternal: true) && StorageFilter.all.shows(isExternal: false))
    XCTAssertEqual(StorageFilter(raw: "bogus"), .cloud)
  }

  func testSharedAccountDecodesDataWrittenBeforeNewFieldsExisted() throws {
    let old = Data(
      """
      {"id":"a","serverUrl":"https://x","username":"u","authHeader":"Basic x","displayName":"u@x"}
      """.utf8)
    let decoded = try JSONDecoder().decode(SharedAccount.self, from: old)
    XCTAssertEqual(decoded.hiddenFilter, "hide")
    XCTAssertEqual(decoded.storageScope, "cloud")
  }
}
