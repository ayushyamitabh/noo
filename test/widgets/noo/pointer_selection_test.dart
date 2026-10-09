import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/core/noo_pointer_selection.dart';

void main() {
  testWidgets('mouse reveals checkbox; clicking selects without opening item', (
    tester,
  ) async {
    var opened = 0;
    var toggled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NooPointerSelection(
          child: Scaffold(
            body: GestureDetector(
              onTap: () => opened++,
              child: NooPointerCheckbox(
                selected: false,
                onToggle: () => toggled++,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Checkbox), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    expect(toggled, 1);
    expect(opened, 0);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
  });
  testWidgets('nonselectable items never show checkboxes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NooPointerSelection(child: NooPointerCheckbox(selected: false)),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });
}
