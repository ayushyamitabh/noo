import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/design_tokens.dart';

/// Initials circle on a secondary-palette colour; the current user uses
/// accent-soft (Noo Design System project, `components/core/Avatar.jsx`).
/// Sizes: 30-32 in bars, 36 in lists, 48 in the drawer, 52-56 on the
/// account card.
class NooAvatar extends StatelessWidget {
  final String? initials;
  final double size;
  /// One of [NooColors.avatarPalette]; ignored when [current] or [icon] is set.
  final Color? color;
  final bool current;
  /// Show an icon instead of initials (e.g. a group share).
  final IconData? icon;

  const NooAvatar({
    super.key,
    this.initials,
    this.size = 36,
    this.color,
    this.current = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final Color bg;
    final Color fg;
    if (current) {
      bg = colors.accentSoft;
      fg = colors.accentText;
    } else if (icon != null) {
      bg = colors.surface2;
      fg = colors.fg2;
    } else {
      bg = color ?? NooColors.avatarPalette.first;
      fg = NooColors.avatarTextColor;
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, size: (size * 0.5).round().toDouble(), color: fg)
          : Text(
              initials ?? '',
              style: GoogleFonts.instrumentSans(
                fontWeight: FontWeight.w600,
                fontSize: (size * 0.36).round().toDouble(),
                height: 1,
                color: fg,
              ),
            ),
    );
  }
}
