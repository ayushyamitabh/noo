import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/tabs/tab_state_slivers.dart';

import '../noo/noo_test_utils.dart';

/// A minimal stand-in for `AppTopBar` - just needs to be a fixed-height
/// [PreferredSizeWidget], same contract `topBarSliver` wraps in real tabs.
class _FakeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _FakeTopBar();

  static const double height = 56;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: height,
    child: ColoredBox(color: Colors.blue),
  );
}

/// Matches the one sliver `topBarSliver` inserts, even once it's fully
/// scrolled away - `find.byType`'s default `skipOffstage: true` treats a
/// sliver with `geometry.visible == false` (paintExtent 0, exactly the
/// "fully hidden" state part of this test exercises) as offstage and
/// excludes it, which would otherwise make `tester.renderObject` throw
/// instead of reporting the 0 this test expects. A function, not a
/// top-level constant, so each call re-evaluates against whichever widget
/// tree is currently pumped.
Finder _header() => find.byType(SliverFloatingHeader, skipOffstage: false);

Future<void> _pumpHost(WidgetTester tester, ScrollController controller) {
  return tester.pumpWidget(
    MaterialApp(
      theme: nooTheme(Brightness.light),
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            topBarSliver(const _FakeTopBar()),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    SizedBox(height: 60, child: Text('Item $index')),
                childCount: 40,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpNooTests();

  testWidgets(
    'topBarSliver floats away scrolling down and reappears the moment the '
    'drag reverses, not only once back at the top (Material floating app '
    'bar behavior)',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpHost(tester, controller);

      // The render object's own `geometry.paintExtent` is the ground truth
      // for how much of the bar is actually visible - more reliable than
      // inferring visibility from hit-testing/finding the child, which a
      // floating header sliver keeps built regardless of paint extent.
      double paintExtent() =>
          tester.renderObject<RenderSliver>(_header()).geometry!.paintExtent;

      // Fully visible before any scroll.
      expect(paintExtent(), _FakeTopBar.height);
      expect(controller.offset, 0);

      // Drive one continuous drag by hand (rather than `tester.drag`, which
      // only pumps once the whole gesture - including the final pointer-up
      // - has already finished): the floating header's reveal-while-
      // dragging behavior keys off the *live* scroll direction as reported
      // mid-gesture, so this needs an intermediate pump while the pointer
      // is still down to actually observe it.
      final gesture = await tester.startGesture(const Offset(200, 300));

      // Drag up (content scrolls down) well past the bar's own height, so
      // it scrolls fully away, same as a plain `SliverToBoxAdapter` would.
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();

      expect(paintExtent(), 0);
      final scrolledOffset = controller.offset;
      expect(
        scrolledOffset,
        greaterThan(_FakeTopBar.height),
        reason: "the drag should have moved past the bar's own height",
      );

      // Reverse direction by a small amount, still mid-gesture and nowhere
      // near the top of the list. A plain `SliverToBoxAdapter`, or a header
      // that only reappears once back at the top, would stay fully hidden
      // here. The floating bar should start reappearing immediately
      // instead, following the drag.
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();

      expect(controller.offset, lessThan(scrolledOffset));
      expect(
        controller.offset,
        greaterThan(_FakeTopBar.height / 2),
        reason: 'still far from the top of the list',
      );
      expect(
        paintExtent(),
        greaterThan(0),
        reason:
            'the bar should already be reappearing on the first upward '
            'movement, without needing to reach the top',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "topBarSliver sizes itself from the wrapped bar's own layout (e.g. its "
    'SafeArea-padded height), not a value declared up front',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpHost(tester, controller);

      expect(
        tester.getSize(find.byType(_FakeTopBar)).height,
        _FakeTopBar.height,
      );
    },
  );
}
