import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/app_tab.dart';
import 'package:noo/models/selection_action.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/photos_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/widgets/noo/nav/noo_bottom_bar.dart';
import 'package:noo/widgets/noo/nav/noo_nav_style.dart';

import '../views/files_test_harness.dart';

/// "Reset UI defaults": every UI preference back to its default and the saved
/// values forgotten - but not accounts, locks or sync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpFilesHarness();

  Future<SettingsController> build() async {
    final settings = SettingsController();
    // `_load` is async and not exposed; one event-loop turn lets it finish.
    await Future<void>.delayed(Duration.zero);
    return settings;
  }

  /// Every getter that carries a preference.
  List<Object?> snapshot(SettingsController s) => [
    s.seedColor,
    s.themeMode,
    s.bottomBarStyle,
    s.bottomBarFrosted,
    s.bottomBarFrostedBlur,
    s.bottomBarFrostedOpacity,
    s.avatarPosition,
    s.navMenuStyle,
    s.searchInBottomBar,
    s.useDynamicColor,
    s.amoledDark,
    s.mediaProgressBarStyle,
    s.tapTabToScrollTop,
    s.selectionBarPosition,
    s.keepFiltersWhileSelecting,
    s.tabOrder,
    s.hiddenTabs,
    s.defaultTab,
    s.selectionActionOrder,
    s.swipeLeftAction,
    s.swipeRightAction,
    s.fabStyle,
  ];

  group('SettingsController.resetToDefaults', () {
    test('puts every preference back to what a fresh install has', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await build();
      settings
        ..setThemeMode(ThemeMode.dark)
        ..setSeedColor(Colors.red)
        ..setAmoledDark(true)
        ..setMediaProgressBarStyle(MediaProgressBarStyle.slim)
        ..setTapTabToScrollTop(false)
        ..setSelectionBarPosition(SelectionBarPosition.bottom)
        ..setKeepFiltersWhileSelecting(false)
        ..setBottomBarStyle(NooBottomBarStyle.floating)
        ..setBottomBarFrosted(true)
        ..setFrostedBlur(33)
        ..setFrostedOpacity(0.4)
        ..setAvatarPosition(AvatarPosition.bottom)
        ..setNavMenuStyle(NooNavMenuStyle.avatarMenu)
        ..setSearchInBottomBar(true)
        ..setSwipeLeftAction(SwipeAction.share)
        ..setSwipeRightAction(SwipeAction.none)
        ..setFabStyle(FabStyle.mini)
        ..setTabOrder(AppTab.values.reversed.toList())
        ..setSelectionActionOrder(SelectionActionKind.values.reversed.toList());
      settings.setTabHidden(settings.tabOrder.last, true);
      settings.setDefaultTab(settings.tabOrder.first);

      await settings.resetToDefaults();

      // Compared with a controller loading from the now-empty store, i.e.
      // exactly what a first launch gets.
      final fresh = await build();
      expect(snapshot(settings), snapshot(fresh));

      // ...and nothing is left saved that would come back on restart.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('ui_')), isEmpty);
    });

    test('tells listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await build();
      var notified = 0;
      settings.addListener(() => notified++);
      await settings.resetToDefaults();
      expect(notified, greaterThan(0));
    });

    test('leaves non-UI settings alone', () async {
      SharedPreferences.setMockInitialValues({
        'ui_theme_mode': 'dark',
        'ui_login_lock_enabled': true,
        'ui_lock_account_switching': true,
        'ui_lock_hidden_files': true,
        'ui_sync_everything': true,
        'ui_cache_policy': 'never',
        'accounts_list': '[]',
      });
      final settings = await build();
      await settings.resetToDefaults();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('ui_theme_mode'), isFalse);
      for (final key in [
        'ui_login_lock_enabled',
        'ui_lock_account_switching',
        'ui_lock_hidden_files',
        'ui_sync_everything',
        'ui_cache_policy',
        'accounts_list',
      ]) {
        expect(prefs.containsKey(key), isTrue, reason: '$key must survive');
      }
    });
  });

  group('per-account list prefs', () {
    test('Files and Photos view prefs reset and are forgotten', () async {
      SharedPreferences.setMockInitialValues({});
      final session = HarnessSession(HarnessConnectivity());
      addTearDown(session.dispose);
      final files = FilesController(session);
      addTearDown(files.dispose);
      final photos = PhotosController(session, files);
      addTearDown(photos.dispose);

      files
        ..setGridView(true)
        ..setStorageScope(StorageScope.cloud)
        ..setOwnershipFilter(OwnershipFilter.shared)
        ..setFilesTypeFilter(FilesTypeFilter.foldersOnly)
        ..setSortFieldFor('/', FileSortField.size);
      await files.setHiddenFilter(HiddenFilesFilter.include);
      photos
        ..toggleFavoritesFilter()
        ..setSortField(FileSortField.name);
      await photos.setHiddenFilter(HiddenFilesFilter.only);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('ui_')), isNotEmpty);

      await files.resetDisplayPrefs();
      await photos.resetDisplayPrefs();

      expect(files.isGridView, isFalse);
      expect(files.storageScope, StorageScope.all);
      expect(files.ownershipFilter, OwnershipFilter.all);
      expect(files.filesTypeFilter, FilesTypeFilter.all);
      expect(files.hiddenFilter, HiddenFilesFilter.hide);
      expect(files.sortFieldFor('/'), FileSortField.name);
      expect(files.sortAscendingFor('/'), isTrue);
      expect(photos.showFavoritesOnly, isFalse);
      expect(photos.hiddenFilter, HiddenFilesFilter.hide);
      expect(photos.sortField, FileSortField.dateCreated);
      expect(photos.sortAscending, isFalse);
      expect(
        prefs.getKeys().where((k) => k.contains('ui_')),
        isEmpty,
        reason: 'nothing saved that would come back on restart',
      );
    });
  });
}
