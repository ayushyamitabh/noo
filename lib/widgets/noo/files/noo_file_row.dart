import 'package:flutter/material.dart';
import '../core/noo_pointer_selection.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';
import 'noo_file_kind.dart';
import 'noo_file_tile.dart';
import 'noo_status_icon.dart';

/// Mobile 64px file row (`DESIGN_SYSTEM.md` 2, "File row"): 40px tile, name
/// (16/500, one line) over a meta line (`[status][shared] size · modified`,
/// 13 fg-3), an optional favorite star / [trailing] widget, then the
/// overflow button. Paints its own `surface` background (accent-soft when
/// [selected]), so it can sit directly in a list or inside a
/// `NooSwipeAction`.
class NooFileRow extends StatelessWidget {
  final NooFileKind kind;
  final String name;

  /// Formatted size, e.g. "2.4 MB". Joined to [modified] with " · ".
  final String? size;

  /// Formatted modified time, e.g. "Yesterday".
  final String? modified;

  /// Replaces the "size · modified" text entirely - use it for the error
  /// hint ("Couldn't sync · Tap to retry") or screen-specific meta (Trash's
  /// "Deleted 3 days ago").
  final String? meta;

  /// Leading meta-line icons, drawn in order (spec order is sync status,
  /// then shared). When this contains [NooSyncStatus.error] the meta text
  /// turns `danger`.
  final List<NooSyncStatus> statuses;

  /// Shows the accent-text star before the overflow button.
  final bool favorite;

  /// Screen-specific trailing icon (e.g. `rotate-ccw` in Trash), placed
  /// after the favorite star and before the overflow button.
  final Widget? trailing;

  /// `ellipsis` on iOS, `ellipsis-vertical` everywhere else.
  final bool iosStyle;
  final bool selected;
  final VoidCallback? onSelectionToggle;

  /// Real image/video thumbnail for the tile; see [NooFileTile.thumbnail].
  final Widget? thumbnail;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overflow menu tap. The button is hidden when null.
  final VoidCallback? onMore;

  const NooFileRow({
    super.key,
    required this.kind,
    required this.name,
    this.size,
    this.modified,
    this.meta,
    this.statuses = const [],
    this.favorite = false,
    this.trailing,
    this.iosStyle = false,
    this.selected = false,
    this.onSelectionToggle,
    this.thumbnail,
    this.onTap,
    this.onLongPress,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final metaText =
        meta ??
        [
          size,
          modified,
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final hasError = statuses.contains(NooSyncStatus.error);

    return Material(
      color: selected ? colors.accentSoft : colors.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: NooSizes.rowMobile,
          child: Padding(
            padding: EdgeInsets.only(
              left: NooSpace.md,
              right: onMore != null ? NooSpace.xxs : NooSpace.md,
            ),
            child: Row(
              children: [
                NooPointerCheckbox(
                  selected: selected,
                  onToggle: onSelectionToggle,
                ),
                NooFileTile(kind: kind, thumbnail: thumbnail),
                const SizedBox(width: NooSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NooText.bodyL.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.fg1,
                        ),
                      ),
                      if (statuses.isNotEmpty || metaText.isNotEmpty) ...[
                        const SizedBox(height: NooSpace.xxs),
                        Row(
                          children: [
                            for (final s in statuses) ...[
                              NooStatusIcon(s),
                              const SizedBox(width: NooSpace.xxs),
                            ],
                            Expanded(
                              child: Text(
                                metaText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NooText.meta.copyWith(
                                  color: hasError ? colors.danger : colors.fg3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (favorite) ...[
                  const SizedBox(width: NooSpace.xs),
                  Icon(LucideIcons.star, size: 18, color: colors.accentText),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: NooSpace.xs),
                  IconTheme.merge(
                    data: IconThemeData(size: 18, color: colors.fg3),
                    child: trailing!,
                  ),
                ],
                if (onMore != null)
                  NooOverflowButton(iosStyle: iosStyle, onTap: onMore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 40px round overflow ("more") hit target used at the end of file
/// rows - `ellipsis` when [iosStyle], `ellipsis-vertical` otherwise, 20px
/// in fg-3.
class NooOverflowButton extends StatelessWidget {
  final bool iosStyle;
  final double size;
  final VoidCallback? onTap;

  const NooOverflowButton({
    super.key,
    this.iosStyle = false,
    this.size = 40,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return SizedBox.square(
      dimension: size,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(
            iosStyle ? LucideIcons.ellipsis : LucideIcons.ellipsisVertical,
            size: size >= 40 ? 20 : 18,
            color: colors.fg3,
          ),
        ),
      ),
    );
  }
}
