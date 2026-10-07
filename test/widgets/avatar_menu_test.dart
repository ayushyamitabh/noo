import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/app_tab.dart';
import 'package:noo/models/saved_account.dart';
import 'package:noo/providers/connectivity_controller.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/session_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/providers/sync_status_controller.dart';
import 'package:noo/providers/trash_controller.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/theme/design_tokens.dart';
import 'package:noo/widgets/noo/core/noo_avatar.dart';
import 'package:noo/widgets/app_top_bar.dart';
import 'package:noo/widgets/noo/nav/noo_top_bar.dart';

/// Covers `SettingsController.navMenuStyle`'s two options as wired through
/// `AppTopBar`/`ShellAvatarButton`: [NooNavMenuStyle.drawer] (today's
/// hamburger-opens-a-left-Drawer pattern, unchanged) vs
/// [NooNavMenuStyle.avatarMenu] (no hamburger at all - the avatar opens
/// `showAvatarMenu`'s dropdown instead of the account switcher).
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
    // Offline, same as `account_view_test.dart`'s setup: keeps
    // SessionController in a provisional login and stops
    // FilesController/SyncStatusController/TrashController's network/timer
    // machinery from hanging the test.
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

  Future<void> pumpTopBar(
    WidgetTester tester, {
    required NooNavMenuStyle navMenuStyle,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          ChangeNotifierProvider(
            create: (context) => TrashController(context.read()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(AppTheme.defaultAccent, useDynamicColor: false),
          home: Scaffold(
            drawer: const Drawer(child: Text('drawer open')),
            appBar: AppTopBar(
              style: NooNavStyle.android,
              tab: AppTab.files,
              navMenuStyle: navMenuStyle,
            ),
            body: const SizedBox(),
          ),
        ),
      ),
    );

    // Not `pumpAndSettle` - the same reasoning as `account_view_test.dart`:
    // the active account's dependent controllers start periodic
    // timers/futures that would spin it forever.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('avatarMenu style: no hamburger, avatar opens the dropdown', (
    tester,
  ) async {
    await pumpTopBar(tester, navMenuStyle: NooNavMenuStyle.avatarMenu);

    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.byIcon(LucideIcons.menu), findsNothing);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The dropdown's own header + Settings row - not the account
    // switcher's "Add account"/"Manage accounts" rows.
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Add account'), findsNothing);
  });

  testWidgets('drawer style (default): hamburger opens the real drawer', (
    tester,
  ) async {
    await pumpTopBar(tester, navMenuStyle: NooNavMenuStyle.drawer);

    expect(find.byTooltip('Menu'), findsOneWidget);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('drawer open'), findsOneWidget);
  });

  testWidgets(
    'drawer style (default): avatar still opens the account switcher',
    (tester) async {
      await pumpTopBar(tester, navMenuStyle: NooNavMenuStyle.drawer);

      expect(find.byTooltip('Accounts'), findsOneWidget);
      await tester.tap(find.byTooltip('Accounts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add account'), findsOneWidget);
    },
  );

  testWidgets("other accounts' avatars sit flush right in the dropdown", (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'account_migration_v1_done': true,
      'accounts_list': jsonEncode([
        const SavedAccount(
          id: accountId,
          serverUrl: 'https://server.example.com',
          username: 'alice',
        ).toJson(),
        const SavedAccount(
          id: 'other_example_org__bob',
          serverUrl: 'https://other.example.org',
          username: 'bob',
        ).toJson(),
      ]),
      'active_account_id': accountId,
    });
    await pumpTopBar(tester, navMenuStyle: NooNavMenuStyle.avatarMenu);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Expand the account list from the header.
    await tester.tap(find.text('alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final row = find.ancestor(
      of: find.text('bob'),
      matching: find.byType(InkWell),
    );
    final avatar = find.descendant(of: row, matching: find.byType(NooAvatar));
    expect(avatar, findsOneWidget);

    // Only the row's own padding between the avatar and the card's edge -
    // no extra gutter pushing it in from the right.
    expect(
      tester.getTopRight(row).dx - tester.getTopRight(avatar).dx,
      NooSpace.md,
    );
  });
}
