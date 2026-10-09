import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/files_controller.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_avatar.dart';
import '../noo/core/noo_button.dart';
import '../noo/core/noo_chip.dart';
import '../noo/core/noo_progress_bar.dart';
import '../noo/noo_layout.dart';
import '../shell/shell_common.dart';
import '../shell/tablet_account_menu.dart';
import 'settings_dialogs.dart';

/// Settings section 1: the account card (DESIGN_SYSTEM.md 4 - "NooAvatar
/// 52-56, name, server, storage NooProgressBar"). The quota/quick-actions
/// (refresh/log out/remove) aren't in the spec's short recipe but were on
/// the pre-rework card and have no other home, so they stay here as a
/// button row under the storage meter.
class SettingsAccountCard extends StatelessWidget {
  final bool compact;
  final VoidCallback? onManage;
  const SettingsAccountCard({super.key, this.compact = false, this.onManage});

  Future<void> _refresh(BuildContext context, FilesController files) async {
    await files.refreshData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshed WebDAV data'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Logout keeps the account saved (see [SessionController.logout]) so
  /// it's harmless/reversible from a one-tap resume on the login screen -
  /// doesn't need a confirmation dialog the way removing an account does.
  Future<void> _logout(BuildContext context, SessionController session) async {
    final navigator = Navigator.of(context);
    await session.logout();
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _remove(BuildContext context, SessionController session) async {
    final id = session.activeAccountId;
    if (id == null) return;
    await confirmRemoveAccount(
      context,
      session,
      accountId: id,
      username: session.displayName,
      host: serverHost(session.serverUrl),
      isActive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final session = context.watch<SessionController>();
    final files = context.watch<FilesController>();
    final quota = files.quota;
    final name = session.displayName;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : NooSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NooRadii.card),
        border: NooLayout.isDesktop(context)
            ? Border.all(color: colors.line)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            TabletAccountMenu(framed: false, onManage: onManage)
          else
            Row(
              children: [
                NooAvatar(
                  initials: accountInitial(name),
                  current: true,
                  size: 56,
                ),
                const SizedBox(width: NooSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NooText.cardTitle.copyWith(color: colors.fg1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        serverHost(session.serverUrl),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NooText.meta.copyWith(color: colors.fg3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: NooSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Storage', style: NooText.label.copyWith(color: colors.fg2)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  quota != null ? quotaDetail(quota) : 'Loading…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: NooText.meta.copyWith(color: colors.fg3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          NooProgressBar(value: quotaFraction(quota)),
          if (quota != null && quota.groups.isNotEmpty) ...[
            const SizedBox(height: NooSpace.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final group in quota.groups) NooChip(child: Text(group)),
              ],
            ),
          ],
          const SizedBox(height: NooSpace.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NooButton(
                variant: NooButtonVariant.secondary,
                size: NooButtonSize.compact,
                icon: LucideIcons.refreshCw,
                onTap: () => _refresh(context, files),
                child: const Text('Refresh'),
              ),
              NooButton(
                variant: NooButtonVariant.secondary,
                size: NooButtonSize.compact,
                icon: LucideIcons.logOut,
                onTap: () => _logout(context, session),
                child: const Text('Log out'),
              ),
              NooButton(
                variant: NooButtonVariant.danger,
                size: NooButtonSize.compact,
                icon: LucideIcons.trash2,
                onTap: () => _remove(context, session),
                child: const Text('Remove account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
