import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_share.dart';
import '../providers/files_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/shares_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/core/noo_segmented_control.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/tabs/tab_state_slivers.dart';

/// Which slice of [SharesController.shares] is on screen - `With you` maps
/// straight onto the controller's own `sharedWithMe: true` fetch, but the
/// controller only ever exposes one boolean scope, so `By you` and `Links`
/// both use its `sharedWithMe: false` fetch and are told apart client-side
/// by [NextcloudShare.shareType] (see `_visibleShares`) - `Links` and
/// `By you` never trigger a re-fetch when switching between each other,
/// only when crossing to/from `With you`.
enum _ShareScope { withYou, byYou, links }

IconData _shareTypeIcon(ShareType type) {
  switch (type) {
    case ShareType.user:
      return LucideIcons.user;
    case ShareType.group:
      return LucideIcons.users;
    case ShareType.publicLink:
      return LucideIcons.link;
    case ShareType.email:
      return LucideIcons.mail;
    case ShareType.federated:
      return LucideIcons.globe;
    case ShareType.other:
      return LucideIcons.share2;
  }
}

/// "Can edit" when any write bit (update/create/delete) is set on the OCS
/// share permissions bitmask, "Can view" otherwise - kept to the two
/// broad buckets the row's one-line meta has room for.
String _permissionLabel(int permissions) {
  const update = 2, create = 4, delete = 8;
  final canWrite = permissions & (update | create | delete) != 0;
  return canWrite ? 'Can edit' : 'Can view';
}

class SharesView extends StatefulWidget {
  final ScrollController scrollController;

  const SharesView({super.key, required this.scrollController});

  @override
  State<SharesView> createState() => _SharesViewState();
}

class _SharesViewState extends State<SharesView> {
  bool _requested = false;
  // Mirrors `SharesController.sharedWithMe`'s own default (false, "shared
  // by me") so the first fetch this triggers matches what's shown.
  _ShareScope _scope = _ShareScope.byYou;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final sharesController = context.watch<SharesController>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => sharesController.fetchAll(),
      );
    }

    final shares = _visibleShares(sharesController);
    final isDesktop = NooLayout.isDesktop(context);

    final List<Widget> contentSlivers = [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          NooLayout.gutter(context),
          NooSpace.md,
          NooLayout.gutter(context),
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: NooSegmentedControl<_ShareScope>(
            value: _scope,
            options: const [
              NooSegmentOption(value: _ShareScope.withYou, label: 'With you'),
              NooSegmentOption(value: _ShareScope.byYou, label: 'By you'),
              NooSegmentOption(value: _ShareScope.links, label: 'Links'),
            ],
            onChanged: (scope) => _selectScope(sharesController, scope),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: NooSpace.md)),
      if (sharesController.isLoading && shares.isEmpty)
        tabLoadingSliver
      else if (sharesController.errorMessage != null)
        tabErrorSliver(
          context,
          title: 'Could not load shares',
          message: sharesController.errorMessage!,
          onRetry: sharesController.fetchAll,
        )
      else if (shares.isEmpty)
        tabEmptySliver(context, icon: LucideIcons.share2, message: _emptyMessage())
      else if (isDesktop)
        _buildDesktopTable(context, shares)
      else
        _buildMobileList(context, shares),
      ...tabBottomInsetSlivers,
    ];

    return ColoredBox(
      color: colors.bg,
      child: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.surface,
        onRefresh: sharesController.fetchAll,
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: contentSlivers,
        ),
      ),
    );
  }

  List<NextcloudShare> _visibleShares(SharesController c) {
    switch (_scope) {
      case _ShareScope.withYou:
        return c.shares;
      case _ShareScope.byYou:
        return c.shares.where((s) => s.shareType != ShareType.publicLink).toList();
      case _ShareScope.links:
        return c.shares.where((s) => s.shareType == ShareType.publicLink).toList();
    }
  }

  String _emptyMessage() {
    switch (_scope) {
      case _ShareScope.withYou:
        return 'Nothing has been shared with you';
      case _ShareScope.byYou:
        return "You haven't shared anything yet";
      case _ShareScope.links:
        return 'No share links yet';
    }
  }

  void _selectScope(SharesController c, _ShareScope scope) {
    setState(() => _scope = scope);
    // No-ops (see `SharesController.setSharedWithMe`) when moving between
    // `byYou`/`links`, which share the same `sharedWithMe: false` fetch.
    c.setSharedWithMe(scope == _ShareScope.withYou);
  }

  Widget _buildMobileList(BuildContext context, List<NextcloudShare> shares) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
      sliver: SliverToBoxAdapter(
        child: NooGroupedList(
          children: [
            for (final share in shares)
              NooFileRow(
                kind: NooFileKind.from(name: share.name, isDirectory: share.isFolder),
                name: share.name,
                meta: '${share.ownerDisplayName} · ${_permissionLabel(share.permissions)}',
                iosStyle: NooLayout.iosStyle(context),
                onTap: share.isFolder ? () => _openFolder(context, share) : null,
                trailing: Icon(_shareTypeIcon(share.shareType), size: 16),
                onMore: () => _confirmUnshare(context, share),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(BuildContext context, List<NextcloudShare> shares) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: NooSpace.xl,
        vertical: NooSpace.xs,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == 0) {
            return const NooFileTableHeader(col2Label: 'Owner', col3Label: 'Permission');
          }
          final share = shares[index - 1];
          return NooFileTableRow(
            kind: NooFileKind.from(name: share.name, isDirectory: share.isFolder),
            name: share.name,
            col2: share.ownerDisplayName,
            col3: _permissionLabel(share.permissions),
            onTap: share.isFolder ? () => _openFolder(context, share) : null,
            onMore: () => _confirmUnshare(context, share),
          );
        }, childCount: shares.length + 1),
      ),
    );
  }

  /// Only folders are safely tappable - unlike Recent/Favorites, a share
  /// doesn't carry the size/mime-type `FileViewerScreen` needs, so opening
  /// a file share here would have to synthesize that data instead of
  /// reading it, same as the original screen (no tap action at all).
  void _openFolder(BuildContext context, NextcloudShare share) {
    context.read<FilesController>().navigateToAbsoluteFolder(share.path);
    context.read<SettingsController>().requestTab(AppTab.files);
  }

  Future<void> _confirmUnshare(
    BuildContext context,
    NextcloudShare share,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(share.sharedWithMe ? 'Remove share' : 'Unshare'),
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
    final success = await context.read<SharesController>().deleteShare(share);
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
