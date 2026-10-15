import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/nextcloud_item.dart';
import 'package:noo/models/nextcloud_share.dart';
import 'package:noo/models/saved_account.dart';
import 'package:noo/providers/connectivity_controller.dart';
import 'package:noo/providers/favorites_controller.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/item_operations.dart';
import 'package:noo/providers/offline_controller.dart';
import 'package:noo/providers/photos_controller.dart';
import 'package:noo/providers/pick_controller.dart';
import 'package:noo/providers/recent_controller.dart';
import 'package:noo/providers/session_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/providers/shares_controller.dart';
import 'package:noo/providers/sync_status_controller.dart';
import 'package:noo/providers/trash_controller.dart';
import 'package:noo/theme/app_theme.dart';

/// A listing item for the Files view tests: [mountType] `shared` / `external`
/// marks received shares / external storage like the server does.
NextcloudItem harnessItem(
  String name, {
  String? mountType,
  String? ownerId,
  String? ownerDisplayName,
  bool folder = false,
  String parent = '/',
}) => NextcloudItem(
  id: name,
  name: name,
  path: '$parent$name',
  type: folder ? NextcloudItemType.folder : NextcloudItemType.file,
  size: 1024,
  lastModified: DateTime(2026, 10, 1),
  mountType: mountType,
  ownerId: ownerId,
  ownerDisplayName: ownerDisplayName,
);

/// Stands in for the signed-in account without touching the network.
class HarnessSession extends SessionController {
  HarnessSession(super.connectivity);
  static const account = SavedAccount(
    id: 'a',
    serverUrl: 'https://cloud.example.com',
    username: 'alex',
  );
  @override
  List<SavedAccount> get accounts => [account];
  @override
  String? get activeAccountId => 'a';
  @override
  SavedAccount? get activeAccount => account;
  @override
  String get serverUrl => 'https://cloud.example.com';
  @override
  String get username => 'alex';
  @override
  String get displayName => 'Alex Morgan';
  @override
  bool get isLoggedIn => true;
}

/// A Files controller over a fixed root listing; the real display-pref
/// filtering still runs on top of it.
class HarnessFiles extends FilesController {
  HarnessFiles(super.session, this.raw);
  final List<NextcloudItem> raw;
  @override
  List<NextcloudItem> get items => applyFilesDisplayPrefs(raw);
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  Future<void> refreshData() async {}
}

/// Share lookups answer with no shares, as for a freshly shared file.
class HarnessOps extends ItemOperations {
  const HarnessOps({
    required super.session,
    required super.files,
    required super.photos,
    required super.favorites,
  });
  @override
  Future<List<NextcloudShare>> fetchItemShares(NextcloudItem item) async => [];
  @override
  Future<List<NextcloudShare>> fetchInheritedShares(NextcloudItem item) async =>
      [];
}

/// A Shares controller over fixed lists for each scope, with no fetching.
class HarnessShares extends SharesController {
  HarnessShares(
    super.session, {
    this.withYou = const [],
    this.byYou = const [],
  });
  final List<NextcloudShare> withYou;
  final List<NextcloudShare> byYou;
  bool _withMe = false;
  @override
  List<NextcloudShare> get shares => _withMe ? withYou : byYou;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  Future<void> fetchAll() async {}
  @override
  void setSharedWithMe(bool value) {
    _withMe = value;
    notifyListeners();
  }
}

class HarnessConnectivity extends ConnectivityController {
  @override
  bool get isOffline => false;
}

/// Mocks the platform channels the controllers touch on construction.
///
/// [loadFonts] registers the app's bundled fonts so text measures like it
/// does on a device (the test default is a much wider fallback font, which
/// overflows tight rows that are fine in the app).
void setUpFilesHarness({bool loadFonts = false}) {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (loadFonts) {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in manifest) {
        final loader = FontLoader(entry['family'] as String);
        for (final font in entry['fonts'] as List) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    for (final name in [
      'dev.fluttercommunity.plus/connectivity_status',
      'dev.ayushya.noo/upload_service/status',
      'dev.ayushya.noo/sync_service/status',
      'dev.ayushya.noo/share_intent/new',
      'dev.ayushya.noo/pick_intent/new',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel(name),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
}

/// Everything a test wants to poke after [pumpWithApp].
class AppHarness {
  final HarnessFiles files;
  final ScrollController scroll;
  final List<ChangeNotifier> _controllers;
  AppHarness(this.files, this.scroll, this._controllers);

  /// Unmounts the app and disposes its controllers. Call at the end of every
  /// test: the binding checks for pending timers (ConnectivityController
  /// arms one on construction) before `addTearDown` callbacks run.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Rows stagger their enter animation with an uncancellable
    // `Future.delayed` (up to 150ms) - let those elapse.
    await tester.pump(const Duration(milliseconds: 200));
    for (final controller in _controllers) {
      controller.dispose();
    }
    scroll.dispose();
  }
}

/// Pumps [home] inside the providers the Files/share screens read, at
/// [size] logical pixels (phone-sized by default - below the 600dp tablet
/// breakpoint).
Future<AppHarness> pumpWithApp(
  WidgetTester tester,
  List<NextcloudItem> raw,
  Widget Function(ScrollController scroll) home, {
  Size size = const Size(400, 800),
  SharesController Function(SessionController session)? sharesBuilder,
}) async {
  // devicePixelRatio 1 so `size` is the logical size - `setSurfaceSize`
  // alone keeps the test default of 3, which makes a "400 wide" phone 133dp.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final connectivity = HarnessConnectivity();
  final session = HarnessSession(connectivity);
  final files = HarnessFiles(session, raw);
  final settings = SettingsController();
  final sync = SyncStatusController(session, files);
  final offline = OfflineController(session, files);
  final pick = PickController(session);
  final photos = PhotosController(session, files);
  final favorites = FavoritesController(session, files);
  final ops = HarnessOps(
    session: session,
    files: files,
    photos: photos,
    favorites: favorites,
  );
  final scroll = ScrollController();
  final shares = sharesBuilder?.call(session) ?? SharesController(session);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectivityController>.value(
          value: connectivity,
        ),
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<FilesController>.value(value: files),
        ChangeNotifierProvider<SyncStatusController>.value(value: sync),
        ChangeNotifierProvider<OfflineController>.value(value: offline),
        ChangeNotifierProvider<PickController>.value(value: pick),
        ChangeNotifierProvider<PhotosController>.value(value: photos),
        ChangeNotifierProvider<FavoritesController>.value(value: favorites),
        ChangeNotifierProvider<TrashController>.value(
          value: TrashController(session),
        ),
        ChangeNotifierProvider<SharesController>.value(value: shares),
        ChangeNotifierProvider<RecentController>.value(
          value: RecentController(session),
        ),
        Provider<ItemOperations>.value(value: ops),
      ],
      child: MaterialApp(
        theme: AppTheme.light(AppTheme.defaultAccent, useDynamicColor: false),
        home: Scaffold(body: home(scroll)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  return AppHarness(files, scroll, [
    connectivity,
    session,
    files,
    settings,
    sync,
    offline,
    pick,
    photos,
    favorites,
    shares,
  ]);
}
