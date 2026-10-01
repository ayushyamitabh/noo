import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/app_tab.dart';
import 'avatar_menu.dart';
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
/// - Android: `menu`, title, avatar actions. Upload has no top-bar icon
///   here - it's the [NooFab] `MainShellView` shows instead. When search
///   isn't in the bottom bar, an inline search-field-styled launcher
///   (`androidTitleTrailing`) sits to the title's own right, rather than a
///   bare search icon over in `actions`.
///
/// [style] is resolved by the caller (`NooLayout.navStyle`) rather than
/// read from context here, since [preferredSize] is a plain getter with no
/// BuildContext - the same reason [NooTopBar] itself takes it as a field.
/// [searchInBottomBar] is [SettingsController.searchInBottomBar], passed in
/// for the same reason: it hides this bar's own search field/icon so
/// there's only ever one search entry point on screen once the bottom bar
/// has taken it over. [navMenuStyle] is
/// [SettingsController.navMenuStyle]: [NooNavMenuStyle.drawer] wires the
/// `menu` icon to `Scaffold.of(context).openDrawer()` as before;
/// [NooNavMenuStyle.avatarMenu] drops that icon (`onMenu: null`) and makes
/// the avatar button open `showAvatarMenu` instead of the account
/// switcher.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final NooNavStyle style;
  final AppTab tab;
  final bool searchInBottomBar;
  final NooNavMenuStyle navMenuStyle;

  const AppTopBar({
    super.key,
    required this.style,
    required this.tab,
    this.searchInBottomBar = false,
    this.navMenuStyle = NooNavMenuStyle.drawer,
  });

  bool get _ios => style == NooNavStyle.ios;
  bool get _showSearch => !searchInBottomBar;

  @override
  Size get preferredSize => NooTopBar(
    style: style,
    title: tab.label,
    // A throwaway placeholder purely to make preferredSize's "is there a
    // search slot" check match what build() actually shows - never
    // inserted into the tree, so its content doesn't matter.
    search: _ios && _showSearch ? const SizedBox.shrink() : null,
  ).preferredSize;

  @override
  Widget build(BuildContext context) {
    return NooTopBar(
      style: style,
      title: tab.label,
      onMenu: navMenuStyle == NooNavMenuStyle.drawer
          ? () => Scaffold.of(context).openDrawer()
          : null,
      // Android has no large title to put a second search row under the
      // way iOS does (`search:` below) - an inline bar sits beside the
      // title instead, rather than a plain search icon over in `actions`.
      androidTitleTrailing: !_ios && _showSearch
          ? const ShellSearchLauncher()
          : null,
      actions: [
        if (_ios && tab == AppTab.files)
          NooTopBarButton(
            icon: LucideIcons.plus,
            tooltip: 'Create',
            onTap: () => showCreateMenu(context),
          ),
        ShellAvatarButton(
          hitBox: _ios ? 44 : 48,
          onTap: navMenuStyle == NooNavMenuStyle.avatarMenu
              ? () => showAvatarMenu(context)
              : null,
          label: navMenuStyle == NooNavMenuStyle.avatarMenu
              ? 'Menu'
              : 'Accounts',
        ),
      ],
      search: _ios && _showSearch ? const ShellSearchLauncher(ios: true) : null,
    );
  }
}
