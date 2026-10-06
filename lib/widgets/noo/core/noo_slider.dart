import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// A continuous (or [divisions]-stepped) value slider in the design system's
/// colors: accent fill on a `surface3` track, accent thumb. Data-agnostic -
/// the caller owns [value] and formats any readout beside it.
class NooSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final String? semanticLabel;

  const NooSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: colors.accent,
        inactiveTrackColor: colors.surface3,
        thumbColor: colors.accent,
        overlayColor: colors.accent.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        trackShape: const RoundedRectSliderTrackShape(),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        semanticFormatterCallback: semanticLabel == null
            ? null
            : (v) => '$semanticLabel ${v.toStringAsFixed(2)}',
        onChanged: onChanged,
      ),
    );
  }
}
