import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Android-only extended Upload pill, bottom-right of Files and Photos (Noo
/// Design System project, `components/core/FAB.jsx`). 56px tall, accent
/// fill - iOS uses a `plus` in the nav bar instead (not yet built).
class NooFab extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const NooFab({super.key, this.label = 'Upload', this.icon = LucideIcons.plus, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(NooRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NooRadii.pill),
        child: Container(
          height: 56,
          padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
          // No `alignment:` here - Container without an explicit width
          // wraps its child in an Align when alignment is set, and Align
          // EXPANDS to fill all available bounded space (not just the
          // child's size) unless the incoming constraints are unbounded.
          // The Scaffold floating-action-button slot gives bounded
          // constraints, so this shipped as a full-width bar instead of a
          // compact pill. Row+mainAxisSize.min already sizes correctly on
          // its own; the fix is just not adding alignment back here.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: Colors.white),
              const SizedBox(width: 10),
              Text(label, style: NooText.button.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
