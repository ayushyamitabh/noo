import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:noo/widgets/settings/settings_about.dart';
import 'package:noo/widgets/noo/core/noo_search_field.dart';
import 'package:noo/views/search_view.dart';
import 'package:noo/widgets/shell/tablet_account_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/saved_account.dart';
import 'package:noo/providers/connectivity_controller.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/session_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/providers/sync_status_controller.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/views/account_view.dart';
import 'package:noo/widgets/noo/nav/noo_top_bar.dart';

/// Covers the mobile Settings navigation restructure: a top-level menu of
/// category rows (`account_view.dart`'s `_MobileMenu`) that pushes a
/// single-section screen per row, replacing the old design where every
/// section rendered inline in one long scrolling column. This only covers
/// the menu/push/back mechanics - each section's own content already has
/// (or doesn't need) its own coverage elsewhere.
void main() {
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  const connectivityStatusChannel = EventChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );

  const accountId = 'server_example_com__alice';
  const passwordKey = 'nc_app_password_$accountId';
  const password = 'app-password';

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'readAll') {
            return <String, String>{passwordKey: password};
          }
          if (call.method == 'read') {
            final key = (call.arguments as Map)['key'] as String?;
            return key == passwordKey ? password : null;
          }
          return null;
        });
    // Offline, like `session_controller_test.dart`'s setup: keeps
    // SessionController in a provisional login (no real HTTP calls) and
    // stops FilesController/SyncStatusController from starting their
    // network-fetch/periodic-refresh machinery, which would otherwise
    // leave timers pending forever in a test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return <String>['none'];
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          connectivityStatusChannel,
          MockStreamHandler.inline(onListen: (arguments, events) {}),
        );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'account_migration_v1_done': true,
      'accounts_list': jsonEncode([
        const SavedAccount(
          id: accountId,
          serverUrl: 'https://server.example.com',
          username: 'alice',
        ).toJson(),
      ]),
      'active_account_id': accountId,
    });
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Widget home = const AccountView(),
    Size size = const Size(400, 800),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ConnectivityController()),
          ChangeNotifierProvider(
            create: (context) => SessionController(context.read()),
          ),
          ChangeNotifierProvider(create: (_) => SettingsController()),
          ChangeNotifierProvider(
            create: (context) => FilesController(context.read()),
          ),
          ChangeNotifierProvider(
            create: (context) =>
                SyncStatusController(context.read(), context.read()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(AppTheme.defaultAccent, useDynamicColor: false),
          home: home,
        ),
      ),
    );

    // Not `pumpAndSettle`: once the saved account is ready,
    // FilesController/SyncStatusController start their own periodic
    // refresh timers, which `pumpAndSettle` would spin on forever. A
    // bounded number of small pumps is enough to flush the async gaps in
    // SessionController's prefs restore and the dependent controllers'
    // one-shot account-ready reactions (mirrors
    // `session_controller_test.dart`'s `pumpUntil` loop).
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// Advances exactly far enough to finish a push/pop transition
  /// (`MaterialPageRoute`'s default is 300ms) without risking
  /// `pumpAndSettle` picking up a pending periodic timer.
  Future<void> settleNav(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  const categoryTitles = [
    'Accounts',
    'Security',
    'File sync',
    'Files cache',
    'Appearance',
    'Tabs',
    'Action bar',
    'Swipe on a file',
    'About',
  ];

  testWidgets(
    'shows a top-level menu of category rows, not every section inline',
    (tester) async {
      await pumpSettings(tester);

      // The account card (pinned, not a category row of its own) ...
      expect(find.text('alice'), findsOneWidget);
      // ... plus exactly one row per section.
      for (final title in categoryTitles) {
        expect(find.text(title), findsOneWidget);
      }
      // A section's own content isn't rendered until its row is tapped -
      // this is a menu, not the old all-sections-inline column.
      expect(
        find.text("Require this device's PIN or biometric to open Noo"),
        findsNothing,
      );
    },
  );

  testWidgets(
    'tapping a category row pushes just that section, with a way back',
    (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Security'));
      await settleNav(tester);

      // Landed on a separate, pushed Security screen: its own content -
      // not shown anywhere on the top-level menu - is now visible. (The
      // menu screen below it may stay mounted per `PageRoute.maintainState`,
      // so this checks for the pushed screen's content rather than the
      // menu's absence.)
      expect(
        find.text("Require this device's PIN or biometric to open Noo"),
        findsOneWidget,
      );
      // At least one `NooTopBarBack` now leads back - the pushed screen's
      // own, on top of `AccountView`'s own (for returning to the shell).
      expect(find.byType(NooTopBarBack), findsAtLeastNWidgets(1));

      // Tapping the topmost back button pops the pushed screen back off,
      // taking its content with it - unlike the underlying menu, a popped
      // route is actually removed, so this absence check is meaningful.
      await tester.tap(find.byType(NooTopBarBack).last);
      await settleNav(tester);

      expect(
        find.text("Require this device's PIN or biometric to open Noo"),
        findsNothing,
      );
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    },
  );
  testWidgets(
    'tablet hides phone navigation preferences and keeps viewer glass',
    (tester) async {
      await pumpSettings(tester, size: const Size(768, 1024));
      expect(find.text('Swipe on a file'), findsNothing);
      await tester.tap(find.text('Appearance'));
      await settleNav(tester);
      for (final label in [
        'Bottom bar style',
        'Menu style',
        'Avatar position',
        'Search in bottom bar',
        'Upload button',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('Frosted glass'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      await tester.tap(find.text('Tabs'));
      await settleNav(tester);
      expect(find.text('Tap tab to scroll to top'), findsNothing);
      expect(find.text('Default tab'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('About reads installed version and build', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Noo',
      packageName: 'dev.ayushya.noo',
      version: '2.3.4',
      buildNumber: '42',
      buildSignature: '',
    );
    await pumpSettings(
      tester,
      home: const Scaffold(body: SettingsAboutSection()),
    );
    expect(find.text('2.3.4'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('dev.ayushya.noo'), findsOneWidget);
  });

  testWidgets('tablet Search header stays below status bar', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 48);
    addTearDown(tester.view.resetPadding);
    await pumpSettings(
      tester,
      home: const SearchView(),
      size: const Size(768, 1024),
    );
    expect(
      tester.getTopLeft(find.byType(NooSearchField)).dy,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'portrait tablet Settings selects sections inline and expands accounts',
    (tester) async {
      await pumpSettings(tester, size: const Size(768, 1024));
      await tester.tap(find.text('Security'));
      await settleNav(tester);
      expect(
        find.text("Require this device's PIN or biometric to open Noo"),
        findsOneWidget,
      );
      // One sidebar label and one toolbar title; no repeated card heading.
      expect(find.text('Security'), findsNWidgets(2));
      expect(find.byType(NooTopBarBack), findsNothing);
      final account = find.descendant(
        of: find.byType(TabletAccountMenu),
        matching: find.text('alice'),
      );
      final menuHeight = tester.getSize(find.byType(TabletAccountMenu)).height;
      await tester.tap(account);
      await settleNav(tester);
      expect(
        tester.getSize(find.byType(TabletAccountMenu)).height,
        greaterThan(menuHeight),
      );
      expect(find.text('Manage Accounts'), findsOneWidget);
      await tester.tap(find.text('Manage Accounts'));
      await settleNav(tester);
      expect(
        find.text("Require this device's PIN or biometric to open Noo"),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
