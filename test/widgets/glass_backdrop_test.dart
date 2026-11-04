import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/glass_backdrop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('glass shader compiles and loads', () async {
    await GlassShader.load();
    // `available` also needs Impeller, which flutter test doesn't enable, so
    // only the asset load itself is asserted here.
    expect(GlassShader.isLoaded, isTrue);
  });

  testWidgets('falls back to blur without the glass setting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassBackdrop(
          radius: BorderRadius.circular(12),
          sigma: 10,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
