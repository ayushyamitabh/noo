import 'dart:convert';
import 'dart:ui' show ImageFilter;
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
import 'package:noo/widgets/noo/core/noo_button.dart';
import 'package:noo/widgets/app_top_bar.dart';
import 'package:noo/widgets/avatar_menu.dart';
import 'package:noo/widgets/bottom_nav_bar.dart';
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
    bool withHost = false,
    AvatarPosition position = AvatarPosition.top,
    bool search = false,
    bool reducedMotion = false,
    NooNavStyle style = NooNavStyle.android,
    NooBottomBarStyle barStyle = NooBottomBarStyle.floating,
    AppTab tab = AppTab.files,
    FabStyle uploadStyle = FabStyle.auto,
    bool frosted = false,
    int settleFrames = 30,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ui_nav_menu_style', navMenuStyle.name);
    await prefs.setString('ui_avatar_position', position.name);
    await prefs.setString('ui_bottom_bar_style', barStyle.name);
    await prefs.setBool('ui_bottom_bar_frosted', frosted);
    await prefs.setDouble('ui_bottom_bar_frosted_blur', 19);
    await prefs.setDouble('ui_bottom_bar_frosted_opacity', 0.45);
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
          theme: AppTheme.light(AppTheme.defaultAccent, useDynamicColor: false)
              .copyWith(
                platform: style == NooNavStyle.ios
                    ? TargetPlatform.iOS
                    : TargetPlatform.android,
              ),
          home: Builder(
            builder: (context) {
              final scaffold = Scaffold(
                drawer: const Drawer(child: Text('drawer open')),
                appBar: AppTopBar(
                  style: style,
                  tab: tab,
                  uploadButtonStyle: uploadStyle,
                  navMenuStyle: navMenuStyle,
                  avatarPosition: position,
                  searchInBottomBar: search,
                ),
                body: const AvatarNavigationBody(
                  child: SizedBox.expand(key: ValueKey('page content')),
                ),
                bottomNavigationBar: withHost
                    ? BottomNavBar(
                        style: style,
                        barStyle: barStyle,
                        tabs: const [AppTab.files, AppTab.photos],
                        selectedIndex: 0,
                        onDestinationSelected: (_) {},
                        avatarInBottomBar: position == AvatarPosition.bottom,
                        onSearchTap: search ? () {} : null,
                      )
                    : null,
              );
              final child = withHost
                  ? AvatarNavigationHost(child: scaffold)
                  : scaffold;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reducedMotion),
                child: child,
              );
            },
          ),
        ),
      ),
    );

    // Not `pumpAndSettle` - the same reasoning as `account_view_test.dart`:
    // the active account's dependent controllers start periodic
    // timers/futures that would spin it forever.
    for (var i = 0; i < settleFrames; i++) {
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
    // The card is as wide as the Files list's rows: inset NooSpace.sm from
    // each screen edge, less its 1px border and 1px inner padding per side.
    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    expect(tester.getSize(row).width, screenWidth - 2 * NooSpace.sm - 4);
  });
  testWidgets(
    'top avatar expands and pushes content down; closing restores it',
    (tester) async {
      await pumpTopBar(
        tester,
        navMenuStyle: NooNavMenuStyle.avatarMenu,
        withHost: true,
      );
      final page = find.byKey(const ValueKey('page content'));
      final before = tester.getTopLeft(page).dy;
      await tester.tap(find.byTooltip('Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final during = tester.getTopLeft(page).dy;
      expect(during, greaterThan(before));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getTopLeft(page).dy, greaterThan(during));
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close menu').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getTopLeft(page).dy, before);
      expect(find.byType(AvatarMenuCard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final search in [false, true]) {
    testWidgets(
      'bottom avatar moves into card without shifting content (search=$search)',
      (tester) async {
        await pumpTopBar(
          tester,
          navMenuStyle: NooNavMenuStyle.avatarMenu,
          withHost: true,
          position: AvatarPosition.bottom,
          search: search,
        );
        final page = find.byKey(const ValueKey('page content'));
        final before = tester.getTopLeft(page);
        expect(find.byTooltip('Menu'), findsOneWidget);
        final origin = tester.getCenter(find.byTooltip('Menu'));
        await tester.tap(find.byTooltip('Menu'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        final moving = tester.getCenter(
          find.bySemanticsLabel('Close menu').last,
        );
        expect(moving.dy, lessThan(origin.dy));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.getTopLeft(page), before);
        final card = find.byType(AvatarMenuCard);
        expect(card, findsOneWidget);
        expect(tester.getBottomRight(card).dy, lessThan(origin.dy));
        expect(tester.getSize(card).width, 376);
        if (search) expect(find.bySemanticsLabel('Search'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Close menu').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AvatarMenuCard), findsNothing);
        expect(tester.getCenter(find.byTooltip('Menu')), origin);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('reduced motion opens immediately and system back dismisses', (
    tester,
  ) async {
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      withHost: true,
      reducedMotion: true,
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AvatarMenuCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final position in AvatarPosition.values) {
    for (final frosted in [false, true]) {
      testWidgets(
        '$position popup shares frost toggle and strength ($frosted)',
        (tester) async {
          await pumpTopBar(
            tester,
            navMenuStyle: NooNavMenuStyle.avatarMenu,
            withHost: true,
            position: position,
            frosted: frosted,
          );
          await tester.tap(find.byTooltip('Menu'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          final card = find.byType(AvatarMenuCard);
          final backdrop = find.ancestor(
            of: card,
            matching: find.byType(BackdropFilter),
          );
          expect(backdrop, frosted ? findsOneWidget : findsNothing);
          if (frosted) {
            expect(
              tester.widget<BackdropFilter>(backdrop).filter,
              ImageFilter.blur(sigmaX: 19, sigmaY: 19),
            );
            final decorations = tester.widgetList<DecoratedBox>(
              find.ancestor(of: card, matching: find.byType(DecoratedBox)),
            );
            expect(
              decorations.any(
                (box) =>
                    box.decoration is BoxDecoration &&
                    ((box.decoration as BoxDecoration).color?.a ?? 0) > 0.44 &&
                    ((box.decoration as BoxDecoration).color?.a ?? 0) < 0.46,
              ),
              isTrue,
            );
            final materials = tester.widgetList<Material>(
              find.descendant(of: card, matching: find.byType(Material)),
            );
            expect(
              materials.every(
                (material) => material.color == Colors.transparent,
              ),
              isTrue,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('iOS upload width interpolates while its label fades', (
    tester,
  ) async {
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      style: NooNavStyle.ios,
      uploadStyle: FabStyle.mini,
    );
    final button = find.byType(NooButton);
    final collapsedWidth = tester.getSize(button).width;
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      style: NooNavStyle.ios,
      uploadStyle: FabStyle.expanded,
      settleFrames: 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final middleWidth = tester.getSize(button).width;
    final labelOpacity = tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text('Upload'), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    expect(labelOpacity, greaterThan(0));
    expect(labelOpacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    final expandedWidth = tester.getSize(button).width;
    expect(middleWidth, greaterThan(collapsedWidth));
    expect(middleWidth, lessThan(expandedWidth));
    expect(tester.getSize(button).height, 32);
    expect(tester.takeException(), isNull);
  });

  for (final uploadStyle in FabStyle.values) {
    for (final tab in [AppTab.files, AppTab.photos, AppTab.favorites]) {
      testWidgets('iOS title row uses $uploadStyle upload control on $tab', (
        tester,
      ) async {
        await pumpTopBar(
          tester,
          navMenuStyle: NooNavMenuStyle.avatarMenu,
          style: NooNavStyle.ios,
          tab: tab,
          uploadStyle: uploadStyle,
        );
        final title = find.descendant(
          of: find.byType(AppTopBar),
          matching: find.text(tab.label),
        );
        final titleY = tester.getCenter(title).dy;
        expect(
          tester.getCenter(find.byTooltip('Upload')).dy,
          closeTo(titleY, 1),
        );
        expect(tester.getCenter(find.byTooltip('Menu')).dy, closeTo(titleY, 1));
        final expanded =
            uploadStyle == FabStyle.expanded ||
            (uploadStyle == FabStyle.auto && tab != AppTab.favorites);
        expect(find.text('Upload'), expanded ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('iOS attached navigation keeps popup above its rail', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = jsonDecode(prefs.getString('accounts_list')!) as List;
    accounts.add(
      const SavedAccount(
        id: 'other_example_org__bob',
        serverUrl: 'https://other.example.org',
        username: 'bob',
      ).toJson(),
    );
    await prefs.setString('accounts_list', jsonEncode(accounts));
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      withHost: true,
      position: AvatarPosition.bottom,
      search: true,
      style: NooNavStyle.ios,
      barStyle: NooBottomBarStyle.attached,
    );
    final origin = tester.getCenter(find.byTooltip('Menu'));
    expect(
      find.descendant(
        of: find.byType(BottomNavBar),
        matching: find.text('Files'),
      ),
      findsOneWidget,
    );
    expect(find.text('Photos'), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.getBottomLeft(find.byType(AvatarMenuCard)).dy,
      origin.dy - 25 - 1,
    );
    expect(tester.getSize(find.byType(AvatarMenuCard)).width, 400);
    expect(tester.getCenter(find.byTooltip('Menu')), origin);
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    await tester.tap(find.text('alice'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      tester.getCenter(find.text('Settings')).dy,
      lessThan(tester.getCenter(find.text('alice')).dy),
    );
    expect(
      tester.getCenter(find.text('alice')).dy,
      lessThan(tester.getCenter(find.text('bob')).dy),
    );
    expect(
      tester.getCenter(find.text('bob')).dy,
      lessThan(tester.getCenter(find.text('Add Account')).dy),
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AvatarMenuCard), findsNothing);
    expect(tester.getCenter(find.byTooltip('Menu')), origin);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android floating popup orders navigation before accounts', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = jsonDecode(prefs.getString('accounts_list')!) as List;
    accounts.add(
      const SavedAccount(
        id: 'other_example_org__bob',
        serverUrl: 'https://other.example.org',
        username: 'bob',
      ).toJson(),
    );
    await prefs.setString('accounts_list', jsonEncode(accounts));
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      withHost: true,
      position: AvatarPosition.bottom,
      search: true,
      style: NooNavStyle.android,
      barStyle: NooBottomBarStyle.floating,
    );
    final origin = tester.getCenter(find.byTooltip('Menu'));
    expect(
      find.descendant(
        of: find.byType(BottomNavBar),
        matching: find.text('Files'),
      ),
      findsOneWidget,
    );
    expect(find.text('Photos'), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.getBottomLeft(find.byType(AvatarMenuCard)).dy,
      origin.dy - 32 - 12 - 1,
    );
    expect(tester.getSize(find.byType(AvatarMenuCard)).width, 376);
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    await tester.tap(find.text('alice'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      tester.getCenter(find.text('Settings')).dy,
      lessThan(tester.getCenter(find.text('alice')).dy),
    );
    expect(
      tester.getCenter(find.text('alice')).dy,
      lessThan(tester.getCenter(find.text('bob')).dy),
    );
    expect(
      tester.getCenter(find.text('bob')).dy,
      lessThan(tester.getCenter(find.text('Add Account')).dy),
    );
    final currentAvatar = find
        .descendant(
          of: find.byType(AvatarMenuCard),
          matching: find.byType(NooAvatar),
        )
        .first;
    expect(
      tester.getCenter(currentAvatar).dy,
      lessThan(tester.getCenter(find.text('bob')).dy),
    );
    await tester.tap(currentAvatar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AvatarMenuCard), findsNothing);
    expect(tester.getCenter(find.byTooltip('Menu')), origin);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding accounts also grows the top content offset', (
    tester,
  ) async {
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      withHost: true,
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final before = tester
        .getTopLeft(find.byKey(const ValueKey('page content')))
        .dy;
    await tester.tap(find.text('alice'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Add Account'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('page content'))).dy,
      greaterThan(before),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Search satellite closes the bottom navigation popup', (
    tester,
  ) async {
    await pumpTopBar(
      tester,
      navMenuStyle: NooNavMenuStyle.avatarMenu,
      withHost: true,
      position: AvatarPosition.bottom,
      search: true,
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AvatarMenuCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
