import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/models/selection_action.dart';
import 'package:noo/widgets/noo/core/noo_progress_bar.dart';
import 'package:noo/widgets/noo/core/noo_toggle.dart';
import 'package:noo/widgets/noo/lists/noo_banner.dart';
import 'package:noo/widgets/noo/lists/noo_grouped_list.dart';
import 'package:noo/widgets/noo/lists/noo_selection_bar.dart';
import 'package:noo/widgets/noo/lists/noo_settings_row.dart';
import 'package:noo/widgets/noo/lists/noo_summary_card.dart';
import 'package:noo/widgets/noo/lists/noo_tab_order_row.dart';

import 'noo_test_utils.dart';

/// [n] actions labelled A, B, C, ... each incrementing an entry in [taps]
/// keyed by its own label when tapped. [n] must be at most
/// `SelectionActionKind.values.length` - each generated action needs its
/// own distinct kind.
List<SelectionAction> _actions(int n, Map<String, int> taps) =>
    List.generate(n, (i) {
      final label = String.fromCharCode(65 + i);
      taps[label] = 0;
      return SelectionAction(
        kind: SelectionActionKind.values[i],
        icon: LucideIcons.star,
        label: label,
        onTap: () => taps[label] = taps[label]! + 1,
      );
    });

void main() {
  setUpNooTests();

  group('NooBanner', () {
    testNooWidgets('renders text and fires action', (tester, theme, c) async {
      var taps = 0;
      await pumpNoo(
        tester,
        NooBanner(
          actionLabel: 'Empty trash',
          onAction: () => taps++,
          child: const Text('Items are deleted after 30 days'),
        ),
        theme: theme,
      );
      expect(find.byIcon(LucideIcons.info), findsOneWidget);
      expect(decorationOf(tester, find.text('Empty trash')).color, c.surface);
      expect(
        tester.widget<Text>(find.text('Empty trash')).style!.color,
        c.danger,
      );
      await tester.tap(find.text('Empty trash'));
      expect(taps, 1);
    });

    testNooWidgets('non-danger action uses accent text', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        const NooBanner(
          actionLabel: 'Undo',
          actionIsDanger: false,
          child: Text('x'),
        ),
        theme: theme,
      );
      expect(tester.widget<Text>(find.text('Undo')).style!.color, c.accentText);
    });
  });

  group('NooGroupedList', () {
    testNooWidgets('label, aside, 1px line gaps and footer', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooGroupedList(
            label: 'Accounts',
            aside: '2',
            footer: const Text('Footer note'),
            children: [
              Container(key: const Key('r1'), height: 52, color: c.surface),
              Container(key: const Key('r2'), height: 52, color: c.surface),
            ],
          ),
        ),
        theme: theme,
      );
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Footer note'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Accounts')).style!.color, c.fg2);
      final gap =
          tester.getTopLeft(find.byKey(const Key('r2'))).dy -
          tester.getBottomLeft(find.byKey(const Key('r1'))).dy;
      expect(gap, 1);
      // Rows paint their own surface; the gaps show the list's line fill.
      expect(decorationOf(tester, find.byKey(const Key('r1'))).color, c.line);
    });

    testNooWidgets('collapsible starts expanded, tapping the label hides '
        'and re-shows the card', (tester, theme, c) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooGroupedList(
            label: 'Appearance',
            collapsible: true,
            children: [
              Container(key: const Key('r1'), height: 52, color: c.surface),
            ],
          ),
        ),
        theme: theme,
      );
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('r1'))).height, 52);
      AnimatedCrossFade crossFade() =>
          tester.widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade));
      expect(crossFade().crossFadeState, CrossFadeState.showFirst);

      await tester.tap(find.text('Appearance'));
      await tester.pump();
      expect(crossFade().crossFadeState, CrossFadeState.showSecond);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0,
      );

      await tester.tap(find.text('Appearance'));
      await tester.pump();
      expect(crossFade().crossFadeState, CrossFadeState.showFirst);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0.5,
      );
    });

    testNooWidgets('non-collapsible has no chevron and ignores label taps', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooGroupedList(
            label: 'Accounts',
            children: [
              Container(key: const Key('r1'), height: 52, color: c.surface),
            ],
          ),
        ),
        theme: theme,
      );
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('r1'))).height, 52);
    });
  });

  group('NooSelectionBar', () {
    testNooWidgets('mobile: all actions show inline when they fit', (
      tester,
      theme,
      c,
    ) async {
      final taps = <String, int>{};
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooSelectionBar(
            count: 2,
            actions: _actions(2, taps),
            onClose: () {},
            isDesktop: false,
          ),
        ),
        theme: theme,
      );
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byIcon(LucideIcons.star), findsNWidgets(2));
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);
      await tester.tap(find.byIcon(LucideIcons.star).first);
      expect(taps['A'], 1);
    });

    testNooWidgets(
      'mobile: actions beyond the inline count collapse behind More',
      (tester, theme, c) async {
        final taps = <String, int>{};
        await pumpNoo(
          tester,
          // Wide enough that the missing-webfont fallback used in tests
          // (Google Fonts network fetch is off, see noo_test_utils.dart)
          // doesn't itself force an overflow unrelated to what's tested here.
          SizedBox(
            width: 500,
            child: NooSelectionBar(
              count: 5,
              actions: _actions(5, taps),
              onClose: () {},
              isDesktop: false,
            ),
          ),
          theme: theme,
        );
        // Only the first 3 actions render inline - no horizontally-
        // scrolling row that could hide the rest with no visible cue.
        expect(find.byIcon(LucideIcons.star), findsNWidgets(3));
        expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);

        await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
        await tester.pumpAndSettle();
        // The sheet lists exactly the overflowed actions (D, E) - the
        // already-inline ones (A, B, C) aren't duplicated in it.
        expect(find.text('D'), findsOneWidget);
        expect(find.text('E'), findsOneWidget);
        expect(find.text('A'), findsNothing);

        await tester.tap(find.text('D'));
        await tester.pumpAndSettle();
        expect(taps['D'], 1);
      },
    );

    testNooWidgets(
      'desktop: actions beyond the inline count collapse behind More',
      (tester, theme, c) async {
        final taps = <String, int>{};
        await pumpNoo(
          tester,
          SizedBox(
            width: 900,
            child: NooSelectionBar(
              count: 6,
              actions: _actions(6, taps),
              onClose: () {},
              isDesktop: true,
            ),
          ),
          theme: theme,
        );
        // The first 4 actions render as labelled pills; the rest are behind
        // "More".
        for (final label in ['A', 'B', 'C', 'D']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('E'), findsNothing);
        expect(find.text('More'), findsOneWidget);

        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        expect(find.text('E'), findsOneWidget);
        expect(find.text('F'), findsOneWidget);
      },
    );

    testNooWidgets('close button fires onClose', (tester, theme, c) async {
      var closed = false;
      final taps = <String, int>{};
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooSelectionBar(
            count: 1,
            actions: _actions(1, taps),
            onClose: () => closed = true,
            isDesktop: false,
          ),
        ),
        theme: theme,
      );
      await tester.tap(find.byIcon(LucideIcons.x));
      expect(closed, isTrue);
    });
  });

  group('NooSettingsRow', () {
    testNooWidgets('value row shows chevron and fires onTap', (
      tester,
      theme,
      c,
    ) async {
      var taps = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooGroupedList(
            children: [
              NooSettingsRow(
                icon: LucideIcons.palette,
                label: const Text('Theme'),
                value: 'System',
                onTap: () => taps++,
              ),
            ],
          ),
        ),
        theme: theme,
      );
      expect(find.text('System'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      expect(tester.getSize(find.byType(NooSettingsRow)).height, 52);
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('subtitle row is 60px, trailing wins over value', (
      tester,
    ) async {
      await pumpNoo(
        tester,
        const SizedBox(
          width: 600,
          child: NooGroupedList(
            children: [
              NooSettingsRow(
                label: Text('Sync on Wi-Fi only'),
                subtitle: Text('Saves mobile data'),
                value: 'ignored',
                trailing: NooToggle(checked: true),
              ),
            ],
          ),
        ),
      );
      expect(find.text('ignored'), findsNothing);
      expect(find.byType(NooToggle), findsOneWidget);
      expect(tester.getSize(find.byType(NooSettingsRow)).height, 60);
    });

    testWidgets('keeps its 52px height inside a tall bounded parent', (
      tester,
    ) async {
      await pumpNoo(
        tester,
        const SizedBox(
          width: 360,
          height: 400,
          child: Align(
            alignment: Alignment.topCenter,
            child: NooSettingsRow(label: Text('Theme'), value: 'System'),
          ),
        ),
      );
      expect(tester.getSize(find.byType(NooSettingsRow)).height, 52);
    });

    testNooWidgets('danger row uses danger colour', (tester, theme, c) async {
      await pumpNoo(
        tester,
        const SizedBox(
          width: 360,
          child: NooSettingsRow(
            icon: LucideIcons.logOut,
            label: Text('Log out'),
            danger: true,
          ),
        ),
        theme: theme,
      );
      final style = DefaultTextStyle.of(
        tester.element(find.text('Log out')),
      ).style;
      expect(style.color, c.danger);
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.logOut)).color,
        c.danger,
      );
    });
  });

  group('NooSummaryCard', () {
    testNooWidgets('stat, caption, progress, meta, action', (
      tester,
      theme,
      c,
    ) async {
      await pumpNoo(
        tester,
        const SizedBox(
          width: 360,
          child: NooSummaryCard(
            stat: '2.4 GB',
            caption: 'Offline',
            progress: 0.4,
            meta: 'Synced 2 min ago',
            action: Text('Sync now'),
          ),
        ),
        theme: theme,
      );
      for (final t in ['2.4 GB', 'Offline', 'Synced 2 min ago', 'Sync now']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.byType(NooProgressBar), findsOneWidget);
      expect(decorationOf(tester, find.text('2.4 GB')).color, c.surface);
      expect(tester.widget<Text>(find.text('2.4 GB')).style!.color, c.fg1);
    });

    testNooWidgets('danger tone', (tester, theme, c) async {
      await pumpNoo(
        tester,
        const SizedBox(
          width: 360,
          child: NooSummaryCard(
            stat: '3',
            caption: 'Errors',
            tone: NooSummaryCardTone.danger,
          ),
        ),
        theme: theme,
      );
      expect(find.byType(NooProgressBar), findsNothing);
      expect(decorationOf(tester, find.text('3')).color, c.dangerSoft);
      expect(tester.widget<Text>(find.text('3')).style!.color, c.danger);
      expect(tester.widget<Text>(find.text('Errors')).style!.color, c.danger);
    });
  });

  group('NooTabOrderRow', () {
    testNooWidgets('pin state drives icon/fill, toggle fires', (
      tester,
      theme,
      c,
    ) async {
      var pinned = true;
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: StatefulBuilder(
            builder: (context, setState) => NooTabOrderRow(
              icon: LucideIcons.folder,
              label: 'Files',
              pinned: pinned,
              onTogglePin: () => setState(() => pinned = !pinned),
            ),
          ),
        ),
        theme: theme,
      );
      expect(find.text('Files'), findsOneWidget);
      expect(
        decorationOf(tester, find.byIcon(LucideIcons.pin)).color,
        c.accentSoft,
      );

      await tester.tap(find.byIcon(LucideIcons.pin));
      await tester.pump();
      expect(pinned, isFalse);
      expect(find.byIcon(LucideIcons.pin), findsNothing);
      expect(
        decorationOf(tester, find.byIcon(LucideIcons.pinOff)).color,
        c.surface2,
      );
    });
  });
}
