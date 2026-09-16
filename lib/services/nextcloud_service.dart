import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/nextcloud_file_version.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../models/nextcloud_sharee.dart';

extension XmlElementHelper on xml.XmlNode {
  Iterable<xml.XmlElement> findLocalChildren(String localName) {
    return children.whereType<xml.XmlElement>().where(
      (e) => e.name.local.toLowerCase() == localName.toLowerCase(),
    );
  }

  Iterable<xml.XmlElement> findLocalDescendants(String localName) {
    if (this is xml.XmlDocument) {
      return (this as xml.XmlDocument).descendants
          .whereType<xml.XmlElement>()
          .where((e) => e.name.local.toLowerCase() == localName.toLowerCase());
    } else if (this is xml.XmlElement) {
      return (this as xml.XmlElement).descendants
          .whereType<xml.XmlElement>()
          .where((e) => e.name.local.toLowerCase() == localName.toLowerCase());
    }
    return [];
  }
}

/// WebDAV date props (`getlastmodified`, `creationdate`) come back as RFC 1123
/// dates (e.g. "Mon, 01 Jan 2024 00:00:00 GMT"), which [DateTime.tryParse]
/// can't read since it only understands ISO 8601. Fall back to [HttpDate].
DateTime? _parseDavDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;
  try {
    return HttpDate.parse(raw);
  } catch (_) {
    return null;
  }
}

/// The OCS Activity API reports each event's time as an ISO 8601 string in
/// a `datetime` field (e.g. "2025-09-15T12:34:56+00:00") - there is no
/// numeric `timestamp` field despite that being a very easy name to guess.
/// Falls back to now() only if the field is missing/unparseable, so a
/// broken response reads as "just now" rather than the Unix epoch.
DateTime _parseActivityDateTime(dynamic raw) {
  return DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.now();
}

/// Normalizes a WebDAV `href` (which servers may return as either a bare
/// path or a full absolute URL) down to just its path, trailing slash
/// stripped, so hrefs from either form can be compared directly.
String _davPath(String value) {
  var path = Uri.parse(value.trim()).path;
  if (path.endsWith('/') && path.length > 1) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

class NextcloudService {
  final String serverUrl;
  final String username;
  final String password;

  NextcloudService({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  String get _cleanServerUrl {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Map<String, String> get _headers {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return {
      'Authorization': 'Basic $credentials',
      'OCS-APIRequest': 'true',
      'Accept': 'application/json, application/xml',
      'User-Agent': 'Noo/1.0',
    };
  }

  /// Auth headers usable directly by widgets that fetch content themselves
  /// (e.g. `Image.network(url, headers: service.authHeaders)`).
  Map<String, String> get authHeaders => _headers;

  /// The direct WebDAV download URL for a file at [itemPath].
  String fileUrl(String itemPath) {
    var cleanPath = itemPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';
    return '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath';
  }

  /// Downloads the file at [itemPath] to [savePath], reporting progress.
  Future<void> downloadToFile(
    String itemPath,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dio = Dio();
    await dio.download(
      fileUrl(itemPath),
      savePath,
      options: Options(headers: _headers),
      onReceiveProgress: onProgress,
    );
  }

  /// Fetches the raw bytes of a file (used for in-app text/PDF previews).
  Future<List<int>> fetchBytes(String itemPath) async {
    final response = await http.get(
      Uri.parse(fileUrl(itemPath)),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to download file. HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<bool> testConnection() async {
    try {
      final davPath = '$_cleanServerUrl/remote.php/dav/files/$username/';
      debugPrint('[Nextcloud Test] Connecting to WebDAV endpoint: $davPath');
      final request = http.Request('PROPFIND', Uri.parse(davPath))
        ..headers.addAll({
          ..._headers,
          'Depth': '0',
          'Content-Type': 'application/xml',
        })
        ..body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''';
      final streamed = await http.Client().send(request);
      debugPrint(
        '[Nextcloud Test] Connection response HTTP status: ${streamed.statusCode}',
      );

      if (streamed.statusCode == 207 || streamed.statusCode == 200) {
        return true;
      }

      // Try fallback endpoint /remote.php/webdav/
      final legacyPath = '$_cleanServerUrl/remote.php/webdav/';
      debugPrint(
        '[Nextcloud Test] Testing legacy WebDAV endpoint: $legacyPath',
      );
      final req2 = http.Request('PROPFIND', Uri.parse(legacyPath))
        ..headers.addAll({
          ..._headers,
          'Depth': '0',
          'Content-Type': 'application/xml',
        });
      final st2 = await http.Client().send(req2);
      debugPrint(
        '[Nextcloud Test] Legacy WebDAV response HTTP status: ${st2.statusCode}',
      );
      if (st2.statusCode == 207 || st2.statusCode == 200) {
        return true;
      }

      if (streamed.statusCode == 401 || st2.statusCode == 401) {
        throw Exception('Invalid username or password (401 Unauthorized)');
      } else if (streamed.statusCode == 404 && st2.statusCode == 404) {
        throw Exception('Nextcloud WebDAV endpoint not found at $davPath');
      } else {
        throw Exception('Server returned status code ${streamed.statusCode}');
      }
    } catch (e) {
      debugPrint('[Nextcloud Test] Error: $e');
      final str = e.toString();
      if (str.contains('XMLHttpRequest') ||
          str.contains('ClientException') ||
          str.contains('Failed to fetch')) {
        throw Exception(
          'Browser CORS Policy Blocked: The web browser blocked the connection preflight request to $_cleanServerUrl. '
          'To bypass browser CORS, run the application as a native Windows app (flutter run -d windows) '
          'or configure CORS headers on your Nextcloud server.',
        );
      }
      if (e is Exception) rethrow;
      throw Exception('Could not connect to Nextcloud host: $e');
    }
  }

  Future<List<NextcloudItem>> fetchDirectory(String folderPath) async {
    var cleanPath = folderPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';
    if (!cleanPath.endsWith('/')) cleanPath = '$cleanPath/';

    final url = '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath';
    debugPrint('[Nextcloud DAV] Requesting PROPFIND for $url');

    final request = http.Request('PROPFIND', Uri.parse(url))
      ..headers.addAll({
        ..._headers,
        'Depth': '1',
        'Content-Type': 'application/xml',
      });

    const body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
  <d:prop>
    <d:getlastmodified/>
    <d:creationdate/>
    <d:getcontentlength/>
    <d:getcontenttype/>
    <d:resourcetype/>
    <oc:favorite/>
    <oc:fileid/>
    <oc:size/>
    <nc:mount-type/>
  </d:prop>
</d:propfind>''';

    request.body = body;

    var streamedResponse = await http.Client().send(request);
    var responseBody = await streamedResponse.stream.bytesToString();

    debugPrint(
      '[Nextcloud DAV] PROPFIND primary URL status: ${streamedResponse.statusCode}, bytes: ${responseBody.length}',
    );

    if (streamedResponse.statusCode != 207 &&
        streamedResponse.statusCode != 200) {
      final fallbackUrl = '$_cleanServerUrl/remote.php/webdav$cleanPath';
      debugPrint(
        '[Nextcloud DAV] Primary URL failed (${streamedResponse.statusCode}). Trying fallback: $fallbackUrl',
      );
      final req2 = http.Request('PROPFIND', Uri.parse(fallbackUrl))
        ..headers.addAll({
          ..._headers,
          'Depth': '1',
          'Content-Type': 'application/xml',
        })
        ..body = body;
      final res2 = await http.Client().send(req2);
      final body2 = await res2.stream.bytesToString();
      debugPrint(
        '[Nextcloud DAV] Fallback URL response status: ${res2.statusCode}, bytes: ${body2.length}',
      );

      if (res2.statusCode == 207 || res2.statusCode == 200) {
        streamedResponse = res2;
        responseBody = body2;
      } else {
        throw Exception(
          'Failed to load directory $cleanPath. HTTP ${streamedResponse.statusCode}',
        );
      }
    }

    final document = xml.XmlDocument.parse(responseBody);
    final responses = document.findLocalDescendants('response');
    debugPrint(
      '[Nextcloud DAV] Found ${responses.length} response nodes in XML',
    );

    List<NextcloudItem> items = [];
    for (var res in responses) {
      final hrefNode =
          res.findLocalChildren('href').firstOrNull ??
          res.findLocalDescendants('href').firstOrNull;
      final href = hrefNode?.innerText ?? '';

      // Servers may return `href` as either a server-relative path or a full
      // absolute URL; compare on path only so both forms line up.
      final hrefPath = _davPath(Uri.decodeFull(href));
      final targetDavPath = _davPath(
        '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath',
      );
      final targetLegacyPath = _davPath(
        '$_cleanServerUrl/remote.php/webdav$cleanPath',
      );

      // Skip current root directory entry itself
      if (hrefPath == targetDavPath ||
          hrefPath == targetLegacyPath ||
          hrefPath.endsWith('/remote.php/dav/files/$username') ||
          hrefPath.endsWith('/remote.php/webdav')) {
        continue;
      }

      final props = res.findLocalDescendants('prop');
      if (props.isEmpty) continue;

      bool isCollection = false;
      String? sizeStr;
      String? lastModStr;
      String? createdStr;
      String? mimeType;
      bool isFav = false;
      String? fileId;
      String? mountType;

      for (var prop in props) {
        if (!isCollection) {
          final resTypeNode = prop
              .findLocalChildren('resourcetype')
              .firstOrNull;
          if (resTypeNode != null &&
              resTypeNode.findLocalChildren('collection').isNotEmpty) {
            isCollection = true;
          }
        }
        sizeStr ??=
            prop.findLocalChildren('size').firstOrNull?.innerText ??
            prop.findLocalChildren('getcontentlength').firstOrNull?.innerText;
        lastModStr ??= prop
            .findLocalChildren('getlastmodified')
            .firstOrNull
            ?.innerText;
        createdStr ??= prop
            .findLocalChildren('creationdate')
            .firstOrNull
            ?.innerText;
        mimeType ??= prop
            .findLocalChildren('getcontenttype')
            .firstOrNull
            ?.innerText;
        if (!isFav) {
          isFav =
              prop.findLocalChildren('favorite').firstOrNull?.innerText == '1';
        }
        fileId ??= prop.findLocalChildren('fileid').firstOrNull?.innerText;
        mountType ??= prop
            .findLocalChildren('mount-type')
            .firstOrNull
            ?.innerText;
      }

      final name = Uri.decodeFull(
        href.split('/').where((s) => s.isNotEmpty).last,
      );
      if (name.isEmpty) continue;

      final size = int.tryParse(sizeStr ?? '0') ?? 0;
      final lastMod = _parseDavDate(lastModStr) ?? DateTime.now();
      final created = _parseDavDate(createdStr);
      final itemType = NextcloudItem.deduceType(name, isCollection, mimeType);
      final validId = (fileId != null && fileId.isNotEmpty) ? fileId : name;

      items.add(
        NextcloudItem(
          id: validId,
          name: name,
          path: '$cleanPath$name',
          type: itemType,
          size: size,
          lastModified: lastMod,
          dateCreated: created,
          isFavorite: isFav,
          mimeType: mimeType,
          previewUrl:
              '$_cleanServerUrl/core/preview?fileId=$validId&x=500&y=500',
          mountType: mountType,
        ),
      );
    }

    debugPrint(
      '[Nextcloud DAV] Successfully parsed ${items.length} items from directory $cleanPath',
    );
    return items;
  }

  /// Searches the whole file tree by name using the WebDAV SEARCH-REPORT
  /// extension (supported by Nextcloud/ownCloud), rather than just the
  /// currently open folder.
  Future<List<NextcloudItem>> searchFiles(String query) async {
    final term = query.trim();
    if (term.isEmpty) return [];

    final url = '$_cleanServerUrl/remote.php/dav/';
    debugPrint('[Nextcloud DAV] SEARCH "$term" from $url');

    final escaped = term
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final body =
        '''<?xml version="1.0" encoding="utf-8" ?>
<d:searchrequest xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:basicsearch>
    <d:select>
      <d:prop>
        <d:displayname/>
        <d:getcontentlength/>
        <d:getlastmodified/>
        <d:getcontenttype/>
        <d:resourcetype/>
        <oc:favorite/>
        <oc:fileid/>
      </d:prop>
    </d:select>
    <d:from>
      <d:scope>
        <d:href>/files/$username</d:href>
        <d:depth>infinity</d:depth>
      </d:scope>
    </d:from>
    <d:where>
      <d:like>
        <d:prop><d:displayname/></d:prop>
        <d:literal>%$escaped%</d:literal>
      </d:like>
    </d:where>
    <d:orderby/>
  </d:basicsearch>
</d:searchrequest>''';

    final request = http.Request('SEARCH', Uri.parse(url))
      ..headers.addAll({..._headers, 'Content-Type': 'text/xml'})
      ..body = body;

    final streamed = await http.Client().send(request);
    final responseBody = await streamed.stream.bytesToString();
    debugPrint(
      '[Nextcloud DAV] SEARCH status: ${streamed.statusCode}, bytes: ${responseBody.length}',
    );

    if (streamed.statusCode != 207 && streamed.statusCode != 200) {
      throw Exception('Search failed. HTTP ${streamed.statusCode}');
    }

    final document = xml.XmlDocument.parse(responseBody);
    final responses = document.findLocalDescendants('response');

    final results = <NextcloudItem>[];
    for (var res in responses) {
      final hrefNode =
          res.findLocalChildren('href').firstOrNull ??
          res.findLocalDescendants('href').firstOrNull;
      final href = hrefNode?.innerText ?? '';
      if (href.isEmpty) continue;

      final props = res.findLocalDescendants('prop');
      if (props.isEmpty) continue;

      bool isCollection = false;
      String? sizeStr;
      String? lastModStr;
      String? mimeType;
      bool isFav = false;
      String? fileId;

      for (var prop in props) {
        if (!isCollection) {
          final resTypeNode = prop
              .findLocalChildren('resourcetype')
              .firstOrNull;
          if (resTypeNode != null &&
              resTypeNode.findLocalChildren('collection').isNotEmpty) {
            isCollection = true;
          }
        }
        sizeStr ??= prop
            .findLocalChildren('getcontentlength')
            .firstOrNull
            ?.innerText;
        lastModStr ??= prop
            .findLocalChildren('getlastmodified')
            .firstOrNull
            ?.innerText;
        mimeType ??= prop
            .findLocalChildren('getcontenttype')
            .firstOrNull
            ?.innerText;
        if (!isFav) {
          isFav =
              prop.findLocalChildren('favorite').firstOrNull?.innerText == '1';
        }
        fileId ??= prop.findLocalChildren('fileid').firstOrNull?.innerText;
      }

      var decodedHref = Uri.decodeFull(href);
      if (decodedHref.endsWith('/') && decodedHref.length > 1) {
        decodedHref = decodedHref.substring(0, decodedHref.length - 1);
      }
      final name = decodedHref.split('/').where((s) => s.isNotEmpty).last;
      if (name.isEmpty) continue;

      // Strip the DAV root prefix so `path` matches what fetchDirectory produces.
      final marker = '/files/$username';
      final markerIndex = decodedHref.indexOf(marker);
      final itemPath = markerIndex >= 0
          ? decodedHref.substring(markerIndex + marker.length)
          : decodedHref;
      if (itemPath.isEmpty) continue;

      final size = int.tryParse(sizeStr ?? '0') ?? 0;
      final lastMod = _parseDavDate(lastModStr) ?? DateTime.now();
      final itemType = NextcloudItem.deduceType(name, isCollection, mimeType);
      final validId = (fileId != null && fileId.isNotEmpty) ? fileId : name;

      results.add(
        NextcloudItem(
          id: validId,
          name: name,
          path: itemPath,
          type: itemType,
          size: size,
          lastModified: lastMod,
          isFavorite: isFav,
          mimeType: mimeType,
          previewUrl:
              '$_cleanServerUrl/core/preview?fileId=$validId&x=500&y=500',
        ),
      );
    }

    debugPrint(
      '[Nextcloud DAV] Search returned ${results.length} results for "$term"',
    );
    return results;
  }

  /// Finds every image/video anywhere in the account (not just the current
  /// folder) via the same WebDAV SEARCH-REPORT mechanism Nextcloud's own
  /// Files app uses for its "Photos" filter, so the Photos tab can show a
  /// true all-folders library instead of just the currently browsed folder.
  Future<List<NextcloudItem>> fetchAllMedia() async {
    final url = '$_cleanServerUrl/remote.php/dav/';
    debugPrint('[Nextcloud DAV] SEARCH for all media from $url');

    final body =
        '''<?xml version="1.0" encoding="utf-8" ?>
<d:searchrequest xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
  <d:basicsearch>
    <d:select>
      <d:prop>
        <d:displayname/>
        <d:getcontentlength/>
        <d:getlastmodified/>
        <d:creationdate/>
        <d:getcontenttype/>
        <d:resourcetype/>
        <oc:favorite/>
        <oc:fileid/>
        <nc:mount-type/>
      </d:prop>
    </d:select>
    <d:from>
      <d:scope>
        <d:href>/files/$username</d:href>
        <d:depth>infinity</d:depth>
      </d:scope>
    </d:from>
    <d:where>
      <d:or>
        <d:like>
          <d:prop><d:getcontenttype/></d:prop>
          <d:literal>image/%</d:literal>
        </d:like>
        <d:like>
          <d:prop><d:getcontenttype/></d:prop>
          <d:literal>video/%</d:literal>
        </d:like>
      </d:or>
    </d:where>
    <d:orderby>
      <d:order>
        <d:prop><d:getlastmodified/></d:prop>
        <d:descending/>
      </d:order>
    </d:orderby>
    <d:limit>
      <d:nresults>2000</d:nresults>
    </d:limit>
  </d:basicsearch>
</d:searchrequest>''';

    final request = http.Request('SEARCH', Uri.parse(url))
      ..headers.addAll({..._headers, 'Content-Type': 'text/xml'})
      ..body = body;

    final streamed = await http.Client().send(request);
    final responseBody = await streamed.stream.bytesToString();
    debugPrint(
      '[Nextcloud DAV] All-media SEARCH status: ${streamed.statusCode}, bytes: ${responseBody.length}',
    );

    if (streamed.statusCode != 207 && streamed.statusCode != 200) {
      throw Exception('Failed to load media. HTTP ${streamed.statusCode}');
    }

    final document = xml.XmlDocument.parse(responseBody);
    final responses = document.findLocalDescendants('response');

    final results = <NextcloudItem>[];
    for (var res in responses) {
      final hrefNode =
          res.findLocalChildren('href').firstOrNull ??
          res.findLocalDescendants('href').firstOrNull;
      final href = hrefNode?.innerText ?? '';
      if (href.isEmpty) continue;

      final props = res.findLocalDescendants('prop');
      if (props.isEmpty) continue;

      String? sizeStr;
      String? lastModStr;
      String? createdStr;
      String? mimeType;
      bool isFav = false;
      String? fileId;
      String? mountType;

      for (var prop in props) {
        sizeStr ??= prop
            .findLocalChildren('getcontentlength')
            .firstOrNull
            ?.innerText;
        lastModStr ??= prop
            .findLocalChildren('getlastmodified')
            .firstOrNull
            ?.innerText;
        createdStr ??= prop
            .findLocalChildren('creationdate')
            .firstOrNull
            ?.innerText;
        mimeType ??= prop
            .findLocalChildren('getcontenttype')
            .firstOrNull
            ?.innerText;
        if (!isFav) {
          isFav =
              prop.findLocalChildren('favorite').firstOrNull?.innerText == '1';
        }
        fileId ??= prop.findLocalChildren('fileid').firstOrNull?.innerText;
        mountType ??= prop
            .findLocalChildren('mount-type')
            .firstOrNull
            ?.innerText;
      }

      var decodedHref = Uri.decodeFull(href);
      if (decodedHref.endsWith('/') && decodedHref.length > 1) {
        decodedHref = decodedHref.substring(0, decodedHref.length - 1);
      }
      final name = decodedHref.split('/').where((s) => s.isNotEmpty).last;
      if (name.isEmpty) continue;

      // Strip the DAV root prefix so `path` matches what fetchDirectory produces.
      final marker = '/files/$username';
      final markerIndex = decodedHref.indexOf(marker);
      final itemPath = markerIndex >= 0
          ? decodedHref.substring(markerIndex + marker.length)
          : decodedHref;
      if (itemPath.isEmpty) continue;

      final size = int.tryParse(sizeStr ?? '0') ?? 0;
      final lastMod = _parseDavDate(lastModStr) ?? DateTime.now();
      final created = _parseDavDate(createdStr);
      final itemType = NextcloudItem.deduceType(name, false, mimeType);
      final validId = (fileId != null && fileId.isNotEmpty) ? fileId : name;

      results.add(
        NextcloudItem(
          id: validId,
          name: name,
          path: itemPath,
          type: itemType,
          size: size,
          lastModified: lastMod,
          dateCreated: created,
          isFavorite: isFav,
          mimeType: mimeType,
          previewUrl:
              '$_cleanServerUrl/core/preview?fileId=$validId&x=500&y=500',
          mountType: mountType,
        ),
      );
    }

    debugPrint(
      '[Nextcloud DAV] All-media SEARCH found ${results.length} items',
    );
    return results;
  }

  /// Finds recently modified files across the whole account (folders
  /// excluded), newest first — same SEARCH-REPORT mechanism as
  /// [fetchAllMedia], just without the image/video mimetype filter.
  Future<List<NextcloudItem>> fetchRecentFiles() async {
    final url = '$_cleanServerUrl/remote.php/dav/';
    debugPrint('[Nextcloud DAV] SEARCH for recent files from $url');

    final body =
        '''<?xml version="1.0" encoding="utf-8" ?>
<d:searchrequest xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:basicsearch>
    <d:select>
      <d:prop>
        <d:displayname/>
        <d:getcontentlength/>
        <d:getlastmodified/>
        <d:creationdate/>
        <d:getcontenttype/>
        <d:resourcetype/>
        <oc:favorite/>
        <oc:fileid/>
      </d:prop>
    </d:select>
    <d:from>
      <d:scope>
        <d:href>/files/$username</d:href>
        <d:depth>infinity</d:depth>
      </d:scope>
    </d:from>
    <d:where>
      <d:like>
        <d:prop><d:displayname/></d:prop>
        <d:literal>%</d:literal>
      </d:like>
    </d:where>
    <d:orderby>
      <d:order>
        <d:prop><d:getlastmodified/></d:prop>
        <d:descending/>
      </d:order>
    </d:orderby>
    <d:limit>
      <d:nresults>200</d:nresults>
    </d:limit>
  </d:basicsearch>
</d:searchrequest>''';

    final request = http.Request('SEARCH', Uri.parse(url))
      ..headers.addAll({..._headers, 'Content-Type': 'text/xml'})
      ..body = body;

    final streamed = await http.Client().send(request);
    final responseBody = await streamed.stream.bytesToString();
    debugPrint(
      '[Nextcloud DAV] Recent SEARCH status: ${streamed.statusCode}, bytes: ${responseBody.length}',
    );

    if (streamed.statusCode != 207 && streamed.statusCode != 200) {
      throw Exception(
        'Failed to load recent files. HTTP ${streamed.statusCode}',
      );
    }

    final document = xml.XmlDocument.parse(responseBody);
    final responses = document.findLocalDescendants('response');

    final results = <NextcloudItem>[];
    for (var res in responses) {
      final hrefNode =
          res.findLocalChildren('href').firstOrNull ??
          res.findLocalDescendants('href').firstOrNull;
      final href = hrefNode?.innerText ?? '';
      if (href.isEmpty) continue;

      final props = res.findLocalDescendants('prop');
      if (props.isEmpty) continue;

      bool isCollection = false;
      String? sizeStr;
      String? lastModStr;
      String? createdStr;
      String? mimeType;
      bool isFav = false;
      String? fileId;

      for (var prop in props) {
        if (!isCollection) {
          final resTypeNode = prop
              .findLocalChildren('resourcetype')
              .firstOrNull;
          if (resTypeNode != null &&
              resTypeNode.findLocalChildren('collection').isNotEmpty) {
            isCollection = true;
          }
        }
        sizeStr ??= prop
            .findLocalChildren('getcontentlength')
            .firstOrNull
            ?.innerText;
        lastModStr ??= prop
            .findLocalChildren('getlastmodified')
            .firstOrNull
            ?.innerText;
        createdStr ??= prop
            .findLocalChildren('creationdate')
            .firstOrNull
            ?.innerText;
        mimeType ??= prop
            .findLocalChildren('getcontenttype')
            .firstOrNull
            ?.innerText;
        if (!isFav) {
          isFav =
              prop.findLocalChildren('favorite').firstOrNull?.innerText == '1';
        }
        fileId ??= prop.findLocalChildren('fileid').firstOrNull?.innerText;
      }

      if (isCollection) continue; // folders aren't "recent files"

      var decodedHref = Uri.decodeFull(href);
      if (decodedHref.endsWith('/') && decodedHref.length > 1) {
        decodedHref = decodedHref.substring(0, decodedHref.length - 1);
      }
      final name = decodedHref.split('/').where((s) => s.isNotEmpty).last;
      if (name.isEmpty) continue;

      // Strip the DAV root prefix so `path` matches what fetchDirectory produces.
      final marker = '/files/$username';
      final markerIndex = decodedHref.indexOf(marker);
      final itemPath = markerIndex >= 0
          ? decodedHref.substring(markerIndex + marker.length)
          : decodedHref;
      if (itemPath.isEmpty) continue;

      final size = int.tryParse(sizeStr ?? '0') ?? 0;
      final lastMod = _parseDavDate(lastModStr) ?? DateTime.now();
      final created = _parseDavDate(createdStr);
      final itemType = NextcloudItem.deduceType(name, false, mimeType);
      final validId = (fileId != null && fileId.isNotEmpty) ? fileId : name;

      results.add(
        NextcloudItem(
          id: validId,
          name: name,
          path: itemPath,
          type: itemType,
          size: size,
          lastModified: lastMod,
          dateCreated: created,
          isFavorite: isFav,
          mimeType: mimeType,
          previewUrl:
              '$_cleanServerUrl/core/preview?fileId=$validId&x=500&y=500',
        ),
      );
    }

    debugPrint('[Nextcloud DAV] Recent SEARCH found ${results.length} items');
    return results;
  }

  Future<NextcloudUserQuota> fetchUserQuota() async {
    final url = '$_cleanServerUrl/ocs/v1.php/cloud/user?format=json';
    debugPrint('[Nextcloud OCS] Fetching user quota from $url');

    final response = await http.get(Uri.parse(url), headers: _headers);
    debugPrint(
      '[Nextcloud OCS] User quota response status: ${response.statusCode}',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final ocsData = data['ocs']?['data'] ?? {};
      final quota = ocsData['quota'] ?? {};

      final used = (quota['used'] as num?)?.toInt() ?? 0;
      final totalRaw = (quota['total'] as num?)?.toInt() ?? 0;
      final total = totalRaw < 0 ? -1 : totalRaw;
      final pct = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
      final display = ocsData['displayname'] ?? username;
      final email = ocsData['email'] ?? '$username@$serverUrl';
      final groups = ((ocsData['groups'] as List?) ?? [])
          .map((g) => g.toString())
          .toList();

      return NextcloudUserQuota(
        usedBytes: used,
        totalBytes: total,
        usagePercentage: pct,
        userName: display,
        email: email,
        serverVersion: 'Nextcloud Server',
        groups: groups,
      );
    } else {
      throw Exception(
        'Failed to fetch user quota. HTTP ${response.statusCode}',
      );
    }
  }

  Future<List<NextcloudActivity>> fetchActivities() async {
    try {
      final url =
          '$_cleanServerUrl/ocs/v2.php/apps/activity/api/v2/activity?format=json';
      debugPrint('[Nextcloud OCS] Fetching activity feed from $url');

      final response = await http.get(Uri.parse(url), headers: _headers);
      debugPrint(
        '[Nextcloud OCS] Activity response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawData = data['ocs']?['data'];
        List<dynamic> list = [];
        if (rawData is List) {
          list = rawData;
        } else if (rawData is Map && rawData['activity'] is List) {
          list = rawData['activity'];
        }

        return list.map((a) {
          return NextcloudActivity(
            id: (a['activity_id'] ?? '').toString(),
            title: a['subject'] ?? 'Server Activity',
            subject: a['message'] ?? (a['subject'] ?? ''),
            timestamp: _parseActivityDateTime(a['datetime']),
            icon: Icons.cloud_outlined,
            author: a['user'] ?? username,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[Nextcloud OCS Activity] Error: $e');
    }
    return [];
  }

  /// Uploads a file from disk, streaming it so large files don't need to be
  /// buffered fully in memory, with progress reporting.
  Future<bool> uploadFileFromPath(
    String folderPath,
    String fileName,
    String localFilePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    var cleanPath = folderPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';
    if (!cleanPath.endsWith('/')) cleanPath = '$cleanPath/';

    final url =
        '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath$fileName';
    debugPrint('[Nextcloud DAV] Streaming upload to $url');

    final file = File(localFilePath);
    final length = await file.length();
    final dio = Dio();

    final response = await dio.put<void>(
      url,
      data: file.openRead(),
      options: Options(
        headers: {..._headers, Headers.contentLengthHeader: length},
        contentType: 'application/octet-stream',
      ),
      onSendProgress: onProgress,
    );

    debugPrint(
      '[Nextcloud DAV] Streaming upload status: ${response.statusCode}',
    );
    return response.statusCode == 201 ||
        response.statusCode == 204 ||
        response.statusCode == 200;
  }

  Future<bool> deleteItem(String itemPath) async {
    var cleanPath = itemPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';

    final url = '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath';
    debugPrint('[Nextcloud DAV] Deleting item at $url');

    final response = await http.delete(Uri.parse(url), headers: _headers);
    debugPrint('[Nextcloud DAV] Delete status: ${response.statusCode}');
    return response.statusCode == 204 || response.statusCode == 200;
  }

  /// Renames (or moves within the same folder) an item via WebDAV MOVE.
  Future<bool> renameItem(String itemPath, String newName) async {
    var cleanPath = itemPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';

    final segments = cleanPath.split('/')..removeLast();
    final destPath = '${segments.join('/')}/$newName';

    final sourceUrl =
        '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath';
    final destUrl = '$_cleanServerUrl/remote.php/dav/files/$username$destPath';
    debugPrint('[Nextcloud DAV] Renaming $sourceUrl -> $destUrl');

    final request = http.Request('MOVE', Uri.parse(sourceUrl))
      ..headers.addAll({
        ..._headers,
        'Destination': Uri.encodeFull(destUrl),
        'Overwrite': 'F',
      });
    final response = await http.Client().send(request);
    debugPrint('[Nextcloud DAV] Rename status: ${response.statusCode}');
    return response.statusCode == 201 || response.statusCode == 204;
  }

  Future<bool> createFolder(String parentPath, String folderName) async {
    var cleanPath = parentPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';
    if (!cleanPath.endsWith('/')) cleanPath = '$cleanPath/';

    final url =
        '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath$folderName';
    debugPrint('[Nextcloud DAV] Creating folder at $url');

    final request = http.Request('MKCOL', Uri.parse(url))
      ..headers.addAll(_headers);
    final response = await http.Client().send(request);
    debugPrint('[Nextcloud DAV] Create folder status: ${response.statusCode}');
    return response.statusCode == 201;
  }

  /// Lists the contents of the Nextcloud trash bin (flat — deleted folders
  /// appear as a single entry, not expanded).
  Future<List<NextcloudItem>> fetchTrash() async {
    final url = '$_cleanServerUrl/remote.php/dav/trashbin/$username/trash/';
    debugPrint('[Nextcloud DAV] Requesting PROPFIND for trash: $url');

    final request = http.Request('PROPFIND', Uri.parse(url))
      ..headers.addAll({
        ..._headers,
        'Depth': '1',
        'Content-Type': 'application/xml',
      });

    const body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
  <d:prop>
    <d:getlastmodified/>
    <d:getcontentlength/>
    <d:getcontenttype/>
    <d:resourcetype/>
    <oc:fileid/>
    <oc:size/>
    <nc:trashbin-original-location/>
    <nc:trashbin-deletion-time/>
  </d:prop>
</d:propfind>''';

    request.body = body;

    final streamedResponse = await http.Client().send(request);
    final responseBody = await streamedResponse.stream.bytesToString();
    debugPrint(
      '[Nextcloud DAV] Trash PROPFIND status: ${streamedResponse.statusCode}, bytes: ${responseBody.length}',
    );

    if (streamedResponse.statusCode != 207 &&
        streamedResponse.statusCode != 200) {
      throw Exception(
        'Failed to load trash. HTTP ${streamedResponse.statusCode}',
      );
    }

    final document = xml.XmlDocument.parse(responseBody);
    final responses = document.findLocalDescendants('response');
    final targetPath = _davPath(
      '$_cleanServerUrl/remote.php/dav/trashbin/$username/trash/',
    );

    final items = <NextcloudItem>[];
    for (var res in responses) {
      final hrefNode =
          res.findLocalChildren('href').firstOrNull ??
          res.findLocalDescendants('href').firstOrNull;
      final href = hrefNode?.innerText ?? '';
      final hrefPath = _davPath(Uri.decodeFull(href));
      if (hrefPath == targetPath) continue; // skip the trash root itself

      final props = res.findLocalDescendants('prop');
      if (props.isEmpty) continue;

      bool isCollection = false;
      String? sizeStr;
      String? mimeType;
      String? fileId;
      String? originalLocation;
      String? deletionTimeStr;

      for (var prop in props) {
        if (!isCollection) {
          final resTypeNode = prop
              .findLocalChildren('resourcetype')
              .firstOrNull;
          if (resTypeNode != null &&
              resTypeNode.findLocalChildren('collection').isNotEmpty) {
            isCollection = true;
          }
        }
        sizeStr ??=
            prop.findLocalChildren('size').firstOrNull?.innerText ??
            prop.findLocalChildren('getcontentlength').firstOrNull?.innerText;
        mimeType ??= prop
            .findLocalChildren('getcontenttype')
            .firstOrNull
            ?.innerText;
        fileId ??= prop.findLocalChildren('fileid').firstOrNull?.innerText;
        originalLocation ??= prop
            .findLocalChildren('trashbin-original-location')
            .firstOrNull
            ?.innerText;
        deletionTimeStr ??= prop
            .findLocalChildren('trashbin-deletion-time')
            .firstOrNull
            ?.innerText;
      }

      // The trash entry's own on-disk name, e.g. "photo.jpg.d1735689600" —
      // this (not the display name) is what restore/delete-forever need.
      final trashName = Uri.decodeFull(
        href.split('/').where((s) => s.isNotEmpty).last,
      );
      if (trashName.isEmpty) continue;

      final displayName =
          (originalLocation != null && originalLocation.isNotEmpty)
          ? originalLocation.split('/').where((s) => s.isNotEmpty).last
          : trashName;

      final size = int.tryParse(sizeStr ?? '0') ?? 0;
      final deletionTime = deletionTimeStr != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (int.tryParse(deletionTimeStr) ?? 0) * 1000,
            )
          : DateTime.now();
      final itemType = NextcloudItem.deduceType(
        displayName,
        isCollection,
        mimeType,
      );
      final validId = (fileId != null && fileId.isNotEmpty)
          ? fileId
          : trashName;

      items.add(
        NextcloudItem(
          id: validId,
          name: displayName,
          path: trashName,
          type: itemType,
          size: size,
          lastModified: deletionTime,
          originalLocation: originalLocation,
          deletedAt: deletionTime,
        ),
      );
    }

    debugPrint('[Nextcloud DAV] Loaded ${items.length} trash items');
    return items;
  }

  /// Restores a trashed item (identified by its trash-relative name, i.e.
  /// [NextcloudItem.path] for a trash item) back to its original location.
  Future<bool> restoreTrashItem(String trashName) async {
    final sourceUrl =
        '$_cleanServerUrl/remote.php/dav/trashbin/$username/trash/$trashName';
    final destUrl =
        '$_cleanServerUrl/remote.php/dav/trashbin/$username/restore/$trashName';
    debugPrint('[Nextcloud DAV] Restoring trash item $sourceUrl -> $destUrl');

    final request = http.Request('MOVE', Uri.parse(sourceUrl))
      ..headers.addAll({..._headers, 'Destination': destUrl});
    final response = await http.Client().send(request);
    debugPrint('[Nextcloud DAV] Restore status: ${response.statusCode}');
    return response.statusCode == 201 || response.statusCode == 204;
  }

  /// Permanently deletes a trashed item (identified by its trash-relative
  /// name, i.e. [NextcloudItem.path] for a trash item). Cannot be undone.
  Future<bool> deleteTrashItemForever(String trashName) async {
    final url =
        '$_cleanServerUrl/remote.php/dav/trashbin/$username/trash/$trashName';
    debugPrint('[Nextcloud DAV] Permanently deleting trash item $url');

    final response = await http.delete(Uri.parse(url), headers: _headers);
    debugPrint(
      '[Nextcloud DAV] Permanent delete status: ${response.statusCode}',
    );
    return response.statusCode == 204 || response.statusCode == 200;
  }

  ShareType _mapShareType(int value) {
    switch (value) {
      case 0:
        return ShareType.user;
      case 1:
        return ShareType.group;
      case 3:
        return ShareType.publicLink;
      case 4:
        return ShareType.email;
      case 6:
        return ShareType.federated;
      default:
        return ShareType.other;
    }
  }

  /// Lists shares: things the current user has shared with others by
  /// default, or things others have shared with the current user when
  /// [sharedWithMe] is true.
  Future<List<NextcloudShare>> fetchShares({bool sharedWithMe = false}) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/shares'
        '?format=json${sharedWithMe ? '&shared_with_me=true' : ''}';
    debugPrint(
      '[Nextcloud OCS] Fetching shares (sharedWithMe=$sharedWithMe) from $url',
    );

    final response = await http.get(Uri.parse(url), headers: _headers);
    debugPrint(
      '[Nextcloud OCS] Shares response status: ${response.statusCode}',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load shares. HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final rawList = data['ocs']?['data'];
    if (rawList is! List) return [];

    return rawList.map<NextcloudShare>((raw) {
      final path = (raw['path'] ?? '/').toString();
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      final name = segments.isNotEmpty ? segments.last : path;
      final isFolder = (raw['item_type'] ?? '').toString() == 'folder';
      final mimeType = raw['mimetype'] as String?;

      return NextcloudShare(
        id: (raw['id'] ?? '').toString(),
        path: path,
        name: name,
        itemType: NextcloudItem.deduceType(name, isFolder, mimeType),
        shareType: _mapShareType((raw['share_type'] as num?)?.toInt() ?? -1),
        ownerDisplayName: (raw['displayname_owner'] ?? raw['uid_owner'] ?? '')
            .toString(),
        sharedWithDisplayName: raw['share_with_displayname'] as String?,
        sharedAt: DateTime.fromMillisecondsSinceEpoch(
          ((raw['stime'] as num?)?.toInt() ?? 0) * 1000,
        ),
        sharedWithMe: sharedWithMe,
      );
    }).toList();
  }

  /// Creates a public link share for [path] and returns its share URL.
  Future<String> createPublicShareLink(String path) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json';
    debugPrint('[Nextcloud OCS] Creating public share link for $path');

    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: {'path': path, 'shareType': '3'},
    );
    debugPrint(
      '[Nextcloud OCS] Create share response status: ${response.statusCode}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to create share link. HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);
    final shareUrl = data['ocs']?['data']?['url'] as String?;
    if (shareUrl == null) {
      throw Exception('Server response did not include a share URL.');
    }
    return shareUrl;
  }

  /// Removes a share (un-shares an item you shared, or removes one shared
  /// with you).
  Future<bool> deleteShare(String shareId) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/shares/$shareId?format=json';
    debugPrint('[Nextcloud OCS] Deleting share $shareId');

    final response = await http.delete(Uri.parse(url), headers: _headers);
    debugPrint('[Nextcloud OCS] Delete share status: ${response.statusCode}');
    return response.statusCode == 200;
  }

  NextcloudShare _shareFromJson(Map raw, {required bool sharedWithMe}) {
    final path = (raw['path'] ?? '/').toString();
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final name = segments.isNotEmpty ? segments.last : path;
    final isFolder = (raw['item_type'] ?? '').toString() == 'folder';
    final mimeType = raw['mimetype'] as String?;
    final expiration = raw['expiration'] as String?;

    return NextcloudShare(
      id: (raw['id'] ?? '').toString(),
      path: path,
      name: name,
      itemType: NextcloudItem.deduceType(name, isFolder, mimeType),
      shareType: _mapShareType((raw['share_type'] as num?)?.toInt() ?? -1),
      ownerDisplayName: (raw['displayname_owner'] ?? raw['uid_owner'] ?? '')
          .toString(),
      sharedWithDisplayName: raw['share_with_displayname'] as String?,
      sharedAt: DateTime.fromMillisecondsSinceEpoch(
        ((raw['stime'] as num?)?.toInt() ?? 0) * 1000,
      ),
      sharedWithMe: sharedWithMe,
      url: raw['url'] as String?,
      permissions: (raw['permissions'] as num?)?.toInt() ?? 1,
      token: raw['token'] as String?,
      expireDate: expiration != null ? DateTime.tryParse(expiration) : null,
    );
  }

  /// The current user's own direct shares on a single file/folder (for the
  /// Details sheet's Sharing tab) — unlike [fetchShares], scoped to one path.
  Future<List<NextcloudShare>> fetchSharesForPath(String path) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/shares'
        '?format=json&path=${Uri.encodeQueryComponent(path)}&reshares=true';
    debugPrint('[Nextcloud OCS] Fetching shares for path $path');

    final response = await http.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load shares. HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    final rawList = data['ocs']?['data'];
    if (rawList is! List) return [];
    return rawList
        .map<NextcloudShare>((raw) => _shareFromJson(raw, sharedWithMe: false))
        .toList();
  }

  /// Shares inherited from a parent folder that the current user doesn't
  /// own directly ("Others with access" in the web UI). Returns an empty
  /// list rather than throwing on servers too old to support this endpoint.
  Future<List<NextcloudShare>> fetchInheritedShares(String path) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/shares/inherited'
        '?format=json&path=${Uri.encodeQueryComponent(path)}';
    debugPrint('[Nextcloud OCS] Fetching inherited shares for path $path');

    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final rawList = data['ocs']?['data'];
      if (rawList is! List) return [];
      return rawList
          .map<NextcloudShare>(
            (raw) => _shareFromJson(raw, sharedWithMe: false),
          )
          .toList();
    } catch (e) {
      debugPrint('[Nextcloud OCS] Inherited shares unavailable: $e');
      return [];
    }
  }

  /// Searches users/teams (groups) a file/folder can be shared with.
  Future<List<NextcloudSharee>> searchSharees(String query) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/sharees'
        '?format=json&itemType=file&search=${Uri.encodeQueryComponent(query)}';
    debugPrint('[Nextcloud OCS] Searching sharees for "$query"');

    final response = await http.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Sharee search failed. HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body)['ocs']?['data'];
    if (data is! Map) return [];

    NextcloudSharee? fromEntry(dynamic raw, ShareeType type) {
      if (raw is! Map) return null;
      final value = raw['value'];
      final shareWith = value is Map ? value['shareWith'] as String? : null;
      if (shareWith == null) return null;
      return NextcloudSharee(
        shareWith: shareWith,
        label: (raw['label'] ?? shareWith).toString(),
        type: type,
        subtitle: value is Map
            ? value['shareWithAdditionalInfo'] as String?
            : null,
      );
    }

    final results = <NextcloudSharee>[];
    final seen = <String>{};
    void addAll(String bucket, ShareeType type) {
      final list = data[bucket];
      final exactList = (data['exact'] is Map) ? data['exact'][bucket] : null;
      for (final raw in [
        ...(exactList is List ? exactList : []),
        ...(list is List ? list : []),
      ]) {
        final sharee = fromEntry(raw, type);
        if (sharee == null) continue;
        final key = '${sharee.type}:${sharee.shareWith}';
        if (seen.add(key)) results.add(sharee);
      }
    }

    addAll('users', ShareeType.user);
    addAll('groups', ShareeType.group);
    return results;
  }

  String _formatDavDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// General-purpose share creation, covering public links (shareType 3),
  /// user/team shares (0/1), and email shares (4). [createPublicShareLink]
  /// is left as the simpler dedicated entry point used by the swipe action.
  Future<NextcloudShare> createShare({
    required String path,
    required int shareType,
    String? shareWith,
    String? password,
    DateTime? expireDate,
  }) async {
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json';
    debugPrint('[Nextcloud OCS] Creating share (type $shareType) for $path');

    final body = {
      'path': path,
      'shareType': '$shareType',
      'shareWith': ?shareWith,
      if (password != null && password.isNotEmpty) 'password': password,
      if (expireDate != null) 'expireDate': _formatDavDate(expireDate),
    };

    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to create share. HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body)['ocs']?['data'];
    if (data is! Map) {
      throw Exception('Server response did not include the new share.');
    }
    return _shareFromJson(data, sharedWithMe: false);
  }

  /// Per-file activity feed (Details sheet's Activity tab), unlike
  /// [fetchActivities] which is the whole-account feed.
  Future<List<NextcloudActivity>> fetchFileActivity(String fileId) async {
    // The server-side `object_type`/`object_id` filter params on the
    // activity endpoints turned out to be silently ignored (still
    // returning the whole account feed) - instead, fetch the same
    // proven-working global feed `fetchActivities` uses (with a larger
    // page so older file-specific entries aren't cut off) and filter to
    // this file ourselves using each entry's own `object_id`, which the
    // server always includes for rich-subject substitution regardless of
    // whether the query-param filter works.
    final url =
        '$_cleanServerUrl/ocs/v2.php/apps/activity/api/v2/activity'
        '?format=json&limit=200';
    debugPrint('[Nextcloud OCS] Fetching activity feed to filter for $fileId');

    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      debugPrint(
        '[Nextcloud OCS] File activity response status: ${response.statusCode}',
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final rawData = data['ocs']?['data'];
      List<dynamic> list = [];
      if (rawData is List) {
        list = rawData;
      } else if (rawData is Map && rawData['activity'] is List) {
        list = rawData['activity'];
      }

      return list.where((a) => (a['object_id'] ?? '').toString() == fileId).map(
        (a) {
          return NextcloudActivity(
            id: (a['activity_id'] ?? '').toString(),
            title: a['subject'] ?? 'Activity',
            subject: a['message'] ?? (a['subject'] ?? ''),
            timestamp: _parseActivityDateTime(a['datetime']),
            icon: Icons.cloud_outlined,
            author: a['user'] ?? username,
          );
        },
      ).toList();
    } catch (e) {
      debugPrint('[Nextcloud OCS] File activity unavailable: $e');
      return [];
    }
  }

  /// Lists a file's version history via the DAV versions endpoint.
  Future<List<NextcloudFileVersion>> fetchFileVersions(String fileId) async {
    final url =
        '$_cleanServerUrl/remote.php/dav/versions/$username/versions/$fileId';
    debugPrint('[Nextcloud DAV] Requesting PROPFIND for versions of $fileId');

    const body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getlastmodified/>
    <d:getcontentlength/>
  </d:prop>
</d:propfind>''';

    try {
      final request = http.Request('PROPFIND', Uri.parse(url))
        ..headers.addAll({
          ..._headers,
          'Depth': '1',
          'Content-Type': 'application/xml',
        })
        ..body = body;
      final streamed = await http.Client().send(request);
      final responseBody = await streamed.stream.bytesToString();
      if (streamed.statusCode != 207 && streamed.statusCode != 200) {
        debugPrint(
          '[Nextcloud DAV] Versions PROPFIND failed: ${streamed.statusCode}',
        );
        return [];
      }

      final document = xml.XmlDocument.parse(responseBody);
      final responses = document.findLocalDescendants('response');
      final versions = <NextcloudFileVersion>[];
      for (final res in responses) {
        final href = res.findLocalChildren('href').firstOrNull?.innerText ?? '';
        final hrefPath = _davPath(Uri.decodeFull(href));
        // Skip the versions collection entry itself.
        if (hrefPath.endsWith('/versions/$fileId')) continue;
        final versionLabel = hrefPath.split('/').lastOrNull;
        if (versionLabel == null || versionLabel.isEmpty) continue;

        final props = res.findLocalDescendants('prop');
        String? lastModStr;
        String? sizeStr;
        for (final prop in props) {
          lastModStr ??= prop
              .findLocalChildren('getlastmodified')
              .firstOrNull
              ?.innerText;
          sizeStr ??= prop
              .findLocalChildren('getcontentlength')
              .firstOrNull
              ?.innerText;
        }
        final timestamp = _parseDavDate(lastModStr) ?? DateTime.now();
        versions.add(
          NextcloudFileVersion(
            versionLabel: versionLabel,
            timestamp: timestamp,
            size: int.tryParse(sizeStr ?? '') ?? 0,
          ),
        );
      }
      versions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return versions;
    } catch (e) {
      debugPrint('[Nextcloud DAV] Fetching versions failed: $e');
      return [];
    }
  }

  /// Restores [versionLabel] as the current version of [fileId].
  Future<bool> restoreFileVersion(String fileId, String versionLabel) async {
    final source =
        '$_cleanServerUrl/remote.php/dav/versions/$username/versions/$fileId/$versionLabel';
    final destination =
        '$_cleanServerUrl/remote.php/dav/versions/$username/restore/$versionLabel';
    debugPrint('[Nextcloud DAV] Restoring version $versionLabel of $fileId');

    final request = http.Request('MOVE', Uri.parse(source))
      ..headers.addAll({..._headers, 'Destination': destination});
    final response = await http.Client().send(request);
    debugPrint(
      '[Nextcloud DAV] Restore version status: ${response.statusCode}',
    );
    return response.statusCode == 201 || response.statusCode == 204;
  }

  /// Downloads a specific historical version's bytes to [savePath].
  Future<void> downloadVersionToFile(
    String fileId,
    String versionLabel,
    String savePath,
  ) async {
    final url =
        '$_cleanServerUrl/remote.php/dav/versions/$username/versions/$fileId/$versionLabel';
    final dio = Dio();
    await dio.download(url, savePath, options: Options(headers: _headers));
  }

  Future<bool> toggleFavorite(
    String itemPath,
    bool currentFavoriteState,
  ) async {
    var cleanPath = itemPath.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';

    final url = '$_cleanServerUrl/remote.php/dav/files/$username$cleanPath';
    final newFavVal = currentFavoriteState ? '0' : '1';
    debugPrint('[Nextcloud DAV] Toggling favorite ($newFavVal) for $url');

    final body =
        '''<?xml version="1.0" encoding="utf-8" ?>
<d:propertyupdate xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:set>
    <d:prop>
      <oc:favorite>$newFavVal</oc:favorite>
    </d:prop>
  </d:set>
</d:propertyupdate>''';

    final request = http.Request('PROPPATCH', Uri.parse(url))
      ..headers.addAll({..._headers, 'Content-Type': 'application/xml'})
      ..body = body;

    final response = await http.Client().send(request);
    debugPrint(
      '[Nextcloud DAV] Toggle favorite status: ${response.statusCode}',
    );
    return response.statusCode == 207 || response.statusCode == 200;
  }
}
