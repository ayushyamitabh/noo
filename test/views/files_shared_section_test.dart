import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/views/files_view.dart';
import 'package:noo/widgets/share_sheet.dart';

import 'files_test_harness.dart';

/// Items shared *with* the user: their own "Shared with me" section in Files
/// (and the "External storage" one beside it), a shared icon on the row,
/// quick-jump chips to both sections, and the real owner in the share sheet.
void main() {
  setUpFilesHarness();

  final listing = [
    for (var i = 0; i < 24; i++) harnessItem('mine-$i.txt'),
    harnessItem('nas', mountType: 'external', folder: true),
    harnessItem(
      'Budget.xlsx',
      mountType: 'shared',
      ownerId: 'jamie',
      ownerDisplayName: 'Jamie Rivera',
    ),
    harnessItem(
      'Trip',
      mountType: 'shared',
      ownerId: 'jamie',
      ownerDisplayName: 'Jamie Rivera',
      folder: true,
    ),
  ];

  Future<AppHarness> pumpFiles(WidgetTester tester) => pumpWithApp(
    tester,
    listing,
    (scroll) => FilesView(scrollController: scroll),
  );

  // Folder rows are keyed by item, so this finds the row of one item.
  Finder row(String name) => find.text(name);

  testWidgets('shared items get their own collapsible section with a chip', (
    tester,
  ) async {
    final app = await pumpFiles(tester);
    app.files.setStorageScope(StorageScope.all);
    await tester.pump(const Duration(milliseconds: 600));

    // Both chips show their counts; the sections hold the right items.
    expect(find.text('Shared with me · 2'), findsOneWidget);
    expect(find.text('External storage · 1'), findsOneWidget);

    // The shared items aren't in the main list: the section header is the
    // only "Shared with me" label and sits after all of the regular items.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Shared with me'), findsOneWidget);
    expect(row('Budget.xlsx'), findsOneWidget);

    // Collapsing hides its items.
    await tester.tap(find.text('Shared with me'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(row('Budget.xlsx'), findsNothing);
    await app.finish(tester);
  });

  testWidgets('shared rows show the shared icon', (tester) async {
    final app = await pumpFiles(tester);
    app.files.setStorageScope(StorageScope.all);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 600));
    // Budget.xlsx's row has the icon; a regular row (scrolled out) doesn't
    // count - so exactly the two shared rows carry it, plus the header.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Shared with you',
      ),
      findsNWidgets(2),
    );
    await app.finish(tester);
  });

  testWidgets('tapping a chip opens a collapsed section and scrolls to it', (
    tester,
  ) async {
    final app = await pumpFiles(tester);
    app.files.setStorageScope(StorageScope.all);
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.scroll.offset, 0);

    // Collapse the shared section, then jump to it by its chip.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Shared with me'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(row('Budget.xlsx'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.scroll.offset, 0);

    await tester.tap(find.text('Shared with me · 2'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(app.scroll.offset, greaterThan(0));
    expect(row('Budget.xlsx'), findsOneWidget);
    final header = tester.getRect(find.text('Shared with me'));
    expect(header.top, greaterThan(0));
    expect(header.bottom, lessThan(800));
    await app.finish(tester);
  });

  testWidgets('mine / shared filters drop the section for a flat list', (
    tester,
  ) async {
    final app = await pumpFiles(tester);
    app.files.setOwnershipFilter(OwnershipFilter.shared);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Budget.xlsx'), findsOneWidget);
    expect(find.text('mine-0.txt'), findsNothing);
    expect(find.textContaining('Shared with me'), findsNothing);

    app.files.setOwnershipFilter(OwnershipFilter.mine);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('mine-0.txt'), findsOneWidget);
    expect(find.text('Budget.xlsx'), findsNothing);
    await app.finish(tester);
  });

  group('share sheet owner', () {
    testWidgets('an item shared with me shows its real owner', (tester) async {
      final app = await pumpWithApp(
        tester,
        listing,
        (_) => ShareSheet(item: listing[25]),
        size: const Size(400, 900),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Jamie Rivera'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsNothing);
      expect(find.text('Owner'), findsOneWidget);
      await app.finish(tester);
    });

    testWidgets('an item inside a shared folder shows its owner too', (
      tester,
    ) async {
      final nested = harnessItem(
        'inside.txt',
        ownerId: 'jamie',
        ownerDisplayName: 'Jamie Rivera',
      );
      final app = await pumpWithApp(
        tester,
        [nested],
        (_) => ShareSheet(item: nested),
        size: const Size(400, 900),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Jamie Rivera'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsNothing);
      await app.finish(tester);
    });

    testWidgets('my own item still shows me as the owner', (tester) async {
      final app = await pumpWithApp(
        tester,
        listing,
        (_) => ShareSheet(item: listing.first),
        size: const Size(400, 900),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      await app.finish(tester);
    });
  });
}
