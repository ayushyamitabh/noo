import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import '../theme/design_tokens.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/files_controls_row.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/files/noo_file_tile.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/lists/noo_selection_bar.dart';
import '../widgets/noo/lists/noo_settings_row.dart';
import '../widgets/noo/media/noo_grid_card.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/noo/overlays/noo_sheet.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/share_sheet.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/tabs/tab_state_slivers.dart';
import '../widgets/synced_header_scaffold.dart' show formatBytes;
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
/// Shares Files' own sort/hidden/type-filter/storage-scope/grid-list
/// display prefs (via `FilesController.applyFilesDisplayPrefs`, and
/// `FilesControlsRow` for the controls themselves) rather than a separate
/// parallel settings dimension. Renders content only - the shell owns the
/// top bar, bottom bar, drawer and FAB.
class FavoritesView extends StatefulWidget {
  final ScrollController scrollController;

  /// This tab's own shell top bar, planted as its first sliver - see
  /// `buildAppTabView`'s doc comment. Null on desktop and while picking.
  final PreferredSizeWidget? topBar;

  const FavoritesView({super.key, required this.scrollController, this.topBar});

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  bool _requested = false;
  final Set<String> _selectedIds = {};

  bool get _isSelecting => _selectedIds.isNotEmpty;

  void _toggleSelection(NextcloudItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedIds.remove(item.id)) _selectedIds.add(item.id);
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
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
    final actions = [
      SelectionAction(
        kind: SelectionActionKind.favorite,
        icon: LucideIcons.starOff,
        label: 'Remove from favorites',
        onTap: () => _unfavoriteSelected(selected),
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
        onTap: () => _moveOrCopySelected(selected, copy: true),
      ),
      SelectionAction(
        kind: SelectionActionKind.move,
        icon: LucideIcons.folderInput,
        label: 'Move',
        onTap: () => _moveOrCopySelected(selected, copy: false),
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

  /// A single item's actions (the same list the multi-select bar offers,
  /// just for one item) - mirrors `FilesView._showItemActionsSheet`.
  void _showItemActionsSheet(BuildContext context, NextcloudItem item) {
    final actions = _buildSelectionActions([item]);
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

  /// A real image/video thumbnail for [item]'s file tile/card, sized so
  /// `NooFileTile`'s `FittedBox` (which needs a concretely-sized child to
  /// scale) always has one to work with; null when there's nothing to show
  /// (falls back to the kind's soft-color tile).
  Widget? _thumbnailFor(
    BuildContext context,
    NextcloudItem item, {
    required double extent,
  }) {
    final isMedia =
        (item.type == NextcloudItemType.image ||
            item.type == NextcloudItemType.video) &&
        item.previewUrl != null;
    if (!isMedia) return null;
    final session = context.watch<SessionController>();
    return Image.network(
      item.previewUrl!,
      width: extent,
      height: extent,
      headers: session.service?.authHeaders,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
    );
  }

  String _metaFor(NextcloudItem item) {
    return item.isFolder
        ? 'Folder'
        : '${formatBytes(item.size)} · ${DateFormat.yMMMd().format(item.lastModified)}';
  }

  Widget _buildRow(
    BuildContext context,
    NextcloudItem item,
    List<NextcloudItem> siblings,
  ) {
    final isSelected = _selectedIds.contains(item.id);
    final kind = NooFileKind.from(
      name: item.name,
      mimeType: item.mimeType,
      isDirectory: item.isFolder,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NooRadii.card),
        child: NooFileRow(
          kind: kind,
          name: item.name,
          meta: _metaFor(item),
          favorite: item.isFavorite,
          iosStyle: NooLayout.iosStyle(context),
          selected: isSelected,
          thumbnail: _thumbnailFor(context, item, extent: NooSizes.rowMobile),
          onTap: () {
            if (_isSelecting) {
              _toggleSelection(item);
            } else {
              _openFavorite(context, item, siblings);
            }
          },
          onLongPress: () => _toggleSelection(item),
          onMore: () => _showItemActionsSheet(context, item),
        ),
      ),
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    NextcloudItem item,
    List<NextcloudItem> siblings,
  ) {
    final isSelected = _selectedIds.contains(item.id);
    final kind = NooFileKind.from(
      name: item.name,
      mimeType: item.mimeType,
      isDirectory: item.isFolder,
    );

    return NooFileTableRow(
      kind: kind,
      name: item.name,
      col2: item.isFolder ? null : DateFormat.yMMMd().format(item.lastModified),
      col3: item.isFolder ? null : formatBytes(item.size),
      favorite: item.isFavorite,
      selected: isSelected,
      thumbnail: _thumbnailFor(
        context,
        item,
        extent: NooFileTileSize.desktop.extent,
      ),
      onTap: () {
        if (_isSelecting) {
          _toggleSelection(item);
        } else {
          _openFavorite(context, item, siblings);
        }
      },
      // Desktop has no long-press gesture; right-click is this row's
      // equivalent entry point into multi-select.
      onSecondaryTap: () => _toggleSelection(item),
      onMore: () => _showItemActionsSheet(context, item),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    NextcloudItem item,
    List<NextcloudItem> siblings,
    bool isDesktop,
  ) {
    final colors = context.nooColors;
    final isSelected = _selectedIds.contains(item.id);
    final kind = NooFileKind.from(
      name: item.name,
      mimeType: item.mimeType,
      isDirectory: item.isFolder,
    );
    final thumbnailHeight = isDesktop ? 118.0 : 104.0;

    return NooGridCard(
      name: item.name,
      meta: item.isFolder ? 'Folder' : formatBytes(item.size),
      placeholderColor: kind.background(colors),
      icon: kind.icon,
      iconColor: kind.foreground(colors),
      thumbnailHeight: thumbnailHeight,
      thumbnail: _thumbnailFor(context, item, extent: thumbnailHeight),
      selected: isSelected,
      verticalOverflowIcon: !NooLayout.iosStyle(context),
      onTap: () {
        if (_isSelecting) {
          _toggleSelection(item);
        } else {
          _openFavorite(context, item, siblings);
        }
      },
      onLongPress: () => _toggleSelection(item),
      onMore: () => _showItemActionsSheet(context, item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final isDesktop = NooLayout.isDesktop(context);
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

    final controlsRow = Padding(
      padding: const EdgeInsets.fromLTRB(
        NooSpace.sm,
        NooSpace.sm,
        NooSpace.sm,
        NooSpace.xs,
      ),
      child: FilesControlsRow(folderPath: filesController.currentFolderPath),
    );

    final contentSlivers = <Widget>[
      if (widget.topBar != null) topBarSliver(widget.topBar!),
      SliverPersistentHeader(
        pinned: !_isSelecting,
        delegate: StickyHeaderDelegate(
          height: _isSelecting ? 56 : 64,
          child: _isSelecting
              ? _buildSelectionBar(context, selectedItems)
              : controlsRow,
        ),
      ),
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
                  Icon(LucideIcons.circleAlert, size: 56, color: colors.danger),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load favorites',
                    style: NooText.cardTitle.copyWith(color: colors.danger),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favoritesController.errorMessage!,
                    textAlign: TextAlign.center,
                    style: NooText.body.copyWith(color: colors.fg3),
                  ),
                  const SizedBox(height: 20),
                  NooButton(
                    variant: NooButtonVariant.secondary,
                    size: NooButtonSize.field,
                    icon: LucideIcons.refreshCw,
                    onTap: favoritesController.fetchAll,
                    child: const Text('Retry'),
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
                Icon(LucideIcons.star, size: 56, color: colors.fg3),
                const SizedBox(height: 12),
                Text(
                  'No favorites yet',
                  style: NooText.cardTitle.copyWith(color: colors.fg2),
                ),
              ],
            ),
          ),
        )
      else if (filesController.isGridView)
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: NooLayout.gutter(context),
            vertical: NooSpace.xs,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isDesktop ? 5 : 2,
              crossAxisSpacing: isDesktop ? 16 : 10,
              mainAxisSpacing: isDesktop ? 16 : 10,
              childAspectRatio: isDesktop ? 0.92 : 0.85,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildGridCard(
                context,
                favorites[index],
                siblings,
                isDesktop,
              );
            }, childCount: favorites.length),
          ),
        )
      else if (isDesktop)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: NooLayout.gutter(context)),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index == 0) {
                return NooFileTableHeader(
                  col2Label: 'Modified',
                  col3Label: 'Size',
                  sortColumn: switch (filesController.filesSortField) {
                    FileSortField.name => 0,
                    FileSortField.dateModified => 1,
                    FileSortField.size => 2,
                    FileSortField.dateCreated => null,
                  },
                  sortAscending: filesController.filesSortAscending,
                  onSort: (column) {
                    final field = [
                      FileSortField.name,
                      FileSortField.dateModified,
                      FileSortField.size,
                    ][column];
                    if (field == filesController.filesSortField) {
                      filesController.toggleFilesSortOrder();
                    } else {
                      filesController.setFilesSortField(field);
                    }
                  },
                );
              }
              return _buildTableRow(context, favorites[index - 1], siblings);
            }, childCount: favorites.length + 1),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: NooLayout.gutter(context)),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildRow(context, favorites[index], siblings);
            }, childCount: favorites.length),
          ),
        ),
      SliverToBoxAdapter(child: SizedBox(height: bottomBarClearance(context))),
    ];

    return PopScope(
      canPop: !_isSelecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelecting) _clearSelection();
      },
      child: ColoredBox(
        color: colors.bg,
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.surface,
          onRefresh: favoritesController.fetchAll,
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

  /// Replaces the controls row's own sticky slot while selecting - mirrors
  /// Files/Photos' identical selection bar.
  Widget _buildSelectionBar(
    BuildContext context,
    List<NextcloudItem> selectedItems,
  ) {
    return NooSelectionBar(
      count: selectedItems.length,
      actions: _buildSelectionActions(selectedItems),
      onClose: _clearSelection,
      isDesktop: NooLayout.isDesktop(context),
      iosStyle: NooLayout.iosStyle(context),
    );
  }
}
