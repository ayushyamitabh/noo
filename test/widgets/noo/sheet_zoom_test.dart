import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/widgets/noo/overlays/noo_sheet.dart';
import 'package:noo/widgets/noo/overlays/sheet_zoom.dart';

void main() {
  testWidgets(
    'the page zooms out while a bottom sheet is open and back after',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppTheme.defaultAccent, useDynamicColor: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNooSheet(
                    context,
                    children: const [Text('Sheet body')],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(SheetZoom.instance.value, 0);

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sheet body'), findsOneWidget);
      expect(SheetZoom.instance.value, 1);
      // The page behind is scaled down.
      final scale = tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(ZoomOutOnSheet),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[0];
      expect(scale, closeTo(1 - SheetZoom.shrink, .001));

      // Dismissing the sheet zooms back in.
      await tester.tapAt(const Offset(200, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Sheet body'), findsNothing);
      expect(SheetZoom.instance.value, 0);
    },
  );
}
