import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import '../services/nextcloud_service.dart';

/// The icon/color/thumbnail treatment for a file or folder, shared by any
/// screen that lists [NextcloudItem]s the same way the Files tab does (see
/// `files_view.dart`, and `share_upload_view.dart`'s destination picker).

IconData getItemIcon(NextcloudItemType type) {
  switch (type) {
    case NextcloudItemType.folder:
      return Icons.folder_rounded;
    case NextcloudItemType.image:
      return Icons.image_rounded;
    case NextcloudItemType.video:
      return Icons.movie_rounded;
    case NextcloudItemType.audio:
      return Icons.audiotrack_rounded;
    case NextcloudItemType.document:
      return Icons.description_rounded;
    case NextcloudItemType.archive:
      return Icons.folder_zip_rounded;
    case NextcloudItemType.file:
      return Icons.insert_drive_file_rounded;
  }
}

Color getIconColor(BuildContext context, NextcloudItemType type) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (type) {
    case NextcloudItemType.folder:
      return colorScheme.primary;
    case NextcloudItemType.image:
      return Colors.amber.shade700;
    case NextcloudItemType.video:
      return Colors.deepOrange.shade600;
    case NextcloudItemType.audio:
      return Colors.purple.shade600;
    case NextcloudItemType.document:
      return Colors.blue.shade700;
    case NextcloudItemType.archive:
      return Colors.teal.shade700;
    case NextcloudItemType.file:
      return colorScheme.outline;
  }
}

/// A file/folder's icon badge — for images and videos this shows an actual
/// thumbnail (falling back to the plain icon on error or if there's no
/// preview URL yet), matching the real-content treatment already used in
/// the Photos tab.
class ItemThumbnail extends StatelessWidget {
  final NextcloudItem item;
  final NextcloudService? service;
  final double size;
  final double borderRadius;
  final double iconSize;

  const ItemThumbnail({
    super.key,
    required this.item,
    required this.service,
    required this.size,
    required this.borderRadius,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = getIconColor(context, item.type);
    final isMedia =
        item.type == NextcloudItemType.image ||
        item.type == NextcloudItemType.video;
    // Decode straight to the size this thumbnail is actually painted at —
    // the server hands back a 500x500 preview regardless, and decoding that
    // in full for a ~40dp tile (times however many are on screen while
    // scrolling) is a real source of jank.
    final cachePixels = (size * MediaQuery.of(context).devicePixelRatio)
        .round();

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: isMedia && item.previewUrl != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  item.previewUrl!,
                  headers: service?.authHeaders,
                  fit: BoxFit.cover,
                  cacheWidth: cachePixels,
                  cacheHeight: cachePixels,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: Icon(
                        getItemIcon(item.type),
                        color: iconColor,
                        size: iconSize,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => Center(
                    child: Icon(
                      getItemIcon(item.type),
                      color: iconColor,
                      size: iconSize,
                    ),
                  ),
                ),
                if (item.type == NextcloudItemType.video)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
              ],
            )
          : Center(
              child: Icon(
                getItemIcon(item.type),
                color: iconColor,
                size: iconSize,
              ),
            ),
    );
  }
}
