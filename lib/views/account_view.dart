import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../models/saved_account.dart';
import '../providers/server_provider.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_glass_container.dart';
import '../widgets/seek_bar_painter.dart';
import '../widgets/synced_header_scaffold.dart' show formatQuota;
import 'login_view.dart';

class AccountView extends StatelessWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final quota = provider.quota;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          physics: const BouncingScrollPhysics(),
          children: [
            // User Profile & Storage Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colorScheme.primary,
                        child: Text(
                          (quota?.userName ?? provider.username)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quota?.userName ?? provider.username,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              quota?.email ?? provider.username,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Storage Quota',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        quota != null ? formatQuota(quota) : 'Loading…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: quota != null && quota.totalBytes > 0
                          ? quota.usagePercentage
                          : 0.1,
                      minHeight: 10,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          Uri.tryParse(provider.serverUrl)?.host ??
                              provider.serverUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        quota != null
                            ? (quota.totalBytes > 0
                                  ? '${(quota.usagePercentage * 100).toStringAsFixed(1)}% used'
                                  : 'Unlimited storage')
                            : '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (quota != null && quota.groups.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(
                      'Groups',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final group in quota.groups)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              group,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Refresh cached data',
                        onPressed: () async {
                          await provider.refreshData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Refreshed WebDAV data'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded),
                        tooltip: 'Logout',
                        color: Colors.orange.shade700,
                        onPressed: () => _handleLogout(context, provider),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Remove account',
                        color: colorScheme.error,
                        onPressed: () =>
                            _confirmRemoveActive(context, provider),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Accounts Section
            Text(
              'Accounts',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _AccountsCard(),
            const SizedBox(height: 24),

            // Security Section
            Text(
              'Security',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _SecurityCard(),
            const SizedBox(height: 24),

            // Device Sync Section
            Text(
              'Device Sync',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _DeviceSyncCard(),
            const SizedBox(height: 24),

            // Material You Design Settings
            Text(
              'Material You Aesthetics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accent Color',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.useDynamicColor
                          ? 'Matching your wallpaper'
                          : 'Custom color',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _AccentSwatch(
                          isSelected: provider.useDynamicColor,
                          onTap: () => provider.setUseDynamicColor(true),
                          borderColor: colorScheme.onSurface,
                          background: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.wallpaper_rounded,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        ...AppTheme.seedColors.map((color) {
                          final isSelected =
                              !provider.useDynamicColor &&
                              provider.seedColor == color;
                          return _AccentSwatch(
                            isSelected: isSelected,
                            onTap: () => provider.setSeedColor(color),
                            borderColor: colorScheme.onSurface,
                            background: color,
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(
                      'Theme Mode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {provider.themeMode},
                        onSelectionChanged: (set) =>
                            provider.setThemeMode(set.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('AMOLED Black'),
                      subtitle: const Text(
                        'Use pure black backgrounds in dark mode',
                      ),
                      value: provider.amoledDark,
                      onChanged: provider.setAmoledDark,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // UI Settings
            Text(
              'UI',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _BottomBarAppearanceCard(),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('Tap Tab to Scroll to Top'),
                subtitle: const Text(
                  'Tapping the current bottom bar tab scrolls its list back to the top',
                ),
                value: provider.tapTabToScrollTop,
                onChanged: provider.setTapTabToScrollTop,
              ),
            ),
            const SizedBox(height: 24),

            // Bottom Nav Tabs
            Text(
              'Bottom Bar Tabs',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Drag to reorder, tap the star to set the default, toggle to show or hide',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            const _TabSettingsCard(),
            const SizedBox(height: 24),

            // Swipe Actions
            Text(
              'Files Swipe Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose what swiping a file left or right does in list view',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            const _SwipeActionsCard(),
            const SizedBox(height: 24),

            // Media Player
            Text(
              'Media Player',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the seek bar style used when playing videos',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            const _MediaPlayerCard(),
            const SizedBox(height: 24),

            // Files Cache
            Text(
              'Files Cache',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Reuse a folder\'s listing instead of refetching it on every visit',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            const _CacheSettingsCard(),
          ],
        ),
      ),
    );
  }

  /// Logout keeps the account saved (see [ServerProvider.logout]) so it's
  /// harmless/reversible from a one-tap resume on the login screen -
  /// doesn't need a confirmation dialog the way [_confirmRemoveActive] does.
  Future<void> _handleLogout(
    BuildContext context,
    ServerProvider provider,
  ) async {
    final navigator = Navigator.of(context);
    await provider.logout();
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _confirmRemoveActive(
    BuildContext context,
    ServerProvider provider,
  ) async {
    final host = Uri.tryParse(provider.serverUrl)?.host ?? provider.serverUrl;
    final hasOtherAccounts = provider.accounts.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Account'),
          content: Text(
            hasOtherAccounts
                ? 'Remove ${provider.username} ($host)? Another saved account will become active.'
                : 'Remove ${provider.username} ($host)? You can add it again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final id = provider.activeAccountId;
    if (id == null) return;
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    await provider.removeAccount(id);
    // Only pop back to the root route if that was the last account and the
    // session actually ended - if it fell back to another saved account,
    // Settings just keeps showing (now for that account) instead.
    if (!provider.isLoggedIn) {
      navigator.popUntil((route) => route.isFirst);
    }
  }
}

/// Lists every saved account, letting the user switch to an inactive one,
/// remove any of them, or add another via [LoginView] pushed in "add
/// account" mode.
class _AccountsCard extends StatelessWidget {
  const _AccountsCard();

  Future<void> _confirmRemove(
    BuildContext context,
    ServerProvider provider,
    SavedAccount account,
  ) async {
    final isActive = account.id == provider.activeAccountId;
    final host = Uri.tryParse(account.serverUrl)?.host ?? account.serverUrl;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Account'),
          content: Text(
            isActive && provider.accounts.length > 1
                ? 'Remove ${account.username} ($host)? Another saved account will become active.'
                : 'Remove ${account.username} ($host)? You can add it again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      if (!context.mounted) return;
      final navigator = Navigator.of(context);
      await provider.removeAccount(account.id);
      // Only when this was the last saved account does isLoggedIn drop to
      // false and main.dart swap the root route to LoginView underneath -
      // pop back to it then, rather than leaving Settings stranded on top.
      // Removing a non-active account, or falling back to another one,
      // both keep the user logged in, so Settings should just stay put.
      if (!provider.isLoggedIn) {
        navigator.popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();
    final accounts = provider.accounts;

    return Card(
      child: Column(
        children: [
          for (final account in accounts) ...[
            _AccountRow(
              account: account,
              isActive: account.id == provider.activeAccountId,
              onTap: account.id == provider.activeAccountId
                  ? null
                  : () => provider.switchAccount(account.id),
              onRemove: () => _confirmRemove(context, provider, account),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
          ListTile(
            leading: const Icon(Icons.add_circle_outline_rounded),
            title: const Text('Add account'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginView(isAddingAccount: true),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final SavedAccount account;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  const _AccountRow({
    required this.account,
    required this.isActive,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(account.serverUrl)?.host ?? account.serverUrl;
    final initial = account.username.isNotEmpty
        ? account.username[0].toUpperCase()
        : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorScheme.primary,
        child: Text(
          initial,
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(account.username),
      subtitle: Text(host),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            Icon(Icons.check_circle_rounded, color: colorScheme.primary),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove account',
            onPressed: onRemove,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Login lock: gates opening the app, switching accounts, and revealing
/// hidden files behind the device's own PIN/biometric credential (see
/// AppLockService - this app never stores or handles a PIN itself).
class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  Future<void> _handleLoginLockChanged(
    BuildContext context,
    ServerProvider provider,
    bool value,
  ) async {
    final success = value
        ? await provider.setupLoginLock()
        : await provider.disableLoginLock();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? "Could not set up login lock - make sure this device has a PIN, pattern, password, or biometric configured"
                : 'Could not turn off login lock',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Login Lock'),
            subtitle: const Text(
              "Require this device's PIN or biometric to open Noo",
            ),
            value: provider.loginLockEnabled,
            onChanged: (value) =>
                _handleLoginLockChanged(context, provider, value),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Lock account switching'),
            subtitle: const Text('Unlock to switch between saved accounts'),
            value: provider.lockAccountSwitching,
            onChanged: provider.loginLockEnabled
                ? provider.setLockAccountSwitching
                : null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_rounded),
            title: const Text('Lock hidden files'),
            subtitle: const Text('Unlock to reveal hidden files and folders'),
            value: provider.lockHiddenFiles,
            onChanged: provider.loginLockEnabled
                ? provider.setLockHiddenFiles
                : null,
          ),
        ],
      ),
    );
  }
}

class _DeviceSyncCard extends StatefulWidget {
  const _DeviceSyncCard();

  @override
  State<_DeviceSyncCard> createState() => _DeviceSyncCardState();
}

class _DeviceSyncCardState extends State<_DeviceSyncCard> {
  bool _syncingNow = false;

  Future<void> _syncNow(ServerProvider provider) async {
    setState(() => _syncingNow = true);
    try {
      await SyncService.syncNow(provider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start sync: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final folders = provider.syncedPaths;
    final everything = provider.syncEverything;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_rounded),
            title: const Text('Sync everything'),
            subtitle: const Text(
              'Mirror the whole account instead of picking folders',
            ),
            value: everything,
            onChanged: provider.setSyncEverything,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          if (everything)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Every folder in this account is being synced to this '
                'device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'No folders synced yet - select a folder in Files and use '
                '"Sync to device" to mirror it here for offline access.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final folder in folders) ...[
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: Text(folder),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Stop syncing',
                  onPressed: () => provider.removeSyncedPath(folder),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          SwitchListTile(
            secondary: const Icon(Icons.signal_cellular_alt_rounded),
            title: const Text('Sync on cellular'),
            subtitle: const Text('Off = background sync only runs on Wi-Fi'),
            value: provider.syncOnCellular,
            onChanged: provider.setSyncOnCellular,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: _syncingNow
                ? const Padding(
                    padding: EdgeInsets.all(2),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            title: const Text('Sync now'),
            enabled: (everything || folders.isNotEmpty) && !_syncingNow,
            onTap: () => _syncNow(provider),
          ),
        ],
      ),
    );
  }
}

class _BottomBarAppearanceCard extends StatefulWidget {
  const _BottomBarAppearanceCard();

  @override
  State<_BottomBarAppearanceCard> createState() =>
      _BottomBarAppearanceCardState();
}

class _BottomBarAppearanceCardState extends State<_BottomBarAppearanceCard> {
  // Mirrors the provider values locally so the slider thumb and the live
  // preview track the drag gesture on every frame. Driving them straight off
  // `provider.bottomBar*` instead would tie the slider's own responsiveness
  // to a full Provider-wide rebuild — including the expensive BackdropFilter
  // blur in the preview — which can't keep up with fast drag ticks and makes
  // the thumb appear stuck until the next unrelated rebuild.
  double? _opacity;
  double? _blur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final opacity = _opacity ?? provider.bottomBarOpacity;
    final blur = _blur ?? provider.bottomBarBlur;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bottom Bar Appearance',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Adjust the glass effect of the floating bottom bar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Live preview
            Container(
              height: 140,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.tertiary,
                    colorScheme.secondary,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PreviewPatternPainter()),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FrostedGlassContainer(
                        opacity: opacity,
                        blurSigma: blur,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.photo_library_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.history_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Opacity', style: theme.textTheme.bodyMedium),
                Text(
                  '${(opacity * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Slider(
              value: opacity,
              min: 0.1,
              max: 1.0,
              onChanged: (value) => setState(() => _opacity = value),
              onChangeEnd: provider.setBottomBarOpacity,
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Blur', style: theme.textTheme.bodyMedium),
                Text(
                  blur.round().toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Slider(
              value: blur,
              min: 0,
              max: 40,
              onChanged: (value) => setState(() => _blur = value),
              onChangeEnd: provider.setBottomBarBlur,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 24) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPatternPainter oldDelegate) => false;
}

class _AccentSwatch extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Color borderColor;
  final Color background;
  final Widget? child;

  const _AccentSwatch({
    required this.isSelected,
    required this.onTap,
    required this.borderColor,
    required this.background,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: borderColor, width: 3) : null,
        ),
        child: child,
      ),
    );
  }
}

class _SwipeActionsCard extends StatelessWidget {
  const _SwipeActionsCard();

  String _label(SwipeAction action) {
    switch (action) {
      case SwipeAction.none:
        return 'None';
      case SwipeAction.favorite:
        return 'Favorite';
      case SwipeAction.delete:
        return 'Delete';
      case SwipeAction.share:
        return 'Share';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ServerProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            _buildRow(
              context,
              theme,
              label: 'Swipe right',
              value: provider.swipeRightAction,
              onChanged: provider.setSwipeRightAction,
            ),
            const Divider(height: 1),
            _buildRow(
              context,
              theme,
              label: 'Swipe left',
              value: provider.swipeLeftAction,
              onChanged: provider.setSwipeLeftAction,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required SwipeAction value,
    required ValueChanged<SwipeAction> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DropdownButton<SwipeAction>(
            value: value,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(12),
            items: SwipeAction.values
                .map((a) => DropdownMenuItem(value: a, child: Text(_label(a))))
                .toList(),
            onChanged: (a) {
              if (a != null) onChanged(a);
            },
          ),
        ],
      ),
    );
  }
}

String _seekBarStyleLabel(MediaProgressBarStyle style) {
  switch (style) {
    case MediaProgressBarStyle.classic:
      return 'Default';
    case MediaProgressBarStyle.wavy:
      return 'Wavy';
    case MediaProgressBarStyle.slim:
      return 'Slim';
    case MediaProgressBarStyle.squiggly:
      return 'Squiggly';
  }
}

class _MediaPlayerCard extends StatelessWidget {
  const _MediaPlayerCard();

  Future<void> _openPicker(
    BuildContext context,
    ServerProvider provider,
  ) async {
    final selected = await showDialog<MediaProgressBarStyle>(
      context: context,
      builder: (_) =>
          _SeekBarStyleDialog(current: provider.mediaProgressBarStyle),
    );
    if (selected != null) provider.setMediaProgressBarStyle(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          'Seek bar style',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(_seekBarStyleLabel(provider.mediaProgressBarStyle)),
        trailing: SizedBox(
          width: 64,
          height: 24,
          child: SeekBarPreview(
            style: provider.mediaProgressBarStyle,
            playedColor: colorScheme.primary,
            trackColor: colorScheme.outlineVariant,
          ),
        ),
        onTap: () => _openPicker(context, provider),
      ),
    );
  }
}

/// A grid of the four [MediaProgressBarStyle] presets, each shown as a live
/// preview of the real seek bar painter, matching the preset-picker pattern
/// other Material You media players use for this same setting.
class _SeekBarStyleDialog extends StatelessWidget {
  final MediaProgressBarStyle current;

  const _SeekBarStyleDialog({required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seek Bar Style',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                for (final style in MediaProgressBarStyle.values)
                  _SeekBarStyleOption(
                    style: style,
                    isSelected: style == current,
                    onTap: () => Navigator.pop(context, style),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekBarStyleOption extends StatelessWidget {
  final MediaProgressBarStyle style;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeekBarStyleOption({
    required this.style,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 100,
                    height: 28,
                    child: SeekBarPreview(
                      style: style,
                      playedColor: colorScheme.primary,
                      trackColor: colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _seekBarStyleLabel(style),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CacheSettingsCard extends StatelessWidget {
  const _CacheSettingsCard();

  String _label(CachePolicy policy) {
    switch (policy) {
      case CachePolicy.never:
        return 'Never cache';
      case CachePolicy.interval:
        return 'Refresh periodically';
      case CachePolicy.manual:
        return 'Refresh manually only';
    }
  }

  String _description(CachePolicy policy) {
    switch (policy) {
      case CachePolicy.never:
        return 'Every visit to a folder fetches it fresh';
      case CachePolicy.interval:
        return 'Reuse a folder\'s listing until it\'s a few minutes old';
      case CachePolicy.manual:
        return 'Reuse a folder\'s listing until you pull to refresh';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            RadioGroup<CachePolicy>(
              groupValue: provider.cachePolicy,
              onChanged: (value) {
                if (value != null) provider.setCachePolicy(value);
              },
              child: Column(
                children: [
                  for (final policy in CachePolicy.values)
                    RadioListTile<CachePolicy>(
                      value: policy,
                      title: Text(_label(policy)),
                      subtitle: Text(_description(policy)),
                    ),
                ],
              ),
            ),
            if (provider.cachePolicy == CachePolicy.interval)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Refresh interval',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '${provider.cacheIntervalMinutes} min',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: provider.cacheIntervalMinutes.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: '${provider.cacheIntervalMinutes} min',
                      onChanged: (value) =>
                          provider.setCacheIntervalMinutes(value.round()),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabSettingsCard extends StatelessWidget {
  const _TabSettingsCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorderItem: (oldIndex, newIndex) {
          final order = List<AppTab>.from(provider.tabOrder);
          final tab = order.removeAt(oldIndex);
          order.insert(newIndex, tab);
          provider.setTabOrder(order);
        },
        children: [
          for (final tab in provider.tabOrder)
            _TabConfigRow(
              key: ValueKey(tab),
              tab: tab,
              isVisible: !provider.hiddenTabs.contains(tab),
              isDefault: provider.defaultTab == tab,
              onVisibilityChanged: (value) {
                final error = provider.setTabHidden(tab, !value);
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(error),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              onSetDefault: () => provider.setDefaultTab(tab),
            ),
        ],
      ),
    );
  }
}

class _TabConfigRow extends StatelessWidget {
  final AppTab tab;
  final bool isVisible;
  final bool isDefault;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback onSetDefault;

  const _TabConfigRow({
    required super.key,
    required this.tab,
    required this.isVisible,
    required this.isDefault,
    required this.onVisibilityChanged,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        tab.icon,
        color: isVisible
            ? colorScheme.onSurfaceVariant
            : colorScheme.outlineVariant,
      ),
      title: Text(
        tab.label,
        style: TextStyle(color: isVisible ? null : colorScheme.outline),
      ),
      subtitle: isDefault ? const Text('Default tab') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isDefault
                  ? Colors.amber.shade700
                  : colorScheme.outlineVariant,
            ),
            tooltip: 'Set as default tab',
            onPressed: isVisible && !isDefault ? onSetDefault : null,
          ),
          Switch(value: isVisible, onChanged: onVisibilityChanged),
        ],
      ),
    );
  }
}
