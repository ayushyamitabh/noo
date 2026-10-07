import XCTest

@testable import Runner

/// An in-memory Nextcloud that answers just enough WebDAV (PROPFIND depth 0/1,
/// GET, PUT) for the sync engine to run end to end against - with ancestor
/// etags bumping on every change, like the real thing.
final class FakeDav: URLProtocol {
  struct Node {
    var isFolder: Bool
    var data = Data()
    var etag: String
    var fileId: String
    var mtime = Date(timeIntervalSince1970: 1_700_000_000)
  }

  static var nodes: [String: Node] = [:]
  static var failAll = false
  /// A folder whose PROPFIND answers 500 while everything else works - for
  /// proving a half-built manifest is never trusted.
  static var failPropfindPath: String?
  /// Answer PROPFIND with a 207 whose XML is cut off mid-way.
  static var truncatePropfind = false
  static var log: [String] = []
  private static var counter = 0
  static let user = "alice"
  private static let base = "/remote.php/dav/files/alice"

  static func reset() {
    nodes = ["/": Node(isFolder: true, etag: nextTag(), fileId: "root")]
    failAll = false
    failPropfindPath = nil
    truncatePropfind = false
    log = []
    counter = 0
  }

  private static func nextTag() -> String {
    counter += 1
    return "tag\(counter)"
  }

  private static func parent(of path: String) -> String {
    let p = (path as NSString).deletingLastPathComponent
    return p.isEmpty ? "/" : p
  }

  /// Bumps [path]'s etag and every ancestor's.
  private static func touch(_ path: String) {
    var p = path
    while true {
      nodes[p]?.etag = nextTag()
      if p == "/" { break }
      p = parent(of: p)
    }
  }

  // MARK: Test-side helpers

  static func mkdir(_ path: String) {
    var parts: [String] = []
    for comp in path.split(separator: "/") {
      parts.append(String(comp))
      let p = "/" + parts.joined(separator: "/")
      if nodes[p] == nil {
        nodes[p] = Node(isFolder: true, etag: nextTag(), fileId: "id\(counter)")
        touch(parent(of: p))
      }
    }
  }

  static func put(_ path: String, _ text: String) {
    mkdir(parent(of: path))
    var node = nodes[path] ?? Node(isFolder: false, etag: "", fileId: "id\(nextTag())")
    node.data = Data(text.utf8)
    nodes[path] = node
    touch(path)
  }

  static func remove(_ path: String) {
    for key in nodes.keys where key == path || key.hasPrefix(path + "/") { nodes[key] = nil }
    touch(parent(of: path))
  }

  static func text(_ path: String) -> String? {
    nodes[path].flatMap { String(data: $0.data, encoding: .utf8) }
  }

  // MARK: URLProtocol

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let request = self.request
    let method = request.httpMethod ?? "GET"
    let depth = request.value(forHTTPHeaderField: "Depth") ?? "-"
    var path = (request.url?.path ?? "").removingPercentEncoding ?? ""
    if path.hasPrefix(Self.base) { path = String(path.dropFirst(Self.base.count)) }
    while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
    if path.isEmpty { path = "/" }
    Self.log.append("\(method) \(depth) \(path)")

    func send(_ status: Int, _ body: Data = Data()) {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }

    if Self.failAll { return send(503) }

    switch method {
    case "PROPFIND":
      if path == Self.failPropfindPath { return send(500) }
      guard Self.nodes[path] != nil else { return send(404) }
      var paths = [path]
      if depth == "1" {
        paths += Self.nodes.keys.filter { $0 != path && Self.parent(of: $0) == path }.sorted()
      }
      var body = Self.multistatus(paths)
      // Only folder listings: a cut-off *listing* still holds a few complete
      // responses, which is the dangerous case (a partial manifest).
      if Self.truncatePropfind && depth == "1" { body = String(body.prefix(body.count * 2 / 3)) }
      send(207, Data(body.utf8))
    case "GET":
      guard let node = Self.nodes[path], !node.isFolder else { return send(404) }
      send(200, node.data)
    case "PUT":
      var data = Data()
      if let stream = request.httpBodyStream {
        stream.open()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let n = stream.read(&buffer, maxLength: buffer.count)
          if n <= 0 { break }
          data.append(buffer, count: n)
        }
        stream.close()
      } else if let body = request.httpBody {
        data = body
      }
      Self.mkdir(Self.parent(of: path))
      var node = Self.nodes[path] ?? Node(isFolder: false, etag: "", fileId: "id\(Self.nextTag())")
      node.data = data
      Self.nodes[path] = node
      Self.touch(path)
      send(201)
    default:
      send(405)
    }
  }

  private static let httpDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return f
  }()

  private static func multistatus(_ paths: [String]) -> String {
    let responses = paths.map { p -> String in
      let node = nodes[p]!
      let encoded = p.split(separator: "/").map { WebDAV.encodeSegment(String($0)) }.joined(separator: "/")
      let href = base + (encoded.isEmpty ? "" : "/" + encoded) + (node.isFolder ? "/" : "")
      return """
        <d:response><d:href>\(href)</d:href><d:propstat><d:prop>\
        <d:getlastmodified>\(httpDate.string(from: node.mtime))</d:getlastmodified>\
        <d:getcontentlength>\(node.data.count)</d:getcontentlength>\
        <d:resourcetype>\(node.isFolder ? "<d:collection/>" : "")</d:resourcetype>\
        <d:getetag>"\(node.etag)"</d:getetag><oc:fileid>\(node.fileId)</oc:fileid>\
        </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        """
    }.joined()
    return """
      <?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">\(responses)</d:multistatus>
      """
  }
}

final class SyncEngineTests: XCTestCase {
  private var store: SyncStore!
  private var bus: SyncStatusBus!
  private var runner: SyncRunner!
  private var fakeSession: URLSession!
  private var clock: Int64 = 1_700_000_000_000
  private let config = SyncAccountConfig(
    accountId: "acct", serverUrl: "https://dav.test", username: "alice", authHeader: "Basic x",
    folders: ["/Docs"], wifiOnly: false, intervalMinutes: nil, notify: false)
  private var creds: SyncCredentials {
    SyncCredentials(serverUrl: config.serverUrl, username: config.username, authHeader: config.authHeader)
  }

  override func setUp() {
    super.setUp()
    FakeDav.reset()
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("noo-sync-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: base) }
    store = SyncStore(base: base)
    bus = SyncStatusBus()

    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [FakeDav.self]
    fakeSession = URLSession(configuration: sessionConfig)
    runner = SyncRunner(
      client: DavSyncClient(session: fakeSession),
      store: store, bus: bus, now: { [unowned self] in self.clock })
  }

  private func state() -> [String: SyncFileState] {
    (try? store.loadState(accountId: "acct")) ?? [:]
  }

  private var mirror: URL { store.syncRoot(accountId: "acct") }
  private func local(_ rel: String) -> String? {
    try? String(contentsOf: mirror.appendingPathComponent(rel), encoding: .utf8)
  }
  private func exists(_ rel: String) -> Bool {
    FileManager.default.fileExists(atPath: mirror.appendingPathComponent(rel).path)
  }
  private func editLocally(_ rel: String, _ text: String) throws {
    let url = mirror.appendingPathComponent(rel)
    try text.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
  }
  private func depth1Requests() -> Int { FakeDav.log.filter { $0.hasPrefix("PROPFIND 1") }.count }

  private func seedServer() {
    FakeDav.put("/Docs/a.txt", "alpha")
    FakeDav.put("/Docs/sub/b.txt", "bravo")
  }

  // MARK: - The happy path

  func testFirstSyncDownloadsEverythingAndMirrorsFolders() async {
    seedServer()
    FakeDav.mkdir("/Docs/empty")
    let summary = await runner.run(config, force: false)

    XCTAssertEqual(summary.downloaded, 2)
    XCTAssertEqual(local("Docs/a.txt"), "alpha")
    XCTAssertEqual(local("Docs/sub/b.txt"), "bravo")
    XCTAssertTrue(exists("Docs/empty"), "empty server folders are mirrored")
    XCTAssertEqual(state().count, 2)
    XCTAssertNotNil(store.loadRootMarkers(accountId: "acct")["/Docs"])
    XCTAssertFalse(bus.snapshot().syncing, "announced as finished")
  }

  func testUnchangedServerIsOneCheapRequestNotAWalk() async {
    seedServer()
    _ = await runner.run(config, force: false)
    let walks = depth1Requests()

    FakeDav.log = []
    let summary = await runner.run(config, force: false)
    XCTAssertFalse(summary.changedAnything)
    XCTAssertEqual(depth1Requests(), 0, "the root etag shortcut skipped the walk (was \(walks) before)")
    XCTAssertEqual(FakeDav.log, ["PROPFIND 0 /Docs"])
  }

  func testForceAlwaysWalks() async {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.log = []
    _ = await runner.run(config, force: true)
    XCTAssertGreaterThan(depth1Requests(), 0)
  }

  func testShortcutExpiresAfterTheMaxAge() async {
    seedServer()
    _ = await runner.run(config, force: false)
    clock += SyncRunner.fullWalkMaxAgeMs + 1
    FakeDav.log = []
    _ = await runner.run(config, force: false)
    XCTAssertGreaterThan(depth1Requests(), 0, "etags aren't trusted forever")
  }

  func testServerChangeIsDownloaded() async {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.put("/Docs/a.txt", "alpha v2")
    FakeDav.put("/Docs/new.txt", "fresh")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.downloaded, 2)
    XCTAssertEqual(local("Docs/a.txt"), "alpha v2")
    XCTAssertEqual(local("Docs/new.txt"), "fresh")
  }

  func testLocalEditIsUploadedOnceAndNotReDownloaded() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    try editLocally("Docs/a.txt", "alpha edited on phone")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.uploaded, 1)
    XCTAssertEqual(FakeDav.text("/Docs/a.txt"), "alpha edited on phone")

    let again = await runner.run(config, force: false)
    XCTAssertFalse(again.changedAnything, "our own upload must not come back as a server change")
    XCTAssertEqual(local("Docs/a.txt"), "alpha edited on phone")
  }

  func testFileDeletedLocallyIsPulledBack() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    try FileManager.default.removeItem(at: mirror.appendingPathComponent("Docs/a.txt"))

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.downloaded, 1)
    XCTAssertEqual(local("Docs/a.txt"), "alpha")
    XCTAssertNotNil(FakeDav.text("/Docs/a.txt"), "a local delete never deletes on the server")
  }

  // MARK: - Conflicts

  func testChangedOnBothSidesIsAConflictAndNothingIsOverwritten() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.put("/Docs/a.txt", "server edit")
    try editLocally("Docs/a.txt", "phone edit")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.conflicts.map(\.relPath), ["Docs/a.txt"])
    XCTAssertEqual(summary.conflicts.first?.name, "a.txt")
    XCTAssertEqual(local("Docs/a.txt"), "phone edit", "the device copy is untouched")
    XCTAssertEqual(FakeDav.text("/Docs/a.txt"), "server edit", "the server copy is untouched")
    XCTAssertEqual(bus.snapshot().conflicts.count, 1)
    XCTAssertNil(store.loadRootMarkers(accountId: "acct")["/Docs"], "an unresolved conflict forces a real walk next time")
  }

  func testResolveWithServerCopyThenNoConflictOnTheNextPass() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.put("/Docs/a.txt", "server edit")
    try editLocally("Docs/a.txt", "phone edit")
    let conflict = await runner.run(config, force: false).conflicts[0]

    let ok = await runner.resolveConflict(conflict, resolution: "server", creds: creds)
    XCTAssertTrue(ok)
    XCTAssertEqual(local("Docs/a.txt"), "server edit")
    XCTAssertTrue(bus.snapshot().conflicts.isEmpty)

    let next = await runner.run(config, force: false)
    XCTAssertTrue(next.conflicts.isEmpty)
    XCTAssertFalse(next.changedAnything)
  }

  func testResolveWithLocalCopyUploadsIt() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.put("/Docs/a.txt", "server edit")
    try editLocally("Docs/a.txt", "phone edit")
    let conflict = await runner.run(config, force: false).conflicts[0]

    let ok = await runner.resolveConflict(conflict, resolution: "local", creds: creds)
    XCTAssertTrue(ok)
    XCTAssertEqual(FakeDav.text("/Docs/a.txt"), "phone edit")
    let next = await runner.run(config, force: false)
    XCTAssertTrue(next.conflicts.isEmpty && !next.changedAnything)
  }

  func testAnUnknownResolutionDoesNothing() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.put("/Docs/a.txt", "server edit")
    try editLocally("Docs/a.txt", "phone edit")
    let conflict = await runner.run(config, force: false).conflicts[0]

    let ok = await runner.resolveConflict(conflict, resolution: "bogus", creds: creds)
    XCTAssertFalse(ok)
    XCTAssertEqual(local("Docs/a.txt"), "phone edit")
    XCTAssertEqual(FakeDav.text("/Docs/a.txt"), "server edit")
  }

  // MARK: - Deletes (the dangerous part)

  func testFileDeletedOnTheServerIsRemovedLocally() async {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.remove("/Docs/a.txt")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.deleted, 1)
    XCTAssertFalse(exists("Docs/a.txt"))
    XCTAssertTrue(exists("Docs/sub/b.txt"), "only the deleted file goes")
  }

  func testFolderDeletedOnTheServerRemovesItsFilesAndTheEmptyDirectory() async {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.remove("/Docs/sub")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.deleted, 1)
    XCTAssertFalse(exists("Docs/sub/b.txt"))
    XCTAssertFalse(exists("Docs/sub"), "the now-empty directory is pruned")
    XCTAssertTrue(exists("Docs/a.txt"))
  }

  func testAnUnreachableServerNeverDeletesAnything() async {
    seedServer()
    _ = await runner.run(config, force: false)
    let before = state()

    FakeDav.failAll = true
    let summary = await runner.run(config, force: true)
    XCTAssertFalse(summary.changedAnything, "a 503 is not an empty folder")
    XCTAssertEqual(local("Docs/a.txt"), "alpha")
    XCTAssertEqual(local("Docs/sub/b.txt"), "bravo")
    XCTAssertEqual(state(), before)
    XCTAssertTrue(store.loadMissingRoots(accountId: "acct").isEmpty, "unreachable is not 'gone'")

    FakeDav.failAll = false
    let recovered = await runner.run(config, force: true)
    XCTAssertFalse(recovered.changedAnything)
    XCTAssertEqual(local("Docs/a.txt"), "alpha")
  }

  func testAPartiallyFailingWalkDoesNotLookLikeAMassDeletion() async {
    seedServer()
    _ = await runner.run(config, force: false)
    // Only the subfolder listing breaks: a half-built manifest must not make
    // sub/b.txt look deleted.
    FakeDav.nodes["/Docs/sub"]?.etag = "changed"
    FakeDav.nodes["/Docs"]?.etag = "changed"
    FakeDav.failPropfindPath = "/Docs/sub"

    let summary = await runner.run(config, force: true)
    XCTAssertEqual(summary.deleted, 0)
    XCTAssertEqual(local("Docs/sub/b.txt"), "bravo")
    XCTAssertEqual(local("Docs/a.txt"), "alpha")
  }

  func testAPathDeletedOnTheServerIsFlaggedAndItsMirrorRemoved() async {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.remove("/Docs")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.deleted, 2)
    XCTAssertEqual(store.loadMissingRoots(accountId: "acct"), ["/Docs"])
    XCTAssertFalse(exists("Docs/a.txt"))
  }

  // MARK: - Single files, scoping, housekeeping

  func testASyncedSingleFilePath() async {
    FakeDav.put("/Notes/todo.txt", "buy milk")
    var single = config
    single.folders = ["/Notes/todo.txt"]

    let summary = await runner.run(single, force: false)
    XCTAssertEqual(summary.downloaded, 1)
    XCTAssertEqual(local("Notes/todo.txt"), "buy milk")
    FakeDav.put("/Notes/todo.txt", "buy milk and eggs")
    _ = await runner.run(single, force: false)
    XCTAssertEqual(local("Notes/todo.txt"), "buy milk and eggs")
  }

  func testSyncOnlyTouchesTheConfiguredPaths() async {
    seedServer()
    FakeDav.put("/Other/x.txt", "not synced")
    _ = await runner.run(config, force: false)
    XCTAssertFalse(exists("Other/x.txt"))
  }

  func testNothingConfiguredDoesNothing() async {
    seedServer()
    var empty = config
    empty.folders = []
    let summary = await runner.run(empty, force: true)
    XCTAssertEqual(summary, SyncRunSummary())
    XCTAssertTrue(FakeDav.log.isEmpty)
  }

  func testRemoveLocalSyncForgetsThePathSoItComesBackOnReAdd() async {
    seedServer()
    _ = await runner.run(config, force: false)
    store.removeLocalSync(accountId: "acct", path: "/Docs/sub")

    XCTAssertFalse(exists("Docs/sub/b.txt"))
    XCTAssertTrue(exists("Docs/a.txt"))
    XCTAssertEqual(state().count, 1)
    XCTAssertNil(store.loadRootMarkers(accountId: "acct")["/Docs"], "an ancestor's marker would skip the re-download")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.downloaded, 1)
    XCTAssertEqual(local("Docs/sub/b.txt"), "bravo")
  }

  func testStatusMarksFilesAsSyncingDuringTheRun() async {
    seedServer()
    var seen = Set<String>()
    bus.onChange = { seen.formUnion($0.syncingFileIds) }
    _ = await runner.run(config, force: false)
    XCTAssertEqual(seen.count, 2, "each transferring file was announced")
    XCTAssertTrue(bus.snapshot().syncingFileIds.isEmpty)
  }

  func testStaleMarkersForRemovedPathsAreDropped() async {
    seedServer()
    _ = await runner.run(config, force: false)
    var other = config
    other.folders = ["/Other"]
    FakeDav.mkdir("/Other")
    _ = await runner.run(other, force: false)
    XCTAssertNil(store.loadRootMarkers(accountId: "acct")["/Docs"])
  }

  // MARK: - Parsing

  func testParserReadsEtagFileIdSizeAndDates() {
    let xml = Data(
      """
      <?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
      <d:response><d:href>/nextcloud/remote.php/dav/files/alice/Docs/</d:href><d:propstat><d:prop>
        <d:resourcetype><d:collection/></d:resourcetype><d:getetag>"abc123"</d:getetag>
        <oc:fileid>7</oc:fileid></d:prop></d:propstat></d:response>
      <d:response><d:href>/nextcloud/remote.php/dav/files/alice/Docs/Tax%20Forms.pdf</d:href><d:propstat><d:prop>
        <d:getlastmodified>Tue, 14 Nov 2023 22:13:20 GMT</d:getlastmodified>
        <d:getcontentlength>2048</d:getcontentlength><d:resourcetype/>
        <d:getetag>"e1"</d:getetag><oc:fileid>9</oc:fileid></d:prop></d:propstat></d:response>
      </d:multistatus>
      """.utf8)
    let entries = try! DavSyncParser.entries(from: xml, username: "alice", requestedPath: "/Docs", skipSelf: true)
    XCTAssertEqual(entries.count, 1, "the folder itself is skipped")
    XCTAssertEqual(entries[0].path, "/Docs/Tax Forms.pdf")
    XCTAssertEqual(entries[0].etag, "e1", "quotes are stripped")
    XCTAssertEqual(entries[0].fileId, "9")
    XCTAssertEqual(entries[0].size, 2048)
    XCTAssertEqual(entries[0].lastModified, 1_700_000_000_000)
    XCTAssertFalse(entries[0].isFolder)

    let all = try! DavSyncParser.entries(from: xml, username: "alice", requestedPath: "/Docs", skipSelf: false)
    XCTAssertEqual(all.map(\.path), ["/Docs", "/Docs/Tax Forms.pdf"])
    XCTAssertTrue(all[0].isFolder)
  }

  func testParserRefusesAnythingThatIsNotACompleteAnswer() {
    func entries(_ xml: String) throws -> [SyncRemoteEntry] {
      try DavSyncParser.entries(from: Data(xml.utf8), username: "alice", requestedPath: "/Docs", skipSelf: false)
    }
    XCTAssertThrowsError(try entries("nope"), "not XML")
    XCTAssertThrowsError(try entries("<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/remote.php"), "truncated")
    XCTAssertThrowsError(
      try entries(
        "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/remote.php/dav/files/alice/Docs/a.txt</d:href></d:response>"
          + "<d:response><d:href>/remote.php/dav/files/alice/Docs/b"),
      "one complete response, then cut off: a partial manifest")
    XCTAssertThrowsError(try entries("<html><body>Maintenance</body></html>"), "well-formed but not a multistatus")
    XCTAssertThrowsError(try entries("<d:multistatus xmlns:d=\"DAV:\"></d:multistatus>"), "a 207 always has the resource itself")
  }

  func testParserRefusesHrefsOutsideTheAccountRootOrClimbingOut() {
    func parse(_ href: String) throws -> [SyncRemoteEntry] {
      let xml = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>\(href)</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response></d:multistatus>"
      return try DavSyncParser.entries(from: Data(xml.utf8), username: "alice", requestedPath: "/", skipSelf: false)
    }
    XCTAssertNoThrow(try parse("/remote.php/dav/files/alice/Docs/a.txt"))
    XCTAssertThrowsError(try parse("/remote.php/dav/files/alice/../bob/secret.txt"), "dot-dot component")
    XCTAssertThrowsError(try parse("/remote.php/dav/files/alice/Docs/%2E%2E/%2E%2E/x"), "encoded dot-dot")
    XCTAssertThrowsError(try parse("/somewhere/else/a.txt"), "not under the files root")
    XCTAssertThrowsError(try parse("/remote.php/dav/files/alicia/a.txt"), "another user's root that merely starts the same")
  }

  // MARK: - Review findings: each of these used to lose or misplace data

  func testATruncatedAnswerIsNotAManifest() async {
    seedServer()
    _ = await runner.run(config, force: false)
    FakeDav.truncatePropfind = true

    let summary = await runner.run(config, force: true)
    XCTAssertFalse(summary.changedAnything, "half a listing must not look like deletions")
    XCTAssertEqual(local("Docs/a.txt"), "alpha")
    XCTAssertEqual(local("Docs/sub/b.txt"), "bravo")
    XCTAssertTrue(store.loadMissingRoots(accountId: "acct").isEmpty, "nor like the folder being gone")
  }

  func testDeletedOnTheServerButEditedHereIsKept() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    try editLocally("Docs/a.txt", "my only copy of this edit")
    FakeDav.remove("/Docs/a.txt")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.deleted, 0)
    XCTAssertEqual(local("Docs/a.txt"), "my only copy of this edit")
    XCTAssertNil(state().first { $0.value.relPath == "Docs/a.txt" }, "no longer tracked")

    let again = await runner.run(config, force: false)
    XCTAssertEqual(local("Docs/a.txt"), "my only copy of this edit", "and not touched later either")
    XCTAssertFalse(again.changedAnything)
  }

  func testSyncingTheWholeAccountNoticesServerDeletions() async {
    FakeDav.put("/a.txt", "top")
    FakeDav.put("/sub/b.txt", "nested")
    var everything = config
    everything.folders = ["/"]

    _ = await runner.run(everything, force: false)
    XCTAssertEqual(local("a.txt"), "top")
    FakeDav.log = []
    _ = await runner.run(everything, force: false)
    XCTAssertEqual(depth1Requests(), 0, "the root shortcut works for '/' too")

    FakeDav.remove("/a.txt")
    let summary = await runner.run(everything, force: false)
    XCTAssertEqual(summary.deleted, 1)
    XCTAssertFalse(exists("a.txt"))
    XCTAssertTrue(exists("sub/b.txt"))
  }

  func testAPathNeverClaimsASiblingWithTheSamePrefix() {
    let entry = { (rel: String) in SyncFileState(relPath: rel, etag: "e", lastModified: 0, size: 1, localMTime: 1) }
    let state = ["1": entry("Docs/a.txt"), "2": entry("Docs2/b.txt"), "3": entry("Documents/c.txt"), "4": entry("Docs")]
    XCTAssertEqual(SyncDiff.priorFileIds(state: state, path: "/Docs"), ["1", "4"])
    XCTAssertEqual(SyncDiff.priorFileIds(state: state, path: "/Docs/"), ["1", "4"])
    XCTAssertEqual(SyncDiff.priorFileIds(state: state, path: "/"), ["1", "2", "3", "4"], "the root covers everything")
  }

  func testTwoRemoteNamesForOneLocalFileAreNeitherDownloaded() async {
    FakeDav.put("/Docs/a.txt", "lower")
    FakeDav.put("/Docs/A.txt", "upper")
    FakeDav.put("/Docs/fine.txt", "ok")

    let summary = await runner.run(config, force: false)
    XCTAssertEqual(summary.downloaded, 1, "only the file with no collision")
    XCTAssertEqual(local("Docs/fine.txt"), "ok")
    XCTAssertNil(local("Docs/a.txt"), "neither of the colliding pair overwrote the other")
    XCTAssertNil(store.loadRootMarkers(accountId: "acct")["/Docs"], "and the path isn't called clean")
    let unicode = SyncDiff.collidingRelPaths([
      SyncRemoteEntry(path: "/x/\u{C4}.txt", fileId: "1", etag: "", lastModified: 0, size: 0, isFolder: false),
      SyncRemoteEntry(path: "/x/A\u{308}.txt", fileId: "2", etag: "", lastModified: 0, size: 0, isFolder: false),
    ])
    XCTAssertTrue(unicode.contains("x/\u{C4}.txt") && unicode.contains("x/A\u{308}.txt"),
      "canonically equivalent Unicode spellings collide too")
    XCTAssertTrue(
      SyncDiff.collidingRelPaths([
        SyncRemoteEntry(path: "/x/same.txt", fileId: "1", etag: "", lastModified: 0, size: 0, isFolder: false)
      ]).isEmpty, "one spelling is never a collision")
  }

  func testServerPathsCanNeverLeaveTheMirror() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("noo-root-\(UUID().uuidString)")
    XCTAssertNotNil(LocalFS.resolve("Docs/a.txt", in: root))
    XCTAssertNil(LocalFS.resolve("../outside.txt", in: root))
    XCTAssertNil(LocalFS.resolve("Docs/../../outside.txt", in: root))
    XCTAssertNil(LocalFS.resolve("./x", in: root))
    XCTAssertNil(LocalFS.resolve("", in: root))
    XCTAssertNil(LocalFS.resolve("/", in: root))
  }

  func testAnUnreadableStateMakesTheRunDoNothing() async throws {
    seedServer()
    _ = await runner.run(config, force: false)
    try editLocally("Docs/a.txt", "unsynced local edit")
    let stateFile = store.base.appendingPathComponent("sync-state/acct/state.json")
    try Data("{ this is not json".utf8).write(to: stateFile)
    FakeDav.log = []

    let summary = await runner.run(config, force: true)
    XCTAssertEqual(summary, SyncRunSummary())
    XCTAssertEqual(local("Docs/a.txt"), "unsynced local edit", "an untracked-looking file must not be overwritten")
    XCTAssertTrue(FakeDav.log.isEmpty, "it didn't even talk to the server")
    XCTAssertThrowsError(try store.loadState(accountId: "acct"))
    XCTAssertEqual(try Data(contentsOf: stateFile), Data("{ this is not json".utf8), "the corrupt file isn't overwritten")
  }

  func testNoStateYetIsJustAFirstSyncNotAnError() throws {
    XCTAssertEqual(try store.loadState(accountId: "brand-new"), [:])
  }

  func testADownloadNeverReplacesAFolderOrDestroysTheOldCopyOnFailure() async throws {
    FakeDav.put("/Docs/a.txt", "server")
    let client = DavSyncClient(session: fakeSession)
    let folder = mirror.appendingPathComponent("Docs/a.txt")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "inside".write(to: folder.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

    let ok = try await client.download(creds, remotePath: "/Docs/a.txt", to: folder)
    XCTAssertFalse(ok, "a folder is not replaced by a file")
    XCTAssertEqual(local("Docs/a.txt/keep.txt"), "inside")

    let file = mirror.appendingPathComponent("Docs/b.txt")
    try "old".write(to: file, atomically: true, encoding: .utf8)
    FakeDav.put("/Docs/b.txt", "new")
    let replaced = try await client.download(creds, remotePath: "/Docs/b.txt", to: file)
    XCTAssertTrue(replaced)
    XCTAssertEqual(local("Docs/b.txt"), "new")
    FakeDav.failAll = true
    let failed = try await client.download(creds, remotePath: "/Docs/b.txt", to: file)
    XCTAssertFalse(failed)
    XCTAssertEqual(local("Docs/b.txt"), "new", "a failed download leaves what was there")
  }

  func testRemovingTheWholeRootForgetsEveryFile() async {
    seedServer()
    _ = await runner.run(config, force: false)
    store.removeLocalSync(accountId: "acct", path: "/")
    XCTAssertTrue(state().isEmpty, "'/' covers everything recorded")
    XCTAssertFalse(exists("Docs/a.txt"))
  }

  func testPruningNeverRemovesAFolderThatHoldsSomething() throws {
    let root = mirror
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Docs/stale"), withIntermediateDirectories: true)
    try "mine".write(to: root.appendingPathComponent("Docs/stale/note.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Docs/empty-stale"), withIntermediateDirectories: true)

    SyncDiff.pruneRemovedFolders(syncRoot: root, rootRel: "Docs", remoteFolders: ["Docs"])
    XCTAssertEqual(local("Docs/stale/note.txt"), "mine")
    XCTAssertFalse(exists("Docs/empty-stale"), "an empty folder the server no longer has goes")
  }

  // MARK: - Status, coordinator, config store, mutex

  func testConflictsAreKeptPerAccount() {
    let a = SyncConflict(accountId: "A", fileId: "7", remotePath: "/x", relPath: "x", name: "x")
    let b = SyncConflict(accountId: "B", fileId: "7", remotePath: "/y", relPath: "y", name: "y")
    bus.addConflicts(accountId: "A", [a])
    bus.addConflicts(accountId: "B", [b])
    XCTAssertEqual(bus.snapshot().conflicts.count, 2, "same file id, different accounts: both kept")

    let coordinator = SyncCoordinator(
      store: store, bus: bus, configs: SyncConfigStore(service: "test-\(UUID().uuidString)"), client: DavSyncClient())
    let forB = coordinator.statusMap(bus.snapshot(), accountIdOverride: "B")["conflicts"] as? [[String: String]]
    XCTAssertEqual(forB?.map { $0["relPath"] }, ["y"], "B never sees A's conflicts")

    bus.removeConflict(accountId: "A", fileId: "7")
    XCTAssertEqual(bus.snapshot().conflicts, [b], "removing A's leaves B's")
  }

  func testSignOutForgetsCredentialsButTurningBackgroundOffKeepsThem() {
    let service = "test-\(UUID().uuidString)"
    let configs = SyncConfigStore(service: service)
    addTeardownBlock { configs.removeAll() }
    let coordinator = SyncCoordinator(store: store, bus: bus, configs: configs, client: DavSyncClient())
    var withBackground = config
    withBackground.intervalMinutes = 30

    coordinator.reschedule(withBackground)
    XCTAssertEqual(configs.config(for: "acct")?.intervalMinutes, 30)

    coordinator.cancel(accountId: "acct", forget: false)
    XCTAssertNotNil(configs.config(for: "acct"), "conflict actions and Sync now still need the credentials")
    XCTAssertNil(configs.config(for: "acct")?.intervalMinutes, "but nothing is scheduled")

    coordinator.cancel(accountId: "acct", forget: true)
    XCTAssertNil(configs.config(for: "acct"), "signing out forgets them")
  }

  func testConfigStoreHoldsSeveralAccountsAndUpdatesInPlace() {
    let configs = SyncConfigStore(service: "test-\(UUID().uuidString)")
    addTeardownBlock { configs.removeAll() }
    let second = SyncAccountConfig(
      accountId: "other", serverUrl: "https://o", username: "bob", authHeader: "Basic y",
      folders: ["/x"], wifiOnly: true, intervalMinutes: 60, notify: true)

    XCTAssertTrue(configs.upsert(config))
    XCTAssertTrue(configs.upsert(second))
    XCTAssertEqual(configs.all().map(\.accountId), ["acct", "other"])

    var changed = config
    changed.folders = ["/Docs", "/More"]
    XCTAssertTrue(configs.upsert(changed))
    XCTAssertEqual(configs.config(for: "acct")?.folders, ["/Docs", "/More"])
    XCTAssertEqual(configs.config(for: "other"), second, "updating one leaves the others")

    XCTAssertTrue(configs.remove(accountId: "acct"))
    XCTAssertEqual(configs.all().map(\.accountId), ["other"])
    XCTAssertTrue(configs.remove(accountId: "never-existed"))
  }

  func testAQueuedWaiterThatIsCancelledLeavesTheQueueAtOnce() async throws {
    let mutex = AsyncMutex()
    let holderStarted = expectation(description: "holder has the lock")
    let holder = Task {
      try await mutex.withLock {
        holderStarted.fulfill()
        try await Task.sleep(nanoseconds: 1_500_000_000)
      }
    }
    await fulfillment(of: [holderStarted], timeout: 5)

    let waiter = Task { try await mutex.withLock { "ran" } }
    try await Task.sleep(nanoseconds: 100_000_000)
    let cancelledAt = Date()
    waiter.cancel()
    do {
      _ = try await waiter.value
      XCTFail("a cancelled waiter must not run")
    } catch {
      XCTAssertTrue(error is CancellationError)
      XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 0.8, "it didn't wait for the 1.5s holder")
    }

    try await holder.value
    let next = try await mutex.withLock { "next" }
    XCTAssertEqual(next, "next", "the lock is free for the next one")
  }

  private final class Counter: @unchecked Sendable {
    var running = 0
    var maxRunning = 0
    var finished = 0
  }

  func testAMutexNeverRunsTwoBodiesAtOnce() async throws {
    let mutex = AsyncMutex()
    let counter = Counter()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<6 {
        group.addTask {
          _ = try? await mutex.withLock {
            counter.running += 1
            counter.maxRunning = max(counter.maxRunning, counter.running)
            try? await Task.sleep(nanoseconds: 10_000_000)
            counter.running -= 1
            counter.finished += 1
          }
        }
      }
    }
    XCTAssertEqual(counter.finished, 6)
    XCTAssertEqual(counter.maxRunning, 1)
  }

  func testOnceGateCompletesOnlyOnce() {
    var calls: [Bool] = []
    let gate = OnceGate { calls.append($0) }
    gate.finish(false)
    gate.finish(true)
    XCTAssertEqual(calls, [false])
  }
}
