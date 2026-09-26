import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// A single icon button that fills with a solid circle when active —
/// the building block for Drive-style toggle controls. Thin wrapper around
/// the native Material 3 toggle `IconButton` (its `isSelected` constructor
/// param, not a hand-rolled Material+InkWell) so every call site here gets
/// the built-in selected/unselected treatment for free.
class ToggleIconButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String? tooltip;

  const ToggleIconButton({
    super.key,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return IconButton(
      isSelected: isSelected,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(CircleBorder()),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentText
              : colors.fg2,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentSoft
              : Colors.transparent,
        ),
      ),
    );
  }
}

/// A pill-shaped row of [ToggleIconButton]s sharing one background, matching
/// the list/grid view switch seen in Google Drive's toolbar.
class SegmentedIconGroup extends StatelessWidget {
  final List<Widget> children;

  const SegmentedIconGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NooRadii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
