import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/app_tab.dart';
import 'noo/nav/noo_bottom_bar.dart';
import 'avatar_menu.dart';

/// Adapts the app's [AppTab] model onto [NooBottomBar]'s generic
/// [NooNavDestination] list, so `MainShellView` only deals in tabs and
/// doesn't need to import `noo/nav` itself. [selectedIndex] may be -1 (no
/// destination highlighted) when the shell is showing a tab opened from the
/// drawer's "More" list that isn't one of the pinned [tabs].
///
/// [onSearchTap] (from Settings' "Search in bottom bar") adds the Search
/// entry [NooBottomBar] itself knows how to place (row's last item when
/// attached, its own satellite when floating) - null leaves the bar
/// exactly as before.
class BottomNavBar extends StatelessWidget {
  final NooNavStyle style;
  final NooBottomBarStyle barStyle;
  final bool frosted;
  final double frostedBlur;
  final double frostedOpacity;
  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback? onSearchTap;
  final bool avatarInBottomBar;

  const BottomNavBar({
    super.key,
    required this.style,
    this.barStyle = NooBottomBarStyle.attached,
    this.frosted = false,
    this.frostedBlur = NooBottomBar.defaultFrostedBlur,
    this.frostedOpacity = NooBottomBar.defaultFrostedOpacity,
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.onSearchTap,
    this.avatarInBottomBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return NooBottomBar(
      style: style,
      barStyle: barStyle,
      frosted: frosted,
      frostedBlur: frostedBlur,
      frostedOpacity: frostedOpacity,
      destinations: [
        for (final tab in tabs)
          NooNavDestination(icon: tab.icon, label: tab.label),
      ],
      selectedIndex: selectedIndex,
      onSelected: (index) {
        AvatarNavigationScope.maybeOf(context)?.close();
        onDestinationSelected(index);
      },
      searchDestination: onSearchTap == null
          ? null
          : const NooNavDestination(icon: LucideIcons.search, label: 'Search'),
      onSearchTap: onSearchTap == null
          ? null
          : () {
              AvatarNavigationScope.maybeOf(context)?.close();
              onSearchTap!();
            },
      avatarSatellite: avatarInBottomBar
          ? AvatarNavigationSatellite(
              size: NooBottomBar.rowHeight(style, barStyle),
            )
          : null,
      avatarMenuProgress: avatarInBottomBar
          ? AvatarNavigationScope.maybeOf(context)?.progress ?? 0
          : 0,
    );
  }
}
