import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/nextcloud_item.dart';
import 'package:noo/providers/connectivity_controller.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/session_controller.dart';

NextcloudItem _item(String path, {String? mountType}) => NextcloudItem(
  id: path,
  name: path.split('/').last,
  path: path,
  type: NextcloudItemType.file,
  size: 1,
  lastModified: DateTime(2026),
  mountType: mountType,
);

/// The shared hidden / storage-scope filtering (`applyCommonFilters`) and
/// how a pref saved before the three-way hidden filter is read back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['none'] : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final items = [
    _item('/a.txt'),
    _item('/.secret'),
    _item('/docs/.git/config'),
    _item('/nas', mountType: 'external'),
    _item('/.nas-hidden', mountType: 'external'),
  ];
  List<String> paths(List<NextcloudItem> l) => l.map((i) => i.path).toList();

  FilesController build() =>
      FilesController(SessionController(ConnectivityController()));

  test('hidden filter: hide / only / include', () {
    final files = build()..setStorageScope(StorageScope.all);
    List<String> run(HiddenFilesFilter h) => paths(
      files.applyCommonFilters(items, showFavoritesOnly: false, hidden: h),
    );
    expect(run(HiddenFilesFilter.hide), ['/a.txt', '/nas']);
    expect(run(HiddenFilesFilter.only), [
      '/.secret',
      '/docs/.git/config',
      '/.nas-hidden',
    ]);
    expect(run(HiddenFilesFilter.include), paths(items));
  });

  test('storage scope: cloud / external / all', () {
    final files = build();
    List<String> run(StorageScope s) {
      files.setStorageScope(s);
      return paths(
        files.applyCommonFilters(
          items,
          showFavoritesOnly: false,
          hidden: HiddenFilesFilter.include,
        ),
      );
    }

    expect(run(StorageScope.cloud), [
      '/a.txt',
      '/.secret',
      '/docs/.git/config',
    ]);
    expect(run(StorageScope.external), ['/nas', '/.nas-hidden']);
    expect(run(StorageScope.all), paths(items));
  });

  test('hidden + external combine', () {
    final files = build()..setStorageScope(StorageScope.external);
    expect(
      paths(
        files.applyCommonFilters(
          items,
          showFavoritesOnly: false,
          hidden: HiddenFilesFilter.only,
        ),
      ),
      ['/.nas-hidden'],
    );
  });

  group('loadHiddenFilter', () {
    Future<HiddenFilesFilter> load(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return FilesController.loadHiddenFilter(
        await SharedPreferences.getInstance(),
        'new',
        'old',
      );
    }

    test('defaults to hide', () async {
      expect(await load({}), HiddenFilesFilter.hide);
    });

    test('the old show-hidden bool maps to hide / include', () async {
      expect(await load({'old': true}), HiddenFilesFilter.include);
      expect(await load({'old': false}), HiddenFilesFilter.hide);
    });

    test('the new key wins and an unknown value falls back to hide', () async {
      expect(await load({'new': 'only', 'old': true}), HiddenFilesFilter.only);
      expect(await load({'new': 'bogus'}), HiddenFilesFilter.hide);
    });
  });
}
