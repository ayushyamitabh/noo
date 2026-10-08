import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/providers/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'defaults to top and safely handles an unknown saved position',
    () async {
      for (final saved in [null, 'unknown']) {
        SharedPreferences.setMockInitialValues({
          'ui_selection_bar_position': ?saved,
        });
        final settings = SettingsController();
        await Future<void>.delayed(Duration.zero);
        expect(settings.selectionBarPosition, SelectionBarPosition.top);
        settings.dispose();
      }
    },
  );

  test(
    'bottom position persists and restores across controller creation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController();
      await Future<void>.delayed(Duration.zero);
      settings.setSelectionBarPosition(SelectionBarPosition.bottom);
      await Future<void>.delayed(Duration.zero);
      final restored = SettingsController();
      await Future<void>.delayed(Duration.zero);
      expect(restored.selectionBarPosition, SelectionBarPosition.bottom);
      settings.dispose();
      restored.dispose();
    },
  );
  test(
    'avatar position defaults to top and restores a saved bottom choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController();
      await Future<void>.delayed(Duration.zero);
      expect(settings.avatarPosition, AvatarPosition.top);
      settings.setAvatarPosition(AvatarPosition.bottom);
      await Future<void>.delayed(Duration.zero);
      final restored = SettingsController();
      await Future<void>.delayed(Duration.zero);
      expect(restored.avatarPosition, AvatarPosition.bottom);
      settings.dispose();
      restored.dispose();
    },
  );
}
