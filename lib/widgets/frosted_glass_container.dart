import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// The blurred/translucent chrome for the media viewer's overlay bars
/// (`file_viewer_screen.dart`'s top bar, `MediaActionBar`, the video
/// transport row) - the one deliberate exception to the design system's
/// flat, no-shadow product UI (DESIGN_SYSTEM.md 1.4), since this chrome
/// floats over photo/video content rather than over the app's own
/// surfaces. No shadow, no outline: [color] defaults to the app's own
/// `surface` token (so this panel reads as light or dark to match the
/// active theme, like the rest of the media viewer, instead of a fixed
/// dark tone regardless of theme) at a higher-than-usual [opacity], since
/// a light tint needs denser coverage than a near-black one did to stay
/// legible over arbitrary photo/video brightness underneath.
class FrostedGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  /// Overrides [borderRadius] for non-uniform corners (e.g. top-only).
  final BorderRadius? radius;

  /// Blur sigma for the backdrop filter. Defaults to a fixed value; pass an
  /// explicit value (e.g. from user settings) to make it adjustable.
  final double blurSigma;

  /// Opacity (0-1) of the tonal fill behind the blur. Defaults to a fixed
  /// value; pass an explicit value (e.g. from user settings) to make it
  /// adjustable.
  final double opacity;

  /// The tint under the blur. Defaults to [NooColors.surface] (resolved at
  /// build time, so it always matches the active theme) - pass an explicit
  /// color only to override that, e.g. for a fixed-color panel elsewhere.
  final Color? color;

  const FrostedGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.radius,
    this.blurSigma = 20,
    this.opacity = 0.8,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final shape = radius ?? BorderRadius.circular(borderRadius);
    final tint = color ?? context.nooColors.surface;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: opacity),
            borderRadius: shape,
          ),
          child: child,
        ),
      ),
    );
  }
}
