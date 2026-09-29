import 'dart:async';
import 'dart:io';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../models/sync_status.dart';
import '../providers/files_controller.dart';
import '../providers/folder_browser.dart';
import '../providers/item_operations.dart';
import '../providers/offline_controller.dart';
import '../providers/pick_controller.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/sync_status_controller.dart';
import '../services/download_service.dart';
import '../services/nextcloud_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/files/file_breadcrumb_row.dart';
import '../widgets/files_controls_row.dart';
import '../widgets/item_icon.dart';
import '../widgets/manage_synced_folders_sheet.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/files/noo_file_tile.dart';
import '../widgets/noo/files/noo_status_icon.dart';
import '../widgets/noo/files/noo_swipe_action.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/lists/noo_selection_bar.dart';
import '../widgets/noo/lists/noo_settings_row.dart';
import '../widgets/noo/lists/noo_summary_card.dart';
import '../widgets/noo/media/noo_grid_card.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/noo/overlays/noo_sheet.dart';
import '../widgets/share_sheet.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/synced_header_scaffold.dart' show formatBytes;
import 'file_viewer_screen.dart';
import 'move_copy_destination_picker.dart';

/// The Files tab - and, with [offline] set, the Offline tab, which is the
/// same view over the device-sync mirror instead of the server: the Files
/// tab's folders filtered down to what's available offline. The two share
/// every display pref/control, the header, breadcrumbs, list/grid tiles and
/// thumbnails; [offline] only swaps the data source (`FolderBrowser`),
/// reads images from the local file instead of a server preview, and turns
/// off everything that needs the server (selection and its bulk actions,
/// swipe actions, the "+" menu, pick mode).
class FilesView extends StatefulWidget {
  final ScrollController scrollController;
  final bool offline;

  const FilesView({
    super.key,
    required this.scrollController,
    this.offline = false,
  });

  @override
  State<FilesView> createState() => _FilesViewState();
}

/// Slides+fades its child in on first build. Give it a [Key] that changes
/// whenever the folder changes (folder path + item id) so Flutter discards
/// and remounts the Element instead of just updating it in place - that's
/// what makes the whole visible list replay the animation on every folder
/// navigation, not just newly-appearing rows.
class _FolderEnterAnimation extends StatefulWidget {
  final Widget child;
  final bool fromRight;
  final int index;

  const _FolderEnterAnimation({
    super.key,
    required this.child,
    required this.fromRight,
    required this.index,
  });

  @override
  State<_FolderEnterAnimation> createState() => _FolderEnterAnimationState();
}

class _FolderEnterAnimationState extends State<_FolderEnterAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: Offset(widget.fromRight ? 0.12 : -0.12, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    // Staggered slightly by position so the list reads as sliding in as a
    // group rather than every row popping in simultaneously; capped so a
    // long list doesn't visibly trickle in for seconds.
    final delay = Duration(milliseconds: (widget.index * 12).clamp(0, 150));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// The 40px round icon button used in the controls row for a
/// screen-specific action ("Manage synced folders") that doesn't fit
/// `FilesControlsRow`'s chip set - same circular-hit-target treatment as
/// `NooFileRow`'s own overflow button.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return SizedBox.square(
      dimension: 40,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: colors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: 18, color: colors.fg1),
          ),
        ),
      ),
    );
  }
}

/// The thumbnail-area content for an image/video grid card: the actual
/// preview fills the area (cropped to cover, decoded at the painted size),
/// falling back to [fallback] (the file-kind icon) on error, with a play
/// badge for video - replaces `MediaGridTile` now that grid cards come from
/// `NooGridCard` instead of a hand-rolled column. Shared by the Files and
/// Offline tabs; they differ only in where the pixels come from
/// ([localFile] - the device-sync mirror vs. a server preview).
class _GridThumbnail extends StatelessWidget {
  final NextcloudItem item;
  final NextcloudService? service;
  final File? localFile;
  final Widget fallback;

  const _GridThumbnail({
    required this.item,
    required this.service,
    required this.localFile,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cachePixels =
            (constraints.maxWidth * MediaQuery.of(context).devicePixelRatio)
                .round();
        final provider = ResizeImage(
          localFile != null
              ? FileImage(localFile!) as ImageProvider
              : NetworkImage(item.previewUrl!, headers: service?.authHeaders),
          width: cachePixels,
          height: cachePixels,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: provider,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (ctx, err, stack) => Center(child: fallback),
            ),
            if (item.type == NextcloudItemType.video)
              const Center(
                child: Icon(
                  LucideIcons.circlePlay,
                  color: Colors.white,
                  size: 36,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FilesViewState extends State<FilesView> {
  final Set<String> _selectedIds = {};
  int _lastPathDepth = 1;

  bool get _isSelecting => _selectedIds.isNotEmpty;

  bool get _offline => widget.offline;

  /// The folder data source for this tab. Watches the concrete controller
  /// (that's what's registered as a provider), then hands it back as the
  /// [FolderBrowser] the rest of the view actually needs.
  FolderBrowser _browserOf(BuildContext context) => _offline
      ? context.watch<OfflineController>()
      : context.watch<FilesController>();

  /// The on-device copy of [item] for the Offline tab; null online, where
  /// thumbnails come from server previews instead.
  File? _localFileFor(BuildContext context, NextcloudItem item) =>
      _offline ? context.read<OfflineController>().localFileFor(item) : null;

  // (Online only - the Offline tab always reloads on first build, since a
  // local listing has no cheap "already loaded" signal.)
  // Normally FilesController's own account-activation listener fetches the
  // first listing (see FilesController._onAccountActivated) - but the
  // bottom nav collapses to just the Offline tab while
  // ConnectivityController briefly (mis)reports offline right after a cold
  // start, which stops this view (and therefore FilesController, a lazily-
  // constructed provider) from ever being built during the window that
  // listener fires in. Photos/Favorites already guard against exactly this
  // with their own one-shot self-fetch on first build; Files needs the same
  // fallback so a folder that's genuinely empty is distinguishable from one
  // that just never got its initial fetch.
  bool _requestedInitialLoad = false;

  void _toggleSelection(NextcloudItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedIds.remove(item.id)) _selectedIds.add(item.id);
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  /// Routes a tap on an item, in picking, selecting or plain-browsing mode
  /// alike - shared by the mobile row, the desktop table row and the grid
  /// card so all three navigate/select/open exactly the same way.
  void _handleItemTap(
    BuildContext context,
    NextcloudItem item, {
    required bool picking,
  }) {
    final browser = _browserOf(context);
    if (picking) {
      _handlePickTap(context, item);
    } else if (_isSelecting) {
      _toggleSelection(item);
    } else if (item.isFolder) {
      browser.navigateToFolder(item.path);
    } else {
      _openFile(context, item);
    }
  }

  /// Routes a tap on an item while Noo is acting as another app's picker:
  /// folders are still browsable, a matching file either toggles selection
  /// (multi-select requests) or immediately finishes the pick, and a
  /// non-matching file (wrong mime type for the caller) is rejected.
  void _handlePickTap(BuildContext context, NextcloudItem item) {
    final files = context.read<FilesController>();
    final pick = context.read<PickController>();
    if (item.isFolder) {
      files.navigateToFolder(item.path);
      return;
    }
    if (!pick.itemMatchesPickFilter(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This app can't accept this file type"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (pick.pickRequest!.allowMultiple) {
      _toggleSelection(item);
    } else {
      pick.confirmPick([item]);
    }
  }

  /// The bulk actions shown in the sticky selection toolbar for the
  /// currently-selected items, and reused for a single item's overflow
  /// sheet (see [_showItemActions]).
  List<SelectionAction> _buildSelectionActions(
    BuildContext context,
    List<NextcloudItem> selected,
  ) {
    // read, not watch: this builds a one-shot action list, and - unlike its
    // other call site inside build() - `_showItemActions` calls this from
    // an onTap/onPressed callback, well outside any build method. `watch`
    // there throws ("Tried to listen to a value exposed with provider...
    // outside of a widget's build method"), which - thrown from inside a
    // tap handler - just aborts silently before `showNooSheet` ever runs:
    // the exact "the menu does nothing" bug.
    final pick = context.read<PickController>();
    final sync = context.read<SyncStatusController>();
    if (pick.isPicking) {
      return [
        SelectionAction(
          kind: SelectionActionKind.favorite,
          icon: LucideIcons.check,
          label: 'Use ${selected.length} item(s)',
          onTap: () => pick.confirmPick(selected),
        ),
      ];
    }
    final allFavorited = selected.every((i) => i.isFavorite);
    final allSynced = selected.every((i) => sync.isPathSynced(i.path));
    final actions = [
      SelectionAction(
        kind: SelectionActionKind.favorite,
        icon: allFavorited ? LucideIcons.starOff : LucideIcons.star,
        label: allFavorited ? 'Remove from favorites' : 'Favorite',
        onTap: () => _favoriteSelected(context, selected),
      ),
      SelectionAction(
        kind: SelectionActionKind.share,
        icon: LucideIcons.share2,
        label: 'Share',
        onTap: () => selected.length == 1
            ? ShareSheet.show(context, selected.single)
            : _shareSelected(context, selected),
      ),
      SelectionAction(
        kind: SelectionActionKind.download,
        icon: LucideIcons.download,
        label: 'Download',
        onTap: () => _downloadSelected(context, selected),
      ),
      SelectionAction(
        kind: SelectionActionKind.delete,
        icon: LucideIcons.trash2,
        label: 'Delete',
        onTap: () => _confirmDeleteSelected(context, selected),
      ),
      SelectionAction(
        kind: SelectionActionKind.copy,
        icon: LucideIcons.copy,
        label: 'Copy',
        onTap: () => _moveOrCopySelected(context, selected, copy: true),
      ),
      SelectionAction(
        kind: SelectionActionKind.move,
        icon: LucideIcons.folderInput,
        label: 'Move',
        onTap: () => _moveOrCopySelected(context, selected, copy: false),
      ),
      if (selected.length == 1)
        SelectionAction(
          kind: SelectionActionKind.rename,
          icon: LucideIcons.filePen,
          label: 'Rename',
          onTap: () => _renameItem(selected.single),
        ),
      SelectionAction(
        kind: SelectionActionKind.sync,
        icon: LucideIcons.hardDriveDownload,
        label: allSynced ? 'Stop syncing to device' : 'Sync to device',
        onTap: () => _toggleSyncSelected(context, sync, selected),
      ),
      if (selected.length == 1)
        SelectionAction(
          kind: SelectionActionKind.details,
          icon: LucideIcons.info,
          label: 'Details',
          onTap: () => DetailsSheet.show(context, selected.single),
        ),
    ];
    return orderSelectionActions(
      actions,
      context.read<SettingsController>().selectionActionOrder,
    );
  }

  Future<void> _renameItem(NextcloudItem item) async {
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    // Not disposed here: `showDialog`'s Future resolves as soon as the pop
    // is initiated, while the dialog (and this controller's TextField)
    // is still mounted and mid-exit-transition - disposing immediately
    // crashes with a "still has listeners" assertion. It's a plain,
    // short-lived controller with no ticker/stream to leak, so letting it
    // get garbage-collected once the transition finishes is the safe call.
    if (newName == null || newName.isEmpty || newName == item.name) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ops = context.read<ItemOperations>();
    final success = await ops.renameItem(item, newName);
    _clearSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Renamed to $newName' : 'Failed to rename ${item.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareSelected(
    BuildContext context,
    List<NextcloudItem> items,
  ) async {
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Creating share link(s)…'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final lines = <String>[];
    for (final item in items) {
      final link = await ops.createShareLink(item);
      if (link != null) {
        lines.add(items.length > 1 ? '${item.name}: $link' : link);
      }
    }

    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    _clearSelection();
    if (lines.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create share link(s)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the share sheet'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// `SyncItemStatus` (this app's device-sync model) -> `NooSyncStatus`
  /// (the design system's row/table status-icon set). There's no "shared"
  /// signal on `NextcloudItem` today, so that half of the design's status
  /// set never lights up here - see the report for the promotion note.
  List<NooSyncStatus> _nooStatuses(SyncItemStatus status) {
    switch (status) {
      case SyncItemStatus.syncing:
        return const [NooSyncStatus.syncing];
      case SyncItemStatus.synced:
        return const [NooSyncStatus.synced];
      case SyncItemStatus.conflict:
        return const [NooSyncStatus.error];
      case SyncItemStatus.none:
        return const [];
    }
  }

  /// Real image/video thumbnail for a row/table tile, reusing
  /// `item_icon.dart`'s existing preview-loading (server or, offline, the
  /// local mirror file) rather than re-deriving it - null falls back to
  /// `NooFileTile`'s plain kind icon.
  Widget? _rowThumbnail(
    BuildContext context,
    NextcloudItem item,
    SessionController session,
    NooFileTileSize size,
  ) {
    final isMedia = _offline
        ? item.type == NextcloudItemType.image
        : (item.type == NextcloudItemType.image ||
                  item.type == NextcloudItemType.video) &&
              item.previewUrl != null;
    if (!isMedia) return null;
    return ItemThumbnail(
      item: item,
      service: session.service,
      localFile: _localFileFor(context, item),
      size: size.extent,
      borderRadius: size.radius,
      iconSize: size.iconSize,
    );
  }

  /// The user's configured swipe action for one side of a row, or null if
  /// that side is off or set to an action the design's two-slot
  /// `NooSwipeAction` has no room for (`SwipeAction.share` - still reachable
  /// via the row's overflow menu / the "Share" bulk action).
  NooSwipeActionSpec? _swipeSpec(
    SwipeAction action,
    NextcloudItem item,
    ItemOperations ops,
  ) {
    switch (action) {
      case SwipeAction.favorite:
        return NooSwipeActionSpec(
          kind: NooSwipeActionKind.favorite,
          onTriggered: () => ops.toggleItemFavorite(item),
        );
      case SwipeAction.delete:
        return NooSwipeActionSpec(
          kind: NooSwipeActionKind.delete,
          onTriggered: () => _confirmAndDeleteViaSwipe(item),
        );
      case SwipeAction.share:
      case SwipeAction.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    // Display prefs (grid/list, filters, sort) live on FilesController for
    // both tabs; `browser` is the tab's own folder listing.
    final files = context.watch<FilesController>();
    final browser = _browserOf(context);
    final sync = context.watch<SyncStatusController>();
    final isDesktop = NooLayout.isDesktop(context);
    final gutter = NooLayout.gutter(context);

    if (!_requestedInitialLoad) {
      _requestedInitialLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_offline || (browser.items.isEmpty && !browser.isLoading)) {
          browser.reload();
        }
      });
    }

    final pathDepth = browser.pathStack.length;
    final navigatingDeeper = pathDepth > _lastPathDepth;
    _lastPathDepth = pathDepth;

    final hasBreadcrumbs = browser.pathStack.length > 1;
    final selectedItems = browser.items
        .where((i) => _selectedIds.contains(i.id))
        .toList();

    final topRow = _isSelecting
        ? _buildSelectionBar(context, selectedItems)
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              NooSpace.sm,
              NooSpace.sm,
              NooSpace.sm,
              NooSpace.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilesControlsRow(
                        folderPath: browser.currentFolderPath,
                        showStorageScope: !_offline,
                      ),
                    ),
                    if (_offline) ...[
                      const SizedBox(width: NooSpace.xs),
                      _HeaderIconButton(
                        icon: LucideIcons.folderSync,
                        tooltip: 'Manage synced folders',
                        onTap: () => ManageSyncedFoldersSheet.show(context),
                      ),
                    ],
                  ],
                ),
                if (hasBreadcrumbs) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: FileBreadcrumbRow(
                      pathStack: browser.pathStack,
                      onTap: (index) => browser.navigateToPathIndex(index),
                    ),
                  ),
                ],
              ],
            ),
          );

    final List<Widget> contentSlivers = [
      // Pinned in both states - while browsing this is the controls row
      // (+ breadcrumbs), while selecting it's the selection bar (see
      // `topRow` above): either way it's the one thing that always stays
      // at the very top of the scroll view.
      SliverPersistentHeader(
        pinned: true,
        delegate: StickyHeaderDelegate(
          // 20 (topRow's own top+bottom padding) + 44 (FilesControlsRow's
          // fixed height) [+ 10 gap + 32 breadcrumbs height, if present].
          // Getting this wrong overflows the sliver header by exactly the
          // shortfall - a real bug this shipped with once already.
          height: _isSelecting ? 56 : (hasBreadcrumbs ? 106 : 64),
          child: topRow,
        ),
      ),
      if (_offline)
        SliverToBoxAdapter(child: _buildOfflineSummary(context, sync)),
      // Files List / Grid
      if (browser.isLoading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (browser.errorMessage != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.circleAlert, size: 56, color: colors.danger),
                  const SizedBox(height: 16),
                  Text(
                    _offline
                        ? 'Could not read local files'
                        : 'WebDAV Sync Error',
                    style: NooText.cardTitle.copyWith(color: colors.danger),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    browser.errorMessage!,
                    textAlign: TextAlign.center,
                    style: NooText.body.copyWith(color: colors.fg3),
                  ),
                  const SizedBox(height: 20),
                  NooButton(
                    variant: NooButtonVariant.secondary,
                    size: NooButtonSize.field,
                    icon: LucideIcons.refreshCw,
                    onTap: browser.reload,
                    child: Text(_offline ? 'Retry' : 'Retry Connection'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (browser.items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _offline ? LucideIcons.hardDriveDownload : LucideIcons.folder,
                  size: 56,
                  color: colors.fg3,
                ),
                const SizedBox(height: 12),
                Text(
                  _offline && !hasBreadcrumbs
                      ? 'Nothing downloaded yet'
                      : 'Folder is empty',
                  style: NooText.cardTitle.copyWith(color: colors.fg2),
                ),
              ],
            ),
          ),
        )
      else if (files.isGridView)
        SliverPadding(
          key: const ValueKey('files-grid'),
          padding: EdgeInsets.fromLTRB(
            gutter,
            NooSpace.xs,
            gutter,
            NooSpace.lg,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isDesktop ? 5 : 2,
              childAspectRatio: isDesktop ? 1.05 : 0.92,
              crossAxisSpacing: isDesktop ? 16 : 10,
              mainAxisSpacing: isDesktop ? 16 : 10,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = browser.items[index];
              return _FolderEnterAnimation(
                key: ValueKey('${browser.currentFolderPath}::${item.id}'),
                index: index,
                fromRight: navigatingDeeper,
                child: _buildGridCard(context, item),
              );
            }, childCount: browser.items.length),
          ),
        )
      else if (isDesktop) ...[
        SliverPadding(
          key: const ValueKey('files-table-header'),
          padding: EdgeInsets.fromLTRB(gutter, NooSpace.xs, gutter, 0),
          sliver: SliverToBoxAdapter(
            child: _buildDesktopHeader(
              context,
              files,
              browser.currentFolderPath,
            ),
          ),
        ),
        SliverPadding(
          key: const ValueKey('files-table'),
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, NooSpace.lg),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = browser.items[index];
              return _FolderEnterAnimation(
                key: ValueKey('${browser.currentFolderPath}::${item.id}'),
                index: index,
                fromRight: navigatingDeeper,
                child: _buildDesktopRow(context, item),
              );
            }, childCount: browser.items.length),
          ),
        ),
      ] else
        SliverPadding(
          key: const ValueKey('files-list'),
          padding: const EdgeInsets.fromLTRB(
            NooSpace.sm,
            NooSpace.xs,
            NooSpace.sm,
            NooSpace.lg,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = browser.items[index];
              return _FolderEnterAnimation(
                key: ValueKey('${browser.currentFolderPath}::${item.id}'),
                index: index,
                fromRight: navigatingDeeper,
                child: _buildMobileRow(
                  context,
                  item,
                  index,
                  browser.items.length,
                ),
              );
            }, childCount: browser.items.length),
          ),
        ),
    ];

    return PopScope(
      canPop: !_isSelecting && browser.pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelecting) {
          _clearSelection();
        } else {
          browser.navigateUp();
        }
      },
      child: ColoredBox(
        color: colors.bg,
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.surface,
          onRefresh: () {
            unawaited(sync.syncOnPull());
            return browser.reload();
          },
          child: CustomScrollView(
            controller: widget.scrollController,
            // Pull-to-refresh needs a scroll physics that allows dragging
            // past the edge even when content doesn't fill the viewport -
            // an empty or single-item list otherwise can't be pulled at all
            // under the platform default physics.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: contentSlivers,
          ),
        ),
      ),
    );
  }

  /// The Offline tab's summary card (`DESIGN_SYSTEM.md`'s "Banner / summary
  /// card", Offline variant): a status headline, a folder/file count
  /// caption, a conflict callout when there is one, and "Sync now".
  ///
  /// `SyncStatusController` doesn't track local bytes used or a last-sync
  /// timestamp anywhere today (no getter exposes either), so the literal
  /// "used GB" stat / progress bar / "last sync" meta the mockup shows
  /// aren't backed by real data - inventing them would mean fabricating
  /// numbers, so this shows the status/count summary that data actually
  /// supports instead. See the report for what a literal match would need.
  Widget _buildOfflineSummary(BuildContext context, SyncStatusController sync) {
    final gutter = NooLayout.gutter(context);
    final hasConflicts = sync.syncConflicts.isNotEmpty;
    final stat = hasConflicts
        ? 'Sync issue'
        : sync.isSyncingNow
        ? 'Syncing…'
        : (sync.syncEverything || sync.syncedPaths.isNotEmpty)
        ? 'Synced'
        : 'Sync off';

    final String caption;
    if (sync.syncEverything) {
      caption = 'Whole account synced to this device';
    } else {
      final folders = sync.syncedFolderCount;
      final files = sync.syncedPaths.length - folders;
      if (folders == 0 && files == 0) {
        caption = 'Nothing synced yet - use "Sync to device" in Files';
      } else {
        final parts = <String>[
          if (folders > 0) '$folders folder${folders == 1 ? '' : 's'}',
          if (files > 0) '$files file${files == 1 ? '' : 's'}',
        ];
        caption = '${parts.join(' & ')} synced to this device';
      }
    }

    final meta = hasConflicts
        ? '${sync.syncConflicts.length} item${sync.syncConflicts.length == 1 ? '' : 's'} couldn\'t sync · tap a row to retry'
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, NooSpace.sm),
      child: NooSummaryCard(
        stat: stat,
        caption: caption,
        meta: meta,
        tone: hasConflicts
            ? NooSummaryCardTone.danger
            : NooSummaryCardTone.normal,
        action: NooButton(
          variant: NooButtonVariant.tonal,
          size: NooButtonSize.compact,
          icon: LucideIcons.refreshCw,
          disabled: sync.isSyncingNow,
          onTap: () => sync.syncOnPull(),
          child: const Text('Sync now'),
        ),
      ),
    );
  }

  /// Takes over the controls row's own sticky slot while selecting - see
  /// `NooSelectionBar` (design canvas
  /// https://claude.ai/artifact/3AGPqqMdkLSC2ypCh2CQs4, "Selection action
  /// bar" - DESIGN_SYSTEM.md has no §4 recipe of its own for this).
  Widget _buildSelectionBar(
    BuildContext context,
    List<NextcloudItem> selectedItems,
  ) {
    return NooSelectionBar(
      count: selectedItems.length,
      actions: _buildSelectionActions(context, selectedItems),
      onClose: _clearSelection,
      isDesktop: NooLayout.isDesktop(context),
      iosStyle: NooLayout.iosStyle(context),
    );
  }

  /// A single item's actions (the same list the multi-select bar offers,
  /// just for one item) - the overflow menu every file row/table row/grid
  /// card opens, so acting on one item doesn't need a long-press into
  /// selection mode first.
  ///
  /// One sheet on every platform: a precisely-anchored desktop context
  /// menu would need the tapped button's screen position, but
  /// `NooFileRow`/`NooFileTableRow`/`NooGridCard`'s `onMore` is a plain
  /// `VoidCallback` with no position, and those components aren't mine to
  /// change - see the report.
  void _showItemActions(BuildContext context, NextcloudItem item) {
    final actions = _buildSelectionActions(context, [item]);
    showNooSheet(
      context,
      children: [
        NooGroupedList(
          children: [
            for (final action in actions)
              NooSettingsRow(
                icon: action.icon,
                label: Text(action.label),
                onTap: () {
                  Navigator.pop(context);
                  action.onTap();
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _favoriteSelected(
    BuildContext context,
    List<NextcloudItem> items,
  ) async {
    final ops = context.read<ItemOperations>();
    final allFavorited = items.every((i) => i.isFavorite);
    for (final item in items) {
      if (item.isFavorite == allFavorited) {
        await ops.toggleItemFavorite(item);
      }
    }
    _clearSelection();
  }

  /// Toggles device sync for every selected item at once - if they're all
  /// already synced this stops syncing all of them (and deletes their local
  /// mirrors, see `SyncStatusController.removeSyncedPath`), otherwise it
  /// starts syncing whichever ones aren't synced yet.
  void _toggleSyncSelected(
    BuildContext context,
    SyncStatusController sync,
    List<NextcloudItem> items,
  ) {
    final allSynced = items.every((i) => sync.isPathSynced(i.path));
    if (allSynced) {
      // Batched (not one removeSyncedPath call per item) so the
      // reschedule/native side effects fire once for the whole selection
      // instead of racing each other - see addSyncedPaths' doc comment
      // for why a per-item loop caused only the first item to actually
      // sync.
      sync.removeSyncedPaths(items.map((i) => i.path).toList());
    } else {
      sync.addSyncedPaths({
        for (final item in items)
          if (!sync.isPathSynced(item.path)) item.path: item.isFolder,
      });
    }
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          allSynced
              ? 'Removed ${items.length} item(s) from device sync'
              : 'Syncing ${items.length} item(s) to this device',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Hands the whole batch off to `DownloadService.kt` (see its doc
  /// comment) rather than downloading each item in Dart then prompting
  /// `file_saver` per file - same reasoning as `UploadService`/
  /// `ShareUploadService.kt` on the upload side: a real Android Service
  /// survives the app being closed mid-download, with one cancellable
  /// notification for the whole selection instead of blocking here.
  Future<void> _downloadSelected(
    BuildContext context,
    List<NextcloudItem> items,
  ) async {
    final session = context.read<SessionController>();
    final sync = context.read<SyncStatusController>();
    final files = items.where((i) => !i.isFolder).toList();
    _clearSelection();
    if (files.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);

    // Already mirrored locally by device sync (every selected file, not
    // just some)? Save straight from the local copy instead of a fresh
    // network fetch through DownloadService - see
    // SyncStatusController.localSyncedFilePath.
    final localPaths = await Future.wait(files.map(sync.localSyncedFilePath));
    if (localPaths.every((path) => path != null)) {
      try {
        for (var i = 0; i < files.length; i++) {
          final ext = p.extension(files[i].name).replaceFirst('.', '');
          final baseName = p.basenameWithoutExtension(files[i].name);
          await FileSaver.instance.saveFile(
            name: baseName,
            filePath: localPaths[i]!,
            fileExtension: ext,
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              files.length == 1
                  ? 'Downloaded ${files.first.name}'
                  : 'Downloaded ${files.length} files',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not save file(s): $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      await DownloadService.startDownload(session, files);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            files.length == 1
                ? 'Downloading ${files.first.name} - see the notification for progress'
                : 'Downloading ${files.length} files - see the notification for progress',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not start download: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    List<NextcloudItem> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Items'),
          content: Text(
            'Delete ${items.length} item(s) from the server? This cannot be undone.',
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
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ops = context.read<ItemOperations>();
    var succeeded = 0;
    for (final item in items) {
      final success = await ops.deleteItem(item.path);
      if (success) succeeded++;
    }

    _clearSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted $succeeded of ${items.length} item(s)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _moveOrCopySelected(
    BuildContext context,
    List<NextcloudItem> items, {
    required bool copy,
  }) async {
    final result = await MoveCopyDestinationPicker.show(
      context,
      items,
      copy: copy,
    );
    if (!context.mounted || result == null) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${copy ? 'Copied' : 'Moved'} ${result.succeeded} of ${items.length} item(s)',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Mobile 64px row (`NooFileRow`) - swipeable when browsing normally,
  /// plain when selecting/picking/offline (matching the old
  /// `SwipeableItem`'s gating exactly). Rounds the top corners of the
  /// first row and the bottom corners of the last one, with a 1px `line`
  /// divider between rows, so the whole list reads as one radius-20
  /// surface card rather than `NooGroupedList`'s own (non-lazy) `Column` -
  /// this list needs to stay a lazily-built `SliverList` for long folders.
  Widget _buildMobileRow(
    BuildContext context,
    NextcloudItem item,
    int index,
    int count,
  ) {
    final colors = context.nooColors;
    final pick = context.watch<PickController>();
    final sync = context.watch<SyncStatusController>();
    final session = context.watch<SessionController>();
    final settings = context.watch<SettingsController>();
    final ops = context.read<ItemOperations>();
    final isSelected = _selectedIds.contains(item.id);
    // Pick mode and selection are server-side features - never on Offline.
    final picking = !_offline && pick.isPicking;
    final status = _offline ? SyncItemStatus.none : sync.syncStatusFor(item);
    final isConflict = status == SyncItemStatus.conflict;

    final row = NooFileRow(
      kind: NooFileKind.from(
        name: item.name,
        mimeType: item.mimeType,
        isDirectory: item.isFolder,
      ),
      name: item.name,
      size: !item.isFolder && !isConflict ? formatBytes(item.size) : null,
      modified: !item.isFolder && !isConflict
          ? DateFormat.yMMMd().format(item.lastModified)
          : null,
      meta: isConflict
          ? "Couldn't sync · Tap to retry"
          : (item.isFolder ? 'Folder' : null),
      statuses: _nooStatuses(status),
      favorite: item.isFavorite,
      iosStyle: NooLayout.iosStyle(context),
      selected: isSelected,
      thumbnail: _rowThumbnail(context, item, session, NooFileTileSize.row),
      onTap: () => _handleItemTap(context, item, picking: picking),
      onLongPress: _offline || (picking && !pick.pickRequest!.allowMultiple)
          ? null
          : () => _toggleSelection(item),
      onMore: !_isSelecting && !picking
          ? () => _showItemActions(context, item)
          : null,
    );

    final swipeable = _isSelecting || picking || _offline
        ? row
        : NooSwipeAction(
            startAction: _swipeSpec(settings.swipeRightAction, item, ops),
            endAction: _swipeSpec(settings.swipeLeftAction, item, ops),
            child: row,
          );

    final isFirst = index == 0;
    final isLast = index == count - 1;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(NooRadii.card) : Radius.zero,
            bottom: isLast ? const Radius.circular(NooRadii.card) : Radius.zero,
          ),
          child: swipeable,
        ),
        if (!isLast) Container(height: 1, color: colors.line),
      ],
    );
  }

  /// Desktop table header - sort state comes from the same per-folder
  /// `FilesController` prefs the mobile sort chip uses, so both tabs and
  /// both layouts always agree.
  Widget _buildDesktopHeader(
    BuildContext context,
    FilesController files,
    String folderPath,
  ) {
    const columns = [
      FileSortField.name,
      FileSortField.size,
      FileSortField.dateModified,
    ];
    final field = files.sortFieldFor(folderPath);
    final sortColumn = columns.indexOf(field);
    return NooFileTableHeader(
      col2Label: 'Size',
      col3Label: 'Modified',
      sortColumn: sortColumn < 0 ? null : sortColumn,
      sortAscending: files.sortAscendingFor(folderPath),
      onSort: (index) {
        final tapped = columns[index];
        if (files.sortFieldFor(folderPath) == tapped) {
          files.toggleSortOrderFor(folderPath);
        } else {
          files.setSortFieldFor(folderPath, tapped);
        }
      },
    );
  }

  /// Desktop 52px table row (`NooFileTableRow`) - no swipe actions or card
  /// framing (the design's desktop rows sit directly on the pane).
  Widget _buildDesktopRow(BuildContext context, NextcloudItem item) {
    final pick = context.watch<PickController>();
    final sync = context.watch<SyncStatusController>();
    final session = context.watch<SessionController>();
    final isSelected = _selectedIds.contains(item.id);
    final picking = !_offline && pick.isPicking;
    final status = _offline ? SyncItemStatus.none : sync.syncStatusFor(item);

    return NooFileTableRow(
      kind: NooFileKind.from(
        name: item.name,
        mimeType: item.mimeType,
        isDirectory: item.isFolder,
      ),
      name: item.name,
      col2: item.isFolder ? null : formatBytes(item.size),
      col3: item.isFolder ? null : DateFormat.yMMMd().format(item.lastModified),
      statuses: _nooStatuses(status),
      favorite: item.isFavorite,
      selected: isSelected,
      thumbnail: _rowThumbnail(context, item, session, NooFileTileSize.desktop),
      onTap: () => _handleItemTap(context, item, picking: picking),
      onMore: !_isSelecting && !picking
          ? () => _showItemActions(context, item)
          : null,
    );
  }

  Future<void> _confirmAndDeleteViaSwipe(NextcloudItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text(
            'Delete "${item.name}" from the server? This cannot be undone.',
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
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.mediumImpact();

    final ops = context.read<ItemOperations>();
    final success = await ops.deleteItem(item.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Deleted ${item.name}' : 'Failed to delete ${item.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// `NooGridCard` (`DESIGN_SYSTEM.md`'s grid card): a full-bleed thumbnail
  /// area (real preview, or the file-kind soft color + icon when there
  /// isn't one) above a name/meta line. The card has no slot for a
  /// favorite star or sync-status icon (only the row/table variants do) -
  /// see the report.
  Widget _buildGridCard(BuildContext context, NextcloudItem item) {
    final colors = context.nooColors;
    final pick = context.watch<PickController>();
    final sync = context.watch<SyncStatusController>();
    final session = context.watch<SessionController>();
    final isSelected = _selectedIds.contains(item.id);
    final picking = !_offline && pick.isPicking;
    final status = _offline ? SyncItemStatus.none : sync.syncStatusFor(item);
    final kind = NooFileKind.from(
      name: item.name,
      mimeType: item.mimeType,
      isDirectory: item.isFolder,
    );
    // Offline reads the image straight from the local mirror; videos have
    // no local thumbnail (that would need a frame-extraction plugin), so
    // they fall through to the plain kind-icon card there.
    final isMedia = _offline
        ? item.type == NextcloudItemType.image
        : (item.type == NextcloudItemType.image ||
                  item.type == NextcloudItemType.video) &&
              item.previewUrl != null;
    final meta = status == SyncItemStatus.conflict
        ? "Couldn't sync · Tap to retry"
        : (item.isFolder ? 'Folder' : formatBytes(item.size));

    return NooGridCard(
      name: item.name,
      meta: meta,
      placeholderColor: kind.background(colors),
      icon: kind.icon,
      iconColor: kind.foreground(colors),
      thumbnail: isMedia
          ? _GridThumbnail(
              item: item,
              service: session.service,
              localFile: _localFileFor(context, item),
              fallback: Icon(
                kind.icon,
                color: kind.foreground(colors),
                size: 32,
              ),
            )
          : null,
      thumbnailHeight: NooLayout.isDesktop(context) ? 118 : 104,
      selected: isSelected,
      onTap: () => _handleItemTap(context, item, picking: picking),
      onLongPress: _offline || (picking && !pick.pickRequest!.allowMultiple)
          ? null
          : () => _toggleSelection(item),
      onMore: !_isSelecting && !picking
          ? () => _showItemActions(context, item)
          : null,
      verticalOverflowIcon: !NooLayout.iosStyle(context),
    );
  }

  void _openFile(BuildContext context, NextcloudItem item) {
    if (_offline) {
      // Same in-app viewer (including swiping between the folder's media),
      // just reading from disk instead of the server - see
      // `FileViewerScreen.localPathResolver`'s doc comment.
      final offline = context.read<OfflineController>();
      Navigator.push(
        context,
        FileViewerScreen.route(
          item: item,
          siblings: offline.items,
          localPathResolver: offline.localPathFor,
        ),
      );
      return;
    }
    final files = context.read<FilesController>();
    Navigator.push(
      context,
      FileViewerScreen.route(item: item, siblings: files.items),
    );
  }
}
