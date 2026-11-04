import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_avatar.dart';
import '../noo/media/noo_photo_tile.dart';
import '../noo/nav/noo_bottom_bar.dart';
import '../noo/noo_layout.dart';

/// A live, tappable preview of the bottom bar over busy content, so bar style,
/// icon-only, frosted glass and its blur/tint/refraction can be judged as
/// they're changed. It builds the real [NooBottomBar] from the current
/// [SettingsController] values, so it can't drift from the actual bar.
class SettingsBottomBarPreview extends StatefulWidget {
  const SettingsBottomBarPreview({super.key});

  @override
  State<SettingsBottomBarPreview> createState() =>
      _SettingsBottomBarPreviewState();
}

class _SettingsBottomBarPreviewState extends State<SettingsBottomBarPreview> {
  static const _destinations = [
    NooNavDestination(icon: LucideIcons.folder, label: 'Files'),
    NooNavDestination(icon: LucideIcons.images, label: 'Photos'),
    NooNavDestination(icon: LucideIcons.star, label: 'Favorites'),
    NooNavDestination(icon: LucideIcons.activity, label: 'Activity'),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final colors = context.nooColors;
    final frosted = settings.bottomBarFrosted;
    final barStyle = settings.bottomBarStyle;
    final iconOnly = settings.bottomBarIconOnly;
    // The real bar sits under the device's safe area; inside a card there is
    // none, so strip it.
    final media = MediaQuery.of(context);

    final compact = settings.bottomBarCompact;
    final avatarAtBottom =
        settings.navMenuStyle == NooNavMenuStyle.avatarMenu &&
        settings.avatarPosition == AvatarPosition.bottom;
    final navStyle = NooLayout.navStyle(context);
    final barHeight = NooBottomBar.rowHeight(
      navStyle,
      barStyle,
      iconOnly: iconOnly,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(NooRadii.card),
      ),
      child: Padding(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NooRadii.card),
          child: SizedBox(
            height: 176,
            child: ColoredBox(
              color: colors.bg,
              child: Stack(
                children: [
                  const Positioned.fill(child: _SampleContent()),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: MediaQuery(
                      data: media.copyWith(padding: EdgeInsets.zero),
                      child: NooBottomBar(
                        style: NooLayout.navStyle(context),
                        barStyle: barStyle,
                        frosted: frosted,
                        iconOnly: iconOnly,
                        fullWidth:
                            !iconOnly || settings.bottomBarIconOnlyFullWidth,
                        frostedBlur: settings.bottomBarFrostedBlur,
                        frostedOpacity: settings.bottomBarFrostedOpacity,
                        destinations: _destinations,
                        selectedIndex: _selected,
                        onSelected: (i) => setState(() => _selected = i),
                        searchDestination: settings.searchInBottomBar
                            ? const NooNavDestination(
                                icon: LucideIcons.search,
                                label: 'Search',
                              )
                            : null,
                        onSearchTap: settings.searchInBottomBar ? () {} : null,
                        avatarSatellite: avatarAtBottom
                            ? _PreviewAvatar(
                                size: compact
                                    ? NooBottomBar.iconOnlyItemWidth
                                    : barHeight,
                                // Inside the compact pill the pill is the
                                // surface; otherwise a floating bar's avatar
                                // is its own circle.
                                circle:
                                    !compact &&
                                    barStyle == NooBottomBarStyle.floating,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stand-in for the real avatar button (which needs a signed-in session).
class _PreviewAvatar extends StatelessWidget {
  final double size;
  final bool circle;

  const _PreviewAvatar({required this.size, required this.circle});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final avatar = Center(child: NooAvatar(initials: 'N', size: 32));
    if (!circle) return SizedBox(width: size, height: size, child: avatar);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.line),
      ),
      child: avatar,
    );
  }
}

/// Colourful tiles with text, standing in for a photo grid scrolling behind
/// the bar - something with edges and detail for blur/refraction to act on.
class _SampleContent extends StatelessWidget {
  const _SampleContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: 6,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < 24; i++)
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NooPhotoTile.paletteColor(i * 3 + 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${i + 1}',
              style: NooText.title.copyWith(color: colors.fg1),
            ),
          ),
      ],
    );
  }
}
