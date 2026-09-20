import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../providers/files_controller.dart';
import '../providers/item_operations.dart';
import '../providers/photos_controller.dart';
import '../providers/pick_controller.dart';
import '../providers/session_controller.dart';
import '../services/download_service.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/segmented_icon_toggle.dart';
import '../widgets/selectable_thumbnail.dart';
import '../widgets/share_sheet.dart';
import '../widgets/sort_menu_button.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/synced_header_scaffold.dart';
import 'file_viewer_screen.dart';
import 'move_copy_destination_picker.dart';

class PhotosView extends StatefulWidget {
  final ScrollController scrollController;

  const PhotosView({super.key, required this.scrollController});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView>
    with SingleTickerProviderStateMixin {
  bool _requested = false;
  final Set<String> _selectedIds = {};
  final ScrollController _selectionActionsScrollController = ScrollController();
  final List<AnimationController> _scrollHintControllers = [];

  bool get _isSelecting => _selectedIds.isNotEmpty;

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

  /// A one-shot hint that the selection actions row actually scrolls -
  /// mirrors `FilesView`'s identical controls-row hint (see its doc
  /// comment): nudges it right and back, once, the first time a selection
  /// starts. No-ops if there's nothing to scroll (row already fits).
  Future<void> _playScrollHint(ScrollController scrollController) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted || !scrollController.hasClients) return;
    final maxExtent = scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final double peak = maxExtent < 36 ? maxExtent : 36;
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
    _selectionActionsScrollController.dispose();
    super.dispose();
  }

  /// Mirrors `FilesView._handlePickTap` - Photos has no folders, so this is
  /// just the matching/toggle/immediate-confirm branch.
  void _handlePickTap(
    BuildContext context,
    PickController pick,
    NextcloudItem item,
  ) {
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
    PickController pick,
    List<NextcloudItem> selected,
  ) {
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
        onTap: () => _favoriteSelected(selected),
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
        onTap: () => _moveOrCopySelected(selected, copy: true),
      ),
      SelectionAction(
        icon: Icons.drive_file_move_rounded,
        label: 'Move',
        onTap: () => _moveOrCopySelected(selected, copy: false),
      ),
      if (selected.length == 1)
        SelectionAction(
          icon: Icons.info_outline_rounded,
          label: 'Details',
          onTap: () => DetailsSheet.show(context, selected.single),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final photosController = context.watch<PhotosController>();
    final filesController = context.watch<FilesController>();
    final pick = context.watch<PickController>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => photosController.fetchAllMedia(),
      );
    }

    final photos = photosController.items;
    final selectedItems = photos
        .where((i) => _selectedIds.contains(i.id))
        .toList();

    final controlsRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                photosController.sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: photosController.sortAscending
                  ? 'Ascending'
                  : 'Descending',
              onPressed: photosController.toggleSortOrder,
            ),
            Expanded(
              child: SortMenuButton(
                field: photosController.sortField,
                onChanged: photosController.setSortField,
              ),
            ),
            ToggleIconButton(
              icon: photosController.showFavoritesOnly
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              isSelected: photosController.showFavoritesOnly,
              onTap: photosController.toggleFavoritesFilter,
              tooltip: 'Favorites only',
            ),
            const SizedBox(width: 4),
            ToggleIconButton(
              icon: photosController.showHidden
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              isSelected: photosController.showHidden,
              onTap: () => photosController.toggleShowHidden(),
              tooltip: 'Show hidden files',
            ),
            const SizedBox(width: 4),
            SegmentedIconGroup(
              children: [
                ToggleIconButton(
                  icon: Symbols.circles_rounded,
                  isSelected: filesController.storageScope == StorageScope.cloud,
                  onTap: () =>
                      filesController.setStorageScope(StorageScope.cloud),
                  tooltip: 'Cloud storage',
                ),
                ToggleIconButton(
                  icon: Symbols.hard_drive_rounded,
                  isSelected:
                      filesController.storageScope == StorageScope.external,
                  onTap: () =>
                      filesController.setStorageScope(StorageScope.external),
                  tooltip: 'External storage',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final List<Widget> contentSlivers = [
      // Sticky while browsing; once selecting, the selection bar takes over
      // the very top of the screen instead (see `selectionBar` below), so
      // this is free to scroll away rather than staying pinned under it.
      SliverPersistentHeader(
        pinned: !_isSelecting,
        delegate: StickyHeaderDelegate(height: 60, child: controlsRow),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),

      if (photosController.isLoading && photos.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (photosController.errorMessage != null)
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
                    'Could not load photos',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    photosController.errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: photosController.fetchAllMedia,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (photos.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'No photos found in Nextcloud library',
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final photo = photos[index];
              return _buildPhotoTile(context, photo);
            }, childCount: photos.length),
          ),
        ),

      // Fixed clearance so the last row isn't hidden behind the floating
      // nav bar, regardless of grid length.
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
      // For a short grid this stretches the white card's background down to
      // the screen edge (matching the empty state above); for a long grid
      // that already fills the viewport it contributes nothing extra.
      const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
    ];

    return PopScope(
      canPop: !_isSelecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelecting) _clearSelection();
      },
      child: SyncedHeaderScaffold(
        scrollController: widget.scrollController,
        actions: const [MoreTabsButton(), ProfileAvatarButton()],
        onRefresh: photosController.fetchAllMedia,
        selectionBar: _isSelecting
            ? _buildSelectionBar(context, theme, pick, selectedItems)
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
    PickController pick,
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
                    pick,
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

  Widget _buildPhotoTile(BuildContext context, NextcloudItem photo) {
    final colorScheme = Theme.of(context).colorScheme;
    final pick = context.watch<PickController>();
    final session = context.watch<SessionController>();
    final isSelected = _selectedIds.contains(photo.id);

    // No border radius on the tile itself — the outer ClipRRect below is
    // the only place that rounds it, so a swipe doesn't reveal a stray
    // floating rounded corner mid-drag (see the same fix in files_view).
    final tile = GestureDetector(
      onTap: () {
        if (pick.isPicking) {
          _handlePickTap(context, pick, photo);
        } else if (_isSelecting) {
          _toggleSelection(photo);
        } else {
          _openLightbox(context, photo);
        }
      },
      onLongPress: pick.isPicking && !pick.pickRequest!.allowMultiple
          ? null
          : () => _toggleSelection(photo),
      child: ColoredBox(
        color: colorScheme.surfaceContainerHigh,
        child: SelectableThumbnail(
          isSelected: isSelected,
          checkmarkSize: 32,
          child: Stack(
            fit: StackFit.expand,
            children: [
              photo.previewUrl != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        // Decode at the tile's actual rendered size rather
                        // than the full 500x500 preview the server returns —
                        // cheaper to decode/cache while scrolling a grid.
                        final cachePixels =
                            (constraints.maxWidth *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round();
                        return Image.network(
                          photo.previewUrl!,
                          headers: session.service?.authHeaders,
                          fit: BoxFit.cover,
                          cacheWidth: cachePixels,
                          cacheHeight: cachePixels,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                          errorBuilder: (ctx, err, stack) =>
                              _buildFallbackTile(context, photo),
                        );
                      },
                    )
                  : _buildFallbackTile(context, photo),
              if (photo.type == NextcloudItemType.video)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              if (photo.isFavorite)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.favorite_rounded,
                    color: Colors.red,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return ClipRRect(borderRadius: BorderRadius.circular(16), child: tile);
  }

  Widget _buildFallbackTile(BuildContext context, NextcloudItem photo) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.secondaryContainer,
      child: Center(
        child: Icon(
          photo.type == NextcloudItemType.video
              ? Icons.movie_rounded
              : Icons.image_rounded,
          color: colorScheme.onSecondaryContainer,
          size: 32,
        ),
      ),
    );
  }

  void _openLightbox(BuildContext context, NextcloudItem photo) {
    final photos = context.read<PhotosController>().items;
    Navigator.push(
      context,
      FileViewerScreen.route(item: photo, siblings: photos),
    );
  }

  Future<void> _favoriteSelected(List<NextcloudItem> items) async {
    final ops = context.read<ItemOperations>();
    final allFavorited = items.every((i) => i.isFavorite);
    for (final item in items) {
      if (item.isFavorite == allFavorited) {
        await ops.toggleItemFavorite(item);
      }
    }
    _clearSelection();
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

  /// Hands the whole batch off to `DownloadService.kt` - see
  /// `FilesView._downloadSelected`'s identical doc comment for why.
  Future<void> _downloadSelected(
    BuildContext context,
    List<NextcloudItem> items,
  ) async {
    final session = context.read<SessionController>();
    _clearSelection();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DownloadService.startDownload(session, items);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            items.length == 1
                ? 'Downloading ${items.first.name} - see the notification for progress'
                : 'Downloading ${items.length} files - see the notification for progress',
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

    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
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
}
