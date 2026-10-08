import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/providers/settings_controller.dart';

/// The frosted-glass bottom bar's blur/opacity settings and their presets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> build() async {
    final settings = SettingsController();
    // `_load` is async and not exposed; one event-loop turn lets it finish.
    await Future<void>.delayed(Duration.zero);
    return settings;
  }

  test('starts on the Default preset', () async {
    final settings = await build();
    expect(settings.frostedPreset, FrostedGlassPreset.standard);
    expect(settings.bottomBarFrostedBlur, 20);
    expect(settings.bottomBarFrostedOpacity, 0.72);
  });

  test('presets set both values and are recognised again', () async {
    final settings = await build();
    for (final preset in FrostedGlassPreset.values) {
      settings.setFrostedPreset(preset);
      expect(settings.bottomBarFrostedBlur, preset.blur);
      expect(settings.bottomBarFrostedOpacity, preset.opacity);
      expect(settings.frostedPreset, preset);
    }
  });

  test('presets run from lighter to stronger frosting', () {
    expect(
      FrostedGlassPreset.less.blur,
      lessThan(FrostedGlassPreset.standard.blur),
    );
    expect(
      FrostedGlassPreset.standard.blur,
      lessThan(FrostedGlassPreset.more.blur),
    );
    expect(
      FrostedGlassPreset.less.opacity,
      greaterThan(FrostedGlassPreset.standard.opacity),
    );
    expect(
      FrostedGlassPreset.standard.opacity,
      greaterThan(FrostedGlassPreset.more.opacity),
    );
  });

  test('moving a slider off every preset leaves none selected', () async {
    final settings = await build();
    settings.setFrostedBlur(27);
    expect(settings.frostedPreset, isNull);
    settings.setFrostedBlur(FrostedGlassPreset.standard.blur);
    expect(settings.frostedPreset, FrostedGlassPreset.standard);
  });

  test('values are clamped to their ranges', () async {
    final settings = await build();
    settings
      ..setFrostedBlur(500)
      ..setFrostedOpacity(0);
    expect(settings.bottomBarFrostedBlur, maxFrostedBlur);
    expect(settings.bottomBarFrostedOpacity, minFrostedOpacity);
    settings
      ..setFrostedBlur(-3)
      ..setFrostedOpacity(9);
    expect(settings.bottomBarFrostedBlur, minFrostedBlur);
    expect(settings.bottomBarFrostedOpacity, maxFrostedOpacity);
  });

  test('saved values are restored (and clamped) on the next launch', () async {
    SharedPreferences.setMockInitialValues({
      'ui_bottom_bar_frosted_blur': 32.0,
      'ui_bottom_bar_frosted_opacity': 7.0,
    });
    final settings = await build();
    expect(settings.bottomBarFrostedBlur, 32);
    expect(settings.bottomBarFrostedOpacity, maxFrostedOpacity);
  });
}
