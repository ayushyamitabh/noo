// Drives the real app through its tabs and states against the fake-data demo
// server and captures the Play Store screenshots. Not part of the normal test
// suite (`flutter test` only runs `test/`) - run it through
// `tool/screenshots.sh`, which starts the demo server, an emulator and the
// driver in `test_driver/integration_test.dart` that saves the images.
//
// The app starts already logged in: the demo user's credentials are written
// straight into storage before `main()` runs, so Login Flow v2's browser
// step is skipped.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noo/main.dart' as app;
import 'package:noo/models/app_tab.dart';
import 'package:noo/models/saved_account.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/providers/sync_status_controller.dart';
import 'package:noo/services/account_store.dart';
import 'package:noo/theme/design_tokens.dart';
import 'package:noo/widgets/bottom_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _serverUrl = String.fromEnvironment(
  'DEMO_SERVER_URL',
  defaultValue: 'http://localhost',
);
const _username = String.fromEnvironment('DEMO_USERNAME', defaultValue: 'Alex');
const _appPassword = String.fromEnvironment('DEMO_APP_PASSWORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Play Store screenshots',
    (tester) async {
      expect(
        _appPassword,
        isNotEmpty,
        reason: 'Pass the demo user\'s app password via '
            '--dart-define=DEMO_APP_PASSWORD=... (tool/screenshots.sh does).',
      );
      await _seedLoggedInStorage();

      app.main();
      await tester.pump();
      await _pumpUntil(tester, find.byType(app.MainShellView));

      // Android only: required before `takeScreenshot()` can capture
      // anything at all.
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

      Future<void> shoot(String name) async {
        // Let scroll/transition animations and image fades finish first.
        await tester.pump(const Duration(seconds: 1));
        await binding.takeScreenshot(name);
      }

      // ---- 01 Files (list) ------------------------------------------------
      final filesTab = find.byKey(const ValueKey('files'));
      await _pumpUntil(
        tester,
        find.descendant(of: filesTab, matching: find.text('Documents')),
      );
      await shoot('01_Files');

      // ---- 02 Files (grid, inside a folder of photos) --------------------
      final files = _read<FilesController>(tester);
      await files.navigateToAbsoluteFolder('/Trips');
      await _pumpUntil(
        tester,
        find.descendant(of: filesTab, matching: find.text('Lake sunrise.jpg')),
      );
      // The controls row scrolls horizontally and doesn't fit every control
      // on a narrow screen, so "Grid view" can start off past the clipped
      // edge - not just off the *current* tab (which `.hitTestable()` alone
      // would handle), but off the *visible part of this tab's own row*.
      // `_tapInTab` scrolls it into view first.
      await _tapInTab(tester, filesTab, find.byTooltip('Grid view'));
      await tester.pump(const Duration(seconds: 4)); // thumbnails
      await shoot('02_Files_Grid');

      // ---- 07 File viewer -------------------------------------------------
      await _tapInTab(tester, filesTab, find.text('Lake sunrise.jpg'));
      await tester.pump(const Duration(seconds: 4));
      await shoot('07_Viewer');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(seconds: 1));

      // Back to the root folder, list view.
      await _tapInTab(tester, filesTab, find.byTooltip('List view'));
      await files.navigateToAbsoluteFolder('/');
      await tester.pump(const Duration(seconds: 2));

      // ---- 03 Photos ------------------------------------------------------
      await _goToTab(tester, AppTab.photos);
      await tester.pump(const Duration(seconds: 5)); // grid + thumbnails
      await shoot('03_Photos');

      // ---- 04 Favorites ---------------------------------------------------
      await _goToTab(tester, AppTab.favorites);
      await _pumpUntil(tester, find.text('Project brief.pdf'));
      await shoot('04_Favorites');

      // ---- 05 Activity ----------------------------------------------------
      await _goToTab(tester, AppTab.activity);
      await tester.pump(const Duration(seconds: 3));
      await shoot('05_Activity');

      // ---- 06 Shares ------------------------------------------------------
      await _goToTab(tester, AppTab.shares);
      await tester.pump(const Duration(seconds: 3));
      await shoot('06_Shares');

      // ---- 08 Sync status panel ------------------------------------------
      // Sync two folders to the device; the header chip flips to "Synced"
      // once the native worker has finished, and tapping it opens the panel.
      await _goToTab(tester, AppTab.files);
      await _read<SyncStatusController>(
        tester,
      ).addSyncedPaths({'/Documents': true, '/Trips': true});
      await _pumpUntil(tester, find.text('Synced'), timeout: 180);
      await _tapInTab(tester, filesTab, find.text('Synced'));
      await tester.pump(const Duration(seconds: 1));
      await shoot('08_Sync_Status');
      await _tapInTab(tester, filesTab, find.byTooltip('Collapse'));

      // ---- 09 Offline -----------------------------------------------------
      _setVisibleTabs(tester, [
        AppTab.files,
        AppTab.photos,
        AppTab.favorites,
        AppTab.shares,
        AppTab.offline,
      ]);
      await tester.pump(const Duration(milliseconds: 500));
      await _goToTab(tester, AppTab.offline);
      await _pumpUntil(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('offline')),
          matching: find.text('Documents'),
        ),
        timeout: 120,
      );
      await shoot('09_Offline');

      // ---- 10/11 Settings -------------------------------------------------
      await _tap(tester, find.byTooltip('Settings').hitTestable().first);
      await _pumpUntil(tester, find.text('Accounts'));
      await shoot('10_Settings');
      // Wait for it, rather than assuming it's already built - ensureVisible
      // itself has no retry/timeout, so on any transient delay (e.g. still
      // mid-route-transition) it fails immediately instead of giving the
      // frame a moment to catch up.
      await _pumpUntil(tester, find.text('Files Cache'));
      await tester.ensureVisible(find.text('Files Cache'));
      await tester.pump(const Duration(milliseconds: 300));
      await shoot('11_Settings_Sync');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(seconds: 1));

      // ---- 12/13 Dark theme -------------------------------------------------
      final settings = _read<SettingsController>(tester);
      settings.setThemeMode(ThemeMode.dark);
      await _goToTab(tester, AppTab.files);
      await tester.pump(const Duration(seconds: 2));
      await shoot('12_Files_Dark');
      await _goToTab(tester, AppTab.photos);
      await tester.pump(const Duration(seconds: 3));
      await shoot('13_Photos_Dark');

      // ---- 14/15 Dark theme, AMOLED (pure black) -----------------------------
      settings.setAmoledDark(true);
      await tester.pump(const Duration(seconds: 1));
      await _goToTab(tester, AppTab.files);
      await tester.pump(const Duration(seconds: 2));
      await shoot('14_Files_Dark_Amoled');
      await _goToTab(tester, AppTab.photos);
      await tester.pump(const Duration(seconds: 3));
      await shoot('15_Photos_Dark_Amoled');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

/// Starts from empty storage, then writes exactly one saved account (the
/// demo user, with the app password from `--dart-define`) and the settings
/// that make screenshots reproducible: light theme, a fixed brand colour
/// (dynamic colour would pick up the emulator's wallpaper), five bottom-nav
/// tabs, and no first-run notification prompt.
Future<void> _seedLoggedInStorage() async {
  await const FlutterSecureStorage().deleteAll();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  final store = AccountStore();
  final account = SavedAccount(
    id: SavedAccount.makeId(_serverUrl, _username),
    serverUrl: _serverUrl,
    username: _username,
  );
  await store.saveAccounts(prefs, [account]);
  await store.saveActiveAccountId(prefs, account.id);
  await store.writePassword(account.id, _appPassword);

  await prefs.setBool('notification_permission_asked', true);
  await prefs.setString('ui_theme_mode', ThemeMode.light.name);
  await prefs.setBool('ui_use_dynamic_color', false);
  await prefs.setStringList('ui_tab_order', [
    for (final t in AppTab.values) t.name,
  ]);
  await prefs.setStringList('ui_hidden_tabs', [
    AppTab.trash.name,
    AppTab.recent.name,
    AppTab.offline.name,
  ]);
}

T _read<T>(WidgetTester tester) => Provider.of<T>(
  tester.element(find.byType(app.MainShellView)),
  listen: false,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Taps the one widget matching [matching] inside [tab] (e.g. `filesTab`) -
/// for chrome that's duplicated across tabs (`IndexedStack` keeps every
/// visible tab's widget tree mounted, not just the active one) and/or can be
/// scrolled out of its own row's clipped viewport (the controls row,
/// `FilesControlsRow`, doesn't fit every control on a narrow screen).
/// Scoping to [tab] picks the right one of several identical matches;
/// `ensureVisible` scrolls it into view before tapping, which plain
/// `.hitTestable()` can't distinguish from "on the wrong tab" - both look
/// like "zero hit-testable matches" and throw the same unhelpful
/// `Bad state: No element`.
Future<void> _tapInTab(WidgetTester tester, Finder tab, Finder matching) async {
  final target = find.descendant(of: tab, matching: matching).first;
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _goToTab(WidgetTester tester, AppTab tab) async {
  // Only one bottom nav bar exists (outside the IndexedStack), so no
  // cross-tab duplicate to worry about - but it can itself overflow a
  // narrow screen, so still scroll the target into view rather than relying
  // on hitTestable() alone (see `_tapInTab`'s doc comment).
  final target = find
      .descendant(
        of: find.byType(BottomNavBar),
        matching: find.byIcon(tab.icon),
      )
      .first;
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 600));

  // Confirm the tap actually landed, rather than trusting it silently - a
  // scroll-imprecise tap (see above) that misses its target doesn't throw,
  // it just does nothing, which would otherwise leave every later
  // screenshot quietly showing whatever tab was already selected instead of
  // failing loudly. Every destination shows its label all the time now (see
  // `BottomNavBar`'s doc comment), so label presence can't signal selection
  // - the icon's color can: it's `accentText` only for the active tab.
  await _pumpUntilTrue(tester, () {
    if (target.evaluate().isEmpty) return false;
    final icon = tester.widget<Icon>(target);
    final colors = tester.element(target).nooColors;
    return icon.color == colors.accentText;
  }, timeout: 10);
}

/// Shows exactly [tabs] in the bottom nav (hiding the rest first, so the
/// five-tab cap is never hit).
void _setVisibleTabs(WidgetTester tester, List<AppTab> tabs) {
  final settings = _read<SettingsController>(tester);
  for (final tab in AppTab.values) {
    if (!tabs.contains(tab)) settings.setTabHidden(tab, true);
  }
  for (final tab in tabs) {
    settings.setTabHidden(tab, false);
  }
}

/// Waits (in real time - this is a live binding, and the app is talking to a
/// real server) until [finder] matches something.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int timeout = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeout));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out after ${timeout}s waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Like [_pumpUntil], but for a condition that isn't just "does a finder
/// match something" (e.g. a widget property).
Future<void> _pumpUntilTrue(
  WidgetTester tester,
  bool Function() predicate, {
  int timeout = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeout));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out after ${timeout}s waiting for condition');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}
