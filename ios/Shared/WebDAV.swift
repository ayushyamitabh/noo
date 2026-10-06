import Foundation

/// URL building for a Nextcloud account's WebDAV files root. Pure functions
/// (no networking), so they're unit-tested in `RunnerTests`.
enum WebDAV {
  /// `urlPathAllowed` minus "/", so a file name containing a slash-like
  /// character can't introduce an extra path segment.
  private static let segmentAllowed: CharacterSet = {
    var set = CharacterSet.urlPathAllowed
    set.remove(charactersIn: "/")
    return set
  }()

  static func encodeSegment(_ segment: String) -> String {
    segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
  }

  /// `<server>/remote.php/dav/files/<user>/<remotePath>` - [remotePath] is
  /// relative to the user's root, with or without a leading slash. A server
  /// installed under a sub-path (`https://host/nextcloud`) keeps it.
  static func fileURL(serverUrl: String, username: String, remotePath: String) -> URL? {
    var base = serverUrl
    while base.hasSuffix("/") { base.removeLast() }
    let segments = remotePath.split(separator: "/").map { encodeSegment(String($0)) }
    var url = base + "/remote.php/dav/files/" + encodeSegment(username)
    if !segments.isEmpty { url += "/" + segments.joined(separator: "/") }
    return URL(string: url)
  }

  /// `folder` + `name` with exactly one slash between them.
  static func join(_ folder: String, _ name: String) -> String {
    folder.hasSuffix("/") ? folder + name : folder + "/" + name
  }
}

enum LocalFiles {
  /// A URL in [directory] for [name] that doesn't exist yet: "a.txt", then
  /// "a (1).txt", "a (2).txt"... - so a second download of the same file
  /// never overwrites the first.
  static func uniqueURL(in directory: URL, name: String, fileManager: FileManager = .default) -> URL {
    let candidate = directory.appendingPathComponent(name)
    if !fileManager.fileExists(atPath: candidate.path) { return candidate }
    let ext = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension
    var index = 1
    while true {
      let numbered = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
      let url = directory.appendingPathComponent(numbered)
      if !fileManager.fileExists(atPath: url.path) { return url }
      index += 1
    }
  }
}
