import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/widgets/noo/core/noo_progress_bar.dart';
import 'package:noo/widgets/noo/core/noo_toggle.dart';
import 'package:noo/widgets/noo/lists/noo_banner.dart';
import 'package:noo/widgets/noo/lists/noo_grouped_list.dart';
import 'package:noo/widgets/noo/lists/noo_settings_row.dart';
import 'package:noo/widgets/noo/lists/noo_summary_card.dart';
import 'package:noo/widgets/noo/lists/noo_tab_order_row.dart';

import 'noo_test_utils.dart';

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
      expect(tester.widget<Text>(find.text('Empty trash')).style!.color, c.danger);
      await tester.tap(find.text('Empty trash'));
      expect(taps, 1);
    });

    testNooWidgets('non-danger action uses accent text', (tester, theme, c) async {
      await pumpNoo(
        tester,
        const NooBanner(actionLabel: 'Undo', actionIsDanger: false, child: Text('x')),
        theme: theme,
      );
      expect(tester.widget<Text>(find.text('Undo')).style!.color, c.accentText);
    });
  });

  group('NooGroupedList', () {
    testNooWidgets('label, aside, 1px line gaps and footer', (tester, theme, c) async {
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
      final gap = tester.getTopLeft(find.byKey(const Key('r2'))).dy -
          tester.getBottomLeft(find.byKey(const Key('r1'))).dy;
      expect(gap, 1);
      // Rows paint their own surface; the gaps show the list's line fill.
      expect(decorationOf(tester, find.byKey(const Key('r1'))).color, c.line);
    });
  });

  group('NooSettingsRow', () {
    testNooWidgets('value row shows chevron and fires onTap', (tester, theme, c) async {
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

    testWidgets('subtitle row is 60px, trailing wins over value', (tester) async {
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

    testWidgets('keeps its 52px height inside a tall bounded parent', (tester) async {
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
          child: NooSettingsRow(icon: LucideIcons.logOut, label: Text('Log out'), danger: true),
        ),
        theme: theme,
      );
      final style = DefaultTextStyle.of(tester.element(find.text('Log out'))).style;
      expect(style.color, c.danger);
      expect(tester.widget<Icon>(find.byIcon(LucideIcons.logOut)).color, c.danger);
    });
  });

  group('NooSummaryCard', () {
    testNooWidgets('stat, caption, progress, meta, action', (tester, theme, c) async {
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
          child: NooSummaryCard(stat: '3', caption: 'Errors', tone: NooSummaryCardTone.danger),
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
    testNooWidgets('pin state drives icon/fill, toggle fires', (tester, theme, c) async {
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
      expect(decorationOf(tester, find.byIcon(LucideIcons.pin)).color, c.accentSoft);

      await tester.tap(find.byIcon(LucideIcons.pin));
      await tester.pump();
      expect(pinned, isFalse);
      expect(find.byIcon(LucideIcons.pin), findsNothing);
      expect(decorationOf(tester, find.byIcon(LucideIcons.pinOff)).color, c.surface2);
    });
  });
}
