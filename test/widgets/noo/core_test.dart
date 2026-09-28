import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/theme/design_tokens.dart';
import 'package:noo/widgets/noo/core/noo_avatar.dart';
import 'package:noo/widgets/noo/core/noo_badge.dart';
import 'package:noo/widgets/noo/core/noo_button.dart';
import 'package:noo/widgets/noo/core/noo_chip.dart';
import 'package:noo/widgets/noo/core/noo_fab.dart';
import 'package:noo/widgets/noo/core/noo_progress_bar.dart';
import 'package:noo/widgets/noo/core/noo_search_field.dart';
import 'package:noo/widgets/noo/core/noo_segmented_control.dart';
import 'package:noo/widgets/noo/core/noo_toggle.dart';

import 'noo_test_utils.dart';

void main() {
  setUpNooTests();

  group('NooColors.fromSeed', () {
    test('the default accent returns the untouched fixed palette', () {
      expect(
        identical(
          NooColors.fromSeed(AppTheme.defaultAccent, Brightness.light),
          NooColors.light,
        ),
        isTrue,
      );
      expect(
        identical(
          NooColors.fromSeed(AppTheme.defaultAccent, Brightness.dark),
          NooColors.dark,
        ),
        isTrue,
      );
    });

    test('a custom seed retints only the accent roles', () {
      const seed = Color(0xFF009688); // Ocean Teal
      final light = NooColors.fromSeed(seed, Brightness.light);
      expect(light.accent, seed);
      expect(light.accentText, seed);
      expect(light.accentSoft, isNot(NooColors.light.accentSoft));
      // The rest of the palette is untouched - a named accent choice
      // retints the brand color, it doesn't reshape the surface.
      expect(light.bg, NooColors.light.bg);
      expect(light.surface, NooColors.light.surface);
      expect(light.fg1, NooColors.light.fg1);

      final dark = NooColors.fromSeed(seed, Brightness.dark);
      expect(dark.accent, seed);
      // Dark accentText is a lighter/desaturated tint for contrast, not
      // the raw seed itself.
      expect(dark.accentText, isNot(seed));
      expect(dark.bg, NooColors.dark.bg);
    });
  });

  group('NooColors.fromDynamicScheme', () {
    test('scrim comes from the fixed palette, not the opaque dynamic role', () {
      // Material 3's ColorScheme.scrim is fully opaque black - using it
      // directly as a sheet/dialog barrierColor hid the screen behind
      // completely instead of dimming it.
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF009688),
        brightness: Brightness.light,
      );
      expect(dynamicScheme.scrim.a, 1.0);
      final nooColors = NooColors.fromDynamicScheme(dynamicScheme);
      expect(nooColors.scrim, NooColors.light.scrim);
      expect(nooColors.scrim.a, lessThan(1.0));
    });
  });

  group('NooAvatar', () {
    testNooWidgets('current user uses accent-soft/accent-text', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        const NooAvatar(initials: 'AY', current: true),
        theme: theme,
      );
      expect(find.text('AY'), findsOneWidget);
      expect(decorationOf(tester, find.text('AY')).color, c.accentSoft);
      expect(tester.widget<Text>(find.text('AY')).style!.color, c.accentText);
    });

    testNooWidgets('palette avatar uses fixed dark text', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        NooAvatar(initials: 'JD', color: NooColors.avatarPalette[3]),
        theme: theme,
      );
      expect(
        decorationOf(tester, find.text('JD')).color,
        NooColors.avatarPalette[3],
      );
      expect(
        tester.widget<Text>(find.text('JD')).style!.color,
        NooColors.avatarTextColor,
      );
    });

    testWidgets('icon avatar and size', (tester) async {
      await pumpNoo(tester, const NooAvatar(icon: LucideIcons.users, size: 48));
      expect(find.byIcon(LucideIcons.users), findsOneWidget);
      expect(tester.getSize(find.byType(NooAvatar)), const Size(48, 48));
    });
  });

  group('NooBadge', () {
    testNooWidgets('tones map to soft/strong pairs', (tester, theme, c) async {
      await pumpNoo(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NooBadge(child: Text('ok')),
            NooBadge(tone: NooBadgeTone.danger, child: Text('bad')),
          ],
        ),
        theme: theme,
      );
      expect(decorationOf(tester, find.text('ok')).color, c.successSoft);
      expect(decorationOf(tester, find.text('bad')).color, c.dangerSoft);
      expect(tester.getSize(find.byType(NooBadge).first).height, 24);
    });
  });

  group('NooButton', () {
    testNooWidgets('primary renders and fires onTap', (tester, theme, c) async {
      var taps = 0;
      await pumpNoo(
        tester,
        NooButton(
          icon: LucideIcons.upload,
          onTap: () => taps++,
          child: const Text('Upload'),
        ),
        theme: theme,
      );
      expect(decorationOf(tester, find.text('Upload')).color, c.accent);
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('disabled ignores taps', (tester) async {
      var taps = 0;
      await pumpNoo(
        tester,
        NooButton(disabled: true, onTap: () => taps++, child: const Text('No')),
      );
      await tester.tap(find.text('No'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('shrink-wraps unless fullWidth, heights follow size', (
      tester,
    ) async {
      await pumpNoo(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NooButton(key: Key('a'), size: NooButtonSize.cta, child: Text('A')),
            NooButton(key: Key('b'), fullWidth: true, child: Text('B')),
          ],
        ),
      );
      final a = tester.getSize(find.byKey(const Key('a')));
      final b = tester.getSize(find.byKey(const Key('b')));
      expect(a.height, NooSizes.buttonCta);
      expect(a.width, lessThan(200));
      expect(b.height, NooSizes.buttonToolbar);
      expect(b.width, greaterThan(700));
    });

    testNooWidgets('variants pick matching fill', (tester, theme, c) async {
      await pumpNoo(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NooButton(variant: NooButtonVariant.tonal, child: Text('t')),
            NooButton(variant: NooButtonVariant.secondary, child: Text('s')),
            NooButton(variant: NooButtonVariant.danger, child: Text('d')),
          ],
        ),
        theme: theme,
      );
      expect(decorationOf(tester, find.text('t')).color, c.accentSoft);
      expect(decorationOf(tester, find.text('s')).color, c.surface2);
      expect(decorationOf(tester, find.text('d')).color, c.dangerSoft);
    });
  });

  group('NooChip', () {
    testNooWidgets('selected vs idle fill, onTap fires', (
      tester,
      theme,
      c,
    ) async {
      var taps = 0;
      await pumpNoo(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NooChip(
              selected: true,
              onTap: () => taps++,
              child: const Text('Name'),
            ),
            const NooChip(trailing: NooChipTrailing.menu, child: Text('Type')),
          ],
        ),
        theme: theme,
      );
      expect(decorationOf(tester, find.text('Name')).color, c.accentSoft);
      expect(decorationOf(tester, find.text('Type')).color, c.surface);
      await tester.tap(find.text('Name'));
      expect(taps, 1);
    });

    testWidgets('outline chip is 32px with a line border', (tester) async {
      await pumpNoo(
        tester,
        const NooChip(outline: true, child: Text('Modified')),
      );
      expect(tester.getSize(find.byType(NooChip)).height, 32);
      final border =
          decorationOf(tester, find.text('Modified')).border as Border;
      expect(border.top.color, NooColors.light.line);
    });
  });

  group('NooFab', () {
    testNooWidgets('shows label and fires onTap', (tester, theme, c) async {
      var taps = 0;
      await pumpNoo(tester, NooFab(onTap: () => taps++), theme: theme);
      expect(find.text('Upload'), findsOneWidget);
      expect(tester.getSize(find.byType(NooFab)).height, 56);
      expect(tester.getSize(find.byType(NooFab)).width, lessThan(200));
      await tester.tap(find.byType(NooFab));
      expect(taps, 1);
    });

    testNooWidgets('collapsed hides the label and shrinks to a circle', (
      tester,
      theme,
      c,
    ) async {
      var taps = 0;
      await pumpNoo(
        tester,
        NooFab(collapsed: true, onTap: () => taps++),
        theme: theme,
      );
      await tester.pumpAndSettle();
      expect(find.text('Upload'), findsNothing);
      final size = tester.getSize(find.byType(NooFab));
      expect(size.height, 56);
      expect(size.width, 56);
      await tester.tap(find.byType(NooFab));
      expect(taps, 1);
    });
  });

  group('NooProgressBar', () {
    testNooWidgets('clamps value and uses track/fill tokens', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        const SizedBox(width: 200, child: NooProgressBar(value: 1.7)),
        theme: theme,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
      expect(bar.backgroundColor, c.surface3);
      expect(bar.valueColor!.value, c.accent);
      expect(tester.getSize(find.byType(NooProgressBar)).height, 6);
    });
  });

  group('NooSearchField', () {
    testNooWidgets('placeholder, typing, surface fill', (
      tester,
      theme,
      c,
    ) async {
      String? typed;
      await pumpNoo(
        tester,
        SizedBox(
          width: 260,
          child: NooSearchField(onSurface: true, onChanged: (v) => typed = v),
        ),
        theme: theme,
      );
      expect(find.text('Search'), findsOneWidget);
      expect(decorationOf(tester, find.byType(TextField)).color, c.surface2);
      await tester.enterText(find.byType(TextField), 'cats');
      expect(typed, 'cats');
    });
  });

  group('NooSegmentedControl', () {
    Widget host() {
      var value = 'list';
      return StatefulBuilder(
        builder: (context, setState) => NooSegmentedControl<String>(
          value: value,
          onChanged: (v) => setState(() => value = v),
          options: const [
            NooSegmentOption(value: 'list', label: 'List'),
            NooSegmentOption(value: 'grid', label: 'Grid'),
          ],
        ),
      );
    }

    testNooWidgets('tapping a segment moves the active fill', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(tester, host(), theme: theme);
      expect(decorationOf(tester, find.text('List')).color, c.accentSoft);
      expect(tester.widget<Text>(find.text('Grid')).style!.color, c.fg2);

      await tester.tap(find.text('Grid'));
      await tester.pump();
      expect(decorationOf(tester, find.text('Grid')).color, c.accentSoft);
      expect(tester.widget<Text>(find.text('Grid')).style!.color, c.accentText);
      expect(tester.widget<Text>(find.text('List')).style!.color, c.fg2);
    });

    testWidgets('icon-only segments are 36x28', (tester) async {
      await pumpNoo(
        tester,
        NooSegmentedControl<int>(
          value: 0,
          iconOnly: true,
          options: const [
            NooSegmentOption(value: 0, icon: LucideIcons.list),
            NooSegmentOption(value: 1, icon: LucideIcons.layoutGrid),
          ],
        ),
      );
      expect(find.byType(Text), findsNothing);
      // 2 x 36 wide segments + 3px track padding each side.
      expect(
        tester.getSize(find.byType(NooSegmentedControl<int>)),
        const Size(78, 34),
      );
    });
  });

  group('NooToggle', () {
    testNooWidgets('tapping flips state and track colour', (
      tester,
      theme,
      c,
    ) async {
      var on = false;
      await pumpNoo(
        tester,
        StatefulBuilder(
          builder: (context, setState) =>
              NooToggle(checked: on, onChanged: (v) => setState(() => on = v)),
        ),
        theme: theme,
      );
      expect(tester.getSize(find.byType(NooToggle)), const Size(48, 28));
      Color track() =>
          (tester
                      .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(track(), c.surface3);

      await tester.tap(find.byType(NooToggle));
      await tester.pumpAndSettle();
      expect(on, isTrue);
      expect(track(), c.accent);

      await tester.tap(find.byType(NooToggle));
      await tester.pumpAndSettle();
      expect(on, isFalse);
    });

    testWidgets('desktop size and null onChanged is inert', (tester) async {
      await pumpNoo(tester, const NooToggle(checked: true, desktop: true));
      expect(tester.getSize(find.byType(NooToggle)), const Size(44, 26));
      await tester.tap(find.byType(NooToggle));
      await tester.pumpAndSettle();
    });
  });
}
