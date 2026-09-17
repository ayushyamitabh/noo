import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../services/share_intent_service.dart';
import '../services/upload_service.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/item_icon.dart';
import '../widgets/segmented_icon_toggle.dart';
import '../widgets/sort_menu_button.dart';
import '../widgets/synced_header_scaffold.dart' show formatBytes;

/// Shown when another app shares one or more files to Noo (Android's
/// "Share to..." sheet). Lets the user browse to a destination folder,
/// mirroring the Files tab's own controls/filters/listing so this feels
/// like the same browser rather than a stripped-down picker, then hands the
/// actual prepare+upload off to [UploadService] - a real Android foreground
/// service (see `ShareUploadService.kt`'s doc comment), not something this
/// screen or even the app needs to stay open for. [files] only ever carry
/// cheap Uri metadata (see [ShareIntentService]'s doc comment); that
/// service is the only thing that ever reads their actual bytes.
class ShareUploadView extends StatefulWidget {
  final List<SharedFileRef> files;

  const ShareUploadView({super.key, required this.files});

  @override
  State<ShareUploadView> createState() => _ShareUploadViewState();
}

class _ShareUploadViewState extends State<ShareUploadView> {
  @override
  void initState() {
    super.initState();
    // Shared files have no relationship to wherever the user was last
    // browsing, so start the destination picker fresh at the root.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ServerProvider>().navigateToAbsoluteFolder('/');
    });
  }

  Future<void> _uploadHere(ServerProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await UploadService.startUpload(provider, widget.files);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not start upload: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    provider.requestTab(AppTab.files);
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.files.length == 1
              ? 'Uploading ${widget.files.first.name} - see the notification for progress'
              : 'Uploading ${widget.files.length} files - see the notification for progress',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
              icon: provider.showFavoritesOnlyFiles
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              isSelected: provider.showFavoritesOnlyFiles,
              onTap: provider.toggleFavoritesFilterFiles,
              tooltip: 'Favorites only',
            ),
            const SizedBox(width: 4),
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
                  icon: Icons.select_all_rounded,
                  isSelected: provider.filesTypeFilter == FilesTypeFilter.all,
                  onTap: () => provider.setFilesTypeFilter(FilesTypeFilter.all),
                  tooltip: 'Files & folders',
                ),
                ToggleIconButton(
                  icon: Icons.insert_drive_file_outlined,
                  isSelected:
                      provider.filesTypeFilter == FilesTypeFilter.filesOnly,
                  onTap: () =>
                      provider.setFilesTypeFilter(FilesTypeFilter.filesOnly),
                  tooltip: 'Files only',
                ),
                ToggleIconButton(
                  icon: Icons.folder_outlined,
                  isSelected:
                      provider.filesTypeFilter == FilesTypeFilter.foldersOnly,
                  onTap: () =>
                      provider.setFilesTypeFilter(FilesTypeFilter.foldersOnly),
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
    );
  }

  // Only folders are valid upload destinations - files still show (so the
  // listing matches what the Files tab itself would show for this folder)
  // but are visually dimmed and inert rather than hidden outright.
  Widget _buildListTile(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
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
              onTap: isFolder
                  ? () => provider.navigateToFolder(item.path)
                  : null,
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

  Widget _buildGridCard(
    BuildContext context,
    NextcloudItem item,
    ServerProvider provider,
  ) {
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
          onTap: isFolder ? () => provider.navigateToFolder(item.path) : null,
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
    final hasBreadcrumbs = provider.pathStack.length > 1;
    final currentPath = provider.pathStack.last;
    final currentLabel = currentPath == '/'
        ? 'Home'
        : currentPath.split('/').where((s) => s.isNotEmpty).last;
    final items = provider.items;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.files.length == 1
              ? 'Upload ${widget.files.first.name}'
              : 'Upload ${widget.files.length} files',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _buildControlsRow(provider),
          ),
          if (hasBreadcrumbs)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Breadcrumbs(
                pathStack: provider.pathStack,
                onTap: (index) => provider.navigateToPathIndex(index),
              ),
            ),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? Center(
                    child: Text(
                      'Folder is empty',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : provider.isGridView
                ? GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildGridCard(context, items[index], provider),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildListTile(context, items[index], provider),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _uploadHere(provider),
            icon: const Icon(Icons.upload_rounded),
            label: Text('Upload to $currentLabel'),
          ),
        ),
      ),
    );
  }
}
