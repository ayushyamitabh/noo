import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/trash_controller.dart';
import '../theme/design_tokens.dart';
import 'noo/core/noo_avatar.dart';
import 'noo/core/noo_badge.dart';
import 'noo/lists/noo_settings_row.dart';
import 'noo/nav/noo_top_bar.dart';
import 'noo/noo_layout.dart';
import 'shell/shell_common.dart';

/// The dropdown [ShellAvatarButton] opens when
/// [SettingsController.navMenuStyle] is [NooNavMenuStyle.avatarMenu] -
/// everything [AppDrawer] holds beyond its storage bar (hidden tabs,
/// Settings), reached from the avatar instead of a hamburger-triggered
/// left `Drawer`. Built with `showGeneralDialog` rather than a `Drawer`/
/// `showNooSheet`/`showNooDialog` - this needs a transparent (non-dimming)
/// barrier and a card anchored under the top bar rather than a modal
/// sheet/dialog, and there's no existing anchored-popup primitive in this
/// app to reuse (`PopupMenuButton`'s own width doesn't stretch to the full
/// content column the way this needs to).
Future<void> showAvatarMenu(BuildContext context) {
  final navStyle = NooLayout.navStyle(context);
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    transitionDuration: NooMotion.fast,
    pageBuilder: (context, _, _) => _AvatarMenuContent(navStyle: navStyle),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: Alignment.topRight,
        scale: Tween<double>(
          begin: 0.96,
          end: 1,
        ).animate(CurvedAnimation(parent: animation, curve: NooMotion.ease)),
        child: child,
      ),
    ),
  );
}

class _AvatarMenuContent extends StatelessWidget {
  final NooNavStyle navStyle;

  const _AvatarMenuContent({required this.navStyle});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final session = context.watch<SessionController>();
    final settings = context.watch<SettingsController>();
    final trashCount = context.watch<TrashController>().items.length;
    final hiddenTabs = settings.tabOrder
        .where((t) => settings.hiddenTabs.contains(t))
        .toList();
    // The row/avatar it opens from is always this tall + the status bar
    // above it (the button that opens this can't be tapped while its own
    // top bar is scrolled away, so it's always on-screen at this exact
    // position when that happens) - matches `NooTopBar.preferredSize`
    // exactly rather than a guessed constant.
    final topBarHeight = NooTopBar(
      style: navStyle,
      title: '',
    ).preferredSize.height;

    void closeAndOpenSettings() {
      Navigator.pop(context);
      openSettings(context);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            NooSpace.md,
            topBarHeight,
            NooSpace.md,
            0,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.line),
                borderRadius: BorderRadius.circular(NooRadii.card),
                boxShadow: const [nooDialogShadow],
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Avatar on the right, name/host on the left - mirrors the
                    // top bar's own right-aligned avatar exactly, so this
                    // header reads as a continuation of the button that
                    // opened it rather than a disconnected card.
                    InkWell(
                      onTap: closeAndOpenSettings,
                      child: Padding(
                        padding: const EdgeInsets.all(NooSpace.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: NooText.bodyL.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.fg1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    serverHost(session.serverUrl),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: NooText.meta.copyWith(
                                      color: colors.fg3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            NooAvatar(
                              initials: accountInitial(session.username),
                              current: true,
                              size: 40,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (hiddenTabs.isNotEmpty) ...[
                      Divider(height: 1, color: colors.line),
                      for (final tab in hiddenTabs)
                        NooSettingsRow(
                          icon: tab.icon,
                          label: Text(tab.label),
                          trailing: tab == AppTab.trash && trashCount > 0
                              ? NooBadge(
                                  tone: NooBadgeTone.accent,
                                  child: Text('$trashCount'),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            settings.requestTab(tab);
                          },
                        ),
                    ],
                    Divider(height: 1, color: colors.line),
                    NooSettingsRow(
                      icon: LucideIcons.settings,
                      label: const Text('Settings'),
                      onTap: closeAndOpenSettings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
