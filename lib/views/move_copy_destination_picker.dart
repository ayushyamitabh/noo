import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../models/move_copy_result.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/item_icon.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/move_copy_conflict_sheet.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/segmented_icon_toggle.dart';
import '../widgets/sort_menu_button.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/synced_header_scaffold.dart';

/// Destination-folder browser for moving/copying [items] (a multi-select
/// batch from Files or Photos). Visually mirrors `ShareUploadView`'s
/// browser (same chrome/controls/listing), but deliberately does **not**
/// reuse `ServerProvider`'s shared `currentFolderPath`/`pathStack`/`items`
/// navigation state the way that screen does - this is pushed mid-browsing
/// session (the user was already looking at a specific Files-tab folder
/// when they selected items and tapped Move/Copy), so clobbering that
/// shared state here would strand the Files tab in whatever folder this
/// picker last visited. Instead it owns its own local navigation state and
/// fetches through `ServerProvider.fetchFolderListing`, a stateless
/// pass-through that never touches shared fields - `ShareUploadView` gets
/// away with the shared state precisely because it always resets to root
/// and pops all the way to the app root afterward (a cold share-intent
/// launch has no prior browsing session to preserve); that doesn't hold
/// here.
class MoveCopyDestinationPicker extends StatefulWidget {
  final List<NextcloudItem> items;
  final bool copy;

  const MoveCopyDestinationPicker({
    super.key,
    required this.items,
    required this.copy,
  });

  /// Pushes the picker and returns the final [MoveCopyResult] (already
  /// including any conflict resolution), or null if the user backed out
  /// without confirming.
  static Future<MoveCopyResult?> show(
    BuildContext context,
    List<NextcloudItem> items, {
    required bool copy,
  }) {
    return Navigator.of(context).push<MoveCopyResult>(
      MaterialPageRoute(
        builder: (_) => MoveCopyDestinationPicker(items: items, copy: copy),
      ),
    );
  }

  @override
  State<MoveCopyDestinationPicker> createState() =>
      _MoveCopyDestinationPickerState();
}

class _MoveCopyDestinationPickerState extends State<MoveCopyDestinationPicker> {
  final ScrollController _scrollController = ScrollController();
  List<String> _pathStack = const ['/'];
  List<NextcloudItem> _rawItems = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(_currentPath));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch(String path) async {
    setState(() => _isLoading = true);
    final raw = await context.read<ServerProvider>().fetchFolderListing(path);
    if (!mounted) return;
    setState(() {
      _rawItems = raw;
      _isLoading = false;
    });
  }

  void _navigateToFolder(String path) {
    setState(() => _pathStack = [..._pathStack, path]);
    _fetch(path);
  }

  void _navigateToPathIndex(int index) {
    if (index < 0 || index >= _pathStack.length - 1) return;
    setState(() => _pathStack = _pathStack.sublist(0, index + 1));
    _fetch(_currentPath);
  }

  bool _navigateUp() {
    if (_pathStack.length <= 1) return false;
    setState(() => _pathStack = _pathStack.sublist(0, _pathStack.length - 1));
    _fetch(_currentPath);
    return true;
  }

  /// Client-side mirror of `ServerProvider`'s own authoritative check (see
  /// `_isSelfOrDescendant`) - just for disabling the confirm button with an
  /// explanation up front instead of letting the request round-trip and
  /// fail.
  bool _destinationIsInvalid() {
    final dest = _currentPath.endsWith('/') ? _currentPath : '$_currentPath/';
    for (final item in widget.items) {
      if (!item.isFolder) continue;
      final folder = item.path.endsWith('/') ? item.path : '${item.path}/';
      if (dest == folder || dest.startsWith(folder)) return true;
    }
    return false;
  }

  Future<void> _confirm(ServerProvider provider) async {
    setState(() => _isSubmitting = true);
    final result = widget.copy
        ? await provider.copyItems(widget.items, _currentPath)
        : await provider.moveItems(widget.items, _currentPath);
    if (!mounted) return;

    if (result.blockedReason != null) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.blockedReason!),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    var succeeded = result.succeeded;
    var failed = result.failed;

    if (result.conflicts.isNotEmpty) {
      final choices = await MoveCopyConflictSheet.show(
        context,
        result.conflicts,
      );
      if (!mounted) return;
      if (choices != null) {
        final resolved = await provider.resolveConflicts(
          result.conflicts,
          _currentPath,
          copy: widget.copy,
          choices: choices,
        );
        succeeded += resolved.succeeded;
        failed += resolved.failed;
      }
      // A dismissed sheet (choices == null) leaves those conflicts
      // untouched at the source - same outcome as explicitly skipping
      // every one, just without a network round-trip to get there.
    }

    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(MoveCopyResult(succeeded: succeeded, failed: failed));
  }

  Widget _buildControlsRow(ServerProvider provider) {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
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
              tooltip: provider.filesSortAscending ? 'Ascending' : 'Descending',
              onPressed: provider.toggleFilesSortOrder,
            ),
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
    );
  }

  // Only folders are valid Move/Copy destinations - files still show (so
  // the listing matches what the Files tab itself would show for this
  // folder) but are visually dimmed and inert, same treatment as
  // ShareUploadView's own destination browser.
  Widget _buildListTile(NextcloudItem item, ServerProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFolder = item.isFolder;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isFolder ? 1 : 0.5,
          child: Material(
            color: colorScheme.surfaceContainerLow,
            child: InkWell(
              onTap: isFolder ? () => _navigateToFolder(item.path) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ItemThumbnail(
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
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isFolder
                                ? 'Folder'
                                : '${formatBytes(item.size)} • ${DateFormat.yMMMd().format(item.lastModified)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isFolder) const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(NextcloudItem item, ServerProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFolder = item.isFolder;
    final iconColor = getIconColor(context, item.type);

    return Opacity(
      opacity: isFolder ? 1 : 0.5,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isFolder ? () => _navigateToFolder(item.path) : null,
          child: Padding(
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
                      isFolder ? 'Folder' : formatBytes(item.size),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final hasBreadcrumbs = _pathStack.length > 1;
    final currentLabel = _currentPath == '/'
        ? 'Home'
        : _currentPath.split('/').where((s) => s.isNotEmpty).last;
    final items = provider.applyFilesDisplayPrefs(_rawItems);
    final invalidDestination = _destinationIsInvalid();

    final controlsColumn = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControlsRow(provider),
          if (hasBreadcrumbs) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: Breadcrumbs(
                pathStack: _pathStack,
                onTap: _navigateToPathIndex,
              ),
            ),
          ],
        ],
      ),
    );

    final contentSlivers = <Widget>[
      SliverPersistentHeader(
        pinned: true,
        delegate: StickyHeaderDelegate(
          height: hasBreadcrumbs ? 114 : 72,
          child: controlsColumn,
        ),
      ),
      if (_isLoading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'Folder is empty',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        )
      else if (provider.isGridView)
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
              return _buildGridCard(items[index], provider);
            }, childCount: items.length),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildListTile(items[index], provider);
            }, childCount: items.length),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return PopScope(
      canPop: _pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _navigateUp();
      },
      child: Scaffold(
        body: SyncedHeaderScaffold(
          scrollController: _scrollController,
          provider: provider,
          actions: const [MoreTabsButton(), ProfileAvatarButton()],
          contentSlivers: contentSlivers,
        ),
        bottomNavigationBar: Material(
          color: colorScheme.surfaceContainerHigh,
          elevation: 8,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (invalidDestination) ...[
                    Text(
                      "Can't ${widget.copy ? 'copy' : 'move'} a folder into "
                      "itself or one of its own subfolders",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: invalidDestination || _isSubmitting
                          ? null
                          : () => _confirm(provider),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              widget.copy
                                  ? Icons.copy_rounded
                                  : Icons.drive_file_move_rounded,
                            ),
                      label: Text(
                        '${widget.copy ? 'Copy' : 'Move'} ${widget.items.length} '
                        'item(s) to $currentLabel',
                      ),
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
}
