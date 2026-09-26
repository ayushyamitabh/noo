import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/app_tab.dart';
import 'create_menu.dart';
import 'noo/nav/noo_top_bar.dart';
import 'shell/shell_common.dart';

/// The shell's mobile top bar (DESIGN_SYSTEM.md 3, "Mobile"): every regular
/// tab now gets the same chrome (this used to only wrap Files - the other
/// tabs built their own via `SyncedHeaderScaffold`, which the rework drops).
/// Built on [NooTopBar]:
///
/// - iOS: `menu` leading, `plus` (Files only - no tab besides Files has a
///   create/upload flow) and the account avatar trailing, then the large
///   title, then an inline search field that opens [SearchView].
/// - Android: `menu`, title, `search` and avatar actions. Upload has no
///   top-bar icon here - it's the [NooFab] `MainShellView` shows instead.
///
/// [style] is resolved by the caller (`NooLayout.navStyle`) rather than
/// read from context here, since [preferredSize] is a plain getter with no
/// BuildContext - the same reason [NooTopBar] itself takes it as a field.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final NooNavStyle style;
  final AppTab tab;

  const AppTopBar({super.key, required this.style, required this.tab});

  bool get _ios => style == NooNavStyle.ios;

  @override
  Size get preferredSize => NooTopBar(
    style: style,
    title: tab.label,
    // A throwaway placeholder purely to make preferredSize's "is there a
    // search slot" check match what build() actually shows - never
    // inserted into the tree, so its content doesn't matter.
    search: _ios ? const SizedBox.shrink() : null,
  ).preferredSize;

  @override
  Widget build(BuildContext context) {
    return NooTopBar(
      style: style,
      title: tab.label,
      onMenu: () => Scaffold.of(context).openDrawer(),
      actions: [
        if (!_ios)
          NooTopBarButton(
            icon: LucideIcons.search,
            tooltip: 'Search',
            onTap: () => openSearch(context),
          ),
        if (_ios && tab == AppTab.files)
          NooTopBarButton(
            icon: LucideIcons.plus,
            tooltip: 'Create',
            onTap: () => showCreateMenu(context),
          ),
        ShellAvatarButton(hitBox: _ios ? 44 : 48),
      ],
      search: _ios ? const ShellSearchLauncher(ios: true) : null,
    );
  }
}
