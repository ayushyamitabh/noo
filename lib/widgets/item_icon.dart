import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/nextcloud_item.dart';
import '../services/nextcloud_service.dart';
import '../theme/design_tokens.dart';

/// The icon/color/thumbnail treatment for a file or folder, shared by any
/// screen that lists [NextcloudItem]s the same way the Files tab does (see
/// `files_view.dart`, and `share_upload_view.dart`'s destination picker).
/// Matches DESIGN_SYSTEM.md 1.2's file-type tile table (`KIND`) - a pdf is
/// its own kind there (distinct from a generic document), which is why
/// these take the whole [NextcloudItem] rather than just its
/// [NextcloudItemType]: the type alone can't tell a pdf from any other
/// document.
bool _isPdf(NextcloudItem item) => item.name.toLowerCase().endsWith('.pdf');

IconData getItemIcon(NextcloudItem item) {
  switch (item.type) {
    case NextcloudItemType.folder:
      return LucideIcons.folder;
    case NextcloudItemType.image:
      return LucideIcons.image;
    case NextcloudItemType.video:
      return LucideIcons.film;
    case NextcloudItemType.document:
      return LucideIcons.fileText;
    case NextcloudItemType.archive:
      return LucideIcons.fileArchive;
    case NextcloudItemType.audio:
    case NextcloudItemType.file:
      return LucideIcons.file;
  }
}

Color getIconColor(BuildContext context, NextcloudItem item) {
  final colors = context.nooColors;
  switch (item.type) {
    case NextcloudItemType.folder:
      return colors.accentText;
    case NextcloudItemType.document:
      return _isPdf(item) ? colors.danger : colors.info;
    case NextcloudItemType.image:
      return colors.info;
    case NextcloudItemType.video:
      return colors.warning;
    case NextcloudItemType.archive:
    case NextcloudItemType.audio:
    case NextcloudItemType.file:
      return colors.fg2;
  }
}

/// The tile's background (the soft-tinted square/circle behind the icon) -
/// the other half of the [getIconColor] pair every call site pairs it with.
Color getIconBackground(BuildContext context, NextcloudItem item) {
  final colors = context.nooColors;
  switch (item.type) {
    case NextcloudItemType.folder:
      return colors.accentSoft;
    case NextcloudItemType.document:
      return _isPdf(item) ? colors.dangerSoft : colors.infoSoft;
    case NextcloudItemType.image:
      return colors.infoSoft;
    case NextcloudItemType.video:
      return colors.warningSoft;
    case NextcloudItemType.archive:
    case NextcloudItemType.audio:
    case NextcloudItemType.file:
      return colors.surface3;
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

  /// The on-device copy of [item] (the Offline tab's synced mirror) - when
  /// set, images render from this file instead of a server preview, so
  /// thumbnails work with no connection.
  final File? localFile;

  const ItemThumbnail({
    super.key,
    required this.item,
    required this.service,
    this.localFile,
    required this.size,
    required this.borderRadius,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = getIconColor(context, item);
    final isMedia =
        item.type == NextcloudItemType.image ||
        item.type == NextcloudItemType.video;
    final useLocal = item.type == NextcloudItemType.image && localFile != null;
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
        color: getIconBackground(context, item),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: useLocal || (isMedia && item.previewUrl != null)
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: ResizeImage(
                    useLocal
                        ? FileImage(localFile!) as ImageProvider
                        : NetworkImage(
                            item.previewUrl!,
                            headers: service?.authHeaders,
                          ),
                    width: cachePixels,
                    height: cachePixels,
                  ),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: Icon(
                        getItemIcon(item),
                        color: iconColor,
                        size: iconSize,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => Center(
                    child: Icon(
                      getItemIcon(item),
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
                getItemIcon(item),
                color: iconColor,
                size: iconSize,
              ),
            ),
    );
  }
}
