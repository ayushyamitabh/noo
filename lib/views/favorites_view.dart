import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../providers/favorites_controller.dart';
import '../providers/files_controller.dart';
import '../providers/item_operations.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../services/download_service.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/item_icon.dart';
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

/// Every favorited file/folder across the whole account, account-wide - a
/// real tab rather than a filter toggle scoped to whatever folder the
/// Files tab happens to be browsing (see `FavoritesController.fetchAll`
/// for why: a favorited item several folders deep needs to show up
/// regardless of whether its parent folders are themselves favorited,
/// which a current-folder-only filter can never do, and a flat account-
/// wide list also means the breadcrumb-vs-content mismatch a filter
/// toggle had - the trail showing wherever Files was last browsing while
/// the content showed something else entirely - simply can't happen).
/// Shares Files' own sort/hidden/storage-scope/grid-list display prefs
/// (via `FilesController.applyFilesDisplayPrefs`) rather than a separate
/// parallel settings dimension.
class FavoritesView extends StatefulWidget {
  final ScrollController scrollController;

  const FavoritesView({super.key, required this.scrollController});

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView>
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

  /// Mirrors `FilesView`/`PhotosView`'s identical scroll-hint - see their
  /// doc comment: nudges the selection actions row right and back, once,
  /// the first time a selection starts. No-ops if there's nothing to
  /// scroll (row already fits).
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

  /// A favorited folder switches to the Files tab, navigated there; a
  /// favorited file just opens directly from here, like Files/Photos do -
  /// no need to reposition Files first since dismissing the viewer lands
  /// back on this tab either way.
  void _openFavorite(
    BuildContext context,
    NextcloudItem item,
    List<NextcloudItem> siblings,
  ) {
    if (item.isFolder) {
      context.read<FilesController>().navigateToAbsoluteFolder(item.path);
      context.read<SettingsController>().requestTab(AppTab.files);
    } else {
      Navigator.push(
        context,
        FileViewerScreen.route(item: item, siblings: siblings),
      );
    }
  }

  /// The bulk actions shown in the sticky selection toolbar for the
  /// currently-selected items - same set Files/Photos offer.
  List<SelectionAction> _buildSelectionActions(List<NextcloudItem> selected) {
    return [
      SelectionAction(
        icon: Icons.favorite_border_rounded,
        label: 'Remove from favorites',
        onTap: () => _unfavoriteSelected(selected),
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

  Future<void> _unfavoriteSelected(List<NextcloudItem> items) async {
    final ops = context.read<ItemOperations>();
    for (final item in items) {
      await ops.toggleItemFavorite(item);
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
    final files = items.where((i) => !i.isFolder).toList();
    _clearSelection();
    if (files.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
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

  Widget _buildControlsRow(FilesController files) {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                files.filesSortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: files.filesSortAscending ? 'Ascending' : 'Descending',
              onPressed: files.toggleFilesSortOrder,
            ),
            SizedBox(
              width: 130,
              child: SortMenuButton(
                field: files.filesSortField,
                onChanged: files.setFilesSortField,
              ),
            ),
            ToggleIconButton(
              icon: files.showHiddenFiles
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              isSelected: files.showHiddenFiles,
              onTap: () => files.toggleShowHiddenFiles(),
              tooltip: 'Show hidden files',
            ),
            const SizedBox(width: 4),
            SegmentedIconGroup(
              children: [
                ToggleIconButton(
                  icon: Symbols.circles_rounded,
                  isSelected: files.storageScope == StorageScope.cloud,
                  onTap: () => files.setStorageScope(StorageScope.cloud),
                  tooltip: 'Cloud storage',
                ),
                ToggleIconButton(
                  icon: Symbols.hard_drive_rounded,
                  isSelected: files.storageScope == StorageScope.external,
                  onTap: () => files.setStorageScope(StorageScope.external),
                  tooltip: 'External storage',
                ),
              ],
            ),
            const SizedBox(width: 8),
            SegmentedIconGroup(
              children: [
                ToggleIconButton(
                  icon: Icons.view_list_rounded,
                  isSelected: !files.isGridView,
                  onTap: () => files.setGridView(false),
                  tooltip: 'List view',
                ),
                ToggleIconButton(
                  icon: Icons.grid_view_rounded,
                  isSelected: files.isGridView,
                  onTap: () => files.setGridView(true),
                  tooltip: 'Grid view',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context,
    NextcloudItem item,
    List<NextcloudItem> siblings,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = context.watch<SessionController>();
    final isSelected = _selectedIds.contains(item.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerLow,
          child: InkWell(
            onTap: () {
              if (_isSelecting) {
                _toggleSelection(item);
              } else {
                _openFavorite(context, item, siblings);
              }
            },
            onLongPress: () => _toggleSelection(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  SelectableThumbnail(
                    isSelected: isSelected,
                    size: 44,
                    checkmarkSize: 24,
                    child: ItemThumbnail(
                      item: item,
                      service: session.service,
                      size: 44,
                      borderRadius: 12,
                      iconSize: 22,
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
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    NextcloudItem item,
    List<NextcloudItem> siblings,
  ) {
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final isSelected = _selectedIds.contains(item.id);
    final isMedia =
        (item.type == NextcloudItemType.image ||
            item.type == NextcloudItemType.video) &&
        item.previewUrl != null;
    final iconColor = getIconColor(context, item.type);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: () {
            if (_isSelecting) {
              _toggleSelection(item);
            } else {
              _openFavorite(context, item, siblings);
            }
          },
          onLongPress: () => _toggleSelection(item),
          child: SelectableThumbnail(
            isSelected: isSelected,
            checkmarkSize: 32,
            child: isMedia
                ? Image.network(
                    item.previewUrl!,
                    headers: session.service?.authHeaders,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    errorBuilder: (ctx, err, stack) => Container(
                      color: theme.colorScheme.secondaryContainer,
                      child: Icon(
                        getItemIcon(item.type),
                        color: theme.colorScheme.onSecondaryContainer,
                        size: 32,
                      ),
                    ),
                  )
                : Padding(
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
                          child: Icon(
                            getItemIcon(item.type),
                            color: iconColor,
                            size: 24,
                          ),
                        ),
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final favoritesController = context.watch<FavoritesController>();
    final filesController = context.watch<FilesController>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => favoritesController.fetchAll(),
      );
    }

    final favorites = favoritesController.items;
    final siblings = favorites.where((i) => !i.isFolder).toList();
    final selectedItems = favorites
        .where((i) => _selectedIds.contains(i.id))
        .toList();

    final contentSlivers = <Widget>[
      SliverPersistentHeader(
        pinned: !_isSelecting,
        delegate: StickyHeaderDelegate(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildControlsRow(filesController),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
      if (favoritesController.isLoading && favorites.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (favoritesController.errorMessage != null)
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
                    'Could not load favorites',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favoritesController.errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: favoritesController.fetchAll,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (favorites.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 64,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'No favorites yet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        )
      else if (filesController.isGridView)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildGridCard(context, favorites[index], siblings);
            }, childCount: favorites.length),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildListTile(context, favorites[index], siblings);
            }, childCount: favorites.length),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
        onRefresh: favoritesController.fetchAll,
        selectionBar: _isSelecting
            ? _buildSelectionBar(context, theme, selectedItems)
            : null,
        contentSlivers: contentSlivers,
      ),
    );
  }

  /// Replaces the top bar entirely while selecting (see
  /// `SyncedHeaderScaffold.selectionBar`) - mirrors Files/Photos' identical
  /// selection bar.
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in _buildSelectionActions(selectedItems))
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
}
