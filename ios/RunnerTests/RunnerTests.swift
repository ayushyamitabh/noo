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
}
