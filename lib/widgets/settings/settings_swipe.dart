import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_settings_row.dart';
import 'settings_section.dart';

/// Settings section 8: what swiping a file left/right does in list view.
class SettingsSwipeSection extends StatelessWidget {
  const SettingsSwipeSection({super.key});

  void _openPicker(
    BuildContext context, {
    required String title,
    required SwipeAction current,
    required ValueChanged<SwipeAction> onChanged,
  }) {
    showSettingsPicker(
      context,
      title: title,
      options: [
        for (final action in SwipeAction.values)
          NooSettingsRow(
            icon: action.selectionKind?.icon,
            label: Text(action.label),
            trailing: action == current
                ? Icon(
                    LucideIcons.check,
                    size: 18,
                    color: context.nooColors.accentText,
                  )
                : null,
            onTap: () {
              onChanged(action);
              Navigator.pop(context);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return SettingsSection(
      title: 'Swipe on a file',
      subtitle: 'Choose what swiping a file left or right does in list view',
      notice: 'Swipe actions have no effect on wide tablets.',
      children: [
        NooSettingsRow(
          icon: LucideIcons.chevronsRight,
          label: const Text('Swipe right'),
          value: settings.swipeRightAction.label,
          onTap: () => _openPicker(
            context,
            title: 'Swipe right',
            current: settings.swipeRightAction,
            onChanged: settings.setSwipeRightAction,
          ),
        ),
        NooSettingsRow(
          icon: LucideIcons.chevronsLeft,
          label: const Text('Swipe left'),
          value: settings.swipeLeftAction.label,
          onTap: () => _openPicker(
            context,
            title: 'Swipe left',
            current: settings.swipeLeftAction,
            onChanged: settings.setSwipeLeftAction,
          ),
        ),
      ],
    );
  }
}
