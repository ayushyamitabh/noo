import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Video badge background from `DESIGN_SYSTEM.md` section 2 ("Photo
/// grid"): `rgba(14,13,11,.7)` - not a [NooColors] token, it's a fixed
/// overlay that sits on photo content in both themes.
const _videoBadgeColor = Color(0xB30E0D0B);

/// Square photo tile for [NooPhotoGrid] (`DESIGN_SYSTEM.md` section 2,
/// "Photo grid"): an image [child] (usually `Image` with `BoxFit.cover`)
/// or, while loading/absent, a flat [placeholderColor] from
/// [NooColors.avatarPalette]. Videos get a bottom-right badge with a `play`
/// icon and [videoDuration].
class NooPhotoTile extends StatelessWidget {
  final Widget? child;

  /// Fill shown behind/instead of [child]; defaults to the first
  /// [NooColors.avatarPalette] entry. Use [NooPhotoTile.paletteColor] to
  /// pick a stable one per item.
  final Color? placeholderColor;

  /// Non-null marks the tile as a video and shows the badge, e.g. `0:42`.
  /// Pass an empty string for a play-icon-only badge.
  final String? videoDuration;

  final bool selected;

  /// Shows the selection check circle even when not [selected] (i.e. the
  /// grid is in multi-select mode).
  final bool selectionMode;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const NooPhotoTile({
    super.key,
    this.child,
    this.placeholderColor,
    this.videoDuration,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  /// Stable secondary-palette colour for an item (e.g. from its id/path
  /// hash), so placeholders don't reshuffle between rebuilds.
  static Color paletteColor(int seed) =>
      NooColors.avatarPalette[seed.abs() % NooColors.avatarPalette.length];

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Selected tiles inset so an accent-soft frame shows around
            // the photo, instead of covering it with a tint.
            ColoredBox(color: selected ? colors.accentSoft : Colors.transparent),
            AnimatedPadding(
              duration: NooMotion.fast,
              curve: NooMotion.ease,
              padding: EdgeInsets.all(selected ? 8 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 8 : 0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: placeholderColor ?? NooColors.avatarPalette.first,
                    ),
                    ?child,
                  ],
                ),
              ),
            ),
            if (videoDuration != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: _VideoBadge(duration: videoDuration!),
              ),
            if (selected || selectionMode)
              Positioned(
                left: 6,
                top: 6,
                child: _SelectCheck(selected: selected),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoBadge extends StatelessWidget {
  final String duration;

  const _VideoBadge({required this.duration});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: EdgeInsets.symmetric(horizontal: duration.isEmpty ? 4 : 6),
      decoration: BoxDecoration(
        color: _videoBadgeColor,
        borderRadius: BorderRadius.circular(NooRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.play, size: 12, color: Colors.white),
          if (duration.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(
              duration,
              style: NooText.meta.copyWith(
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 22px selection circle: accent fill + white check when selected, a
/// white-outlined empty circle on the video-badge scrim otherwise.
class _SelectCheck extends StatelessWidget {
  final bool selected;

  const _SelectCheck({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.accent : _videoBadgeColor,
        border: selected
            ? null
            : Border.all(color: Colors.white, width: 1.5),
      ),
      child: selected
          ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}
