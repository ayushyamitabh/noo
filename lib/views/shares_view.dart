import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../providers/server_provider.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/synced_header_scaffold.dart';

IconData _shareItemIcon(NextcloudItemType type) {
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

IconData _shareTypeIcon(ShareType type) {
  switch (type) {
    case ShareType.user:
      return Icons.person_rounded;
    case ShareType.group:
      return Icons.groups_rounded;
    case ShareType.publicLink:
      return Icons.link_rounded;
    case ShareType.email:
      return Icons.email_rounded;
    case ShareType.federated:
      return Icons.public_rounded;
    case ShareType.other:
      return Icons.share_rounded;
  }
}

class SharesView extends StatefulWidget {
  final ScrollController scrollController;

  const SharesView({super.key, required this.scrollController});

  @override
  State<SharesView> createState() => _SharesViewState();
}

class _SharesViewState extends State<SharesView> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.fetchShares(),
      );
    }

    final shares = provider.shares;

    final List<Widget> contentSlivers = [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Shared by me')),
              ButtonSegment(value: true, label: Text('Shared with me')),
            ],
            selected: {provider.sharesWithMe},
            onSelectionChanged: (set) => provider.setSharesWithMe(set.first),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),

      if (provider.isSharesLoading && shares.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (provider.sharesErrorMessage != null)
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
                    'Could not load shares',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.sharesErrorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: provider.fetchShares,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (shares.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  provider.sharesWithMe
                      ? 'Nothing has been shared with you'
                      : 'You haven\'t shared anything yet',
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
              final share = shares[index];
              return _buildShareTile(context, share, provider);
            }, childCount: shares.length),
          ),
        ),

      const SliverToBoxAdapter(child: SizedBox(height: 100)),
      const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
    ];

    return SyncedHeaderScaffold(
      scrollController: widget.scrollController,
      provider: provider,
      actions: const [MoreTabsButton(), ProfileAvatarButton()],
      onRefresh: provider.fetchShares,
      contentSlivers: contentSlivers,
    );
  }

  Widget _buildShareTile(
    BuildContext context,
    NextcloudShare share,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = colorScheme.primary;

    final withWhom = share.sharedWithMe
        ? 'From ${share.ownerDisplayName}'
        : (share.sharedWithDisplayName != null
              ? 'With ${share.sharedWithDisplayName}'
              : 'Shared link');

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
                  _shareItemIcon(share.itemType),
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
                      share.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            _shareTypeIcon(share.shareType),
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$withWhom • ${DateFormat.yMMMd().format(share.sharedAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.link_off_rounded, color: colorScheme.error),
                tooltip: share.sharedWithMe ? 'Remove' : 'Unshare',
                onPressed: () => _confirmUnshare(context, provider, share),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmUnshare(
    BuildContext context,
    ServerProvider provider,
    NextcloudShare share,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(share.sharedWithMe ? 'Remove Share' : 'Unshare'),
          content: Text(
            share.sharedWithMe
                ? 'Remove "${share.name}" shared with you by ${share.ownerDisplayName}?'
                : 'Stop sharing "${share.name}"?',
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
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deleteShare(share);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Removed share for ${share.name}'
              : 'Failed to remove share for ${share.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
