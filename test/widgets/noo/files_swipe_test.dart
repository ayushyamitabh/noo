import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/files/noo_swipe_action.dart';
import 'package:noo/models/selection_action.dart';
import 'package:noo/providers/settings_controller.dart';

import 'noo_test_utils.dart';

void main() {
  setUpNooTests();

  group('NooSwipeAction', () {
    test('every action-bar action has a swipe setting', () {
      expect(
        SwipeAction.values
            .map((action) => action.selectionKind)
            .whereType<SelectionActionKind>()
            .toSet(),
        SelectionActionKind.values.toSet(),
      );
    });

    for (final kind in SelectionActionKind.values) {
      testNooWidgets('a full swipe runs ${kind.label}', (
        tester,
        theme,
        c,
      ) async {
        var triggered = 0;
        await pumpNoo(
          tester,
          SizedBox(
            width: 360,
            height: 64,
            child: NooSwipeAction(
              startAction: NooSwipeActionSpec(
                kind: kind,
                onTriggered: () => triggered++,
              ),
              child: const ColoredBox(
                color: Colors.white,
                child: SizedBox(width: 360, height: 64),
              ),
            ),
          ),
          theme: theme,
        );
        await tester.drag(find.byType(NooSwipeAction), const Offset(60, 0));
        await tester.pumpAndSettle();
        expect(triggered, 0);
        expect(find.text(kind.label), findsOneWidget);
        expect(find.byIcon(kind.icon), findsOneWidget);
        await tester.drag(find.byType(NooSwipeAction), const Offset(300, 0));
        await tester.pump();
        expect(triggered, 1);
      });
    }

    testNooWidgets('a moderate swipe opens the action without triggering it', (
      tester,
      theme,
      c,
    ) async {
      var triggered = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 64,
          child: NooSwipeAction(
            endAction: NooSwipeActionSpec(
              kind: NooSwipeActionKind.delete,
              onTriggered: () => triggered++,
            ),
            child: const ColoredBox(
              color: Colors.white,
              child: SizedBox(width: 360, height: 64),
            ),
          ),
        ),
        theme: theme,
      );
      // Half the block's own width (96) is well past the "snap open"
      // threshold but nowhere near the 1.8x trigger extent.
      await tester.drag(find.byType(NooSwipeAction), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(triggered, 0);
      expect(find.text('Delete'), findsOneWidget);
    });

    testNooWidgets(
      'swiping past the trigger extent fires the action on release - no '
      'second tap needed',
      (tester, theme, c) async {
        var triggered = 0;
        await pumpNoo(
          tester,
          SizedBox(
            width: 360,
            height: 64,
            child: NooSwipeAction(
              endAction: NooSwipeActionSpec(
                kind: NooSwipeActionKind.delete,
                onTriggered: () => triggered++,
              ),
              child: const ColoredBox(
                color: Colors.white,
                child: SizedBox(width: 360, height: 64),
              ),
            ),
          ),
          theme: theme,
        );
        // 300px of drag on a 96px-wide block clears the 1.8x (~173px)
        // trigger extent well past the clamp ceiling.
        await tester.drag(find.byType(NooSwipeAction), const Offset(-300, 0));
        await tester.pump();
        expect(triggered, 1);
      },
    );

    testNooWidgets('tapping the revealed block still triggers the action too', (
      tester,
      theme,
      c,
    ) async {
      var triggered = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 64,
          child: NooSwipeAction(
            startAction: NooSwipeActionSpec(
              kind: NooSwipeActionKind.favorite,
              onTriggered: () => triggered++,
            ),
            child: const ColoredBox(
              color: Colors.white,
              child: SizedBox(width: 360, height: 64),
            ),
          ),
        ),
        theme: theme,
      );
      await tester.drag(find.byType(NooSwipeAction), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(triggered, 0);
      await tester.tap(find.text('Favorite'));
      await tester.pump();
      expect(triggered, 1);
    });
  });
}
