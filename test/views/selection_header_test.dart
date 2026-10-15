import 'package:flutter_test/flutter_test.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/views/files_view.dart';

import 'files_test_harness.dart';

/// Selecting items shouldn't make the filter row pop out. With "Keep filters
/// visible" (the default) it stays and the action bar slides in beside it;
/// switched off, the bar replaces the filters like it used to.
void main() {
  setUpFilesHarness(loadFonts: true);

  final listing = [for (var i = 0; i < 12; i++) harnessItem('Report $i.pdf')];

  Future<AppHarness> pumpFiles(WidgetTester tester) => pumpWithApp(
    tester,
    listing,
    (scroll) => FilesView(scrollController: scroll),
  );

  Future<void> select(WidgetTester tester) async {
    await tester.longPress(find.text('Report 0.pdf'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('filters stay while the action bar slides in above them', (
    tester,
  ) async {
    final app = await pumpFiles(tester);
    expect(app.settings.keepFiltersWhileSelecting, isTrue);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);
    final filtersBefore = tester.getRect(find.text('Filters'));

    await select(tester);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    // The bar is above the filter row; the filter row shifted down by the
    // bar's height rather than disappearing.
    final bar = tester.getRect(find.text('1 selected'));
    final filters = tester.getRect(find.text('Filters'));
    expect(bar.bottom, lessThan(filters.top));
    expect(filters.top - filtersBefore.top, closeTo(56, 1));

    // Clearing the selection slides the bar away again and the filters
    // return to where they were.
    await tester.tap(find.bySemanticsLabel('Cancel selection').first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('1 selected'), findsNothing);
    expect(tester.getRect(find.text('Filters')).top, filtersBefore.top);
    await app.finish(tester);
  });

  testWidgets('bottom position leaves the filter row exactly where it is', (
    tester,
  ) async {
    final app = await pumpFiles(tester);
    app.settings.setSelectionBarPosition(SelectionBarPosition.bottom);
    await tester.pump(const Duration(milliseconds: 100));
    final filtersBefore = tester.getRect(find.text('Filters'));

    await select(tester);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(tester.getRect(find.text('Filters')), filtersBefore);
    // ...with the bar down at the bottom of the screen.
    expect(
      tester.getRect(find.text('1 selected')).top,
      greaterThan(filtersBefore.bottom + 400),
    );
    await app.finish(tester);
  });

  testWidgets('turned off, the action bar replaces the filters', (
    tester,
  ) async {
    final app = await pumpFiles(tester);
    app.settings.setKeepFiltersWhileSelecting(false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Filters'), findsOneWidget);

    await select(tester);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Filters'), findsNothing);
    await app.finish(tester);
  });
}
