import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/app_tab.dart';
import '../providers/settings_controller.dart';
import 'avatar_menu.dart';
import 'create_menu.dart';
import 'noo/nav/noo_top_bar.dart';
import 'noo/core/noo_button.dart';
import '../theme/design_tokens.dart';
import 'shell/shell_common.dart';

/// The shell's mobile top bar (DESIGN_SYSTEM.md 3, "Mobile"): every regular
/// tab now gets the same chrome (this used to only wrap Files - the other
/// tabs built their own via `SyncedHeaderScaffold`, which the rework drops).
/// Built on [NooTopBar]:
///
/// - iOS: large title, Upload button and account avatar in one row, then
///   an inline search field that opens [SearchView]. Upload shares Android's
///   Auto/Collapsed/Expanded preference.
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
  final AvatarPosition avatarPosition;
  final FabStyle uploadButtonStyle;

  const AppTopBar({
    super.key,
    required this.style,
    required this.tab,
    this.searchInBottomBar = false,
    this.navMenuStyle = NooNavMenuStyle.drawer,
    this.avatarPosition = AvatarPosition.top,
    this.uploadButtonStyle = FabStyle.auto,
  });

  bool get _ios => style == NooNavStyle.ios;
  bool get _showSearch => !searchInBottomBar;
  bool get _uploadCollapsed => switch (uploadButtonStyle) {
    FabStyle.auto => tab != AppTab.files && tab != AppTab.photos,
    FabStyle.mini => true,
    FabStyle.expanded => false,
  };

  @override
  Size get preferredSize => NooTopBar(
    style: style,
    title: tab.label,
    iosActionsInTitleRow: true,
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
      iosActionsInTitleRow: true,
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
        if (_ios)
          Tooltip(
            message: 'Upload',
            child: Semantics(
              button: true,
              label: 'Upload',
              child: Builder(
                builder: (context) {
                  Widget button(double progress) => NooButton(
                    variant: NooButtonVariant.tonal,
                    size: NooButtonSize.compact,
                    icon: LucideIcons.plus,
                    expansion: progress,
                    onTap: () => showCreateMenu(context),
                    child: const Text('Upload'),
                  );
                  final scope = context
                      .dependOnInheritedWidgetOfExactType<
                        UploadButtonAnimation
                      >();
                  if (scope != null) return button(scope.progress);
                  return TweenAnimationBuilder<double>(
                    tween: Tween(end: _uploadCollapsed ? 0 : 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : NooMotion.base,
                    curve: NooMotion.ease,
                    builder: (context, progress, _) => button(progress),
                  );
                },
              ),
            ),
          ),
        if (navMenuStyle != NooNavMenuStyle.avatarMenu ||
            avatarPosition == AvatarPosition.top)
          AvatarNavigationAnchor(
            child: Builder(
              builder: (anchorContext) => ShellAvatarButton(
                hitBox: _ios ? 44 : 48,
                onTap: navMenuStyle == NooNavMenuStyle.avatarMenu
                    ? () => showAvatarMenu(anchorContext)
                    : null,
                label: navMenuStyle == NooNavMenuStyle.avatarMenu
                    ? 'Menu'
                    : 'Accounts',
              ),
            ),
          ),
      ],
      search: _ios && _showSearch ? const ShellSearchLauncher(ios: true) : null,
    );
  }
}

/// Shares one transition across the shell's separately mounted tab headers.
class UploadButtonAnimation extends InheritedWidget {
  final double progress;
  const UploadButtonAnimation({
    super.key,
    required this.progress,
    required super.child,
  });
  @override
  bool updateShouldNotify(UploadButtonAnimation oldWidget) =>
      progress != oldWidget.progress;
}
