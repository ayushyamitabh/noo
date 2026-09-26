import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// Radius-20 surface card of rows with 1px line dividers and an optional
/// label above it (Noo Design System project,
/// `components/lists/GroupedList.jsx`, mobile variant - desktop's bordered/
/// titled card isn't built yet). Each child (`SettingsRow`, `FileRow`, ...)
/// paints its own `surface` background; this only supplies the 1px `line`
/// gaps between them and the rounded clip. Stack groups 18-20px apart.
class NooGroupedList extends StatelessWidget {
  final String? label;
  /// Right-aligned secondary text next to [label].
  final String? aside;
  final List<Widget> children;
  final Widget? footer;

  const NooGroupedList({
    super.key,
    this.label,
    this.aside,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label!, style: NooText.label.copyWith(color: colors.fg2)),
                if (aside != null)
                  Text(
                    aside!,
                    style: NooText.body.copyWith(
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: colors.fg3,
                    ),
                  ),
              ],
            ),
          ),
        if (label != null) const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(NooRadii.card),
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.line),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DefaultTextStyle(
              style: NooText.meta.copyWith(color: colors.fg3),
              child: footer!,
            ),
          ),
        ],
      ],
    );
  }
}
