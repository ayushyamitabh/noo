import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/synced_header_scaffold.dart';
import 'file_viewer_screen.dart';

IconData _recentItemIcon(NextcloudItemType type) {
  switch (type) {
    case NextcloudItemType.folder:
      return Icons.folder_rounded;
    case NextcloudItemType.image:
      return Icons.image_rounded;
    case NextcloudItemType.video:
      return Icons.movie_rounded;
    case NextcloudItemType.audio:
      return Icons.audiotrack_rounded;
    case NextcloudItemType.document:
      return Icons.description_rounded;
    case NextcloudItemType.archive:
      return Icons.folder_zip_rounded;
    case NextcloudItemType.file:
      return Icons.insert_drive_file_rounded;
  }
}

Color _recentItemIconColor(BuildContext context, NextcloudItemType type) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (type) {
    case NextcloudItemType.folder:
      return colorScheme.primary;
    case NextcloudItemType.image:
      return Colors.amber.shade700;
    case NextcloudItemType.video:
      return Colors.deepOrange.shade600;
    case NextcloudItemType.audio:
      return Colors.purple.shade600;
    case NextcloudItemType.document:
      return Colors.blue.shade700;
    case NextcloudItemType.archive:
      return Colors.teal.shade700;
    case NextcloudItemType.file:
      return colorScheme.outline;
  }
}

/// Recently modified files across the whole account (not folders), newest
/// first — see [ServerProvider.fetchRecent].
class RecentView extends StatefulWidget {
  final ScrollController scrollController;

  const RecentView({super.key, required this.scrollController});

  @override
  State<RecentView> createState() => _RecentViewState();
}

class _RecentViewState extends State<RecentView> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.fetchRecent(),
      );
    }

    final items = provider.recentItems;

    final List<Widget> contentSlivers = [
      const SliverToBoxAdapter(child: SizedBox(height: 16)),

      if (provider.isRecentLoading && items.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (provider.recentErrorMessage != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load recent files',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.recentErrorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: provider.fetchRecent,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'No recent files',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = items[index];
              return _buildTile(context, item, provider);
            }, childCount: items.length),
          ),
        ),

      const SliverToBoxAdapter(child: SizedBox(height: 100)),
      const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
    ];

    return SyncedHeaderScaffold(
      scrollController: widget.scrollController,
      provider: provider,
      actions: const [MoreTabsButton(), ProfileAvatarButton()],
      onRefresh: provider.fetchRecent,
      contentSlivers: contentSlivers,
    );
  }

  Widget _buildTile(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = _recentItemIconColor(context, item.type);
    final folderPath = item.path.substring(
      0,
      item.path.length - item.name.length,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openFile(context, item, provider),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _recentItemIcon(item.type),
                    color: iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        folderPath.isEmpty ? '/' : folderPath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat.yMMMd().add_jm().format(item.lastModified),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFile(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final siblings = provider.recentItems.where((i) => i.isMedia).toList();
    Navigator.push(
      context,
      FileViewerScreen.route(item: item, siblings: siblings),
    );
  }
}
