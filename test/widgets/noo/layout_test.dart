import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/noo_layout.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final size in [
      const Size(600, 960),
      const Size(768, 1024),
      const Size(1024, 768),
      const Size(430, 932),
      const Size(932, 430),
      const Size(599, 1024),
    ]) {
      testWidgets('$platform sidebar at $size', (tester) async {
        bool? sidebar;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(size: size),
              child: Builder(
                builder: (context) {
                  sidebar = NooLayout.isDesktop(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        expect(sidebar, size.shortestSide >= 600);
      });
    }
  }
}
