import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/widgets/noo/overlays/noo_messenger.dart';

Widget _app(TargetPlatform platform) => MaterialApp(
  theme: AppTheme.light(
    AppTheme.defaultAccent,
    useDynamicColor: false,
  ).copyWith(platform: platform),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => NooMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved'))),
          child: const Text('Go'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('Android shows a Material snackbar', (tester) async {
    await tester.pumpWidget(_app(TargetPlatform.android));
    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('iOS shows a top banner instead, and it goes away', (
    tester,
  ) async {
    await tester.pumpWidget(_app(TargetPlatform.iOS));
    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Saved'), findsOneWidget);
    // Sits under the status bar, not at the bottom.
    expect(tester.getTopLeft(find.text('Saved')).dy, lessThan(100));

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('iOS banner can be swiped away and is replaced by the next', (
    tester,
  ) async {
    await tester.pumpWidget(_app(TargetPlatform.iOS));
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.fling(find.text('Saved'), const Offset(0, -60), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsNothing);
  });
}
