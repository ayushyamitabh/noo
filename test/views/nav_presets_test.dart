import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:noo/providers/nav_preset.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/views/account_view.dart';
import 'package:noo/widgets/noo/core/noo_toggle.dart';
import 'package:noo/widgets/noo/lists/noo_settings_row.dart';
import 'package:noo/widgets/noo/nav/noo_nav_style.dart';

import 'files_test_harness.dart';

/// Settings -> Appearance -> Layout: presets that set the bar/menu/search
/// options in bulk, and the "Navigation & bottom bar" page one level deeper.
void main() {
  setUpFilesHarness(loadFonts: true);
  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'Noo',
      packageName: 'dev.ayushya.noo',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  Future<AppHarness> openAppearance(WidgetTester tester) async {
    final app = await pumpWithApp(tester, [], (_) => const AccountView());
    await tester.enterText(find.byType(TextField), 'amoled');
    await tester.pump();
    await tester.tap(find.widgetWithText(NooSettingsRow, 'AMOLED black'));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('each preset applies its settings and is then the one selected', (
    tester,
  ) async {
    final app = await pumpWithApp(tester, [], (_) => const SizedBox());
    for (final preset in NavPreset.values) {
      preset.apply(app.settings);
      expect(preset.matches(app.settings), isTrue, reason: preset.label);
      expect(
        [
          for (final p in NavPreset.values)
            if (p.matches(app.settings)) p,
        ],
        [preset],
        reason: '${preset.label} should be the only match',
      );
    }
    await app.finish(tester);
  });

  testWidgets('options a preset does not use do not deselect it', (
    tester,
  ) async {
    final app = await pumpWithApp(tester, [], (_) => const SizedBox());
    NavPreset.classic.apply(app.settings);
    // Attached bar: the inline label and icon-only width mean nothing here.
    app.settings.setBottomBarInlineLabel(true);
    app.settings.setBottomBarIconOnlyFullWidth(false);
    expect(NavPreset.classic.matches(app.settings), isTrue);

    NavPreset.capsule.apply(app.settings);
    // Not frosted: the glass style is moot.
    app.settings.setGlassStyle(GlassStyle.glass);
    expect(NavPreset.capsule.matches(app.settings), isTrue);
    // ...but a real difference does deselect it.
    app.settings.setSearchInBottomBar(false);
    expect(NavPreset.capsule.matches(app.settings), isFalse);
    await app.finish(tester);
  });

  testWidgets('applying a preset can turn search into the bar', (tester) async {
    final app = await pumpWithApp(tester, [], (_) => const SizedBox());
    NavPreset.classic.apply(app.settings);
    expect(app.settings.searchInBottomBar, isFalse);
    NavPreset.withinReach.apply(app.settings);
    expect(app.settings.searchInBottomBar, isTrue);
    expect(app.settings.bottomBarStyle, NooBottomBarStyle.floating);
    expect(app.settings.avatarPosition.name, 'bottom');
    await app.finish(tester);
  });

  testWidgets('Appearance lists the presets; tapping one applies it', (
    tester,
  ) async {
    final app = await openAppearance(tester);
    for (final preset in NavPreset.values) {
      expect(find.text(preset.label), findsOneWidget, reason: preset.label);
    }
    await tester.ensureVisible(find.text('Capsule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capsule'));
    await tester.pumpAndSettle();
    expect(NavPreset.capsule.matches(app.settings), isTrue);
    expect(app.settings.bottomBarIconOnly, isTrue);
    expect(app.settings.searchInBottomBar, isTrue);
    await app.finish(tester);
  });

  testWidgets('the individual options live on the Navigation page', (
    tester,
  ) async {
    final app = await openAppearance(tester);
    // Not on Appearance itself any more...
    expect(find.text('Icon-only bottom bar'), findsNothing);
    expect(find.text('Search in bottom bar'), findsNothing);

    final row = find.widgetWithText(NooSettingsRow, 'Navigation & bottom bar');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    // ...but one level down, along with the rest of the bar tweaks.
    expect(find.text('Icon-only bottom bar'), findsOneWidget);
    expect(find.text('Search in bottom bar'), findsOneWidget);
    expect(find.text('Frosted glass'), findsOneWidget);
    expect(find.text('Navigation menu'), findsWidgets);

    // Changing one there is a real setting change.
    final toggle = find.descendant(
      of: find.widgetWithText(NooSettingsRow, 'Search in bottom bar'),
      matching: find.byType(NooToggle),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.settings.searchInBottomBar, isTrue);
    await app.finish(tester);
  });
}
