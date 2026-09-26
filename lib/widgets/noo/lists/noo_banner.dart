import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Inline info card with an optional text action, e.g. Trash's retention
/// notice + "Empty trash" (Noo Design System project,
/// `components/lists/Banner.jsx`, mobile variant).
class NooBanner extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionIsDanger;

  const NooBanner({
    super.key,
    this.icon = LucideIcons.info,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.actionIsDanger = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(NooRadii.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: colors.fg2),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle(
              style: NooText.body.copyWith(color: colors.fg2),
              child: child,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: NooText.buttonSm.copyWith(
                  fontSize: 14,
                  color: actionIsDanger ? colors.danger : colors.accentText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
