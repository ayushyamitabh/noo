import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Reorderable tab row with a grip and pin toggle - max 5 pinned (Noo
/// Design System project, `components/lists/TabOrderRow.jsx`, mobile
/// variant).
class NooTabOrderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool pinned;
  final VoidCallback? onTogglePin;

  const NooTabOrderRow({
    super.key,
    required this.icon,
    required this.label,
    this.pinned = false,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: colors.surface,
      child: Row(
        children: [
          Icon(LucideIcons.gripVertical, size: 18, color: colors.fg3),
          const SizedBox(width: 12),
          Icon(icon, size: 20, color: colors.fg2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: NooText.bodyL.copyWith(height: 1, color: colors.fg1),
            ),
          ),
          GestureDetector(
            onTap: onTogglePin,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pinned ? colors.accentSoft : colors.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(
                pinned ? LucideIcons.pin : LucideIcons.pinOff,
                size: 16,
                color: pinned ? colors.accentText : colors.fg3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
