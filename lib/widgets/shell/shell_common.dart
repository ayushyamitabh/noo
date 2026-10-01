import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../../views/account_view.dart';
import '../../views/login_view.dart';
import '../../views/search_view.dart';
import '../noo/core/noo_avatar.dart';
import '../noo/core/noo_search_field.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../noo/lists/noo_settings_row.dart';
import '../noo/noo_layout.dart';
import '../noo/overlays/noo_dialog.dart';
import '../noo/overlays/noo_sheet.dart';

// Small pieces shared by the mobile drawer/top bar and the desktop
// sidebar/toolbar, so both shells show the same account/storage data and
// open the same screens.

String accountInitial(String username) =>
    username.isNotEmpty ? username[0].toUpperCase() : '?';

String serverHost(String serverUrl) =>
    serverUrl.replaceFirst(RegExp(r'^https?://'), '');

void openSettings(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AccountView()),
  );
}

void openSearch(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SearchView()),
  );
}

// A local copy rather than importing `synced_header_scaffold.dart`'s, since
// that legacy header is on its way out with the rework.
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 0-1 share of the quota used (0 when unknown or unlimited).
double quotaFraction(NextcloudUserQuota? quota) =>
    quota != null && quota.totalBytes > 0
    ? (quota.usedBytes / quota.totalBytes).clamp(0.0, 1.0)
    : 0;

/// "38.2 GB of 100 GB used" (drawer).
String quotaUsedLabel(NextcloudUserQuota? quota) {
  if (quota == null) return 'Storage usage unavailable';
  final total = quota.totalBytes > 0 ? _formatBytes(quota.totalBytes) : '∞';
  return '${_formatBytes(quota.usedBytes)} of $total used';
}

/// "38.2 GB of 100 GB" (sidebar, next to the "Storage" label).
String quotaDetail(NextcloudUserQuota? quota) {
  if (quota == null) return 'Unavailable';
  final total = quota.totalBytes > 0 ? _formatBytes(quota.totalBytes) : '∞';
  return '${_formatBytes(quota.usedBytes)} of $total';
}

/// The saved-accounts switcher behind the drawer's chevron and the desktop
/// sidebar's account card: every saved account (tap to switch, same
/// `switchAccount` call - and login-lock gate - as Settings' account list),
/// "Add account", and a shortcut to the full account settings. A sheet on
/// mobile, a dialog on desktop.
void showAccountSwitcher(BuildContext context) {
  final session = context.read<SessionController>();

  List<Widget> content(BuildContext overlayContext) {
    void close() => Navigator.pop(overlayContext);
    return [
      NooGroupedList(
        label: 'Accounts',
        children: [
          for (final account in session.accounts)
            _AccountSwitchRow(
              name: account.username,
              host: serverHost(account.serverUrl),
              active: account.id == session.activeAccountId,
              onTap: account.id == session.activeAccountId
                  ? null
                  : () {
                      close();
                      session.switchAccount(account.id);
                    },
            ),
          NooSettingsRow(
            icon: LucideIcons.plus,
            accent: true,
            label: const Text('Add account'),
            onTap: () {
              close();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginView(isAddingAccount: true),
                ),
              );
            },
          ),
          NooSettingsRow(
            icon: LucideIcons.settings,
            label: const Text('Manage accounts'),
            onTap: () {
              close();
              openSettings(context);
            },
          ),
        ],
      ),
    ];
  }

  if (NooLayout.isDesktop(context)) {
    showNooDialog(
      context,
      title: 'Switch account',
      children: [Builder(builder: (c) => Column(children: content(c)))],
    );
  } else {
    showNooSheet(
      context,
      children: [Builder(builder: (c) => Column(children: content(c)))],
    );
  }
}

/// A switcher row: avatar, name over host, and a check on the active one.
/// `NooSettingsRow` only takes an icon, not an avatar, hence its own row.
class _AccountSwitchRow extends StatelessWidget {
  final String name;
  final String host;
  final bool active;
  final VoidCallback? onTap;

  const _AccountSwitchRow({
    required this.name,
    required this.host,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NooSpace.md,
            vertical: 10,
          ),
          child: Row(
            spacing: 12,
            children: [
              NooAvatar(
                initials: accountInitial(name),
                current: active,
                size: 36,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.body.copyWith(
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: colors.fg1,
                      ),
                    ),
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.meta.copyWith(
                        height: 1.2,
                        color: colors.fg3,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(LucideIcons.check, size: 20, color: colors.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

/// The current user's avatar in the mobile top bar. Tap opens the accounts
/// sheet ([showAccountSwitcher]) by default - or [onTap], when the caller
/// overrides it (`AppTopBar` does this for
/// `SettingsController.navMenuStyle`'s `avatarMenu` option, which
/// repurposes this same button to open `showAvatarMenu` instead; avoids
/// this file importing `widgets/avatar_menu.dart`, which itself imports
/// this file for `openSettings`/`accountInitial`/`serverHost`). Swiping
/// up/down on it cycles to the next/previous saved account immediately,
/// with no confirmation, regardless of [onTap] - a shortcut that stays
/// available either way.
class ShellAvatarButton extends StatelessWidget {
  final double hitBox;
  final VoidCallback? onTap;

  /// Describes whatever [onTap] actually does - defaults to "Accounts"
  /// (the account switcher), but a caller overriding [onTap] should
  /// override this too so the tooltip/semantics describe the real action
  /// instead of a stale default.
  final String label;

  const ShellAvatarButton({
    super.key,
    this.hitBox = 48,
    this.onTap,
    this.label = 'Accounts',
  });

  Future<void> _handleVerticalSwipe(
    BuildContext context,
    DragEndDetails details,
  ) async {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;

    final session = context.read<SessionController>();
    final target = velocity < 0
        ? await session.cycleToNextAccount()
        : await session.cycleToPreviousAccount();
    if (target == null || !context.mounted) return;

    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to ${target.username}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onVerticalDragEnd: (details) =>
              _handleVerticalSwipe(context, details),
          child: SizedBox.square(
            dimension: hitBox,
            child: InkResponse(
              onTap: onTap ?? () => showAccountSwitcher(context),
              radius: hitBox / 2,
              child: Center(
                child: NooAvatar(
                  initials: accountInitial(session.username),
                  current: true,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [NooSearchField] that doesn't take input itself but opens
/// `SearchView` on tap - the shell's search entry point (iOS top bar,
/// desktop toolbar). Search has its own screen with results, so the field
/// here is only a launcher.
class ShellSearchLauncher extends StatelessWidget {
  final bool ios;
  final bool onSurface;

  const ShellSearchLauncher({
    super.key,
    this.ios = false,
    this.onSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openSearch(context),
          child: AbsorbPointer(
            child: ExcludeFocus(
              child: NooSearchField(
                placeholder: 'Search files',
                ios: ios,
                onSurface: onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
