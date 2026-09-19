import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../providers/server_provider.dart';
import '../services/download_service.dart';
import '../services/share_intent_service.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/item_icon.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/segmented_icon_toggle.dart';
import '../widgets/selectable_thumbnail.dart';
import '../widgets/share_sheet.dart';
import '../widgets/sort_menu_button.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/swipeable_item.dart';
import '../widgets/sync_status_badge.dart';
import '../widgets/synced_header_scaffold.dart';
import 'file_viewer_screen.dart';
import 'move_copy_destination_picker.dart';
import 'share_upload_view.dart';

class FilesView extends StatefulWidget {
  final ScrollController scrollController;

  const FilesView({super.key, required this.scrollController});

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
  void _handlePickTap(
    BuildContext context,
    ServerProvider provider,
    NextcloudItem item,
  ) {
    if (item.isFolder) {
      provider.navigateToFolder(item.path);
      return;
    }
    if (!provider.itemMatchesPickFilter(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This app can't accept this file type"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (provider.pickRequest!.allowMultiple) {
      _toggleSelection(item);
    } else {
      provider.confirmPick([item]);
    }
  }

  /// The bulk actions shown in the sticky selection toolbar for the
  /// currently-selected items.
  List<SelectionAction> _buildSelectionActions(
    ServerProvider provider,
    List<NextcloudItem> selected,
  ) {
    if (provider.isPicking) {
      return [
        SelectionAction(
          icon: Icons.check_rounded,
          label: 'Use ${selected.length} item(s)',
          onTap: () => provider.confirmPick(selected),
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
        onTap: () => _favoriteSelected(provider, selected),
      ),
      SelectionAction(
        icon: Icons.share_rounded,
        label: 'Share',
        onTap: () => selected.length == 1
            ? ShareSheet.show(context, selected.single)
            : _shareSelected(context, provider, selected),
      ),
      SelectionAction(
        icon: Icons.download_rounded,
        label: 'Download',
        onTap: () => _downloadSelected(context, provider, selected),
      ),
      SelectionAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        onTap: () => _confirmDeleteSelected(context, provider, selected),
      ),
      SelectionAction(
        icon: Icons.copy_rounded,
        label: 'Copy',
        onTap: () => _moveOrCopySelected(provider, selected, copy: true),
      ),
      SelectionAction(
        icon: Icons.drive_file_move_rounded,
        label: 'Move',
        onTap: () => _moveOrCopySelected(provider, selected, copy: false),
      ),
      if (selected.length == 1)
        SelectionAction(
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename',
          onTap: () => _renameItem(provider, selected.single),
        ),
      if (selected.length == 1)
        SelectionAction(
          icon: provider.isPathSynced(selected.single.path)
              ? Icons.sync_rounded
              : Icons.sync_outlined,
          label: provider.isPathSynced(selected.single.path)
              ? 'Stop syncing to device'
              : 'Sync to device',
          onTap: () => provider.isPathSynced(selected.single.path)
              ? provider.removeSyncedPath(selected.single.path)
              : provider.addSyncedPath(selected.single.path),
        ),
      if (selected.length == 1)
        SelectionAction(
          icon: Icons.info_outline_rounded,
          label: 'Details',
          onTap: () => DetailsSheet.show(context, selected.single),
        ),
    ];
  }

  Future<void> _renameItem(ServerProvider provider, NextcloudItem item) async {
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
    final success = await provider.renameItem(item, newName);
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
    ServerProvider provider,
    List<NextcloudItem> items,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Creating share link(s)…'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final lines = <String>[];
    for (final item in items) {
      final link = await provider.createShareLink(item);
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
    final provider = context.watch<ServerProvider>();

    final pathDepth = provider.pathStack.length;
    final navigatingDeeper = pathDepth > _lastPathDepth;
    _lastPathDepth = pathDepth;

    final hasBreadcrumbs = provider.pathStack.length > 1;
    final selectedItems = provider.items
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
          SizedBox(
            height: 44,
            // No persistent hint widget here - instead, a one-shot nudge
            // (see _playControlsScrollHint, triggered from initState) just
            // scrolls this row a little to the right and back, once, right
            // after it first appears. Two static attempts before this -
            // fading the controls' own opacity via ShaderMask, then a
            // chevron badge overlaid on the edge - both add a
            // permanent element competing with the actual controls; a
            // motion cue that plays once and gets out of the way reads
            // just as clearly without that cost.
            child: SingleChildScrollView(
              controller: _controlsScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      provider.filesSortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: provider.filesSortAscending
                        ? 'Ascending'
                        : 'Descending',
                    onPressed: provider.toggleFilesSortOrder,
                  ),
                  // A plain width, not Expanded - this row scrolls
                  // horizontally now, which gives every control unbounded
                  // width to lay out in, so a flex child would throw.
                  SizedBox(
                    width: 130,
                    child: SortMenuButton(
                      field: provider.filesSortField,
                      onChanged: provider.setFilesSortField,
                    ),
                  ),
                  ToggleIconButton(
                    icon: provider.showHiddenFiles
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    isSelected: provider.showHiddenFiles,
                    onTap: () => provider.toggleShowHiddenFiles(),
                    tooltip: 'Show hidden files',
                  ),
                  const SizedBox(width: 4),
                  SegmentedIconGroup(
                    children: [
                      ToggleIconButton(
                        icon: Symbols.circles_rounded,
                        isSelected: provider.storageScope == StorageScope.cloud,
                        onTap: () =>
                            provider.setStorageScope(StorageScope.cloud),
                        tooltip: 'Cloud storage',
                      ),
                      ToggleIconButton(
                        icon: Symbols.hard_drive_rounded,
                        isSelected:
                            provider.storageScope == StorageScope.external,
                        onTap: () =>
                            provider.setStorageScope(StorageScope.external),
                        tooltip: 'External storage',
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  SegmentedIconGroup(
                    children: [
                      ToggleIconButton(
                        icon: Icons.select_all_rounded,
                        isSelected:
                            provider.filesTypeFilter == FilesTypeFilter.all,
                        onTap: () =>
                            provider.setFilesTypeFilter(FilesTypeFilter.all),
                        tooltip: 'Files & folders',
                      ),
                      ToggleIconButton(
                        icon: Icons.insert_drive_file_outlined,
                        isSelected:
                            provider.filesTypeFilter ==
                            FilesTypeFilter.filesOnly,
                        onTap: () => provider.setFilesTypeFilter(
                          FilesTypeFilter.filesOnly,
                        ),
                        tooltip: 'Files only',
                      ),
                      ToggleIconButton(
                        icon: Icons.folder_outlined,
                        isSelected:
                            provider.filesTypeFilter ==
                            FilesTypeFilter.foldersOnly,
                        onTap: () => provider.setFilesTypeFilter(
                          FilesTypeFilter.foldersOnly,
                        ),
                        tooltip: 'Folders only',
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  SegmentedIconGroup(
                    children: [
                      ToggleIconButton(
                        icon: Icons.view_list_rounded,
                        isSelected: !provider.isGridView,
                        onTap: () => provider.setGridView(false),
                        tooltip: 'List view',
                      ),
                      ToggleIconButton(
                        icon: Icons.grid_view_rounded,
                        isSelected: provider.isGridView,
                        onTap: () => provider.setGridView(true),
                        tooltip: 'Grid view',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (hasBreadcrumbs) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: Breadcrumbs(
                pathStack: provider.pathStack,
                onTap: (index) => provider.navigateToPathIndex(index),
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
      if (provider.isLoading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (provider.errorMessage != null)
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
                    'WebDAV Sync Error',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: provider.refreshData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry Connection'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (provider.items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'Folder is empty',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        )
      else if (provider.isGridView)
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
              final item = provider.items[index];
              return _FolderEnterAnimation(
                key: ValueKey('${provider.currentFolderPath}::${item.id}'),
                index: index,
                fromRight: navigatingDeeper,
                child: _buildGridCard(context, item, provider),
              );
            }, childCount: provider.items.length),
          ),
        )
      else
        SliverPadding(
          key: const ValueKey('files-list'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = provider.items[index];
              return _FolderEnterAnimation(
                key: ValueKey('${provider.currentFolderPath}::${item.id}'),
                index: index,
                fromRight: navigatingDeeper,
                child: _buildListTile(context, item, provider),
              );
            }, childCount: provider.items.length),
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
      canPop: !_isSelecting && provider.pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelecting) {
          _clearSelection();
        } else {
          provider.navigateUp();
        }
      },
      child: SyncedHeaderScaffold(
        scrollController: widget.scrollController,
        provider: provider,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New',
            onPressed: () => _showCreateMenu(context, provider),
          ),
          const MoreTabsButton(),
          const ProfileAvatarButton(),
        ],
        selectionBar: _isSelecting
            ? _buildSelectionBar(context, theme, provider, selectedItems)
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
    ServerProvider provider,
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
                    provider,
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
    ServerProvider provider,
    List<NextcloudItem> items,
  ) async {
    final allFavorited = items.every((i) => i.isFavorite);
    for (final item in items) {
      if (item.isFavorite == allFavorited) {
        await provider.toggleItemFavorite(item);
      }
    }
    _clearSelection();
  }

  /// Hands the whole batch off to `DownloadService.kt` (see its doc
  /// comment) rather than downloading each item in Dart then prompting
  /// `file_saver` per file - same reasoning as `UploadService`/
  /// `ShareUploadService.kt` on the upload side: a real Android Service
  /// survives the app being closed mid-download, with one cancellable
  /// notification for the whole selection instead of blocking here.
  Future<void> _downloadSelected(
    BuildContext context,
    ServerProvider provider,
    List<NextcloudItem> items,
  ) async {
    final files = items.where((i) => !i.isFolder).toList();
    _clearSelection();
    if (files.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);

    // Already mirrored locally by device sync (every selected file, not
    // just some)? Save straight from the local copy instead of a fresh
    // network fetch through DownloadService - see
    // ServerProvider.localSyncedFilePath.
    final localPaths = await Future.wait(
      files.map(provider.localSyncedFilePath),
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
      await DownloadService.startDownload(provider, files);
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
    ServerProvider provider,
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
    var succeeded = 0;
    for (final item in items) {
      final success = await provider.deleteItem(item.path);
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
    ServerProvider provider,
    List<NextcloudItem> items, {
    required bool copy,
  }) async {
    final result = await MoveCopyDestinationPicker.show(
      context,
      items,
      copy: copy,
    );
    if (!mounted || result == null) return;
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

  Widget _buildListTile(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedIds.contains(item.id);

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
          if (provider.isPicking) {
            _handlePickTap(context, provider, item);
          } else if (_isSelecting) {
            _toggleSelection(item);
          } else if (item.isFolder) {
            provider.navigateToFolder(item.path);
          } else {
            _openFile(context, item, provider);
          }
        },
        onLongPress: provider.isPicking && !provider.pickRequest!.allowMultiple
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
                      provider: provider,
                      size: 44,
                      borderRadius: 12,
                      iconSize: 22,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: SyncStatusBadge(
                      status: provider.syncStatusFor(item),
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

    final content = _isSelecting || provider.isPicking
        ? card
        : SwipeableItem(
            itemKey: ValueKey('file-${item.id}'),
            itemName: item.name,
            provider: provider,
            onFavorite: () => provider.toggleItemFavorite(item),
            onShare: () => ShareSheet.show(context, item),
            onDelete: () => _deleteViaSwipe(provider, item),
            child: card,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: content),
    );
  }

  Future<void> _deleteViaSwipe(
    ServerProvider provider,
    NextcloudItem item,
  ) async {
    final success = await provider.deleteItem(item.path);
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

  Widget _buildGridCard(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final isSelected = _selectedIds.contains(item.id);
    final isMedia =
        (item.type == NextcloudItemType.image ||
            item.type == NextcloudItemType.video) &&
        item.previewUrl != null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (provider.isPicking) {
            _handlePickTap(context, provider, item);
          } else if (_isSelecting) {
            _toggleSelection(item);
          } else if (item.isFolder) {
            provider.navigateToFolder(item.path);
          } else {
            _openFile(context, item, provider);
          }
        },
        onLongPress: provider.isPicking && !provider.pickRequest!.allowMultiple
            ? null
            : () => _toggleSelection(item),
        child: Stack(
          children: [
            SelectableThumbnail(
              isSelected: isSelected,
              checkmarkSize: 32,
              child: isMedia
                  ? _buildMediaGridContent(context, item, provider)
                  : _buildPlainGridContent(context, item),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: SyncStatusBadge(status: provider.syncStatusFor(item)),
            ),
          ],
        ),
      ),
    );
  }

  /// Grid content for images/videos: the actual preview fills the whole
  /// card as a background, with the name/size legible over a bottom scrim
  /// — matching a Google Photos-style grid instead of a small icon badge.
  Widget _buildMediaGridContent(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cachePixels =
            (constraints.maxWidth * MediaQuery.of(context).devicePixelRatio)
                .round();
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              item.previewUrl!,
              headers: provider.service?.authHeaders,
              fit: BoxFit.cover,
              cacheWidth: cachePixels,
              cacheHeight: cachePixels,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (ctx, err, stack) =>
                  _buildPlainGridContent(context, item),
            ),
            if (item.type == NextcloudItemType.video)
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      formatBytes(item.size),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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

  void _openFile(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    Navigator.push(
      context,
      FileViewerScreen.route(item: item, siblings: provider.items),
    );
  }

  void _showCreateMenu(BuildContext context, ServerProvider provider) {
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
                    _showCreateFolderDialog(context, provider);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateFolderDialog(BuildContext context, ServerProvider provider) {
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
                  final success = await provider.createFolder(name);
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
