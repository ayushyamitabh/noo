import 'dart:ui';
import 'package:flutter/material.dart';

/// The frosted-glass pill background shared by all floating chrome in the
/// app (bottom nav bar, media viewer action bar): blurred backdrop, a
/// translucent tonal fill, a faint outline, and a soft drop shadow.
class FrostedGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  /// Blur sigma for the backdrop filter. Defaults to a fixed value; pass an
  /// explicit value (e.g. from user settings) to make it adjustable.
  final double blurSigma;

  /// Opacity (0-1) of the tonal fill behind the blur. Defaults to a fixed
  /// value; pass an explicit value (e.g. from user settings) to make it
  /// adjustable.
  final double opacity;

  const FrostedGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 32,
    this.blurSigma = 28,
    this.opacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(
              alpha: opacity,
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
