import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/files/noo_file_kind.dart';
import 'package:noo/widgets/noo/files/noo_file_row.dart';
import 'package:noo/widgets/noo/files/noo_file_table.dart';
import 'package:noo/widgets/noo/media/noo_grid_card.dart';
import 'noo_test_utils.dart';
import 'package:noo/services/mac_secondary_click.dart';

/// Right-clicking (mouse or touchpad secondary click) a file row, table row
/// or grid card opens the same overflow menu as its 3-dot button.
void main() {
  setUpNooTests();

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(
      finder,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  final cases =
      <String, Widget Function(VoidCallback onMore, VoidCallback onTap)>{
        'NooFileRow': (onMore, onTap) => NooFileRow(
          kind: NooFileKind.pdf,
          name: 'Report.pdf',
          onTap: onTap,
          onMore: onMore,
        ),
        'NooFileTableRow': (onMore, onTap) => NooFileTableRow(
          kind: NooFileKind.pdf,
          name: 'Report.pdf',
          onTap: onTap,
          onMore: onMore,
        ),
        'NooGridCard': (onMore, onTap) => SizedBox(
          width: 200,
          child: NooGridCard(name: 'Report.pdf', onTap: onTap, onMore: onMore),
        ),
      };

  for (final entry in cases.entries) {
    testWidgets('right-click on ${entry.key} opens its overflow menu', (
      tester,
    ) async {
      var more = 0, taps = 0;
      await pumpNoo(
        tester,
        SizedBox(width: 700, child: entry.value(() => more++, () => taps++)),
      );
      await rightClick(tester, find.text('Report.pdf'));
      expect(more, 1);
      expect(taps, 0, reason: 'a right-click must not also open the item');
    });
  }

  for (final entry in cases.entries) {
    testWidgets(
      'Mac native secondary click reaches ${entry.key} without opening it',
      (tester) async {
        var more = 0, taps = 0;
        await pumpNoo(
          tester,
          SizedBox(width: 700, child: entry.value(() => more++, () => taps++)),
        );
        MacSecondaryClick.dispatch(tester.getCenter(find.text('Report.pdf')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(more, 1);
        expect(taps, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an explicit onSecondaryTap still overrides the default', (
    tester,
  ) async {
    var more = 0, secondary = 0;
    await pumpNoo(
      tester,
      SizedBox(
        width: 700,
        child: NooFileTableRow(
          kind: NooFileKind.pdf,
          name: 'Report.pdf',
          onMore: () => more++,
          onSecondaryTap: () => secondary++,
        ),
      ),
    );
    await rightClick(tester, find.text('Report.pdf'));
    expect(secondary, 1);
    expect(more, 0);
  });
}
