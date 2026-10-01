import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Radius-20 surface card of rows with 1px line dividers and an optional
/// label above it (Noo Design System project,
/// `components/lists/GroupedList.jsx`, mobile variant - desktop's bordered/
/// titled card isn't built yet). Each child (`SettingsRow`, `FileRow`, ...)
/// paints its own `surface` background; this only supplies the 1px `line`
/// gaps between them and the rounded clip. Stack groups 18-20px apart.
///
/// [collapsible] makes [label] (required alongside it) a tap target that
/// shows/hides the card and [footer] below it, with a trailing chevron -
/// used by `SettingsSection` for Settings' mobile sections so a long
/// Settings screen can be collapsed section by section instead of needing a
/// separate jump rail. Every other call site leaves this false and renders
/// exactly as before, always expanded and non-interactive.
class NooGroupedList extends StatefulWidget {
  final String? label;

  /// Right-aligned secondary text next to [label].
  final String? aside;
  final List<Widget> children;
  final Widget? footer;

  /// Shown between [label] and the card (e.g. a `NooInfoNote`).
  final Widget? notice;
  final bool collapsible;
  final bool initiallyExpanded;

  const NooGroupedList({
    super.key,
    this.label,
    this.aside,
    required this.children,
    this.footer,
    this.notice,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  State<NooGroupedList> createState() => _NooGroupedListState();
}

class _NooGroupedListState extends State<NooGroupedList> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final expanded = !widget.collapsible || _expanded;
    final label = widget.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildLabelRow(label, colors, expanded),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.notice != null) ...[
          widget.notice!,
          const SizedBox(height: NooSpace.md),
        ],
        AnimatedCrossFade(
          duration: NooMotion.fast,
          sizeCurve: NooMotion.ease,
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(NooRadii.card),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: colors.line),
                  child: Column(
                    children: [
                      for (var i = 0; i < widget.children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 1),
                        widget.children[i],
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DefaultTextStyle(
                    style: NooText.meta.copyWith(color: colors.fg3),
                    child: widget.footer!,
                  ),
                ),
              ],
            ],
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildLabelRow(String label, NooColors colors, bool expanded) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: NooText.label.copyWith(color: colors.fg2)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.aside != null)
              Padding(
                padding: EdgeInsets.only(right: widget.collapsible ? 8 : 0),
                child: Text(
                  widget.aside!,
                  style: NooText.body.copyWith(
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: colors.fg3,
                  ),
                ),
              ),
            if (widget.collapsible)
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: NooMotion.fast,
                curve: NooMotion.ease,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: colors.fg3,
                ),
              ),
          ],
        ),
      ],
    );
    if (!widget.collapsible) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: row,
    );
  }
}
