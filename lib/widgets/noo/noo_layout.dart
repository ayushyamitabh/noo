import 'package:flutter/material.dart';
import 'nav/noo_nav_style.dart';
import '../../theme/design_tokens.dart';

/// The one place screens decide mobile vs desktop layout and iOS vs Android
/// chrome (DESIGN_SYSTEM.md 3), so every screen switches at the same point.
class NooLayout {
  const NooLayout._();

  /// Shortest window side that counts as a tablet-class window (the usual
  /// 600dp rule). A phone in landscape is wide but short, so it stays on the
  /// mobile layout.
  static const double tabletShortestSide = 600;

  static bool isDesktop(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= tabletShortestSide;
  }

  /// A quieter pane tone keeps cards distinct from their container.
  static Color contentBackground(BuildContext context) =>
      isDesktop(context) ? context.nooColors.surface2 : context.nooColors.bg;

  static NooNavStyle navStyle(BuildContext context) =>
      NooNavStyle.fromPlatform(Theme.of(context).platform);

  /// True where the spec calls for the iOS variant of a content detail
  /// (`ellipsis` rather than `ellipsis-vertical` overflow, etc.).
  static bool iosStyle(BuildContext context) =>
      navStyle(context) == NooNavStyle.ios;

  /// Horizontal content gutter: 12 on mobile (cards), 24 on desktop.
  static double gutter(BuildContext context) => isDesktop(context) ? 24 : 12;

  /// File cards use the available pane width and a content-sized height.
  static SliverGridDelegate fileGridDelegate(BuildContext context) {
    final tablet = isDesktop(context);
    final scale = MediaQuery.textScalerOf(context);
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 220,
      mainAxisExtent:
          (tablet ? 118 : 104) +
          26 +
          scale.scale(14) * 1.2 +
          scale.scale(12) * 1.3,
      crossAxisSpacing: tablet ? 16 : 10,
      mainAxisSpacing: tablet ? 16 : 10,
    );
  }

  /// Grid column count for [minTile]-wide tiles, never fewer than [phone].
  static int gridColumns(
    BuildContext context, {
    required int phone,
    required double minTile,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / minTile).floor().clamp(phone, 12);
  }
}
