import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';

/// Icon-only action button for the media viewer's floating chrome (top bar,
/// bottom action bar, video transport controls) - a fixed 22px icon in a
/// round hit box. Colored from [NooColors.fg1] by default, matching
/// [FrostedGlassContainer]'s own theme-following panel underneath it (both
/// used to be fixed white-on-black regardless of theme - see their git
/// history). Kept as one small widget so every floating control in this
/// screen looks the same instead of drifting apart across the three call
/// sites that need one.
class ViewerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Overrides the default [NooColors.fg1] (e.g. `danger` for delete,
  /// `accent-text` for a favorited state). Ignored while [onTap] is null -
  /// a disabled button always dims regardless of its normal color.
  final Color? color;

  const ViewerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg1 = context.nooColors.fg1;
    final fg = onTap == null ? fg1.withValues(alpha: 0.4) : (color ?? fg1);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Icon(icon, color: fg, size: 22),
        ),
      ),
    );
  }
}
