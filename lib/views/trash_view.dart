import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/synced_header_scaffold.dart';

IconData _trashItemIcon(NextcloudItemType type) {
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

class TrashView extends StatefulWidget {
  final ScrollController scrollController;

  const TrashView({super.key, required this.scrollController});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.fetchTrash(),
      );
    }

    final trash = provider.trashItems;

    final List<Widget> contentSlivers = [
      const SliverToBoxAdapter(child: SizedBox(height: 16)),

      if (provider.isTrashLoading && trash.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (provider.trashErrorMessage != null)
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
                    'Could not load trash',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.trashErrorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: provider.fetchTrash,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (trash.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'Trash is empty',
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
              final item = trash[index];
              return _buildTrashTile(context, item, provider);
            }, childCount: trash.length),
          ),
        ),

      const SliverToBoxAdapter(child: SizedBox(height: 100)),
      const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
    ];

    return SyncedHeaderScaffold(
      scrollController: widget.scrollController,
      provider: provider,
      actions: const [MoreTabsButton(), ProfileAvatarButton()],
      onRefresh: provider.fetchTrash,
      contentSlivers: contentSlivers,
    );
  }

  Widget _buildTrashTile(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = colorScheme.outline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
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
                  _trashItemIcon(item.type),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.deletedAt != null
                          ? 'Deleted ${DateFormat.yMMMd().format(item.deletedAt!)}'
                          : 'Deleted',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.restore_rounded),
                tooltip: 'Restore',
                color: colorScheme.primary,
                onPressed: () => _restore(context, provider, item),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_forever_rounded,
                  color: colorScheme.error,
                ),
                tooltip: 'Delete forever',
                onPressed: () => _confirmDeleteForever(context, provider, item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    ServerProvider provider,
    NextcloudItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.restoreTrashItem(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Restored ${item.name}' : 'Failed to restore ${item.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDeleteForever(
    BuildContext context,
    ServerProvider provider,
    NextcloudItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Forever'),
          content: Text(
            'Permanently delete "${item.name}"? This cannot be undone.',
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
              child: const Text('Delete Forever'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deleteTrashItemForever(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Deleted ${item.name}' : 'Failed to delete ${item.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
