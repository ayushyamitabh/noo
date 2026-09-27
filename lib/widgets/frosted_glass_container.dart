import 'dart:ui';
import 'package:flutter/material.dart';

/// The blurred/translucent chrome for the media viewer's overlay bars
/// (`file_viewer_screen.dart`'s top bar, `MediaActionBar`, the video
/// transport row) - the one deliberate exception to the design system's
/// flat, no-shadow product UI (DESIGN_SYSTEM.md 1.4), since this chrome
/// floats over photo/video content rather than over the app's own
/// surfaces. No shadow, no outline, no `ColorScheme` tint: a fixed dark
/// translucent fill (`color`) that reads correctly over any media,
/// regardless of the app's light/dark theme - matching the canvas at
/// https://claude.ai/artifact/3AGPqqMdkLSC2ypCh2CQs4.
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

  /// The tint under the blur. Defaults to the design's fixed dark tone
  /// (`#141311`, the spec's `fg-1` dark value) - deliberately not a
  /// `ColorScheme`/`NooColors` lookup, since this chrome always sits over a
  /// black media stage, not over a themed surface.
  final Color color;

  const FrostedGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.blurSigma = 20,
    this.opacity = 0.55,
    this.color = const Color(0xFF141311),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        ),
      ),
    );
  }
}
