import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:noo/views/account_view.dart';
import 'package:noo/widgets/noo/lists/noo_settings_row.dart';
import 'package:noo/widgets/settings/settings_search.dart';

import 'files_test_harness.dart';

List<String> _labels(String query, {bool phone = true, bool ios = false}) => [
  for (final e in searchSettings(query, phone: phone, ios: ios)) e.label,
];

void main() {
  setUpFilesHarness(loadFonts: true);

  group('searchSettings', () {
    test('finds by label, case-insensitively', () {
      expect(_labels('frosted'), contains('Frosted glass'));
      expect(_labels('APP LOCK'), ['App lock']);
    });

    test('finds by keyword and category', () {
      expect(_labels('biometric'), contains('App lock'));
      expect(_labels('dark mode'), contains('Theme'));
      // A category name lists everything in it.
      expect(_labels('security'), [
        'App lock',
        'Lock account switching',
        'Lock hidden files',
      ]);
    });

    test('every word has to match', () {
      expect(_labels('lock hidden'), ['Lock hidden files']);
      expect(_labels('lock zebra'), isEmpty);
      expect(_labels('   '), isEmpty);
    });

    test('label matches rank above keyword-only ones', () {
      expect(_labels('blur'), containsAll(['Frosted glass', 'Frost strength']));
      // "theme" is Theme's label but only a keyword of Accent color.
      expect(_labels('theme').first, 'Theme');
      expect(_labels('theme'), contains('Accent color'));
    });

    test('leaves out options the layout does not have', () {
      expect(
        _labels('bottom bar', phone: false),
        isNot(contains('Bottom bar')),
      );
      expect(_labels('seek bar', ios: true), isEmpty);
      expect(_labels('seek bar'), ['Seek bar style']);
    });
  });

  group('settings search in the app', () {
    setUpAll(
      () => PackageInfo.setMockInitialValues(
        appName: 'Noo',
        packageName: 'dev.ayushya.noo',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      ),
    );

    // The search box's own text also matches `find.text`, so tap the result
    // row itself.
    Finder resultRow(String label) =>
        find.widgetWithText(NooSettingsRow, label);

    testWidgets('typing lists matches and clearing brings the menu back', (
      tester,
    ) async {
      final app = await pumpWithApp(tester, [], (_) => const AccountView());
      expect(find.text('Appearance'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'biometric');
      await tester.pump();
      expect(resultRow('App lock'), findsOneWidget);
      expect(find.text('Security'), findsWidgets); // the results' subtitles
      expect(find.text('Appearance'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump();
      expect(find.text('No matching settings'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Appearance'), findsOneWidget);
      await app.finish(tester);
    });

    testWidgets('a result opens its category with the option in view', (
      tester,
    ) async {
      final app = await pumpWithApp(tester, [], (_) => const AccountView());
      await tester.enterText(find.byType(TextField), 'amoled');
      await tester.pump();
      await tester.tap(resultRow('AMOLED black'));
      await tester.pumpAndSettle();

      // Off the menu (no search box), on Appearance, with the option on
      // screen rather than scrolled off the bottom of the phone.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Appearance'), findsWidgets);
      final row = tester.getRect(find.text('AMOLED black'));
      expect(row.top, greaterThan(0));
      expect(row.bottom, lessThan(800));
      await app.finish(tester);
    });

    testWidgets('on a tablet, a result selects its category in place', (
      tester,
    ) async {
      final app = await pumpWithApp(
        tester,
        [],
        (_) => const AccountView(),
        size: const Size(1100, 800),
      );
      await tester.enterText(find.byType(TextField), 'amoled');
      await tester.pump();
      expect(find.text('Search results'), findsOneWidget);
      await tester.tap(resultRow('AMOLED black'));
      await tester.pumpAndSettle();

      // Same screen: the search is cleared and Appearance is showing, with
      // the option on screen.
      expect(find.text('Search results'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      final row = tester.getRect(find.text('AMOLED black'));
      expect(row.top, greaterThan(0));
      expect(row.bottom, lessThan(800));
      await app.finish(tester);
    });

    // The index is hand-maintained, so make sure each entry still lands on a
    // category that has its row: the whole point of keeping it honest.
    testWidgets('every index entry opens a screen showing its row', (
      tester,
    ) async {
      final app = await pumpWithApp(tester, [], (_) => const AccountView());
      for (final entry in settingsSearchIndex.where((e) => !e.hiddenOnIos)) {
        await tester.enterText(find.byType(TextField), entry.label);
        await tester.pump();
        await tester.tap(resultRow(entry.label));
        await tester.pumpAndSettle();
        expect(
          find.byType(TextField),
          findsNothing,
          reason: '"${entry.label}" should open ${entry.category}',
        );
        final target = entry.scrollTarget;
        if (target != null) {
          expect(
            find.text(target),
            findsWidgets,
            reason:
                '"${entry.label}" should open ${entry.category} with '
                '"$target" on screen',
          );
        }
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
      await app.finish(tester);
    });
  });
}
