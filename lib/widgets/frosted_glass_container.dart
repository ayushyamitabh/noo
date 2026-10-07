import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_controller.dart';
import '../theme/design_tokens.dart';

/// Media viewer chrome that shares the navigation frost preference.
/// Turning frosting off produces an opaque themed surface without blur.
class FrostedGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  /// Overrides [borderRadius] for non-uniform corners (e.g. top-only).
  final BorderRadius? radius;

  /// Blur sigma for the backdrop filter. Defaults to the shared frost setting.
  final double? blurSigma;

  /// Opacity (0-1) of the tonal fill behind the blur. Defaults to the shared frost setting.
  final double? opacity;
  final bool? frosted;

  /// The tint under the blur. Defaults to [NooColors.surface] (resolved at
  /// build time, so it always matches the active theme) - pass an explicit
  /// color only to override that, e.g. for a fixed-color panel elsewhere.
  final Color? color;

  const FrostedGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.radius,
    this.blurSigma,
    this.opacity,
    this.frosted,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final shape = radius ?? BorderRadius.circular(borderRadius);
    final tint = color ?? context.nooColors.surface;
    final settings = context.watch<SettingsController?>();
    final enabled = frosted ?? settings?.bottomBarFrosted ?? false;
    final sigma = blurSigma ?? settings?.bottomBarFrostedBlur ?? 20;
    final fill = Container(
      decoration: BoxDecoration(
        color: enabled
            ? tint.withValues(
                alpha: opacity ?? settings?.bottomBarFrostedOpacity ?? 0.72,
              )
            : tint,
        borderRadius: shape,
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: shape,
      child: enabled
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: fill,
            )
          : fill,
    );
  }
}
