import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../providers/files_controller.dart';
import '../providers/item_operations.dart';
import '../providers/photos_controller.dart';
import '../providers/pick_controller.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../services/download_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/core/noo_chip.dart';
import '../widgets/noo/core/noo_segmented_control.dart';
import '../widgets/noo/core/noo_toggle.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/lists/noo_selection_bar.dart';
import '../widgets/noo/lists/noo_settings_row.dart';
import '../widgets/noo/media/noo_photo_group.dart';
import '../widgets/noo/media/noo_photo_tile.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/noo/overlays/noo_sheet.dart';
import '../widgets/share_sheet.dart';
import '../widgets/sort_menu_button.dart' show sortFieldLabel;
import '../widgets/sticky_header_delegate.dart';
import '../widgets/tabs/tab_state_slivers.dart';
import 'file_viewer_screen.dart';
import 'move_copy_destination_picker.dart';

/// The type chips PhotosController actually has data for (DESIGN_SYSTEM.md
/// section 4 also lists "Camera", but there's no camera-upload/EXIF source
/// to distinguish that from any other photo - see the view's doc comment).
enum _PhotoTypeFilter { all, image, video }

/// A contiguous run of [PhotosController.items] that shares a calendar
/// month, in whatever order the controller already sorted them - see
/// [_PhotosViewState._groupByMonth].
class _MonthGroup {
  final DateTime month;
  final List<NextcloudItem> items;
  _MonthGroup(this.month, this.items);
}

/// The Photos tab: every image/video across the account, grouped by month
/// (DESIGN_SYSTEM.md section 4). Renders content only - the shell
/// (`MainShellView`) owns the top bar, bottom bar, drawer and FAB.
class PhotosView extends StatefulWidget {
  final ScrollController scrollController;

  /// This tab's own shell top bar, planted as its first sliver - see
  /// `buildAppTabView`'s doc comment. Null on desktop and while picking.
  final PreferredSizeWidget? topBar;

  const PhotosView({super.key, required this.scrollController, this.topBar});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  bool _requested = false;
  final Set<String> _selectedIds = {};

  // Session-local only (not one of PhotosController's persisted display
  // prefs) - a pure narrowing of the already-fetched/filtered/sorted list,
  // same way the type chips narrow Files' listing without touching the
  // controller.
  _PhotoTypeFilter _typeFilter = _PhotoTypeFilter.all;

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
          kind: SelectionActionKind.favorite,
          icon: LucideIcons.check,
          label: 'Use ${selected.length} item(s)',
          onTap: () => pick.confirmPick(selected),
        ),
      ];
    }
    // Matches the star/star-off convention Files' own selection toolbar
    // uses for favorite/unfavorite (see `files_view.dart`) rather than a
    // filled heart.
    final allFavorited = selected.every((i) => i.isFavorite);
    final actions = [
      SelectionAction(
        kind: SelectionActionKind.favorite,
        icon: allFavorited ? LucideIcons.starOff : LucideIcons.star,
        label: allFavorited ? 'Remove from favorites' : 'Favorite',
        onTap: () => _favoriteSelected(selected),
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

  /// Splits an already-filtered/sorted list into contiguous month runs
  /// (`dateCreated`) in list order - deliberately not a global re-sort by
  /// date, so a "Name"/"Size" sort chip still governs the order shown
  /// (see the group header row it feeds).
  List<_MonthGroup> _groupByMonth(List<NextcloudItem> items) {
    final groups = <_MonthGroup>[];
    for (final item in items) {
      final d = item.dateCreated;
      final month = DateTime(d.year, d.month);
      if (groups.isNotEmpty && groups.last.month == month) {
        groups.last.items.add(item);
      } else {
        groups.add(_MonthGroup(month, [item]));
      }
    }
    return groups;
  }

  bool _matchesTypeFilter(NextcloudItem item) {
    switch (_typeFilter) {
      case _PhotoTypeFilter.all:
        return true;
      case _PhotoTypeFilter.image:
        return item.type == NextcloudItemType.image;
      case _PhotoTypeFilter.video:
        return item.type == NextcloudItemType.video;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final isDesktop = NooLayout.isDesktop(context);
    final photosController = context.watch<PhotosController>();
    final filesController = context.watch<FilesController>();
    final pick = context.watch<PickController>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => photosController.fetchAllMedia(),
      );
    }

    final allPhotos = photosController.items;
    final visiblePhotos = allPhotos.where(_matchesTypeFilter).toList();
    // Selection tracks the full (favorites/hidden-filtered) list, not just
    // the type-filtered view, so switching the type chip mid-selection
    // never silently drops a selected item from the bulk actions.
    final selectedItems = allPhotos
        .where((i) => _selectedIds.contains(i.id))
        .toList();
    final groups = _groupByMonth(visiblePhotos);

    final controlsRow = _buildControlsRow(
      context,
      photosController,
      filesController,
    );

    final List<Widget> contentSlivers = [
      if (widget.topBar != null) topBarSliver(widget.topBar!),
      // Sticky while browsing; once selecting, the selection bar takes over
      // the same slot instead.
      SliverPersistentHeader(
        pinned: !_isSelecting,
        delegate: StickyHeaderDelegate(
          height: _isSelecting ? 56 : 64,
          child: _isSelecting
              ? _buildSelectionBar(context, pick, selectedItems)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NooSpace.sm,
                    NooSpace.sm,
                    NooSpace.sm,
                    NooSpace.xs,
                  ),
                  child: controlsRow,
                ),
        ),
      ),

      if (photosController.isLoading && allPhotos.isEmpty)
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
                  Icon(LucideIcons.circleAlert, size: 56, color: colors.danger),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load photos',
                    style: NooText.cardTitle.copyWith(color: colors.danger),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    photosController.errorMessage!,
                    textAlign: TextAlign.center,
                    style: NooText.body.copyWith(color: colors.fg3),
                  ),
                  const SizedBox(height: 20),
                  NooButton(
                    variant: NooButtonVariant.secondary,
                    size: NooButtonSize.field,
                    icon: LucideIcons.refreshCw,
                    onTap: photosController.fetchAllMedia,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (visiblePhotos.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.image, size: 56, color: colors.fg3),
                const SizedBox(height: 12),
                Text(
                  allPhotos.isEmpty
                      ? 'No photos found in Nextcloud library'
                      : 'No photos match this filter',
                  style: NooText.cardTitle.copyWith(color: colors.fg2),
                ),
              ],
            ),
          ),
        )
      else
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: NooPhotoGroupHeader(
              title: DateFormat('MMMM yyyy').format(group.month),
              count:
                  '${group.items.length} ${group.items.length == 1 ? 'item' : 'items'}',
              padding: EdgeInsets.fromLTRB(
                NooLayout.gutter(context),
                NooSpace.lg,
                NooLayout.gutter(context),
                NooSpace.sm,
              ),
            ),
          ),
          NooPhotoGrid(
            itemCount: group.items.length,
            columns: isDesktop
                ? NooPhotoGrid.desktopColumns
                : NooLayout.gridColumns(
                    context,
                    phone: NooPhotoGrid.mobileColumns,
                    minTile: 130,
                  ),
            gap: isDesktop ? NooPhotoGrid.desktopGap : NooPhotoGrid.mobileGap,
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? NooLayout.gutter(context) : 0,
            ),
            itemBuilder: (context, index) =>
                _buildPhotoTile(context, group.items[index], visiblePhotos),
          ),
        ],

      // Clearance so the last row isn't hidden behind the nav bar,
      // regardless of grid length - see `bottomBarClearance`'s own doc
      // comment for why this has to be dynamic rather than a flat 100.
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
          onRefresh: photosController.fetchAllMedia,
          // See files_view.dart's identical fix - without this, the sticky
          // controls row rides up under the status bar once the floating
          // top bar above it fully collapses.
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
      ),
    );
  }

  /// Type chips (All/Photos/Videos - "Camera" from the spec has no data
  /// source, see the view's doc comment), a sort chip and a filter chip for
  /// favorites-only/hidden/external-storage, mirroring `FilesControlsRow`'s
  /// layout/pattern.
  Widget _buildControlsRow(
    BuildContext context,
    PhotosController photos,
    FilesController files,
  ) {
    final filtersActive =
        _typeFilter != _PhotoTypeFilter.all ||
        photos.showFavoritesOnly ||
        photos.showHidden ||
        files.storageScope != StorageScope.cloud;

    // A plain Row, not a horizontally-scrolling one - see
    // `FilesControlsRow`'s identical fix/doc comment: a `SingleChildScrollView`
    // gives its child unbounded width for no benefit here (two chips never
    // need to scroll), and it's actively harmful for a row with a trailing
    // `Spacer`/flex child.
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          NooChip(
            icon: photos.sortAscending
                ? LucideIcons.arrowUp
                : LucideIcons.arrowDown,
            onTap: () => _showSortSheet(context, photos),
            child: Text(sortFieldLabel(photos.sortField)),
          ),
          const SizedBox(width: 8),
          NooChip(
            icon: LucideIcons.filter,
            trailing: NooChipTrailing.menu,
            selected: filtersActive,
            onTap: () => _showFilterSheet(context, photos, files),
            child: const Text('Filters'),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context, PhotosController photos) {
    showNooSheet(
      context,
      children: [
        // `showNooSheet`'s `children` are built once, up front - a bare
        // checkmark here would freeze at whatever it was when the sheet
        // opened, since tapping a row calls `photos.set...`/notifies the
        // controller, not this already-built widget tree. `ListenableBuilder`
        // re-runs its `builder` on every notification instead, so the
        // selection updates live.
        ListenableBuilder(
          listenable: photos,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NooSegmentedControl<bool>(
                fill: true,
                onSurface: true,
                value: photos.sortAscending,
                onChanged: (asc) {
                  if (asc != photos.sortAscending) photos.toggleSortOrder();
                },
                options: const [
                  NooSegmentOption(
                    value: true,
                    icon: LucideIcons.arrowUp,
                    label: 'Ascending',
                  ),
                  NooSegmentOption(
                    value: false,
                    icon: LucideIcons.arrowDown,
                    label: 'Descending',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              NooGroupedList(
                children: [
                  for (final field in FileSortField.values)
                    NooSettingsRow(
                      label: Text(sortFieldLabel(field)),
                      trailing: field == photos.sortField
                          ? Icon(
                              LucideIcons.check,
                              size: 18,
                              color: context.nooColors.accentText,
                            )
                          : null,
                      onTap: () {
                        photos.setSortField(field);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFilterSheet(
    BuildContext context,
    PhotosController photos,
    FilesController files,
  ) {
    showNooSheet(
      context,
      children: [
        // `_typeFilter` lives on this State, not a ChangeNotifier, so
        // `Listenable.merge([photos, files])` alone doesn't rebuild this
        // sheet when it changes - it used to only visibly move once the
        // sheet was closed and reopened. `StatefulBuilder` gives it a
        // rebuild trigger of its own; see `_showSortSheet`'s comment for
        // why the two controllers still need `ListenableBuilder`.
        StatefulBuilder(
          builder: (context, setSheetState) => ListenableBuilder(
            listenable: Listenable.merge([photos, files]),
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Same "icon always, label only when selected" pill as
                // Files' own type filter - not a fully-labelled track, so
                // the two screens' filter sheets look and behave the same.
                NooSegmentedControl<_PhotoTypeFilter>(
                  fill: true,
                  onSurface: true,
                  labelOnlySelected: true,
                  value: _typeFilter,
                  onChanged: (filter) => setState(() {
                    _typeFilter = filter;
                    setSheetState(() {});
                  }),
                  options: const [
                    NooSegmentOption(
                      value: _PhotoTypeFilter.all,
                      icon: LucideIcons.layoutGrid,
                      label: 'All',
                    ),
                    NooSegmentOption(
                      value: _PhotoTypeFilter.image,
                      icon: LucideIcons.image,
                      label: 'Photos',
                    ),
                    NooSegmentOption(
                      value: _PhotoTypeFilter.video,
                      icon: LucideIcons.film,
                      label: 'Videos',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                NooGroupedList(
                  children: [
                    NooSettingsRow(
                      icon: LucideIcons.heart,
                      label: const Text('Favorites only'),
                      trailing: NooToggle(
                        checked: photos.showFavoritesOnly,
                        onChanged: (_) => photos.toggleFavoritesFilter(),
                      ),
                    ),
                    NooSettingsRow(
                      icon: LucideIcons.eye,
                      label: const Text('Show hidden files'),
                      trailing: NooToggle(
                        checked: photos.showHidden,
                        onChanged: (_) => photos.toggleShowHidden(),
                      ),
                    ),
                    NooSettingsRow(
                      icon: LucideIcons.hardDrive,
                      label: const Text('External storage'),
                      trailing: NooToggle(
                        checked: files.storageScope == StorageScope.external,
                        onChanged: (external) => files.setStorageScope(
                          external ? StorageScope.external : StorageScope.cloud,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Replaces the controls row's own sticky slot while selecting - a close
  /// button, the "N selected" count, and the bulk actions. Mirrors
  /// `FilesView`'s identical selection bar.
  Widget _buildSelectionBar(
    BuildContext context,
    PickController pick,
    List<NextcloudItem> selectedItems,
  ) {
    return NooSelectionBar(
      count: selectedItems.length,
      actions: _buildSelectionActions(pick, selectedItems),
      onClose: _clearSelection,
      isDesktop: NooLayout.isDesktop(context),
      iosStyle: NooLayout.iosStyle(context),
    );
  }

  Widget _buildPhotoTile(
    BuildContext context,
    NextcloudItem photo,
    List<NextcloudItem> siblings,
  ) {
    final pick = context.watch<PickController>();
    final session = context.watch<SessionController>();
    final isSelected = _selectedIds.contains(photo.id);
    final isVideo = photo.type == NextcloudItemType.video;

    return NooPhotoTile(
      selected: isSelected,
      selectionMode: _isSelecting,
      // No real duration source (no video-metadata extraction anywhere in
      // the app) - an empty string still marks it as a video and shows the
      // icon-only badge (DESIGN_SYSTEM.md: "else icon-only").
      videoDuration: isVideo ? '' : null,
      placeholderColor: NooPhotoTile.paletteColor(photo.id.hashCode),
      onTap: () {
        if (pick.isPicking) {
          _handlePickTap(context, pick, photo);
        } else if (_isSelecting) {
          _toggleSelection(photo);
        } else {
          _openLightbox(context, photo, siblings);
        }
      },
      onLongPress: pick.isPicking && !pick.pickRequest!.allowMultiple
          ? null
          : () => _toggleSelection(photo),
      child: photo.previewUrl != null
          ? LayoutBuilder(
              builder: (context, constraints) {
                // Decode at the tile's actual rendered size rather than the
                // full 500x500 preview the server returns - cheaper to
                // decode/cache while scrolling a grid.
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
    );
  }

  Widget _buildFallbackTile(BuildContext context, NextcloudItem photo) {
    final colors = context.nooColors;
    final kind = NooFileKind.from(name: photo.name, mimeType: photo.mimeType);
    return ColoredBox(
      color: kind.background(colors),
      child: Center(
        child: Icon(kind.icon, color: kind.foreground(colors), size: 32),
      ),
    );
  }

  void _openLightbox(
    BuildContext context,
    NextcloudItem photo,
    List<NextcloudItem> siblings,
  ) {
    Navigator.push(
      context,
      FileViewerScreen.route(item: photo, siblings: siblings),
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
