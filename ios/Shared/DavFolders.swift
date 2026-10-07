import Foundation

/// A folder in the account's WebDAV tree. [path] is relative to the user's
/// root with a leading slash ("/Documents/Tax Forms"); "/" is the root.
/// [isExternal] is true for an external-storage mount point (Nextcloud's
/// `nc:mount-type` = `external`) - only the mount's root carries it, its
/// children don't, so callers track mount roots to know what's inside one.
struct DavFolder: Equatable {
  let name: String
  let path: String
  var isExternal = false
}

/// The app's Files storage scope (`StorageScope` in Dart): internal ("cloud")
/// folders only (the default), only external-storage ones, or both.
enum StorageFilter: String {
  case cloud, external, all

  init(raw: String) {
    self = StorageFilter(rawValue: raw) ?? .cloud
  }

  func shows(isExternal: Bool) -> Bool {
    switch self {
    case .cloud: return !isExternal
    case .external: return isExternal
    case .all: return true
    }
  }
}

/// The app's Files "hidden files" filter (`HiddenFilesFilter` in Dart):
/// leave dot-folders out (`hide`, the default), list only them (`only`), or
/// list everything (`include`). A folder counts as hidden when it - or any
/// folder above it - starts with a dot, exactly as in the app.
enum HiddenFilter: String {
  case hide, only, include

  init(raw: String) {
    self = HiddenFilter(rawValue: raw) ?? .hide
  }

  static func isHidden(path: String) -> Bool {
    path.split(separator: "/").contains { $0.hasPrefix(".") }
  }

  func shows(path: String) -> Bool {
    switch self {
    case .hide: return !Self.isHidden(path: path)
    case .only: return Self.isHidden(path: path)
    case .include: return true
    }
  }
}

/// Parses a WebDAV `PROPFIND` multistatus into folders. Pure (no
/// networking), so it's unit-tested. Compiled into both targets.
enum DavFolderParser {
  private struct Response {
    var href = ""
    var isCollection = false
    var mountType = ""
  }

  private final class Delegate: NSObject, XMLParserDelegate {
    var responses: [Response] = []
    private var current: Response?
    private var text = ""

    private func local(_ name: String) -> String {
      name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      switch local(elementName) {
      case "response": current = Response()
      case "href", "mount-type": text = ""
      case "collection": current?.isCollection = true
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      text += string
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      switch local(elementName) {
      case "href": current?.href = text.trimmingCharacters(in: .whitespacesAndNewlines)
      case "mount-type": current?.mountType = text.trimmingCharacters(in: .whitespacesAndNewlines)
      case "response":
        if let current { responses.append(current) }
        current = nil
      default: break
      }
    }
  }

  /// "/nextcloud/remote.php/dav/files/alice/Tax%20Forms/" -> "/Tax Forms".
  /// The server may live under a sub-path, so the files root is located by
  /// its marker instead of assumed to start at the beginning.
  static func relativePath(fromHref href: String) -> String? {
    let decoded = href.removingPercentEncoding ?? href
    let marker = "/remote.php/dav/files/"
    guard let range = decoded.range(of: marker) else { return nil }
    var parts = decoded[range.upperBound...].split(separator: "/", omittingEmptySubsequences: true)
    guard !parts.isEmpty else { return nil }
    parts.removeFirst()  // the username
    return "/" + parts.joined(separator: "/")
  }

  /// Child folders of [currentPath], sorted by name, filtered by [hidden].
  /// The requested folder itself (which a Depth-1 PROPFIND also returns) is
  /// always left out.
  static func folders(
    from xml: Data, excluding currentPath: String, hidden: HiddenFilter = .hide
  ) -> [DavFolder] {
    let delegate = Delegate()
    let parser = XMLParser(data: xml)
    parser.delegate = delegate
    parser.parse()

    let current = currentPath == "/" ? "/" : currentPath.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    return delegate.responses
      .filter(\.isCollection)
      .compactMap { response -> DavFolder? in
        guard let path = relativePath(fromHref: response.href), path != current else { return nil }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, hidden.shows(path: path) else { return nil }
        return DavFolder(name: name, path: path, isExternal: response.mountType == "external")
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

/// Lists folders over WebDAV for the Share Extension's picker, in the
/// foreground (the sheet is on screen while it runs).
enum DavClient {
  private static let body = """
    <?xml version="1.0"?>
    <d:propfind xmlns:d="DAV:" xmlns:nc="http://nextcloud.org/ns"><d:prop><d:resourcetype/><nc:mount-type/></d:prop></d:propfind>
    """

  /// Every child folder, hidden and external ones included - the sheet's
  /// toggles filter that list in memory, so changing one doesn't refetch.
  static func listFolders(account: SharedAccount, path: String) async throws -> [DavFolder] {
    guard let url = WebDAV.fileURL(serverUrl: account.serverUrl, username: account.username, remotePath: path)
    else { throw TransferError(message: "Invalid server address.") }
    var request = URLRequest(url: url)
    request.httpMethod = "PROPFIND"
    request.setValue("1", forHTTPHeaderField: "Depth")
    request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
    request.setValue(account.authHeader, forHTTPHeaderField: "Authorization")
    request.httpBody = body.data(using: .utf8)
    request.timeoutInterval = 20

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 207 else {
      throw TransferError(message: status == 401 ? "Signed out - open Noo to sign in again." : "Server returned \(status).")
    }
    return DavFolderParser.folders(from: data, excluding: path, hidden: .include)
  }
}
