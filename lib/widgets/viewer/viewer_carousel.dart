import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/nextcloud_item.dart';
import '../../services/thumbnail_cache.dart';
import '../noo/media/noo_photo_tile.dart';

/// The Photos-app style thumbnail strip under the media viewer: tiny
/// thumbnails of the neighbouring items with the current one enlarged in the
/// middle. It follows [controller]'s page position continuously (so it
/// slides in step with the swipe), jumps on tap, and scrubs the viewer when
/// dragged.
class ViewerCarousel extends StatelessWidget {
  final PageController controller;
  final List<NextcloudItem> items;
  final Map<String, String>? headers;

  /// False while browsing offline, where thumbnails can't be fetched and the
  /// strip shows tinted placeholders instead.
  final bool network;

  const ViewerCarousel({
    super.key,
    required this.controller,
    required this.items,
    this.headers,
    this.network = true,
  });

  static const double height = 56;
  static const double _narrow = 22;
  static const double _wide = 38;
  static const double _narrowH = 34;
  static const double _wideH = 46;
  static const double _gap = 2;
  static const double _currentPad = 8;
  // How many items to lay out either side of the current one - more than fit
  // on any phone/tablet width, few enough to stay cheap.
  static const int _window = 14;

  double get _page {
    if (controller.hasClients && controller.position.haveDimensions) {
      return controller.page ?? controller.initialPage.toDouble();
    }
    return controller.initialPage.toDouble();
  }

  /// 1 at the current page, falling to 0 a full page away.
  static double _focus(int index, double page) =>
      (1 - (index - page).abs()).clamp(0.0, 1.0);

  static double _boxWidth(double t) =>
      _narrow + (_wide - _narrow) * t + _gap + _currentPad * t;

  void _scrub(double dx) {
    if (!controller.hasClients) return;
    final pos = controller.position;
    final pitch = _narrow + _gap;
    final delta = -dx / pitch * pos.viewportDimension;
    pos.jumpTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
    );
  }

  void _settle() {
    if (!controller.hasClients) return;
    controller.animateToPage(
      _page.round().clamp(0, items.length - 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _scrub(d.delta.dx),
        onHorizontalDragEnd: (_) => _settle(),
        onHorizontalDragCancel: _settle,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) =>
                  _strip(context, constraints.maxWidth),
            ),
          ),
        ),
      ),
    );
  }

  Widget _strip(BuildContext context, double width) {
    final page = _page.clamp(0.0, (items.length - 1).toDouble());
    final base = page.floor();
    final frac = page - base;
    final from = math.max(0, base - _window);
    final to = math.min(items.length - 1, base + _window + 1);

    // Box centres relative to the centre of item [base]'s box, laid out with
    // each box's width derived from how focused it is right now.
    final centres = <int, double>{base: 0};
    for (var i = base - 1; i >= from; i--) {
      centres[i] =
          centres[i + 1]! -
          _boxWidth(_focus(i + 1, page)) / 2 -
          _boxWidth(_focus(i, page)) / 2;
    }
    for (var i = base + 1; i <= to; i++) {
      centres[i] =
          centres[i - 1]! +
          _boxWidth(_focus(i - 1, page)) / 2 +
          _boxWidth(_focus(i, page)) / 2;
    }
    // Slide so the (fractional) current page sits at the strip's centre.
    final next = centres[base + 1] ?? 0;
    final origin =
        width / 2 - (centres[base]! + (next - centres[base]!) * frac);

    return Stack(
      children: [
        for (var i = from; i <= to; i++)
          () {
            final t = _focus(i, page);
            final w = _narrow + (_wide - _narrow) * t;
            final h = _narrowH + (_wideH - _narrowH) * t;
            return Positioned(
              left: origin + centres[i]! - w / 2,
              top: (height - h) / 2,
              width: w,
              height: h,
              child: GestureDetector(
                onTap: () => controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                ),
                child: _Thumb(
                  item: items[i],
                  headers: headers,
                  network: network,
                ),
              ),
            );
          }(),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final NextcloudItem item;
  final Map<String, String>? headers;
  final bool network;

  const _Thumb({
    required this.item,
    required this.headers,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: NooPhotoTile.paletteColor(item.id.hashCode),
    );
    final url = item.previewUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: network && url != null
          ? Image(
              // Disk-cached (shares its entry with the Photos grid's tile),
              // so thumbnails evicted from memory while swiping the strip
              // reload from disk instead of the server.
              image: ResizeImage(
                CachedPreviewImage(
                  url: url,
                  version: item.lastModified,
                  headers: headers,
                ),
                // Decoded small: the strip only ever shows ~40px thumbnails.
                width: 120,
              ),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}
