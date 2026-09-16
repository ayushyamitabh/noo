import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/selection_action.dart';
import '../providers/server_provider.dart';
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

class PhotosView extends StatefulWidget {
  final ScrollController scrollController;

  const PhotosView({super.key, required this.scrollController});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
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

  /// The bulk actions shown in the sticky selection toolbar for the
  /// currently-selected items.
  List<SelectionAction> _buildSelectionActions(
    ServerProvider provider,
    List<NextcloudItem> selected,
  ) {
    return [
      SelectionAction(
        icon: selected.every((i) => i.isFavorite)
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        label: selected.every((i) => i.isFavorite)
            ? 'Remove from favorites'
            : 'Favorite',
        color: Colors.red.shade400,
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
        color: Theme.of(context).colorScheme.error,
        onTap: () => _confirmDeleteSelected(context, provider, selected),
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
    final provider = context.watch<ServerProvider>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.fetchAllMedia(),
      );
    }

    final photos = provider.photoItems;
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
                provider.sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: provider.sortAscending ? 'Ascending' : 'Descending',
              onPressed: provider.toggleSortOrder,
            ),
            Expanded(
              child: SortMenuButton(
                field: provider.sortField,
                onChanged: provider.setSortField,
              ),
            ),
            ToggleIconButton(
              icon: provider.showFavoritesOnlyPhotos
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              isSelected: provider.showFavoritesOnlyPhotos,
              onTap: provider.toggleFavoritesFilterPhotos,
              tooltip: 'Favorites only',
            ),
            const SizedBox(width: 4),
            ToggleIconButton(
              icon: provider.showHiddenPhotos
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              isSelected: provider.showHiddenPhotos,
              onTap: provider.toggleShowHiddenPhotos,
              tooltip: 'Show hidden files',
            ),
            const SizedBox(width: 4),
            SegmentedIconGroup(
              children: [
                ToggleIconButton(
                  icon: Symbols.circles_rounded,
                  isSelected: provider.storageScope == StorageScope.cloud,
                  onTap: () => provider.setStorageScope(StorageScope.cloud),
                  tooltip: 'Cloud storage',
                ),
                ToggleIconButton(
                  icon: Symbols.hard_drive_rounded,
                  isSelected: provider.storageScope == StorageScope.external,
                  onTap: () => provider.setStorageScope(StorageScope.external),
                  tooltip: 'External storage',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final List<Widget> contentSlivers = [
      // Sticky while browsing; once selecting, the toolbar below takes over
      // the pinned slot and this is free to scroll away.
      SliverPersistentHeader(
        pinned: !_isSelecting,
        delegate: StickyHeaderDelegate(height: 60, child: controlsRow),
      ),
      if (_isSelecting)
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel selection',
            onPressed: _clearSelection,
          ),
          title: Text('${selectedItems.length} selected'),
          actions: [
            for (final action in _buildSelectionActions(
              provider,
              selectedItems,
            ))
              IconButton(
                icon: Icon(action.icon, color: action.color),
                tooltip: action.label,
                onPressed: action.onTap,
              ),
            const SizedBox(width: 4),
          ],
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),

      if (provider.isMediaLoading && photos.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (provider.mediaErrorMessage != null)
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
                    provider.mediaErrorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: provider.fetchAllMedia,
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
              return _buildPhotoTile(context, photo, provider);
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
        provider: provider,
        actions: const [MoreTabsButton(), ProfileAvatarButton()],
        onRefresh: provider.fetchAllMedia,
        contentSlivers: contentSlivers,
      ),
    );
  }

  Widget _buildPhotoTile(
    BuildContext context,
    NextcloudItem photo,
    ServerProvider provider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedIds.contains(photo.id);

    // No border radius on the tile itself — the outer ClipRRect below is
    // the only place that rounds it, so a swipe doesn't reveal a stray
    // floating rounded corner mid-drag (see the same fix in files_view).
    final tile = GestureDetector(
      onTap: () {
        if (_isSelecting) {
          _toggleSelection(photo);
        } else {
          _openLightbox(context, photo, provider);
        }
      },
      onLongPress: () => _toggleSelection(photo),
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
                          headers: provider.service?.authHeaders,
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

  void _openLightbox(
    BuildContext context,
    NextcloudItem photo,
    ServerProvider provider,
  ) {
    Navigator.push(
      context,
      FileViewerScreen.route(item: photo, siblings: provider.photoItems),
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

  Future<void> _downloadSelected(
    BuildContext context,
    ServerProvider provider,
    List<NextcloudItem> items,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading ${items.length} item(s)...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    var succeeded = 0;
    for (final item in items) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempPath = p.join(tempDir.path, item.name);
        await provider.service!.downloadToFile(item.path, tempPath);
        final ext = p.extension(item.name).replaceFirst('.', '');
        final baseName = p.basenameWithoutExtension(item.name);
        await FileSaver.instance.saveFile(
          name: baseName,
          filePath: tempPath,
          ext: ext,
        );
        succeeded++;
      } catch (_) {
        // Reported in the summary snackbar below.
      }
    }

    _clearSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloaded $succeeded of ${items.length} item(s)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
}
