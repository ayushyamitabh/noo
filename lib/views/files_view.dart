import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../providers/files_controller.dart';
import '../providers/folder_browser.dart';
import '../providers/item_operations.dart';
import '../providers/offline_controller.dart';
import '../providers/pick_controller.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../providers/sync_status_controller.dart';
import '../services/download_service.dart';
import '../services/share_intent_service.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/files_controls_row.dart';
import '../widgets/item_icon.dart';
import '../widgets/manage_synced_folders_sheet.dart';
import '../widgets/media_grid_tile.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/selectable_thumbnail.dart';
import '../widgets/share_sheet.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/swipeable_item.dart';
import '../widgets/sync_status_badge.dart';
import '../widgets/synced_header_scaffold.dart';
import 'file_viewer_screen.dart';
import 'move_copy_destination_picker.dart';
import 'share_upload_view.dart';

/// The Files tab - and, with [offline] set, the Offline tab, which is the
/// same view over the device-sync mirror instead of the server: the Files
/// tab's folders filtered down to what's available offline. The two share
/// every display pref/control, the header, breadcrumbs, list/grid tiles and
/// thumbnails; [offline] only swaps the data source (`FolderBrowser`),
/// reads images from the local file instead of a server preview, and turns
/// off everything that needs the server (selection and its bulk actions,
/// swipe actions, sync badges, the "+" menu, pick mode).
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

class _FilesViewState extends State<FilesView>
    with SingleTickerProviderStateMixin {
  final Set<String> _selectedIds = {};
  int _lastPathDepth = 1;
  final ScrollController _controlsScrollController = ScrollController();
  final ScrollController _selectionActionsScrollController = ScrollController();
  final List<AnimationController> _scrollHintControllers = [];

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
  File? _localFileFor(BuildContext context, NextcloudItem item) => _offline
      ? context.read<OfflineController>().localFileFor(item)
      : null;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _playScrollHint(_controlsScrollController),
    );
  }

  /// A one-shot hint that a horizontally-scrollable row actually scrolls:
  /// nudges it a little to the right and back, once - a motion cue instead
  /// of a persistent widget (a chevron badge, an edge fade) sitting on top
  /// of the actual controls the whole time. Shared by the controls row
  /// (played once it first appears) and the selection actions row (played
  /// the first time a selection starts, see `_toggleSelection`). No-ops if
  /// there's nothing to scroll (row already fits).
  Future<void> _playScrollHint(ScrollController scrollController) async {
    // The delay lets the row's first frame (and its actual layout/max
    // scroll extent) settle before nudging it, and reads more like a
    // deliberate hint than something that happens to fire on load.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted || !scrollController.hasClients) return;
    final maxExtent = scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final double peak = maxExtent < 36 ? maxExtent : 36;
    // Driven as a single controller (rather than two chained animateTo
    // calls) with mirrored ease-in-out halves, so the motion decelerates
    // smoothly into the peak and back out instead of visibly changing
    // pace where the two legs meet.
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scrollHintControllers.add(controller);
    final hint = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: peak,
        ).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: peak,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
    ]).animate(controller);
    void onTick() {
      if (scrollController.hasClients) {
        scrollController.jumpTo(hint.value);
      }
    }

    hint.addListener(onTick);
    await controller.forward();
    hint.removeListener(onTick);
    _scrollHintControllers.remove(controller);
    controller.dispose();
  }

  @override
  void dispose() {
    for (final controller in _scrollHintControllers) {
      controller.dispose();
    }
    _controlsScrollController.dispose();
    _selectionActionsScrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(NextcloudItem item) {
    HapticFeedback.selectionClick();
    final enteringSelection = _selectedIds.isEmpty;
    setState(() {
      if (!_selectedIds.remove(item.id)) _selectedIds.add(item.id);
    });
    if (enteringSelection && _isSelecting) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _playScrollHint(_selectionActionsScrollController),
      );
    }
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
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
  /// currently-selected items.
  List<SelectionAction> _buildSelectionActions(
    BuildContext context,
    List<NextcloudItem> selected,
  ) {
    final pick = context.watch<PickController>();
    final sync = context.watch<SyncStatusController>();
    if (pick.isPicking) {
      return [
        SelectionAction(
          icon: Icons.check_rounded,
          label: 'Use ${selected.length} item(s)',
          onTap: () => pick.confirmPick(selected),
        ),
      ];
    }
    return [
      SelectionAction(
        icon: selected.every((i) => i.isFavorite)
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        label: selected.every((i) => i.isFavorite)
            ? 'Remove from favorites'
            : 'Favorite',
        onTap: () => _favoriteSelected(context, selected),
      ),
      SelectionAction(
        icon: Icons.share_rounded,
        label: 'Share',
        onTap: () => selected.length == 1
            ? ShareSheet.show(context, selected.single)
            : _shareSelected(context, selected),
      ),
      SelectionAction(
        icon: Icons.download_rounded,
        label: 'Download',
        onTap: () => _downloadSelected(context, selected),
      ),
      SelectionAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        onTap: () => _confirmDeleteSelected(context, selected),
      ),
      SelectionAction(
        icon: Icons.copy_rounded,
        label: 'Copy',
        onTap: () => _moveOrCopySelected(context, selected, copy: true),
      ),
      SelectionAction(
        icon: Icons.drive_file_move_rounded,
        label: 'Move',
        onTap: () => _moveOrCopySelected(context, selected, copy: false),
      ),
      if (selected.length == 1)
        SelectionAction(
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename',
          onTap: () => _renameItem(selected.single),
        ),
      SelectionAction(
        icon: selected.every((i) => sync.isPathSynced(i.path))
            ? Icons.sync_rounded
            : Icons.sync_outlined,
        label: selected.every((i) => sync.isPathSynced(i.path))
            ? 'Stop syncing to device'
            : 'Sync to device',
        onTap: () => _toggleSyncSelected(context, sync, selected),
      ),
      if (selected.length == 1)
        SelectionAction(
          icon: Icons.info_outline_rounded,
          label: 'Details',
          onTap: () => DetailsSheet.show(context, selected.single),
        ),
    ];
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Display prefs (grid/list, filters, sort) live on FilesController for
    // both tabs; `browser` is the tab's own folder listing.
    final files = context.watch<FilesController>();
    final browser = _browserOf(context);

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

    final controlsRow = Padding(
      // 16, not 20 - matches the SliverAppBar toolbar's own default
      // horizontal content inset when it's selecting, so the two rows'
      // content lines up instead of the controls row looking shifted in.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The scroll-hint nudge (see _playScrollHint) plays on this row
          // once, right after it first appears.
          FilesControlsRow(
            folderPath: browser.currentFolderPath,
            showStorageScope: !_offline,
            scrollController: _controlsScrollController,
          ),
          if (hasBreadcrumbs) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: Breadcrumbs(
                pathStack: browser.pathStack,
                onTap: (index) => browser.navigateToPathIndex(index),
              ),
            ),
          ],
        ],
      ),
    );

    final List<Widget> contentSlivers = [
      // Sticky while browsing; once selecting, the selection bar takes over
      // the very top of the screen instead (see `selectionBar` below), so
      // this is free to scroll away rather than staying pinned under it.
      SliverPersistentHeader(
        pinned: !_isSelecting,
        delegate: StickyHeaderDelegate(
          height: hasBreadcrumbs ? 114 : 72,
          child: controlsRow,
        ),
      ),
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
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _offline ? 'Could not read local files' : 'WebDAV Sync Error',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    browser.errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: browser.reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_offline ? 'Retry' : 'Retry Connection'),
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
                  _offline
                      ? Icons.offline_pin_outlined
                      : Icons.folder_open_rounded,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  _offline && !hasBreadcrumbs
                      ? 'Nothing downloaded yet'
                      : 'Folder is empty',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        )
      else if (files.isGridView)
        SliverPadding(
          key: const ValueKey('files-grid'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
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
      else
        SliverPadding(
          key: const ValueKey('files-list'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = browser.items[index];
              return _FolderEnterAnimation(
                key: ValueKey('${browser.currentFolderPath}::${item.id}'),
                index: index,
                fromRight: navigatingDeeper,
                child: _buildListTile(context, item),
              );
            }, childCount: browser.items.length),
          ),
        ),

      // Fixed clearance so the last item isn't hidden behind the floating
      // nav bar, regardless of list length.
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
      // For a short list this stretches the white card's background down to
      // the screen edge (matching the empty/loading/error states, which
      // already use SliverFillRemaining); for a long list that already fills
      // the viewport it contributes nothing extra.
      const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
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
      child: SyncedHeaderScaffold(
        scrollController: widget.scrollController,
        onRefresh: browser.reload,
        actions: [
          if (_offline)
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'Manage synced folders',
              onPressed: () => ManageSyncedFoldersSheet.show(context),
            )
          else
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'New',
              onPressed: () => _showCreateMenu(context),
            ),
          const MoreTabsButton(),
          const ProfileAvatarButton(),
        ],
        selectionBar: _isSelecting
            ? _buildSelectionBar(context, theme, selectedItems)
            : null,
        contentSlivers: contentSlivers,
      ),
    );
  }

  /// Replaces the top bar entirely while selecting (see
  /// `SyncedHeaderScaffold.selectionBar`) - a close button, the "N
  /// selected" count, and the horizontally-scrollable bulk actions.
  Widget _buildSelectionBar(
    BuildContext context,
    ThemeData theme,
    List<NextcloudItem> selectedItems,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Cancel selection',
                    onPressed: _clearSelection,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${selectedItems.length} selected',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _selectionActionsScrollController,
              scrollDirection: Axis.horizontal,
              // Left-aligned (not anchored to the trailing edge) so the
              // first action's left edge sits at a fixed spot - lining up
              // with the controls row's own first icon directly below it -
              // regardless of how many actions there are.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in _buildSelectionActions(
                    context,
                    selectedItems,
                  ))
                    IconButton(
                      icon: Icon(action.icon, size: 20),
                      tooltip: action.label,
                      onPressed: action.onTap,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    final localPaths = await Future.wait(
      files.map(sync.localSyncedFilePath),
    );
    if (localPaths.every((path) => path != null)) {
      try {
        for (var i = 0; i < files.length; i++) {
          final ext = p.extension(files[i].name).replaceFirst('.', '');
          final baseName = p.basenameWithoutExtension(files[i].name);
          await FileSaver.instance.saveFile(
            name: baseName,
            filePath: localPaths[i]!,
            ext: ext,
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

  Widget _buildListTile(BuildContext context, NextcloudItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final browser = _browserOf(context);
    final pick = context.watch<PickController>();
    final sync = context.watch<SyncStatusController>();
    final session = context.watch<SessionController>();
    final settings = context.watch<SettingsController>();
    final ops = context.read<ItemOperations>();
    final isSelected = _selectedIds.contains(item.id);
    // Pick mode and selection are server-side features - never on Offline.
    final picking = !_offline && pick.isPicking;

    // No border radius here — the outer ClipRRect below is the only place
    // that rounds this tile's corners. Rounding it here too would give the
    // tile its own independent rounded edge, which becomes visible as a
    // stray floating corner while it slides during a swipe.
    final card = Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () {
          if (picking) {
            _handlePickTap(context, item);
          } else if (_isSelecting) {
            _toggleSelection(item);
          } else if (item.isFolder) {
            browser.navigateToFolder(item.path);
          } else {
            _openFile(context, item);
          }
        },
        onLongPress: _offline || (picking && !pick.pickRequest!.allowMultiple)
            ? null
            : () => _toggleSelection(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SelectableThumbnail(
                    isSelected: isSelected,
                    size: 44,
                    checkmarkSize: 24,
                    child: ItemThumbnail(
                      item: item,
                      service: session.service,
                      localFile: _localFileFor(context, item),
                      size: 44,
                      borderRadius: 12,
                      iconSize: 22,
                    ),
                  ),
                  // Everything on the Offline tab is synced by definition.
                  if (!_offline)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: SyncStatusBadge(
                        status: sync.syncStatusFor(item),
                      ),
                    ),
                ],
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
                      item.isFolder
                          ? 'Folder'
                          : '${formatBytes(item.size)} • ${DateFormat.yMMMd().format(item.lastModified)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final content = _isSelecting || picking || _offline
        ? card
        : SwipeableItem(
            itemKey: ValueKey('file-${item.id}'),
            itemName: item.name,
            settings: settings,
            onFavorite: () => ops.toggleItemFavorite(item),
            onShare: () => ShareSheet.show(context, item),
            onDelete: () => _deleteViaSwipe(item),
            child: card,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: content),
    );
  }

  Future<void> _deleteViaSwipe(NextcloudItem item) async {
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

  Widget _buildGridCard(BuildContext context, NextcloudItem item) {
    final browser = _browserOf(context);
    final pick = context.watch<PickController>();
    final sync = context.watch<SyncStatusController>();
    final isSelected = _selectedIds.contains(item.id);
    final picking = !_offline && pick.isPicking;
    // Offline reads the image straight from the local mirror; videos have
    // no local thumbnail (that would need a frame-extraction plugin), so
    // they fall through to the plain icon card there.
    final isMedia = _offline
        ? item.type == NextcloudItemType.image
        : (item.type == NextcloudItemType.image ||
                  item.type == NextcloudItemType.video) &&
              item.previewUrl != null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (picking) {
            _handlePickTap(context, item);
          } else if (_isSelecting) {
            _toggleSelection(item);
          } else if (item.isFolder) {
            browser.navigateToFolder(item.path);
          } else {
            _openFile(context, item);
          }
        },
        onLongPress: _offline || (picking && !pick.pickRequest!.allowMultiple)
            ? null
            : () => _toggleSelection(item),
        child: Stack(
          children: [
            SelectableThumbnail(
              isSelected: isSelected,
              checkmarkSize: 32,
              child: isMedia
                  ? _buildMediaGridContent(context, item)
                  : _buildPlainGridContent(context, item),
            ),
            if (!_offline)
              Positioned(
                right: 6,
                bottom: 6,
                child: SyncStatusBadge(status: sync.syncStatusFor(item)),
              ),
          ],
        ),
      ),
    );
  }

  /// Grid content for images/videos - see [MediaGridTile].
  Widget _buildMediaGridContent(BuildContext context, NextcloudItem item) {
    final session = context.watch<SessionController>();
    final localFile = _localFileFor(context, item);

    return MediaGridTile(
      item: item,
      imageBuilder: (cachePixels) => ResizeImage(
        localFile != null
            ? FileImage(localFile)
            : NetworkImage(
                item.previewUrl!,
                headers: session.service?.authHeaders,
              ),
        width: cachePixels,
        height: cachePixels,
      ),
      fallbackBuilder: (ctx) => _buildPlainGridContent(ctx, item),
    );
  }

  /// Grid content for folders and non-previewable files: an icon badge
  /// with name/size below, since there's no meaningful preview to show.
  Widget _buildPlainGridContent(BuildContext context, NextcloudItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = getIconColor(context, item.type);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(getItemIcon(item.type), color: iconColor, size: 24),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.isFolder ? 'Folder' : formatBytes(item.size),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
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

  void _showCreateMenu(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_rounded),
                  title: const Text('Upload File'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUploadFile(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New Folder'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showCreateFolderDialog(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final files = context.read<FilesController>();
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Folder Name',
              hintText: 'e.g. Finance',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  final success = await files.createFolder(name);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Created folder $name'
                              : 'Failed to create folder',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  // Mirrors `main.dart`'s `_handleSharedFiles` exactly, so picking a file
  // via "+" lands on the same destination-picker screen and background
  // foreground-service upload as receiving one via Android's "Share
  // to..." sheet does, rather than a separate in-app-only upload path.
  Future<void> _pickAndUploadFile(BuildContext context) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final files = picked
        .where((f) => f.path != null)
        .map(
          (f) => SharedFileRef(
            uri: Uri.file(f.path!).toString(),
            name: f.name,
            size: f.lengthSync(),
          ),
        )
        .toList();
    if (files.isEmpty || !context.mounted) return;

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ShareUploadView(files: files)));
  }
}
