import 'package:flutter/material.dart';

/// Icon-only action button for the media viewer's floating chrome (top bar,
/// bottom action bar, video transport controls) - a fixed 22px icon in a
/// round hit box. Colored white by default, not from [NooColors]/
/// [ColorScheme]: this chrome always sits on the dark translucent panel
/// over a black media stage (see `FrostedGlassContainer`'s doc comment),
/// regardless of the app's light/dark theme, so a theme-derived color would
/// go near-invisible in light mode. Kept as one small widget so every
/// floating control in this screen looks the same instead of drifting
/// apart across the three call sites that need one.
class ViewerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Overrides the default white (e.g. `danger` for delete, `accent-text`
  /// for a favorited state). Ignored while [onTap] is null - a disabled
  /// button always dims to faded white regardless of its normal color.
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
    final fg = onTap == null
        ? Colors.white.withValues(alpha: 0.4)
        : (color ?? Colors.white);

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
