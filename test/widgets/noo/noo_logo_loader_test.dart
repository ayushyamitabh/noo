import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/core/noo_logo_loader.dart';

void main() {
  Widget host({bool reduceMotion = false, String? label = 'Loading'}) =>
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: NooLogoLoader(width: 112, semanticLabel: label)),
        ),
      );

  testWidgets('loops through a full cycle without throwing', (tester) async {
    await tester.pumpWidget(host());
    // Step across one whole cycle (balls entering, flying, fading out) and
    // into the next.
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    // Keeps the artwork's 720:741 aspect.
    expect(
      tester.getSize(find.byType(NooLogoLoader)),
      const Size(112, 112 * 741 / 720),
    );
  });

  testWidgets('reduced motion shows a still, finished frame', (tester) async {
    await tester.pumpWidget(host(reduceMotion: true));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decorative mode keeps looping, unannounced', (tester) async {
    await tester.pumpWidget(host(label: null));
    await tester.pump(const Duration(seconds: 15));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.bySemanticsLabel('Loading'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
