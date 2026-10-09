import 'package:flutter/material.dart';
import '../core/noo_pointer_selection.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Grid-view file card: a thumbnail area (file-type soft colour + 32px
/// icon, or a real [thumbnail]) above the name, an overflow button and a
/// meta line (`DESIGN_SYSTEM.md` section 2, "Grid card"). Mobile lays these
/// out with 10px phone / 16px tablet gaps and responsive columns - the parent grid
/// owns that, this card just fills its cell.
///
/// The placeholder colours/icon are plain parameters rather than a file
/// kind so this stays independent of the file-kind mapping; callers pass
/// e.g. `accentSoft`/`accentText`/`LucideIcons.folder` for a folder.
class NooGridCard extends StatelessWidget {
  final String name;
  final String? meta;

  /// Soft fill behind [icon] when there's no [thumbnail] (e.g. `infoSoft`).
  final Color? placeholderColor;
  final IconData? icon;

  /// Icon colour on the placeholder (e.g. `info`).
  final Color? iconColor;

  /// Real thumbnail (typically an `Image` with `BoxFit.cover`); replaces
  /// the placeholder and is clipped to the card's top corners.
  final Widget? thumbnail;

  /// 104 (mobile) - 118 (desktop).
  final double thumbnailHeight;

  final bool selected;
  final VoidCallback? onSelectionToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Shows the overflow button when non-null.
  final VoidCallback? onMore;

  /// `ellipsis` on iOS/desktop, `ellipsis-vertical` on Android.
  final bool verticalOverflowIcon;

  const NooGridCard({
    super.key,
    required this.name,
    this.meta,
    this.placeholderColor,
    this.icon,
    this.iconColor,
    this.thumbnail,
    this.thumbnailHeight = 104,
    this.selected = false,
    this.onSelectionToggle,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.verticalOverflowIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final radius = BorderRadius.circular(NooRadii.gridCard);

    final thumb = SizedBox(
      height: thumbnailHeight,
      width: double.infinity,
      child:
          thumbnail ??
          ColoredBox(
            color: placeholderColor ?? colors.surface2,
            child: Center(
              child: Icon(
                icon ?? LucideIcons.file,
                size: 32,
                color: iconColor ?? colors.fg2,
              ),
            ),
          ),
    );

    return Material(
      color: selected ? colors.accentSoft : colors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                thumb,
                Positioned(
                  top: 4,
                  left: 4,
                  child: NooPointerCheckbox(
                    selected: selected,
                    onToggle: onSelectionToggle,
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                NooSpace.sm,
                10,
                onMore != null ? NooSpace.xxs : NooSpace.sm,
                NooSpace.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NooText.body.copyWith(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: selected ? colors.accentText : colors.fg1,
                          ),
                        ),
                        if (meta != null) ...[
                          const SizedBox(height: NooSpace.xxs),
                          Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NooText.meta.copyWith(
                              fontSize: 12,
                              color: colors.fg3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onMore != null)
                    _OverflowButton(
                      icon: verticalOverflowIcon
                          ? LucideIcons.ellipsisVertical
                          : LucideIcons.ellipsis,
                      color: colors.fg3,
                      onTap: onMore!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact 28px circular hit target so the overflow button doesn't push
/// the name/meta column taller than the text itself.
class _OverflowButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OverflowButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
