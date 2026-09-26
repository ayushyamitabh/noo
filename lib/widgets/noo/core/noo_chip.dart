import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

enum NooChipTrailing { none, menu, remove }

/// A pill filter/sort chip; selected = accent-soft (Noo Design System
/// project, `components/core/Chip.jsx`).
class NooChip extends StatelessWidget {
  final Widget child;
  final IconData? icon;
  final bool selected;
  final NooChipTrailing trailing;
  /// filled = mobile (surface fill, 34px); outline = desktop (1px line, 32px)
  final bool outline;
  final VoidCallback? onTap;

  const NooChip({
    super.key,
    required this.child,
    this.icon,
    this.selected = false,
    this.trailing = NooChipTrailing.none,
    this.outline = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final height = outline ? 32.0 : 34.0;
    final hasSideContent = icon != null || trailing != NooChipTrailing.none;

    Color bg;
    Color fg;
    FontWeight weight;
    Border? border;
    if (selected) {
      bg = colors.accentSoft;
      fg = colors.accentText;
      weight = FontWeight.w600;
    } else if (outline) {
      bg = Colors.transparent;
      fg = colors.fg1;
      weight = FontWeight.w500;
      border = Border.all(color: colors.line, width: 1);
    } else {
      bg = colors.surface;
      fg = colors.fg1;
      weight = FontWeight.w500;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: hasSideContent ? 12 : 14),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(NooRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: outline ? 14 : 16, color: fg),
              const SizedBox(width: 6),
            ],
            DefaultTextStyle(
              style: NooText.body.copyWith(
                fontSize: outline ? 13 : 14,
                height: 1,
                fontWeight: weight,
                color: fg,
              ),
              child: child,
            ),
            if (trailing == NooChipTrailing.menu) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronDown, size: 14, color: fg),
            ],
            if (trailing == NooChipTrailing.remove) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.x, size: 14, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
