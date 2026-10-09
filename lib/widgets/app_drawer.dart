import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/trash_controller.dart';
import 'noo/core/noo_avatar.dart';
import 'noo/nav/noo_drawer.dart';
import 'shell/shell_common.dart';

/// The mobile drawer (DESIGN_SYSTEM.md 2 "Drawer" / 3; `drawer` in
/// `Mobile Screen.dc.html`): account block, storage bar, the tabs not
/// pinned to the bottom nav bar ("More"), Settings, and an "Edit tabs"
/// link. Opened the same way as before (menu icon in [AppTopBar]), but
/// built on [NooDrawer] instead of the old Material [Drawer] + ad hoc rows.
///
/// Tapping a "More" tab switches the shell straight to it (rather than
/// pushing it as a standalone screen, like the pre-rework `MoreTabsButton`
/// did) via `SettingsController.requestTab` - the same one-shot mechanism
/// `SearchView`/`FavoritesView`/`ShareUploadView` already use to jump the
/// shell to a tab from outside it, so `MainShellView` needs no extra
/// plumbing to support it.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final settings = context.watch<SettingsController>();
    final quota = context.watch<FilesController>().quota;
    // Cheap and already loaded when the Trash tab has been visited this
    // session - not worth a fetch just to populate a drawer badge.
    final trashCount = context.watch<TrashController>().items.length;
    final hiddenTabs = settings.tabOrder
        .where((t) => settings.hiddenTabs.contains(t))
        .toList();

    void closeAndOpenSettings() {
      Navigator.pop(context);
      openSettings(context);
    }

    return NooDrawer(
      account: NooDrawerAccount(
        avatar: NooAvatar(
          initials: accountInitial(session.displayName),
          current: true,
          size: 48,
        ),
        name: session.displayName,
        subtitle: serverHost(session.serverUrl),
        onTap: closeAndOpenSettings,
        onSwitchAccount: () => showAccountSwitcher(context),
      ),
      storage: NooDrawerStorage(
        value: quotaFraction(quota),
        label: quotaUsedLabel(quota),
      ),
      moreItems: [
        for (final tab in hiddenTabs)
          NooDrawerItem(
            icon: tab.icon,
            label: tab.label,
            count: tab == AppTab.trash && trashCount > 0
                ? '$trashCount'
                : null,
            onTap: () {
              Navigator.pop(context);
              settings.requestTab(tab);
            },
          ),
      ],
      settings: NooDrawerItem(
        icon: LucideIcons.settings,
        label: 'Settings',
        onTap: closeAndOpenSettings,
      ),
      footer: NooDrawerLink(onTap: closeAndOpenSettings),
    );
  }
}
