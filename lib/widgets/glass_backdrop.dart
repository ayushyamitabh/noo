import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_controller.dart';

/// Loads and caches the "true glass" fragment shader (`shaders/glass.frag`).
///
/// [load] runs once at startup. If it fails, or the engine can't use a shader
/// as a backdrop filter ([ui.ImageFilter.isShaderFilterSupported] is Impeller
/// only), [available] stays false and every [GlassBackdrop] falls back to the
/// plain blur - the setting never breaks rendering.
class GlassShader {
  GlassShader._();

  static ui.FragmentProgram? _program;

  static Future<void> load() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/glass.frag');
    } catch (_) {
      _program = null;
    }
  }

  static bool get isLoaded => _program != null;

  static bool get available =>
      _program != null && ui.ImageFilter.isShaderFilterSupported;

  /// A backdrop filter for a region with corner radius [radius] px. The
  /// engine supplies the region size and the backdrop texture; the rest are
  /// the uniforms declared in `glass.frag` after `uSize`.
  static ui.ImageFilter filter({required double radius, required bool dark}) {
    final shader = _program!.fragmentShader()
      ..setFloat(2, radius) // uRadius
      ..setFloat(3, 14) // uBevel
      ..setFloat(4, 9) // uRefraction
      ..setFloat(5, dark ? 0.32 : 0.5) // uRim
      ..setFloat(6, 1.4); // uFrost
    return ui.ImageFilter.shader(shader);
  }
}

/// Clips [child] to [radius] and renders whatever is behind it as frosted
/// glass, in the style chosen in Settings -> Appearance ([GlassStyle]):
/// a Gaussian blur, or the GPU "true glass" shader (refractive edge,
/// dispersion, specular rim). [child] supplies the tinted fill on top - use
/// [fillColor] for it so the tint matches the style.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;

  /// Blur sigma used in [GlassStyle.blur] (and as the fallback).
  final double sigma;

  const GlassBackdrop({
    super.key,
    required this.child,
    required this.radius,
    required this.sigma,
  });

  /// Whether the true-glass shader is in use for [context].
  static bool usesGlass(BuildContext context) =>
      GlassShader.available &&
      (context.watch<SettingsController?>()?.glassStyle ?? GlassStyle.blur) ==
          GlassStyle.glass;

  /// Opacity of the surface tint on a glass bar. True glass stays mostly
  /// clear so the refraction shows; the user's opacity slider only applies to
  /// the blur style.
  static const double glassTintOpacity = 0.16;

  /// The surface tint for a frosted element: [opacity] (the user's slider) for
  /// blur, a light fixed tint for true glass.
  static Color fillColor(BuildContext context, Color surface, double opacity) =>
      surface.withValues(
        alpha: usesGlass(context) ? glassTintOpacity : opacity,
      );

  @override
  Widget build(BuildContext context) {
    final glass = usesGlass(context);
    final filter = glass
        ? GlassShader.filter(
            radius: radius.topLeft.x,
            dark: Theme.of(context).brightness == Brightness.dark,
          )
        : ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(filter: filter, child: child),
    );
  }
}
