import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

class NooSegmentOption<T> {
  final T value;
  final String? label;
  final IconData? icon;

  const NooSegmentOption({required this.value, this.label, this.icon});
}

enum NooSegmentedSize { md, sm, xs }

const _heights = {
  NooSegmentedSize.md: 34.0,
  NooSegmentedSize.sm: 30.0,
  NooSegmentedSize.xs: 28.0,
};

/// Pill track with an accent-soft active segment - List/Grid, Shares scope,
/// Theme (Noo Design System project, `components/core/SegmentedControl.jsx`).
/// Replaces the older `SegmentedIconGroup`/`ToggleIconButton` pair; migrate
/// call sites to this as they're touched rather than adding new ones there.
class NooSegmentedControl<T> extends StatelessWidget {
  final List<NooSegmentOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Use surface on bg, surface-2 on surface.
  final bool onSurface;
  final NooSegmentedSize size;
  final bool fill;
  final bool iconOnly;

  /// Every segment always shows its icon, but only the *selected* one also
  /// shows its label - a middle ground between `iconOnly` (no segment is
  /// ever distinguishable without a label) and the default (every segment's
  /// label always visible, crowding a 3+-option control). Used for Files'/
  /// Photos' type filter (All/Files/Folders, All/Photos/Videos) so both use
  /// the same List/Grid-toggle-style pill instead of Files' old checkmark
  /// list and Photos' own always-labelled control.
  final bool labelOnlySelected;

  const NooSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    this.onChanged,
    this.onSurface = false,
    this.size = NooSegmentedSize.md,
    this.fill = false,
    this.iconOnly = false,
    this.labelOnlySelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final h = iconOnly ? 28.0 : (_heights[size] ?? 34.0);
    final segments = options.map((o) {
      final on = o.value == value;
      final showLabel = labelOnlySelected ? on : !iconOnly;
      final child = Container(
        height: h,
        width: iconOnly ? 36 : null,
        padding: iconOnly || fill
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? colors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(NooRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.icon != null)
              Icon(
                o.icon,
                size: iconOnly ? (size == NooSegmentedSize.md ? 18 : 16) : 14,
                color: on ? colors.accentText : colors.fg2,
              ),
            if (o.icon != null && showLabel && o.label != null)
              const SizedBox(width: 6),
            if (showLabel && o.label != null)
              Text(
                o.label!,
                style: NooText.body.copyWith(
                  fontSize: size == NooSegmentedSize.md ? 14 : 13,
                  height: 1,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? colors.accentText : colors.fg2,
                ),
              ),
          ],
        ),
      );
      final tappable = GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(o.value),
        child: child,
      );
      return fill ? Expanded(child: tappable) : tappable;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onSurface ? colors.surface2 : colors.surface,
        borderRadius: BorderRadius.circular(NooRadii.pill),
      ),
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: segments,
      ),
    );
  }
}
