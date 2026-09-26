import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// 6px pill meter for storage, cache and offline limits (Noo Design System
/// project, `components/core/ProgressBar.jsx`).
class NooProgressBar extends StatelessWidget {
  /// 0-1
  final double value;

  const NooProgressBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NooRadii.pill),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: colors.surface3,
          valueColor: AlwaysStoppedAnimation(colors.accent),
        ),
      ),
    );
  }
}
