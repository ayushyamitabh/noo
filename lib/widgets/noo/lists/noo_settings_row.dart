import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// 52/60px settings row: icon, label, subtitle, trailing control (Noo
/// Design System project, `components/lists/SettingsRow.jsx`, mobile
/// variant). Goes inside a [NooGroupedList] - it paints its own `surface`
/// background, the list only supplies the line gaps.
class NooSettingsRow extends StatelessWidget {
  final IconData? icon;
  final Widget label;
  final Widget? subtitle;
  /// Renders as `value` text + a trailing chevron - mutually exclusive with
  /// [trailing] (a `NooToggle`, button, badge, etc.).
  final String? value;
  final Widget? trailing;
  final bool danger;
  /// Accent-text action row, e.g. "Add account".
  final bool accent;
  final VoidCallback? onTap;

  const NooSettingsRow({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.danger = false,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final color = danger ? colors.danger : (accent ? colors.accentText : colors.fg1);
    final minHeight = subtitle != null ? 60.0 : 52.0;

    Widget? trail = trailing;
    if (trail == null && value != null) {
      trail = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value!,
            style: NooText.body.copyWith(fontSize: 15, height: 1, color: colors.fg3),
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 18, color: colors.fg3),
        ],
      );
    }

    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: NooSpace.md,
              vertical: subtitle != null ? 11 : 0,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: danger || accent ? color : colors.fg2),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DefaultTextStyle(
                        style: NooText.bodyL.copyWith(
                          height: 1.1,
                          fontWeight: danger || accent
                              ? (accent ? FontWeight.w600 : FontWeight.w500)
                              : FontWeight.w400,
                          color: color,
                        ),
                        child: label,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        DefaultTextStyle(
                          style: NooText.meta.copyWith(color: colors.fg3),
                          child: subtitle!,
                        ),
                      ],
                    ],
                  ),
                ),
                ?trail,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
