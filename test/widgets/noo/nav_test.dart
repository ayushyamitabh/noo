import 'dart:ui' show ImageFilter;
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
    for (final style in NooNavStyle.values) {
      for (final barStyle in NooBottomBarStyle.values) {
        testNooWidgets(
          '$style/$barStyle: frosted draws a backdrop blur, solid does not',
          (tester, theme, c) async {
            for (final frosted in [false, true]) {
              await pumpNoo(
                tester,
                SizedBox(
                  width: 360,
                  height: 120,
                  child: NooBottomBar(
                    style: style,
                    barStyle: barStyle,
                    frosted: frosted,
                    destinations: _destinations,
                    selectedIndex: 0,
                    onSelected: (_) {},
                    searchDestination: const NooNavDestination(
                      icon: LucideIcons.search,
                      label: 'Search',
                    ),
                    onSearchTap: () {},
                  ),
                ),
                theme: theme,
              );
              expect(
                find.byType(BackdropFilter),
                frosted ? findsWidgets : findsNothing,
              );
            }
          },
        );
      }
    }

    testNooWidgets('frosted bar uses the given blur sigma and fill opacity', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 120,
          child: NooBottomBar(
            style: NooNavStyle.android,
            frosted: true,
            frostedBlur: 31,
            frostedOpacity: 0.5,
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
        theme: theme,
      );
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
        ImageFilter.blur(sigmaX: 31, sigmaY: 31),
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  c.surface.withValues(alpha: 0.5),
        ),
        findsOneWidget,
      );
    });

    test('drawsBehindBody: floating or frosted', () {
      expect(
        NooBottomBar.drawsBehindBody(NooBottomBarStyle.attached, false),
        isFalse,
      );
      expect(
        NooBottomBar.drawsBehindBody(NooBottomBarStyle.attached, true),
        isTrue,
      );
      expect(
        NooBottomBar.drawsBehindBody(NooBottomBarStyle.floating, false),
        isTrue,
      );
    });

    test('floating row height is the Android one on both nav styles', () {
      expect(
        NooBottomBar.rowHeight(NooNavStyle.ios, NooBottomBarStyle.floating),
        64,
      );
      expect(
        NooBottomBar.rowHeight(NooNavStyle.ios, NooBottomBarStyle.attached),
        50,
      );
    });

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

    testNooWidgets('ios: only selected tab has a label, no indicator', (
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
      expect(find.text('Files'), findsNothing);
      expect(find.text('Favorites'), findsNothing);
    });

    testNooWidgets('floating: inset, rounded, bordered - not edge to edge', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 96,
          child: NooBottomBar(
            style: NooNavStyle.android,
            barStyle: NooBottomBarStyle.floating,
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
        theme: theme,
      );
      final pillFinder = find.descendant(
        of: find.byType(NooBottomBar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration != null,
        ),
      );
      final container = tester.widget<Container>(pillFinder);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(28));
      expect(decoration.border, Border.all(color: c.line));
      // Inset from both side edges of the bar's own host box, not flush
      // against it - both rects are in the same (global) coordinate space,
      // so comparing them directly still holds regardless of where
      // `pumpNoo`'s own harness centers that host box on screen.
      final hostRect = tester.getRect(find.byType(NooBottomBar));
      final rect = tester.getRect(pillFinder);
      expect(rect.left, greaterThan(hostRect.left));
      expect(rect.right, lessThan(hostRect.right));
    });

    testNooWidgets(
      'floating android: idle icon has no reserved label space and is '
      'bigger than the active one',
      (tester, theme, c) async {
        await pumpNoo(
          tester,
          SizedBox(
            width: 360,
            height: 96,
            child: NooBottomBar(
              style: NooNavStyle.android,
              barStyle: NooBottomBarStyle.floating,
              destinations: _destinations,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
          theme: theme,
        );
        // Unlike attached, an idle floating tab has no label at all - not
        // just an invisible one - so there's nothing to find here.
        expect(find.text('Photos'), findsNothing);
        expect(
          find.ancestor(
            of: find.byIcon(LucideIcons.images),
            matching: find.byType(AnimatedOpacity),
          ),
          findsNothing,
        );
        final activeIcon = tester.widget<Icon>(find.byIcon(LucideIcons.folder));
        final idleIcon = tester.widget<Icon>(find.byIcon(LucideIcons.images));
        expect(idleIcon.size, greaterThan(activeIcon.size!));
      },
    );

    testNooWidgets(
      'attached: search is the row\'s last item and never highlights',
      (tester, theme, c) async {
        var searchTaps = 0;
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
                searchDestination: const NooNavDestination(
                  icon: LucideIcons.search,
                  label: 'Search',
                ),
                onSearchTap: () => searchTaps++,
              ),
            ),
          ),
          theme: theme,
        );
        expect(find.byIcon(LucideIcons.search), findsOneWidget);
        final iconCenters = [
          tester.getCenter(find.byIcon(LucideIcons.folder)),
          tester.getCenter(find.byIcon(LucideIcons.images)),
          tester.getCenter(find.byIcon(LucideIcons.star)),
          tester.getCenter(find.byIcon(LucideIcons.search)),
        ];
        // Evenly spaced, search landing after every real destination.
        for (var i = 1; i < iconCenters.length; i++) {
          expect(iconCenters[i].dx, greaterThan(iconCenters[i - 1].dx));
        }

        await tester.tap(find.byIcon(LucideIcons.search));
        await tester.pump();
        expect(searchTaps, 1);
        // Tapping search never selects it or moves the indicator.
        expect(selected, 0);
        expect(_indicator(tester, c), findsOneWidget);
        final indicatorLeft = tester.getTopLeft(_indicator(tester, c)).dx;
        expect(indicatorLeft, lessThan(iconCenters[3].dx));
      },
    );

    testNooWidgets('floating: search is a separate round satellite', (
      tester,
      theme,
      c,
    ) async {
      var searchTaps = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          height: 96,
          child: NooBottomBar(
            style: NooNavStyle.ios,
            barStyle: NooBottomBarStyle.floating,
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
            searchDestination: const NooNavDestination(
              icon: LucideIcons.search,
              label: 'Search',
            ),
            onSearchTap: () => searchTaps++,
          ),
        ),
        theme: theme,
      );
      // Not part of the main pill - its own separately-tappable icon.
      expect(find.text('Search'), findsNothing);
      final satellite = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(LucideIcons.search),
          matching: find.byType(Container),
        ),
      );
      final decoration = satellite.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);

      await tester.tap(find.byIcon(LucideIcons.search));
      await tester.pump();
      expect(searchTaps, 1);
    });

    testWidgets('floating with search sizes correctly in a real Scaffold '
        '(regression: unbounded stretch used to fill the whole screen)', (
      tester,
    ) async {
      // A bare SizedBox host (as the other tests use) gives this widget a
      // bounded height, masking this exact bug - Scaffold.bottomNavigationBar
      // gives its child a *loose*, unbounded-max height instead, which is
      // what a Row with crossAxisAlignment.stretch blows up against in
      // profile/release (the debug assertion that would catch it is
      // stripped there). Only a real Scaffold reproduces that.
      await tester.pumpWidget(
        MaterialApp(
          theme: nooTheme(Brightness.light),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: NooBottomBar(
              style: NooNavStyle.android,
              barStyle: NooBottomBarStyle.floating,
              destinations: _destinations,
              selectedIndex: 0,
              onSelected: (_) {},
              searchDestination: const NooNavDestination(
                icon: LucideIcons.search,
                label: 'Search',
              ),
              onSearchTap: () {},
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(NooBottomBar));
      expect(size.height, lessThan(150));
    });
  });
}
