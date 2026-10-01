import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/saved_account.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../../views/login_view.dart';
import '../noo/core/noo_avatar.dart';
import '../noo/lists/noo_settings_row.dart';
import '../shell/shell_common.dart';
import 'settings_dialogs.dart';
import 'settings_section.dart';

/// Settings section 2: every saved account (switch/remove), then "Add
/// account" (DESIGN_SYSTEM.md 4).
class SettingsAccountsSection extends StatelessWidget {
  const SettingsAccountsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return SettingsSection(
      title: 'Accounts',
      children: [
        for (final account in session.accounts)
          _SavedAccountRow(
            account: account,
            isActive: account.id == session.activeAccountId,
            onTap: account.id == session.activeAccountId
                ? null
                : () => session.switchAccount(account.id),
            onRemove: () => confirmRemoveAccount(
              context,
              session,
              accountId: account.id,
              username: account.username,
              host: serverHost(account.serverUrl),
              isActive: account.id == session.activeAccountId,
            ),
          ),
        NooSettingsRow(
          icon: LucideIcons.userPlus,
          accent: true,
          label: const Text('Add account'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginView(isAddingAccount: true)),
          ),
        ),
      ],
    );
  }
}

/// A saved-account row: avatar, name over host, a check on the active one,
/// and a remove button - [NooSettingsRow] can't show an avatar leading
/// widget (only an [IconData]), so this is its own row built to the same
/// proportions (mirrors `shell_common.dart`'s private `_AccountSwitchRow`,
/// which the account switcher sheet/dialog uses for the same data).
class _SavedAccountRow extends StatelessWidget {
  final SavedAccount account;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  const _SavedAccountRow({
    required this.account,
    required this.isActive,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NooSpace.md, vertical: 10),
          child: Row(
            spacing: 12,
            children: [
              NooAvatar(initials: accountInitial(account.username), current: isActive, size: 36),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      account.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.bodyL.copyWith(
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                        color: colors.fg1,
                      ),
                    ),
                    Text(
                      serverHost(account.serverUrl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.meta.copyWith(color: colors.fg3),
                    ),
                  ],
                ),
              ),
              if (isActive) Icon(LucideIcons.checkCircle, size: 20, color: colors.accentText),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.surface2, shape: BoxShape.circle),
                  child: Icon(LucideIcons.trash2, size: 16, color: colors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
