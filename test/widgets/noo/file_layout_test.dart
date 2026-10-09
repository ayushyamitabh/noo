import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/lists/noo_selection_bar.dart';
import 'package:noo/models/selection_action.dart';
import 'package:noo/widgets/noo/noo_layout.dart';
import 'package:noo/widgets/noo/media/noo_grid_card.dart';
import 'package:noo/widgets/noo/files/noo_file_table.dart';
import 'package:noo/widgets/noo/files/noo_file_kind.dart';
import 'noo_test_utils.dart';
import 'package:noo/widgets/noo/media/noo_photo_group.dart';

void main() {
  setUpNooTests();
  testWidgets('photo columns follow the pane rather than the tablet width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: CustomScrollView(
              slivers: [
                NooPhotoGrid(
                  minTileWidth: 150,
                  itemCount: 6,
                  itemBuilder: (_, index) =>
                      SizedBox(key: ValueKey('photo-$index')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final first = tester.getRect(find.byKey(const ValueKey('photo-0')));
    final third = tester.getRect(find.byKey(const ValueKey('photo-2')));
    final fourth = tester.getRect(find.byKey(const ValueKey('photo-3')));
    expect(first.width, greaterThan(100));
    expect(third.right, lessThanOrEqualTo(first.left + 400));
    expect(fourth.top, greaterThan(first.top));
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 430.0, 700.0]) {
    testWidgets('selection actions fit portrait tablet pane $width', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nooTheme(Brightness.light),
          builder: (_, child) => Material(child: child),
          home: Center(
            child: SizedBox(
              width: width,
              child: NooSelectionBar(
                count: 100,
                isDesktop: true,
                onClose: () {},
                actions: [
                  for (final kind in SelectionActionKind.values)
                    SelectionAction(
                      kind: kind,
                      icon: kind.icon,
                      label: kind.label,
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('100 selected'), findsOneWidget);
    });
    testWidgets('file cards fit pane width $width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nooTheme(Brightness.light),
          builder: (_, child) => Material(child: child),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(768, 1024),
              textScaler: TextScaler.linear(1.4),
            ),
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: width,
                  height: 500,
                  child: GridView.builder(
                    gridDelegate: NooLayout.fileGridDelegate(context),
                    itemCount: 6,
                    itemBuilder: (_, index) => const NooGridCard(
                      name: 'Long file name.pdf',
                      meta: '2 MB',
                      thumbnailHeight: 118,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(NooGridCard).first).height,
        lessThan(200),
      );
    });
    testWidgets('file table preserves name space at $width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: nooTheme(Brightness.light),
          builder: (_, child) => Material(child: child),
          home: Center(
            child: SizedBox(
              width: width,
              child: const NooFileTableRow(
                kind: NooFileKind.folder,
                name: 'Important project documents',
                col2: 'Yesterday',
                col3: 'Folder',
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.text('Important project documents')).width,
        greaterThan(80),
      );
    });
  }
}
