import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';

/// Icon-only action button for the media viewer's floating chrome (top bar,
/// bottom action bar, video transport controls) - a fixed 22px icon in a
/// round hit box, colored from [NooColors] rather than Material's
/// [ColorScheme]. Kept as one small widget (matching the pre-rework
/// `_ActionIconButton` it replaces - see `styling.md`) so every floating
/// control in this screen looks the same instead of drifting apart across
/// the three call sites that need one.
class ViewerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Overrides the default `fg-1` (e.g. `danger` for delete). Ignored while
  /// [onTap] is null - a disabled button always dims to the same faded fg-1
  /// regardless of its normal color.
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
    final colors = context.nooColors;
    final fg = onTap == null
        ? colors.fg1.withValues(alpha: 0.4)
        : (color ?? colors.fg1);

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
