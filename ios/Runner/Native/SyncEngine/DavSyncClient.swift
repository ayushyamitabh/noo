import Foundation

/// Credentials for one account's WebDAV root.
struct SyncCredentials {
  let serverUrl: String
  let username: String
  let authHeader: String
}

/// The WebDAV calls sync needs: PROPFIND (a folder's children, or one item),
/// a recursive walk, and GET/PUT of a single file. Foreground
/// `URLSession` work - sync runs inside the app or a `BGTask`, not on a
/// background session, so a run can walk, diff and decide in one go.
///
/// Authenticates by each request's own `Authorization` header only (no cookies,
/// no credential cache): two accounts can share a server, and one account's
/// session must never answer for another.
final class DavSyncClient {
  private let session: URLSession

  init(session: URLSession = DavSyncClient.makeSession()) {
    self.session = session
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.urlCredentialStorage = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 15 * 60
    return URLSession(configuration: config)
  }

  // MARK: - PROPFIND

  private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8" ?>
    <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
      <d:prop>
        <d:getlastmodified/>
        <d:getcontentlength/>
        <d:resourcetype/>
        <d:getetag/>
        <oc:fileid/>
      </d:prop>
    </d:propfind>
    """

  /// Depth-1 PROPFIND of [path]: its direct children only. A clean 404 (the
  /// folder is genuinely gone) is an empty list; anything else that goes wrong
  /// throws `SyncRemoteUnavailable`.
  func propfindChildren(_ creds: SyncCredentials, path: String) async throws -> [SyncRemoteEntry] {
    try await propfind(creds, path: path, depth: "1", skipSelf: true)
  }

  /// Depth-0 PROPFIND of [path] itself - nil on a clean 404.
  func propfindSelf(_ creds: SyncCredentials, path: String) async throws -> SyncRemoteEntry? {
    try await propfind(creds, path: path, depth: "0", skipSelf: false).first
  }

  private func propfind(
    _ creds: SyncCredentials, path: String, depth: String, skipSelf: Bool
  ) async throws -> [SyncRemoteEntry] {
    var clean = path.trimmingCharacters(in: .whitespaces)
    if !clean.hasPrefix("/") { clean = "/" + clean }
    guard var url = WebDAV.fileURL(serverUrl: creds.serverUrl, username: creds.username, remotePath: clean)
    else { throw SyncRemoteUnavailable(message: "Invalid server address.") }
    // Collections are addressed with a trailing slash.
    if depth == "1", let slashed = URL(string: url.absoluteString + "/") { url = slashed }

    var request = URLRequest(url: url)
    request.httpMethod = "PROPFIND"
    request.setValue(depth, forHTTPHeaderField: "Depth")
    request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
    request.setValue(creds.authHeader, forHTTPHeaderField: "Authorization")
    request.httpBody = Self.propfindBody.data(using: .utf8)

    let data: Data
    let status: Int
    do {
      let (body, response) = try await session.data(for: request)
      data = body
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
      try Self.rethrowIfCancelled(error)
      throw SyncRemoteUnavailable(message: "PROPFIND \(url.path) failed: \(error.localizedDescription)")
    }
    if status == 404 { return [] }  // genuinely gone
    guard status == 207 else {
      throw SyncRemoteUnavailable(message: "PROPFIND \(url.path) -> \(status)")
    }
    return try DavSyncParser.entries(from: data, username: creds.username, requestedPath: clean, skipSelf: skipSelf)
  }

  /// Recursively walks [root] (Depth-1 PROPFINDs, breadth-first) into a flat
  /// manifest. Throws if *any* level fails - a partial manifest would look
  /// like the missing part had been deleted on the server.
  func walk(_ creds: SyncCredentials, root: String) async throws -> [SyncRemoteEntry] {
    var result: [SyncRemoteEntry] = []
    var queue = [root]
    var index = 0
    while index < queue.count {
      try Task.checkCancellation()
      let children = try await propfindChildren(creds, path: queue[index])
      index += 1
      for child in children {
        result.append(child)
        if child.isFolder { queue.append(child.path) }
      }
    }
    return result
  }

  // MARK: - GET / PUT

  /// Downloads [remotePath] to [destination]. Written to a temp file first and
  /// moved into place, so an interrupted download never leaves a truncated
  /// file where a good one used to be. False on any failure.
  func download(_ creds: SyncCredentials, remotePath: String, to destination: URL) async throws -> Bool {
    guard let url = WebDAV.fileURL(serverUrl: creds.serverUrl, username: creds.username, remotePath: remotePath)
    else { return false }
    var request = URLRequest(url: url)
    request.setValue(creds.authHeader, forHTTPHeaderField: "Authorization")
    do {
      let (temp, response) = try await session.download(for: request)
      guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
        try? FileManager.default.removeItem(at: temp)
        return false
      }
      try Task.checkCancellation()
      let fm = FileManager.default
      try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      var isDirectory: ObjCBool = false
      if fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
        // Never replace a folder with a file, and replace a file atomically:
        // the old copy stays until the new one is fully in place.
        guard !isDirectory.boolValue else {
          try? fm.removeItem(at: temp)
          return false
        }
        _ = try fm.replaceItemAt(destination, withItemAt: temp)
      } else {
        try fm.moveItem(at: temp, to: destination)
      }
      return true
    } catch {
      try Self.rethrowIfCancelled(error)
      return false
    }
  }

  /// PUTs [source] to [remotePath]. False on any failure.
  func upload(_ creds: SyncCredentials, remotePath: String, from source: URL) async throws -> Bool {
    guard let url = WebDAV.fileURL(serverUrl: creds.serverUrl, username: creds.username, remotePath: remotePath)
    else { return false }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(creds.authHeader, forHTTPHeaderField: "Authorization")
    do {
      let (_, response) = try await session.upload(for: request, fromFile: source)
      guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
      return (200..<300).contains(status)
    } catch {
      try Self.rethrowIfCancelled(error)
      return false
    }
  }

  /// A cancelled run must stop, not be mistaken for a flaky network.
  private static func rethrowIfCancelled(_ error: Error) throws {
    if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
      throw CancellationError()
    }
  }
}

/// Parses a PROPFIND multistatus into [SyncRemoteEntry]s. Pure, so it's
/// unit-tested.
enum DavSyncParser {
  private struct Raw {
    var href = ""
    var etag = ""
    var modified = ""
    var length = ""
    var fileId = ""
    var isCollection = false
  }

  private final class Delegate: NSObject, XMLParserDelegate {
    var responses: [Raw] = []
    var sawMultistatus = false
    private var current: Raw?
    private var text = ""

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      text = ""
      if elementName == "multistatus" { sawMultistatus = true }
      if elementName == "response" { current = Raw() }
      if elementName == "collection" { current?.isCollection = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      text += string
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      switch elementName {
      case "href": current?.href = value
      case "getetag": current?.etag = value
      case "getlastmodified": current?.modified = value
      case "getcontentlength": current?.length = value
      case "fileid": current?.fileId = value
      case "response":
        if let current { responses.append(current) }
        current = nil
      default: break
      }
      text = ""
    }
  }

  private static let httpDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return f
  }()

  /// Parses a PROPFIND multistatus. Throws `SyncRemoteUnavailable` for
  /// anything that isn't a complete, plausible answer - malformed or
  /// truncated XML, no `multistatus` envelope, no responses at all (a 207
  /// always has at least the requested resource), or an href that isn't
  /// under this account's files root or tries to climb out of it. A partial
  /// manifest would look like the missing part was deleted on the server
  /// (and an empty one like the whole path was), so the caller must treat
  /// those as "couldn't reach the server", never as data.
  static func entries(
    from xml: Data, username: String, requestedPath: String, skipSelf: Bool
  ) throws -> [SyncRemoteEntry] {
    let delegate = Delegate()
    let parser = XMLParser(data: xml)
    parser.shouldProcessNamespaces = true
    parser.delegate = delegate
    guard parser.parse(), delegate.sawMultistatus, !delegate.responses.isEmpty else {
      throw SyncRemoteUnavailable(message: "Unusable PROPFIND answer")
    }

    let marker = "/remote.php/dav/files/\(username)"
    let selfPath = trimTrailingSlashes(requestedPath)

    var entries: [SyncRemoteEntry] = []
    for raw in delegate.responses {
      let decoded = raw.href.removingPercentEncoding ?? raw.href
      guard let range = decoded.range(of: marker) else {
        throw SyncRemoteUnavailable(message: "PROPFIND href outside the account's files root")
      }
      let hrefPath = String(decoded[range.upperBound...])
      // A well-formed path continues the marker at a component boundary and
      // never contains a dot component.
      guard hrefPath.isEmpty || hrefPath.hasPrefix("/"),
        !hrefPath.split(separator: "/").contains(where: { $0 == ".." || $0 == "." })
      else {
        throw SyncRemoteUnavailable(message: "PROPFIND href has an unexpected path")
      }
      let normalized = trimTrailingSlashes(hrefPath.isEmpty ? "/" : hrefPath)
      if skipSelf && normalized == selfPath { continue }  // the folder itself, not a child
      entries.append(
        SyncRemoteEntry(
          path: normalized.isEmpty ? "/" : normalized,
          fileId: raw.fileId.isEmpty ? (normalized.isEmpty ? "/" : normalized) : raw.fileId,
          etag: raw.etag.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
          lastModified: httpDate.date(from: raw.modified).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0,
          size: Int64(raw.length) ?? 0,
          isFolder: raw.isCollection))
    }
    return entries
  }

  private static func trimTrailingSlashes(_ path: String) -> String {
    var p = path
    while p.hasSuffix("/") { p.removeLast() }
    return p
  }
}
