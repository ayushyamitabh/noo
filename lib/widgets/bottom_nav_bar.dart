import 'package:flutter/material.dart';
import '../models/app_tab.dart';
import 'noo/nav/noo_bottom_bar.dart';

/// Adapts the app's [AppTab] model onto [NooBottomBar]'s generic
/// [NooNavDestination] list, so `MainShellView` only deals in tabs and
/// doesn't need to import `noo/nav` itself. [selectedIndex] may be -1 (no
/// destination highlighted) when the shell is showing a tab opened from the
/// drawer's "More" list that isn't one of the pinned [tabs].
class BottomNavBar extends StatelessWidget {
  final NooNavStyle style;
  final NooBottomBarStyle barStyle;
  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const BottomNavBar({
    super.key,
    required this.style,
    this.barStyle = NooBottomBarStyle.attached,
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NooBottomBar(
      style: style,
      barStyle: barStyle,
      destinations: [
        for (final tab in tabs)
          NooNavDestination(icon: tab.icon, label: tab.label),
      ],
      selectedIndex: selectedIndex,
      onSelected: onDestinationSelected,
    );
  }
}
