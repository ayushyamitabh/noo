import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/selection_action.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/widgets/noo/lists/noo_selection_bar.dart';
import 'package:noo/widgets/settings/settings_action_bar.dart';
import 'package:noo/widgets/settings/settings_swipe.dart';

import 'noo/noo_test_utils.dart';

void main() {
  setUpNooTests();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final desktop in [false, true]) {
    testNooWidgets(
      'action preview follows reorder and exposes overflow (${desktop ? 'tablet' : 'phone'})',
      (tester, theme, colors) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = desktop
            ? const Size(1200, 900)
            : const Size(380, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = SettingsController();
        addTearDown(settings.dispose);
        await pumpNoo(
          tester,
          ChangeNotifierProvider.value(
            value: settings,
            child: SizedBox(
              width: desktop ? 640 : 340,
              child: const SingleChildScrollView(
                child: SettingsActionBarSection(),
              ),
            ),
          ),
          theme: theme,
          surfaceSize: desktop ? const Size(1200, 900) : const Size(380, 900),
        );
        await tester.pumpAndSettle();
        final bar = find.byType(NooSelectionBar);
        expect(bar, findsOneWidget);
        expect(tester.widget<NooSelectionBar>(bar).isDesktop, desktop);
        expect(find.text('Preview'), findsOneWidget);
        settings.setSelectionActionOrder([
          SelectionActionKind.details,
          ...SelectionActionKind.values.where(
            (kind) => kind != SelectionActionKind.details,
          ),
        ]);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: bar, matching: find.byIcon(LucideIcons.info)),
        );
        await tester.pump();
        expect(find.text('Details preview'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: bar,
            matching: desktop
                ? find.text('More')
                : find.byIcon(LucideIcons.ellipsisVertical),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sync to device'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testNooWidgets('swipe picker offers every action and saves the choice', (
    tester,
    theme,
    colors,
  ) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await pumpNoo(
      tester,
      ChangeNotifierProvider.value(
        value: settings,
        child: const SettingsSwipeSection(),
      ),
      theme: theme,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swipe right'));
    await tester.pumpAndSettle();
    for (final kind in SelectionActionKind.values) {
      expect(find.text(kind.label), findsAtLeastNWidgets(1));
    }
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(settings.swipeRightAction, SwipeAction.details);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ui_swipe_right_action'), 'details');
    expect(tester.takeException(), isNull);
  });
}
