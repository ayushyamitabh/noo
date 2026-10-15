import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/widgets/noo/lists/noo_selection_bar.dart';
import 'package:noo/views/files_view.dart';
import 'package:noo/widgets/files_controls_row.dart';

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

  testWidgets('rows scrolled under the header never show through it', (
    tester,
  ) async {
    final key = GlobalKey();
    final app = await pumpWithApp(
      tester,
      listing,
      (scroll) => RepaintBoundary(
        key: key,
        child: FilesView(scrollController: scroll),
      ),
    );
    await select(tester);

    // The 4px margin under the action bar's card (header is the 56px bar over
    // the filter row). Sampled with nothing beneath it, then with rows
    // scrolled up under the header: a see-through header would show the row's
    // surface the second time.
    Future<List<int>> margin() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late List<int> rgb;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = (await image.toByteData())!.buffer.asUint8List();
        int at(int x, int y, int c) => data[(y * image.width + x) * 4 + c];
        rgb = [
          for (final y in [53, 54, 55])
            for (final c in [0, 1, 2]) at(200, y, c),
        ];
        image.dispose();
      });
      return rgb;
    }

    final before = await margin();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await margin(), before);
    await app.finish(tester);
  });

  testWidgets('on a tablet the bar spans the same width as the filter row', (
    tester,
  ) async {
    final app = await pumpWithApp(
      tester,
      listing,
      (scroll) => FilesView(scrollController: scroll),
      size: const Size(1100, 700),
    );
    // The filter row sits at the pane's 12px inset...
    final filterRow = tester.getRect(find.byType(FilesControlsRow));
    await select(tester);

    // ...and the bar's card runs from that same inset to the mirrored one on
    // the right, instead of floating in by the table's 24px gutter.
    final card = tester.getRect(
      find
          .descendant(
            of: find.byType(NooSelectionBar),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).border != null,
            ),
          )
          .first,
    );
    expect(card.left, 12);
    expect(card.right, 1100 - 12);
    expect(card.left, filterRow.left);
    expect(card.right, filterRow.right);
    await app.finish(tester);
  });
}
