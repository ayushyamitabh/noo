import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/views/account_view.dart';
import 'package:noo/widgets/noo/core/noo_button.dart';
import 'package:noo/widgets/noo/lists/noo_settings_row.dart';

import 'files_test_harness.dart';

/// Settings -> Appearance -> "Reset UI defaults": confirm first, then every
/// UI preference (global and the active account's list prefs) is reset.
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

  /// Opens Settings on the Appearance screen via search, scrolled to the row.
  Future<AppHarness> openReset(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    final app = await pumpWithApp(
      tester,
      [],
      (_) => const AccountView(),
      size: size,
    );
    await tester.enterText(find.byType(TextField), 'reset ui');
    await tester.pump();
    await tester.tap(find.widgetWithText(NooSettingsRow, 'Reset UI defaults'));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('Cancel leaves everything as it was', (tester) async {
    final app = await openReset(tester);
    app.settings.setThemeMode(ThemeMode.dark);
    app.files.setGridView(true);

    await tester.tap(find.widgetWithText(NooSettingsRow, 'Reset UI defaults'));
    await tester.pumpAndSettle();
    // The confirm step says what's (not) affected and offers Cancel.
    expect(find.textContaining('accounts, locks and sync'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(app.settings.themeMode, ThemeMode.dark);
    expect(app.files.isGridView, isTrue);
    await app.finish(tester);
  });

  testWidgets('Reset restores the defaults everywhere', (tester) async {
    final app = await openReset(tester);
    app.settings
      ..setThemeMode(ThemeMode.dark)
      ..setAmoledDark(true)
      ..setSwipeLeftAction(SwipeAction.share);
    app.files
      ..setGridView(true)
      ..setStorageScope(StorageScope.cloud)
      ..setOwnershipFilter(OwnershipFilter.mine);

    await tester.tap(find.widgetWithText(NooSettingsRow, 'Reset UI defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NooButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(app.settings.themeMode, ThemeMode.system);
    expect(app.settings.amoledDark, isFalse);
    expect(app.settings.swipeLeftAction, SwipeAction.delete);
    expect(app.files.isGridView, isFalse);
    expect(app.files.storageScope, StorageScope.all);
    expect(app.files.ownershipFilter, OwnershipFilter.all);
    expect(find.text('UI settings reset to defaults'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('on a tablet the confirm is a dialog and works the same', (
    tester,
  ) async {
    final app = await openReset(tester, size: const Size(1100, 800));
    app.settings.setThemeMode(ThemeMode.light);
    app.files.setStorageScope(StorageScope.external);

    // Below the fold on a tablet now that Appearance holds the action bar.
    await tester.ensureVisible(
      find.widgetWithText(NooSettingsRow, 'Reset UI defaults'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NooSettingsRow, 'Reset UI defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NooButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(app.settings.themeMode, ThemeMode.system);
    expect(app.files.storageScope, StorageScope.all);
    await app.finish(tester);
  });
}
