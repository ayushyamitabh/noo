import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/theme/design_tokens.dart';
import 'package:noo/widgets/noo/nav/noo_bottom_bar.dart';

import 'noo_test_utils.dart';

const _destinations = [
  NooNavDestination(icon: LucideIcons.folder, label: 'Files'),
  NooNavDestination(icon: LucideIcons.images, label: 'Photos'),
  NooNavDestination(icon: LucideIcons.star, label: 'Favorites'),
];

/// The single sliding accent-soft indicator `NooBottomBar` draws behind the
/// Android row - there should only ever be one, never a per-item pill.
Finder _indicator(WidgetTester tester, NooColors c) => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).color == c.accentSoft,
);

void main() {
  setUpNooTests();

  group('NooBottomBar', () {
    testNooWidgets('android: label sits below the icon, not beside it', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 80,
          child: NooBottomBar(
            style: NooNavStyle.android,
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
        theme: theme,
      );
      final iconCenter = tester.getCenter(find.byIcon(LucideIcons.folder));
      final labelCenter = tester.getCenter(find.text('Files'));
      expect(labelCenter.dy, greaterThan(iconCenter.dy));
      expect((labelCenter.dx - iconCenter.dx).abs(), lessThan(1));
    });

    testNooWidgets(
      'android: exactly one indicator, it slides to the tapped tab',
      (tester, theme, c) async {
        var selected = 0;
        await pumpNoo(
          tester,
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 360,
              height: 80,
              child: NooBottomBar(
                style: NooNavStyle.android,
                destinations: _destinations,
                selectedIndex: selected,
                onSelected: (i) => setState(() => selected = i),
              ),
            ),
          ),
          theme: theme,
        );
        expect(_indicator(tester, c), findsOneWidget);
        final startX = tester.getTopLeft(_indicator(tester, c)).dx;

        await tester.tap(find.text('Favorites'));
        await tester.pumpAndSettle();
        expect(_indicator(tester, c), findsOneWidget);
        expect(
          tester.getTopLeft(_indicator(tester, c)).dx,
          greaterThan(startX),
        );
      },
    );

    testNooWidgets('android: idle labels stay laid out but invisible', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 80,
          child: NooBottomBar(
            style: NooNavStyle.android,
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
        theme: theme,
      );
      // Idle labels are still in the tree (fixed row height, no jump when
      // selection changes) - just invisible.
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('Photos'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0);
    });

    testNooWidgets('ios: unchanged icon-above-label layout, no indicator', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 50,
          child: NooBottomBar(
            style: NooNavStyle.ios,
            destinations: _destinations,
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
        theme: theme,
      );
      expect(_indicator(tester, c), findsNothing);
      final iconCenter = tester.getCenter(find.byIcon(LucideIcons.images));
      final labelCenter = tester.getCenter(find.text('Photos'));
      expect(labelCenter.dy, greaterThan(iconCenter.dy));
    });
  });
}
