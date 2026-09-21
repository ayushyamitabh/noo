import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import 'synced_header_scaffold.dart' show formatBytes;

/// Grid content for an image/video: the actual preview fills the whole card
/// as a background, with the name/size legible over a bottom scrim -
/// matching a Google Photos-style grid instead of a small icon badge.
/// Shared by the Files and Offline tabs; they differ only in where the
/// pixels come from ([imageBuilder] - a server preview vs. the local
/// mirror file) and what to show if that fails ([fallbackBuilder]).
class MediaGridTile extends StatelessWidget {
  final NextcloudItem item;

  /// Given the pixel width to decode at, returns the image to paint.
  /// Decoding straight to the painted size (rather than the full 500x500
  /// server preview / full-resolution local file) avoids a real source of
  /// scrolling jank.
  final ImageProvider Function(int cachePixels) imageBuilder;
  final WidgetBuilder fallbackBuilder;

  const MediaGridTile({
    super.key,
    required this.item,
    required this.imageBuilder,
    required this.fallbackBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cachePixels =
            (constraints.maxWidth * MediaQuery.of(context).devicePixelRatio)
                .round();
        return Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: imageBuilder(cachePixels),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (ctx, err, stack) => fallbackBuilder(ctx),
            ),
            if (item.type == NextcloudItemType.video)
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      formatBytes(item.size),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
