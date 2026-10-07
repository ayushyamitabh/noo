import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/selection_bar_overlay.dart';

void main() {
  for (final extendsBody in [false, true]) {
    for (final safeBottom in [0.0, 34.0]) {
      testWidgets(
        'action bar clears navigation: extend=$extendsBody, inset=$safeBottom',
        (tester) async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(bottom: safeBottom);
          addTearDown(tester.view.reset);
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                extendBody: extendsBody,
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: SizedBox(
                    key: const ValueKey('navigation'),
                    height: 64,
                  ),
                ),
                body: SelectionBarOverlay(
                  bar: GestureDetector(
                    onTap: () => taps++,
                    child: Container(
                      key: const ValueKey('actions'),
                      color: Colors.blue,
                    ),
                  ),
                  child: ListView.builder(
                    itemCount: 100,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 48, child: Text('Item $i')),
                  ),
                ),
              ),
            ),
          );
          final actions = find.byKey(const ValueKey('actions'));
          final navTop = tester
              .getTopLeft(find.byKey(const ValueKey('navigation')))
              .dy;
          expect(tester.getBottomLeft(actions).dy, navTop - 8);
          final before = tester.getTopLeft(actions);
          await tester.drag(find.byType(ListView), const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(actions), before);
          await tester.tap(actions);
          expect(taps, 1);
        },
      );
    }
  }
}
