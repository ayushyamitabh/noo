import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/drop_preparation_overlay.dart';
import 'noo/noo_test_utils.dart';

void main() {
  setUpNooTests();

  testWidgets(
    'preparation blocks input and releases it when staging finishes',
    (tester) async {
      final progress = StreamController<int>();
      addTearDown(progress.close);
      var taps = 0;
      await pumpNoo(
        tester,
        DropPreparationOverlay(
          preparation: progress.stream,
          child: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Files'),
            ),
          ),
        ),
      );
      progress.add(2);
      await tester.pump();
      expect(find.text('Preparing 2 files…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Files'), warnIfMissed: false);
      expect(taps, 0);
      progress.add(1);
      await tester.pump();
      expect(find.text('Preparing file…'), findsOneWidget);
      progress.add(0);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Files'));
      expect(taps, 1);
    },
  );
}
