import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/theme/design_tokens.dart';
import 'package:noo/widgets/noo/nav/noo_bottom_bar.dart';
import 'package:noo/widgets/noo/nav/noo_nav_style.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const dests = [
    NooNavDestination(icon: LucideIcons.folder, label: 'Files'),
    NooNavDestination(icon: LucideIcons.image, label: 'Photos'),
  ];

  Widget bar(NooNavStyle style, NooBottomBarStyle barStyle, bool iconOnly) =>
      MaterialApp(
        theme: ThemeData(extensions: [NooColors.light]),
        home: Scaffold(
          bottomNavigationBar: NooBottomBar(
            style: style,
            barStyle: barStyle,
            iconOnly: iconOnly,
            destinations: dests,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );

  for (final style in NooNavStyle.values) {
    for (final barStyle in NooBottomBarStyle.values) {
      testWidgets('icon-only hides every label ($style/$barStyle)', (t) async {
        await t.pumpWidget(bar(style, barStyle, true));
        expect(find.text('Files'), findsNothing);
        expect(find.text('Photos'), findsNothing);
        expect(find.byIcon(LucideIcons.folder), findsOneWidget);
        expect(find.byIcon(LucideIcons.image), findsOneWidget);
      });
    }
  }

  testWidgets('labels still show by default', (t) async {
    await t.pumpWidget(bar(NooNavStyle.android, NooBottomBarStyle.attached, false));
    expect(find.text('Files'), findsOneWidget);
  });

  test('icon-only makes the Android attached row shorter', () {
    expect(
      NooBottomBar.rowHeight(NooNavStyle.android, NooBottomBarStyle.attached),
      80,
    );
    expect(
      NooBottomBar.rowHeight(
        NooNavStyle.android,
        NooBottomBarStyle.attached,
        iconOnly: true,
      ),
      64,
    );
  });
}
