import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/nextcloud_item.dart';

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
      'User-Agent': 'Nextcloud-Flutter-Client/1.0',
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

      return NextcloudUserQuota(
        usedBytes: used,
        totalBytes: total,
        usagePercentage: pct,
        userName: display,
        email: email,
        serverVersion: 'Nextcloud Server',
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
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (a['timestamp'] as int? ?? 0) * 1000,
            ),
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
