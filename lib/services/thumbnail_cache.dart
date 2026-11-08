import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/nextcloud_item.dart';

/// A small on-disk cache for server-rendered previews (the 500x500 thumbnails
/// behind `core/preview`).
///
/// `Image.network`/`NetworkImage` only keep *decoded* images in Flutter's
/// in-memory `ImageCache` (100 MiB by default - a few hundred grid tiles at
/// screen resolution) and have no disk cache at all. Scrolling a large
/// Photos grid evicted tiles from memory and every scroll back re-downloaded
/// them; the media viewer's thumbnail strip did the same. This keeps the
/// downloaded bytes on disk so an evicted thumbnail is just a local read +
/// decode, and survives app restarts.
///
/// Entries are keyed by preview URL (which carries the server and file id)
/// plus the file's last-modified time, so an edited file gets a fresh
/// thumbnail instead of a stale one. Total size is capped at [maxBytes],
/// trimming the least recently used files first.
class ThumbnailCache {
  const ThumbnailCache._();

  static const int maxBytes = 300 * 1024 * 1024;
  static const int _trimEveryWrites = 40;

  static Directory? _dir;
  static final Map<String, Future<Uint8List>> _inflight = {};
  static int _writesSinceTrim = 0;

  static Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'thumbnails'));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// A filesystem-safe, stable name for [url] + [version] (64-bit FNV-1a -
  /// collisions would only ever show the wrong thumbnail, never leak data,
  /// and are vanishingly unlikely at this scale).
  static String keyFor(String url, DateTime version) {
    var hash = 0xcbf29ce484222325;
    for (final b in utf8.encode('$url|${version.millisecondsSinceEpoch}')) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    // Two unsigned 32-bit halves: a Dart int is signed 64-bit, so printing
    // it whole would sometimes give a leading '-'.
    String half(int v) => v.toRadixString(16).padLeft(8, '0');
    return half(hash >>> 32) + half(hash & 0xFFFFFFFF);
  }

  /// The preview bytes for [key]: from disk if cached, otherwise downloaded
  /// from [url] with [headers] and stored. Concurrent requests for the same
  /// key share one download.
  static Future<Uint8List> load({
    required String url,
    required String key,
    Map<String, String>? headers,
  }) {
    return _inflight[key] ??= _load(url, key, headers).whenComplete(() {
      _inflight.remove(key);
    });
  }

  static Future<Uint8List> _load(
    String url,
    String key,
    Map<String, String>? headers,
  ) async {
    final dir = await _directory();
    final file = File(p.join(dir.path, key));
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _touchIfStale(file);
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailCache] Read failed for $key: $e');
    }

    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw HttpException('Preview failed (HTTP ${response.statusCode})');
    }
    final bytes = response.bodyBytes;
    try {
      // Written to a temp name then renamed, so a killed write can never
      // leave a truncated thumbnail that later "loads" as a corrupt image.
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      if (++_writesSinceTrim >= _trimEveryWrites) {
        _writesSinceTrim = 0;
        unawaited(_trim());
      }
    } catch (e) {
      debugPrint('[ThumbnailCache] Write failed for $key: $e');
    }
    return bytes;
  }

  /// Marks [file] as recently used (the LRU order is the files' modified
  /// times), but only when its stamp is over a day old - not on every read
  /// while scrolling.
  static void _touchIfStale(File file) {
    unawaited(() async {
      try {
        final stat = await file.stat();
        if (DateTime.now().difference(stat.modified) >
            const Duration(days: 1)) {
          await file.setLastModified(DateTime.now());
        }
      } catch (_) {}
    }());
  }

  /// Deletes least-recently-used files until the cache is back under 80% of
  /// [maxBytes], once it has grown past it.
  static Future<void> _trim() async {
    try {
      final dir = await _directory();
      final entries = <(File, FileStat)>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        entries.add((entity, stat));
        total += stat.size;
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      final target = (maxBytes * 0.8).round();
      for (final (file, stat) in entries) {
        if (total <= target) break;
        try {
          await file.delete();
          total -= stat.size;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ThumbnailCache] Trim failed: $e');
    }
  }

  /// Drops every cached thumbnail - used when an account is removed, so its
  /// previews don't outlive it on disk.
  static Future<void> clear() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
      _inflight.clear();
    } catch (e) {
      debugPrint('[ThumbnailCache] Clear failed: $e');
    }
  }

  static Future<void> _evict(String key) async {
    try {
      final dir = await _directory();
      final file = File(p.join(dir.path, key));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// An [ImageProvider] for a server preview, backed by [ThumbnailCache].
/// Wrap in a `ResizeImage` to decode at the tile's size, as before.
///
/// Equality is URL + version only (not [headers]), so the in-memory
/// `ImageCache` still dedupes the same preview across screens.
@immutable
class CachedPreviewImage extends ImageProvider<CachedPreviewImage> {
  final String url;
  final DateTime version;
  final Map<String, String>? headers;

  const CachedPreviewImage({
    required this.url,
    required this.version,
    this.headers,
  });

  /// The cached preview of [item] (which must have a `previewUrl`).
  factory CachedPreviewImage.of(
    NextcloudItem item,
    Map<String, String>? headers,
  ) => CachedPreviewImage(
    url: item.previewUrl!,
    version: item.lastModified,
    headers: headers,
  );

  @override
  Future<CachedPreviewImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedPreviewImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedPreviewImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: 1.0,
      debugLabel: key.url,
      informationCollector: () => [DiagnosticsProperty('Preview', key.url)],
    );
  }

  Future<ui.Codec> _decode(
    CachedPreviewImage key,
    ImageDecoderCallback decode,
  ) async {
    final cacheKey = ThumbnailCache.keyFor(key.url, key.version);
    final bytes = await ThumbnailCache.load(
      url: key.url,
      key: cacheKey,
      headers: key.headers,
    );
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      // A cached file that no longer decodes (corrupt/partial) must not
      // keep failing forever - drop it so the next load re-downloads.
      await ThumbnailCache._evict(cacheKey);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedPreviewImage &&
      other.url == url &&
      other.version == version;

  @override
  int get hashCode => Object.hash(url, version);

  @override
  String toString() => 'CachedPreviewImage($url)';
}
