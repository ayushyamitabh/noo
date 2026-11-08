// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/services/thumbnail_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  late HttpServer server;
  late Directory tmp;
  var hits = 0;
  final authSeen = <String?>[];

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test stubs every HttpClient with a 400 responder by default.
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('thumbs');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await ThumbnailCache.clear();
    hits = 0;
    authSeen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      hits++;
      authSeen.add(req.headers.value('authorization'));
      req.response
        ..statusCode = req.uri.path == '/missing' ? 404 : 200
        ..add([1, 2, 3, 4])
        ..close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  test('keyFor is stable and changes with url and version', () {
    final v = DateTime.utc(2026, 1, 1);
    expect(ThumbnailCache.keyFor('a', v), ThumbnailCache.keyFor('a', v));
    expect(ThumbnailCache.keyFor('a', v), isNot(ThumbnailCache.keyFor('b', v)));
    expect(
      ThumbnailCache.keyFor('a', v),
      isNot(ThumbnailCache.keyFor('a', v.add(const Duration(seconds: 1)))),
    );
  });

  test('second load comes from disk, not the network', () async {
    final key = ThumbnailCache.keyFor(url('/p'), DateTime.utc(2026));
    final first = await ThumbnailCache.load(
      url: url('/p'),
      key: key,
      headers: {'authorization': 'Basic abc'},
    );
    final second = await ThumbnailCache.load(url: url('/p'), key: key);
    expect(first, [1, 2, 3, 4]);
    expect(second, [1, 2, 3, 4]);
    expect(hits, 1);
    expect(authSeen.single, 'Basic abc');
  });

  test('concurrent loads of one key share a single download', () async {
    final key = ThumbnailCache.keyFor(url('/p'), DateTime.utc(2026));
    await Future.wait([
      for (var i = 0; i < 5; i++) ThumbnailCache.load(url: url('/p'), key: key),
    ]);
    expect(hits, 1);
  });

  test('a changed version re-downloads; clear() empties the cache', () async {
    final k1 = ThumbnailCache.keyFor(url('/p'), DateTime.utc(2026));
    final k2 = ThumbnailCache.keyFor(url('/p'), DateTime.utc(2027));
    await ThumbnailCache.load(url: url('/p'), key: k1);
    await ThumbnailCache.load(url: url('/p'), key: k2);
    expect(hits, 2);
    await ThumbnailCache.clear();
    await ThumbnailCache.load(url: url('/p'), key: k1);
    expect(hits, 3);
  });

  test('an HTTP error throws and caches nothing', () async {
    final key = ThumbnailCache.keyFor(url('/missing'), DateTime.utc(2026));
    await expectLater(
      ThumbnailCache.load(url: url('/missing'), key: key),
      throwsA(isA<HttpException>()),
    );
    await expectLater(
      ThumbnailCache.load(url: url('/missing'), key: key),
      throwsA(isA<HttpException>()),
    );
    expect(hits, 2);
  });
}
