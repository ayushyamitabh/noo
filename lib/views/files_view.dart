import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/segmented_icon_toggle.dart';
import 'file_viewer_screen.dart';

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class FilesView extends StatefulWidget {
  final ScrollController scrollController;

  const FilesView({super.key, required this.scrollController});

  @override
  State<FilesView> createState() => _FilesViewState();
}

IconData _getItemIcon(NextcloudItemType type) {
  switch (type) {
    case NextcloudItemType.folder:
      return Icons.folder_rounded;
    case NextcloudItemType.image:
      return Icons.image_rounded;
    case NextcloudItemType.video:
      return Icons.movie_rounded;
    case NextcloudItemType.audio:
      return Icons.audiotrack_rounded;
    case NextcloudItemType.document:
      return Icons.description_rounded;
    case NextcloudItemType.archive:
      return Icons.folder_zip_rounded;
    case NextcloudItemType.file:
      return Icons.insert_drive_file_rounded;
  }
}

Color _getIconColor(BuildContext context, NextcloudItemType type) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (type) {
    case NextcloudItemType.folder:
      return colorScheme.primary;
    case NextcloudItemType.image:
      return Colors.amber.shade700;
    case NextcloudItemType.video:
      return Colors.deepOrange.shade600;
    case NextcloudItemType.audio:
      return Colors.purple.shade600;
    case NextcloudItemType.document:
      return Colors.blue.shade700;
    case NextcloudItemType.archive:
      return Colors.teal.shade700;
    case NextcloudItemType.file:
      return colorScheme.outline;
  }
}

/// A file/folder's icon badge — for images and videos this shows an actual
/// thumbnail (falling back to the plain icon on error or if there's no
/// preview URL yet), matching the real-content treatment already used in
/// the Photos tab.
class _ItemThumbnail extends StatelessWidget {
  final NextcloudItem item;
  final ServerProvider provider;
  final double size;
  final double borderRadius;
  final double iconSize;

  const _ItemThumbnail({
    required this.item,
    required this.provider,
    required this.size,
    required this.borderRadius,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor(context, item.type);
    final isMedia =
        item.type == NextcloudItemType.image ||
        item.type == NextcloudItemType.video;
    // Decode straight to the size this thumbnail is actually painted at —
    // the server hands back a 500x500 preview regardless, and decoding that
    // in full for a ~40dp tile (times however many are on screen while
    // scrolling) is a real source of jank.
    final cachePixels = (size * MediaQuery.of(context).devicePixelRatio)
        .round();

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: isMedia && item.previewUrl != null
          ? Stack(
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
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: Icon(
                        _getItemIcon(item.type),
                        color: iconColor,
                        size: iconSize,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => Center(
                    child: Icon(
                      _getItemIcon(item.type),
                      color: iconColor,
                      size: iconSize,
                    ),
                  ),
                ),
                if (item.type == NextcloudItemType.video)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
              ],
            )
          : Center(
              child: Icon(
                _getItemIcon(item.type),
                color: iconColor,
                size: iconSize,
              ),
            ),
    );
  }
}

String _sortFieldLabel(FileSortField field) {
  switch (field) {
    case FileSortField.name:
      return 'Name';
    case FileSortField.dateCreated:
      return 'Date created';
    case FileSortField.dateModified:
      return 'Date modified';
    case FileSortField.size:
      return 'Size';
  }
}

/// Dropdown trigger (replacing the old "My files" label) for choosing which
/// field the file list is sorted by.
class _SortMenuButton extends StatelessWidget {
  final FileSortField field;
  final ValueChanged<FileSortField> onChanged;

  const _SortMenuButton({required this.field, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopupMenuButton<FileSortField>(
      initialValue: field,
      onSelected: onChanged,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => FileSortField.values.map((f) {
        return PopupMenuItem(
          value: f,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: f == field
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(_sortFieldLabel(f)),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sortFieldLabel(field),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable "Home / Folder / Sub-folder" trail shown under the sort/filter
/// row whenever the user has navigated below the root.
class _Breadcrumbs extends StatelessWidget {
  final List<String> pathStack;
  final ValueChanged<int> onTap;

  const _Breadcrumbs({required this.pathStack, required this.onTap});

  String _labelFor(int index) {
    if (index == 0) return 'Home';
    final segments = pathStack[index]
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? 'Home' : segments.last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lastIndex = pathStack.length - 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < pathStack.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colorScheme.outlineVariant,
                ),
              ),
            if (i == lastIndex)
              Text(
                _labelFor(i),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              )
            else
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Text(
                    _labelFor(i),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FilesViewState extends State<FilesView> {
  static const double _lockThreshold = 100;
  static const double _syncThreshold = 14;
  static const double _pullingEpsilon = 8;

  bool _headerLocked = false;
  bool _isPulling = false;
  double _pullDistance = 0;

  void _revealPanel() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _lockOpen() {
    if (!_headerLocked) setState(() => _headerLocked = true);
    _revealPanel();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.pixels < metrics.minScrollExtent) {
      _pullDistance = metrics.minScrollExtent - metrics.pixels;
      final pulling = _pullDistance > _pullingEpsilon;
      if (pulling != _isPulling && !_headerLocked) {
        setState(() => _isPulling = pulling);
      }
    } else if (_isPulling) {
      setState(() => _isPulling = false);
    }

    if (notification is ScrollEndNotification) {
      final pulled = _pullDistance;
      _pullDistance = 0;
      if (_isPulling) setState(() => _isPulling = false);

      if (pulled >= _lockThreshold) {
        _lockOpen();
        context.read<ServerProvider>().refreshData();
      } else if (pulled >= _syncThreshold) {
        context.read<ServerProvider>().refreshData();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    final Widget leadingWidget;
    if (_headerLocked) {
      leadingWidget = IconButton(
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
        tooltip: 'Collapse',
        onPressed: () => setState(() => _headerLocked = false),
      );
    } else if (_isPulling) {
      leadingWidget = const SizedBox.shrink();
    } else {
      leadingWidget = _SyncStatusChip(provider: provider, onTap: _lockOpen);
    }

    final List<Widget> contentSlivers = [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      provider.sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: provider.sortAscending
                        ? 'Ascending'
                        : 'Descending',
                    onPressed: provider.toggleSortOrder,
                  ),
                  Expanded(
                    child: _SortMenuButton(
                      field: provider.sortField,
                      onChanged: provider.setSortField,
                    ),
                  ),
                  ToggleIconButton(
                    icon: Icons.star_rounded,
                    isSelected: provider.showFavoritesOnly,
                    onTap: provider.toggleFavoritesFilter,
                    tooltip: 'Favorites only',
                  ),
                  const SizedBox(width: 4),
                  ToggleIconButton(
                    icon: Symbols.hard_drive_rounded,
                    isSelected: provider.showExternalOnly,
                    onTap: provider.toggleExternalStorageFilter,
                    tooltip: 'External storage only',
                  ),
                  const SizedBox(width: 4),
                  ToggleIconButton(
                    icon: Icons.visibility_rounded,
                    isSelected: provider.showHidden,
                    onTap: provider.toggleShowHidden,
                    tooltip: 'Show hidden files',
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
              if (provider.pathStack.length > 1) ...[
                const SizedBox(height: 10),
                _Breadcrumbs(
                  pathStack: provider.pathStack,
                  onTap: (index) => provider.navigateToPathIndex(index),
                ),
              ],
            ],
          ),
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
              return _buildGridCard(context, item, provider);
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
              return _buildListTile(context, item, provider);
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
      canPop: provider.pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) provider.navigateUp();
      },
      child: ColoredBox(
        color: colorScheme.surfaceContainer,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: CustomScrollView(
            controller: widget.scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: _headerLocked ? 190 : kToolbarHeight,
                collapsedHeight: kToolbarHeight,
                backgroundColor: colorScheme.surfaceContainer,
                surfaceTintColor: colorScheme.surfaceContainer,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                leadingWidth: _headerLocked ? 56 : 160,
                leading: leadingWidget,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'New',
                    onPressed: () => _showCreateMenu(context, provider),
                  ),
                  const ProfileAvatarButton(),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _FilesStretchPanel(
                    provider: provider,
                    forceVisible: _headerLocked,
                  ),
                ),
              ),
              DecoratedSliver(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                sliver: SliverMainAxisGroup(slivers: contentSlivers),
              ),
            ],
          ),
        ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (item.isFolder) {
              provider.navigateToFolder(item.path);
            } else {
              _openFile(context, item, provider);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _ItemThumbnail(
                  item: item,
                  provider: provider,
                  size: 44,
                  borderRadius: 12,
                  iconSize: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.isFolder
                            ? 'Folder'
                            : '${_formatBytes(item.size)} • ${DateFormat.yMMMd().format(item.lastModified)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    item.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: item.isFavorite
                        ? Colors.amber.shade700
                        : colorScheme.outlineVariant,
                    size: 20,
                  ),
                  onPressed: () => provider.toggleItemFavorite(item),
                ),
                IconButton(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: () =>
                      _showFileDetailsSheet(context, item, provider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (item.isFolder) {
            provider.navigateToFolder(item.path);
          } else {
            _openFile(context, item, provider);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ItemThumbnail(
                    item: item,
                    provider: provider,
                    size: 40,
                    borderRadius: 12,
                    iconSize: 24,
                  ),
                  IconButton(
                    icon: Icon(
                      item.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: item.isFavorite
                          ? Colors.amber.shade700
                          : colorScheme.outlineVariant,
                      size: 20,
                    ),
                    onPressed: () => provider.toggleItemFavorite(item),
                  ),
                ],
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
                    item.isFolder ? 'Folder' : _formatBytes(item.size),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

  Future<void> _downloadItem(
    BuildContext context,
    ServerProvider provider,
    NextcloudItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading ${item.name}...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved ${item.name} to Downloads'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showFileDetailsSheet(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getIconColor(
                        context,
                        item.type,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _getItemIcon(item.type),
                      color: _getIconColor(context, item.type),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.path,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 16),
              if (!item.isFolder) ...[
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open'),
                  onTap: () {
                    Navigator.pop(context);
                    _openFile(context, item, provider);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Download'),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadItem(context, provider, item);
                  },
                ),
              ],
              ListTile(
                leading: Icon(
                  item.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: item.isFavorite ? Colors.amber.shade700 : null,
                ),
                title: Text(
                  item.isFavorite
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                ),
                onTap: () {
                  provider.toggleItemFavorite(item);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                title: Text(
                  'Delete from Server',
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final success = await provider.deleteItem(item.path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Deleted ${item.name}'
                              : 'Failed to delete ${item.name}',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateMenu(BuildContext context, ServerProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
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
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file_rounded),
                  title: const Text('Upload File'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUploadFile(context, provider);
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

  Future<void> _pickAndUploadFile(
    BuildContext context,
    ServerProvider provider,
  ) async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    final picked = result.first;
    if (picked.path == null) return;

    final progress = ValueNotifier<double?>(0);
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Uploading ${picked.name}'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) =>
                LinearProgressIndicator(value: value),
          ),
        );
      },
    );

    bool success = false;
    try {
      success = await provider.uploadFileFromPath(
        picked.name,
        picked.path!,
        onProgress: (sent, total) {
          if (total > 0) progress.value = sent / total;
        },
      );
    } catch (_) {
      success = false;
    }

    if (context.mounted) {
      Navigator.pop(context); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Uploaded ${picked.name} to Nextcloud'
                : 'Failed to upload ${picked.name}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// A compact, always-visible summary of the same status shown by
/// [_FilesStretchPanel] — tapping it is a discoverable shortcut for pulling
/// the header down to expand that same "Synced" view.
class _SyncStatusChip extends StatelessWidget {
  final ServerProvider provider;
  final VoidCallback onTap;

  const _SyncStatusChip({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quota = provider.quota;

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.isLoading
                      ? Icons.cloud_sync_rounded
                      : Icons.cloud_done_outlined,
                  color: colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  quota != null ? _formatBytes(quota.usedBytes) : 'Sync',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Revealed by pulling the "Files" header down past its normal height
/// (Google Photos' "pull to see backup status" pattern). Shows storage quota;
/// [_FilesViewState] decides via [forceVisible] whether it stays locked open.
class _FilesStretchPanel extends StatelessWidget {
  final ServerProvider provider;

  /// Keeps the panel fully shown even without live overscroll — used once
  /// the header has "locked" open after a deliberate pull-down.
  final bool forceVisible;

  const _FilesStretchPanel({required this.provider, this.forceVisible = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topInset = MediaQuery.of(context).padding.top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
        final maxExtent = settings?.maxExtent ?? constraints.maxHeight;
        final stretch = (constraints.maxHeight - maxExtent).clamp(0.0, 80.0);
        // Reaches 1.0 (title fully hidden) at 50px of pull — comfortably
        // before the 100px stretchTriggerOffset that locks the header open.
        final progress = forceVisible ? 1.0 : (stretch / 50).clamp(0.0, 1.0);
        final quota = provider.quota;

        return Stack(
          children: [
            if (progress > 0)
              // Anchored below the toolbar row (icons), never the bottom,
              // so it can never share space with the title above.
              Positioned(
                left: 20,
                right: 20,
                top: topInset + kToolbarHeight + 4,
                child: Opacity(
                  opacity: progress,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.isLoading ? 'Syncing…' : 'Synced',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_done_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                quota != null
                                    ? (quota.totalBytes > 0
                                          ? '${_formatBytes(quota.usedBytes)} of ${_formatBytes(quota.totalBytes)} used'
                                          : '${_formatBytes(quota.usedBytes)} used')
                                    : 'Pull to refresh',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
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
}
