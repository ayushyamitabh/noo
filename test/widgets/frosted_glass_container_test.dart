import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/providers/settings_controller.dart';
import 'package:noo/widgets/frosted_glass_container.dart';
import 'noo/noo_test_utils.dart';

void main() {
  setUpNooTests();
  testNooWidgets('viewer glass follows toggle, blur and opacity', (
    tester,
    theme,
    colors,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ui_bottom_bar_frosted': false,
      'ui_bottom_bar_frosted_blur': 19.0,
      'ui_bottom_bar_frosted_opacity': 0.45,
    });
    final settings = SettingsController();
    await pumpNoo(
      tester,
      ChangeNotifierProvider.value(
        value: settings,
        child: const FrostedGlassContainer(
          child: SizedBox(width: 200, height: 80),
        ),
      ),
      theme: theme,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    final fill = find.descendant(
      of: find.byType(FrostedGlassContainer),
      matching: find.byType(Container),
    );
    expect(
      (tester.widget<Container>(fill).decoration as BoxDecoration).color,
      colors.surface,
    );
    settings.setBottomBarFrosted(true);
    await tester.pump();
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
      ImageFilter.blur(sigmaX: 19, sigmaY: 19),
    );
    expect(
      (tester.widget<Container>(fill).decoration as BoxDecoration).color,
      colors.surface.withValues(alpha: 0.45),
    );
    settings.setBottomBarFrosted(false);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
