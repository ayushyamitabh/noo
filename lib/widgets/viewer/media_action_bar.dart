import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/design_tokens.dart';
import '../frosted_glass_container.dart';
import 'viewer_icon_button.dart';

/// The bottom panel overlaid on the media viewer: an optional transport row
/// ([transportControls], video only) above the action row
/// (share/favorite/open/download/delete/details) - one continuous flush,
/// full-width `FrostedGlassContainer` panel, not two separate floating
/// pills. Kept on that blurred chrome as a deliberate exception to the
/// design system's flat product UI (see `file_viewer_screen.dart`'s
/// build() comment for why), unlike the now-flat bottom nav bar
/// (`bottom_nav_bar.dart`) this screen sits above.
class MediaActionBar extends StatelessWidget {
  final bool isFavorite;
  final bool isBusy;
  final bool showServerActions;
  final Widget? transportControls;
  final VoidCallback onShare;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onOpenExternally;
  final VoidCallback onDownload;
  final VoidCallback onDetails;

  const MediaActionBar({
    super.key,
    required this.isFavorite,
    required this.isBusy,
    required this.showServerActions,
    this.transportControls,
    required this.onShare,
    required this.onFavorite,
    required this.onDelete,
    required this.onOpenExternally,
    required this.onDownload,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    // The blurred/tinted background lives outside the SafeArea (not inside
    // it) so it extends all the way to the physical bottom edge, behind the
    // gesture bar/home indicator, instead of the panel itself stopping
    // short and leaving that strip unstyled - only the actual row content
    // needs padding up and away from the gesture area.
    return FrostedGlassContainer(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (transportControls != null) ...[
              transportControls!,
              Divider(height: 1, color: colors.fg1.withValues(alpha: 0.14)),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ViewerIconButton(
                    icon: LucideIcons.share2,
                    tooltip: 'Share',
                    onTap: isBusy ? null : onShare,
                  ),
                  if (showServerActions)
                    ViewerIconButton(
                      // Matches the star/star-off convention Files' own
                      // selection toolbar uses for favorite/unfavorite
                      // (see `files_view.dart`) rather than a filled heart.
                      icon: isFavorite ? LucideIcons.starOff : LucideIcons.star,
                      tooltip: isFavorite
                          ? 'Remove from favorites'
                          : 'Favorite',
                      color: isFavorite ? colors.accentText : null,
                      onTap: onFavorite,
                    ),
                  ViewerIconButton(
                    icon: LucideIcons.externalLink,
                    tooltip: 'Open externally',
                    onTap: isBusy ? null : onOpenExternally,
                  ),
                  if (showServerActions)
                    ViewerIconButton(
                      icon: LucideIcons.download,
                      tooltip: 'Download',
                      onTap: isBusy ? null : onDownload,
                    ),
                  if (showServerActions)
                    ViewerIconButton(
                      icon: LucideIcons.trash2,
                      tooltip: 'Delete',
                      color: colors.danger,
                      onTap: isBusy ? null : onDelete,
                    ),
                  ViewerIconButton(
                    icon: LucideIcons.info,
                    tooltip: 'Details',
                    onTap: onDetails,
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
