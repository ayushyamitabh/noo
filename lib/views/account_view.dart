import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';
import '../theme/app_theme.dart';

class AccountView extends StatelessWidget {
  final ScrollController scrollController;

  const AccountView({super.key, required this.scrollController});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 GB';
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final quota = provider.quota;

    return CustomScrollView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Account & Storage',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () {
                        _showLogoutConfirmation(context, provider);
                      },
                      icon: const Icon(Icons.logout_rounded),
                      tooltip: 'Log Out',
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Connected to ${provider.serverUrl}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

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
                              (quota?.userName ?? provider.username).substring(0, 1).toUpperCase(),
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: provider.isLoggedIn ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              provider.isLoggedIn ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: provider.isLoggedIn ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
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
                            quota != null
                                ? (quota.totalBytes > 0
                                    ? '${_formatBytes(quota.usedBytes)} of ${_formatBytes(quota.totalBytes)}'
                                    : '${_formatBytes(quota.usedBytes)} (Unlimited)')
                                : 'Live Server Storage',
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
                          value: quota != null && quota.totalBytes > 0 ? quota.usagePercentage : 0.1,
                          minHeight: 10,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        quota != null
                            ? (quota.totalBytes > 0
                                ? '${(quota.usagePercentage * 100).toStringAsFixed(1)}% used'
                                : 'Unlimited Storage Plan')
                            : 'WebDAV connection active',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Server Credentials Section
                Text(
                  'Server Connection Info',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dns_rounded),
                        title: const Text('Nextcloud Host'),
                        subtitle: Text(provider.serverUrl),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.person_rounded),
                        title: const Text('Logged In User'),
                        subtitle: Text(provider.username),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.refresh_rounded),
                        title: const Text('Refresh WebDAV Cache'),
                        onTap: () async {
                          await provider.refreshData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Refreshed WebDAV directory data'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
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
                          'Dynamic Accent Color Seed',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: AppTheme.seedColors.map((color) {
                            final isSelected = provider.seedColor == color;
                            return GestureDetector(
                              onTap: () => provider.setSeedColor(color),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(color: colorScheme.onSurface, width: 3)
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Theme Mode',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SegmentedButton<ThemeMode>(
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
                              onSelectionChanged: (set) => provider.setThemeMode(set.first),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  void _showLogoutConfirmation(BuildContext context, ServerProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: Text('Are you sure you want to disconnect from ${provider.serverUrl}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                Navigator.pop(context);
                provider.logout();
              },
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );
  }
}
