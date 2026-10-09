import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;

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

  /// The vertical fold (or hinge) splitting an unfolded foldable's window
  /// into left and right screens, or null. A horizontal one (e.g. the
  /// device rotated) divides top from bottom and doesn't count.
  ///
  /// Android reports folds itself; iOS adds a fold only while partially open.
  static DisplayFeature? _verticalFold(MediaQueryData media) {
    for (final feature in media.displayFeatures) {
      final bounds = feature.bounds;
      if ((feature.type == DisplayFeatureType.fold ||
              feature.type == DisplayFeatureType.hinge) &&
          feature.state == DisplayFeatureState.postureHalfOpened &&
          bounds.height > bounds.width &&
          bounds.left > media.padding.left &&
          bounds.left < media.size.width) {
        return feature;
      }
    }
    return null;
  }

  /// Width of the tablet layout's leading column (the [NooSidebar]) on an
  /// unfolded foldable, so the sidebar and content split at the fold
  /// instead of the content pane running across the crease - 50/50 on a
  /// book-style fold; null anywhere else, where the sidebar keeps its usual
  /// width.
  ///
  /// Call with a context above any [SafeArea]: it subtracts the window's own
  /// leading inset, which the layout's [SafeArea] pads the row by.
  static double? foldSplitWidth(BuildContext context) {
    if (!isDesktop(context)) {
      return null;
    }
    final media = MediaQuery.of(context);
    final fold = _verticalFold(media);
    return fold == null ? null : fold.bounds.left - media.padding.left;
  }

  /// `anchorPoint` for every dialog and sheet: on an unfolded foldable it
  /// opens them on the right-hand screen. Flutter keeps a popup to one side
  /// of a fold, picking the side nearest its anchor - top-left by default,
  /// so without this they'd all land on the left half (next to the sidebar,
  /// away from the content). Null elsewhere, which keeps Flutter's default.
  static Offset? popupAnchor(BuildContext context) {
    final media = MediaQuery.of(context);
    return _verticalFold(media) == null ? null : Offset(media.size.width, 0);
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
