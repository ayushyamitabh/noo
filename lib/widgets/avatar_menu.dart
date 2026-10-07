import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/trash_controller.dart';
import '../theme/design_tokens.dart';
import 'noo/core/noo_avatar.dart';
import '../views/login_view.dart';
import 'noo/core/noo_badge.dart';
import 'noo/lists/noo_settings_row.dart';
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
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    transitionDuration: NooMotion.fast,
    pageBuilder: (context, _, _) => const _AvatarMenuContent(),
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

class _AvatarMenuContent extends StatefulWidget {
  const _AvatarMenuContent();

  @override
  State<_AvatarMenuContent> createState() => _AvatarMenuContentState();
}

class _AvatarMenuContentState extends State<_AvatarMenuContent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final session = context.watch<SessionController>();
    final settings = context.watch<SettingsController>();
    final trashCount = context.watch<TrashController>().items.length;
    final hiddenTabs = settings.tabOrder
        .where((t) => settings.hiddenTabs.contains(t))
        .toList();

    void closeAndOpenSettings() {
      Navigator.pop(context);
      openSettings(context);
    }

    return Align(
      alignment: Alignment.topCenter,
      // Just the status-bar inset, not the top bar's own height on top of
      // it - the card covers the top bar (title included) rather than
      // sitting below it, so opening it reads as the avatar growing into
      // this instead of a separate element appearing underneath the row
      // it came from.
      child: SafeArea(
        bottom: false,
        child: Padding(
          // Same side inset as the Files list's rows (`NooSpace.sm`), so the
          // card is as wide as the list beneath it.
          padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
          child: SizedBox(
            width: double.infinity,
            child: Container(
              // No `color`/`clipBehavior` here - a `Container` with both a
              // `border` and `clipBehavior` set paints the border as part
              // of its *outer* decoration, then paints its (clipped) child
              // on top right up to that same boundary with no gap for the
              // border's own stroke width to show through. An opaque child
              // touching that edge - every row below has its own full-bleed
              // `Material` fill - then paints straight over the inner half
              // of the border, which read as the border going missing
              // specifically wherever an opaque row sits (every corner but
              // the two by the header, which has no opaque fill of its
              // own). The 1px `Padding` + inset `ClipRRect` below keeps the
              // clipped, filled content entirely inside the border's own
              // stroke instead of racing it for the same pixels.
              decoration: BoxDecoration(
                border: Border.all(color: colors.line),
                borderRadius: BorderRadius.circular(NooRadii.card),
                // `nooDialogShadow` alone is a wide, soft, fairly faint
                // shadow - built for a desktop dialog with plenty of room
                // to fall off into. On a small card over a dark theme's
                // near-black `bg`, that falloff is too gradual to read as
                // elevation at all (a dark shadow needs real density close
                // to the edge to be visible against an already-dark
                // backdrop). A second, tighter, more opaque contact shadow
                // underneath it gives an immediate value-step right at the
                // card's edge in both themes, with the soft one still
                // doing the wider ambient falloff on top.
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                  nooDialogShadow,
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NooRadii.card - 1),
                  child: Material(
                    color: colors.surface,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Avatar on the right, name/host on the left - mirrors the
                        // top bar's own right-aligned avatar exactly, so this
                        // header reads as a continuation of the button that
                        // opened it rather than a disconnected card.
                        InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.all(NooSpace.md),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                const SizedBox(width: 8),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.fg1.withValues(alpha: 0.08),
                                  ),
                                  child: Icon(
                                    _expanded
                                        ? LucideIcons.chevronUp
                                        : LucideIcons.chevronDown,
                                    size: 20,
                                    color: colors.fg2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: NooMotion.fast,
                          curve: NooMotion.ease,
                          alignment: Alignment.topCenter,
                          child: _expanded
                              ? Column(
                                  children: [
                                    for (final account in session.accounts)
                                      if (account.id != session.activeAccountId)
                                        _OtherAccountRow(
                                          name: account.username,
                                          host: serverHost(account.serverUrl),
                                          onTap: () {
                                            Navigator.pop(context);
                                            session.switchAccount(account.id);
                                          },
                                        ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        NooSpace.md,
                                        0,
                                        NooSpace.md,
                                        NooSpace.md,
                                      ),
                                      child: Row(
                                        spacing: 8,
                                        children: [
                                          Expanded(
                                            child: _AccountButton(
                                              icon: LucideIcons.userPlus,
                                              label: 'Add Account',
                                              onTap: () {
                                                final nav = Navigator.of(
                                                  context,
                                                );
                                                nav.pop();
                                                nav.push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const LoginView(
                                                          isAddingAccount: true,
                                                        ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          Expanded(
                                            child: _AccountButton(
                                              icon: LucideIcons.users,
                                              label: 'Manage Accounts',
                                              onTap: closeAndOpenSettings,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox(width: double.infinity),
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
        ),
      ),
    );
  }
}

class _OtherAccountRow extends StatelessWidget {
  final String name;
  final String host;
  final VoidCallback onTap;

  const _OtherAccountRow({
    required this.name,
    required this.host,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(NooSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.bodyL.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.fg1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.meta.copyWith(color: colors.fg3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            NooAvatar(initials: accountInitial(name), current: false, size: 40),
          ],
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AccountButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final radius = BorderRadius.circular(NooRadii.input);
    return Material(
      color: colors.bg,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              Icon(icon, size: 18, color: colors.fg2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.body.copyWith(color: colors.fg1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
