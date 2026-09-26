import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import 'noo_file_kind.dart';

/// The four tile sizes from `DESIGN_SYSTEM.md` 1.2 - pick by context; the
/// icon is always half the tile.
enum NooFileTileSize {
  /// 40px / r12 - mobile file rows.
  row(40, 12),

  /// 30px / r9 - desktop table rows.
  desktop(30, 9),

  /// 44px / r12 - share sheet/dialog header.
  header(44, 12),

  /// 32px / r10 - activity items.
  activity(32, 10);

  final double extent;
  final double radius;
  const NooFileTileSize(this.extent, this.radius);

  double get iconSize => extent / 2;
}

/// Rounded-square file-type tile: the kind's soft tint with its Lucide icon
/// in the strong tint (`DESIGN_SYSTEM.md` 1.2). Pass [thumbnail] (e.g. an
/// `Image`) to show real content instead - it's clipped to the same shape
/// and cover-fit over the kind's tint, which shows while it loads.
class NooFileTile extends StatelessWidget {
  final NooFileKind kind;
  final NooFileTileSize size;
  final Widget? thumbnail;

  const NooFileTile({
    super.key,
    required this.kind,
    this.size = NooFileTileSize.row,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final radius = BorderRadius.circular(size.radius);
    return SizedBox.square(
      dimension: size.extent,
      child: thumbnail != null
          ? ClipRRect(
              borderRadius: radius,
              child: ColoredBox(
                color: kind.background(colors),
                child: SizedBox.expand(
                  child: FittedBox(fit: BoxFit.cover, child: thumbnail),
                ),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: kind.background(colors),
                borderRadius: radius,
              ),
              child: Center(
                child: Icon(
                  kind.icon,
                  size: size.iconSize,
                  color: kind.foreground(colors),
                ),
              ),
            ),
    );
  }
}
