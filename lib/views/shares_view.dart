import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/nextcloud_share.dart';
import '../providers/files_controller.dart';
import '../providers/shares_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/core/noo_segmented_control.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/share_sheet.dart';
import '../widgets/tabs/tab_state_slivers.dart';

/// Which slice of [SharesController.shares] is on screen - `With you` maps
/// straight onto the controller's own `sharedWithMe: true` fetch, but the
/// controller only ever exposes one boolean scope, so `By you` and `Links`
/// both use its `sharedWithMe: false` fetch and are told apart client-side
/// by [NextcloudShare.shareType] (see `_visibleShares`). `SharesController`
/// caches each of its two scopes after its first fetch, so switching
/// between any of the three - including back to `With you` after leaving
/// it - only re-fetches a scope that's never been loaded yet, not on every
/// single switch.
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

  /// This tab's own shell top bar, planted as its first sliver - see
  /// `buildAppTabView`'s doc comment. Null on desktop and while picking.
  final PreferredSizeWidget? topBar;

  const SharesView({super.key, required this.scrollController, this.topBar});

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
      if (widget.topBar != null) topBarSliver(widget.topBar!),
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
        tabEmptySliver(
          context,
          icon: LucideIcons.share2,
          message: _emptyMessage(),
        )
      else if (isDesktop)
        _buildDesktopTable(context, shares)
      else
        _buildMobileList(context, shares),
      ...tabBottomInsetSlivers(context),
    ];

    return ColoredBox(
      color: NooLayout.contentBackground(context),
      child: RefreshIndicator(
        key: TabRefreshScope.keyOf(context),
        color: colors.accent,
        backgroundColor: colors.surface,
        onRefresh: sharesController.fetchAll,
        // See files_view.dart's identical fix - without this, the sticky
        // controls row rides up under the status bar once the floating top
        // bar above it fully collapses.
        child: SafeArea(
          top: true,
          bottom: false,
          child: CustomScrollView(
            controller: widget.scrollController,
            // See files_view.dart's identical fix - without this, pull-to-
            // refresh can't be triggered on an empty or single-item list.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: contentSlivers,
          ),
        ),
      ),
    );
  }

  List<NextcloudShare> _visibleShares(SharesController c) {
    switch (_scope) {
      case _ShareScope.withYou:
        return c.shares;
      case _ShareScope.byYou:
        return c.shares
            .where((s) => s.shareType != ShareType.publicLink)
            .toList();
      case _ShareScope.links:
        return c.shares
            .where((s) => s.shareType == ShareType.publicLink)
            .toList();
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

  // A lazily-built `SliverList`, not `NooGroupedList` (its own `Column`
  // isn't lazy - see files_view.dart's `_buildMobileRow` doc comment, and
  // trash_view.dart's `_buildMobileList`, which had the same bug: a heavy
  // account's full share list built eagerly up front). Each row still
  // reads as one continuous radius-20 card via per-row corner rounding +
  // a 1px `line` divider.
  Widget _buildMobileList(BuildContext context, List<NextcloudShare> shares) {
    final colors = context.nooColors;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final share = shares[index];
          final row = NooFileRow(
            kind: NooFileKind.from(
              name: share.name,
              isDirectory: share.isFolder,
            ),
            name: share.name,
            meta:
                '${share.ownerDisplayName} · ${_permissionLabel(share.permissions)}',
            iosStyle: NooLayout.iosStyle(context),
            onTap: () => _openShareSheet(context, share),
            trailing: Icon(_shareTypeIcon(share.shareType), size: 16),
          );
          final isFirst = index == 0;
          final isLast = index == shares.length - 1;
          return Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: isFirst
                      ? const Radius.circular(NooRadii.card)
                      : Radius.zero,
                  bottom: isLast
                      ? const Radius.circular(NooRadii.card)
                      : Radius.zero,
                ),
                child: row,
              ),
              if (!isLast) Container(height: 1, color: colors.line),
            ],
          );
        }, childCount: shares.length),
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
            return const NooFileTableHeader(
              col2Label: 'Owner',
              col3Label: 'Permission',
            );
          }
          final share = shares[index - 1];
          return NooFileTableRow(
            kind: NooFileKind.from(
              name: share.name,
              isDirectory: share.isFolder,
            ),
            name: share.name,
            col2: share.ownerDisplayName,
            col3: _permissionLabel(share.permissions),
            onTap: () => _openShareSheet(context, share),
          );
        }, childCount: shares.length + 1),
      ),
    );
  }

  /// Every row's whole-row tap - a share only carries enough metadata for
  /// its own row, not the size/dates the Share sheet's header needs, so
  /// this fetches the real item first (see `FilesController.fetchItemAtPath`)
  /// rather than opening the sheet straight from [share]. Reused by every
  /// scope (With you/By you/Links) - the Share sheet is the one place that
  /// already knows how to copy a link or remove access, so there's no
  /// separate overflow menu here any more.
  Future<void> _openShareSheet(
    BuildContext context,
    NextcloudShare share,
  ) async {
    final files = context.read<FilesController>();
    final messenger = ScaffoldMessenger.of(context);
    final item = await files.fetchItemAtPath(share.path);
    if (!context.mounted) return;
    if (item == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not find this item - it may have moved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await ShareSheet.show(context, item);
    // The sheet manages shares through `ItemOperations`, not this tab's own
    // `SharesController` (see its `deleteShare`'s doc comment) - refetch so
    // a share added/removed from inside it doesn't leave this list stale.
    if (context.mounted) context.read<SharesController>().fetchAll();
  }
}
