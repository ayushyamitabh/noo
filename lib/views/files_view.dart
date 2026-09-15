import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';

class FilesView extends StatelessWidget {
  final ScrollController scrollController;

  const FilesView({super.key, required this.scrollController});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    return CustomScrollView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // App Bar / Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nextcloud Files',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${provider.username} @ ${provider.serverUrl}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => _showCreateFolderDialog(context, provider),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          tooltip: 'New Folder',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () => _showUploadDialog(context, provider),
                          icon: const Icon(Icons.upload_file_rounded),
                          tooltip: 'Upload File',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search & Filter Bar
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          onChanged: provider.setSearchQuery,
                          decoration: InputDecoration(
                            hintText: 'Search files & folders...',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: provider.showFavoritesOnly,
                      label: const Icon(Icons.star_rounded, size: 18),
                      onSelected: (_) => provider.toggleFavoritesFilter(),
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                      selectedColor: colorScheme.primaryContainer,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: provider.toggleViewMode,
                      icon: Icon(
                        provider.isGridView
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Breadcrumbs & Path Navigator
                if (provider.pathStack.length > 1)
                  Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('Back'),
                        onPressed: provider.navigateUp,
                        backgroundColor: colorScheme.surfaceContainerLow,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            provider.currentFolderPath,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),

        // Files List / Grid
        if (provider.isLoading)
          const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (provider.errorMessage != null)
          SliverFillRemaining(
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = provider.items[index];
                  return _buildGridCard(context, item, provider);
                },
                childCount: provider.items.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = provider.items[index];
                  return _buildListTile(context, item, provider);
                },
                childCount: provider.items.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildListTile(BuildContext context, NextcloudItem item, ServerProvider provider) {
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
              _showFileDetailsSheet(context, item, provider);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getIconColor(context, item.type).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getItemIcon(item.type),
                    color: _getIconColor(context, item.type),
                  ),
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
                    item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: item.isFavorite ? Colors.amber.shade700 : colorScheme.outlineVariant,
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
                  onPressed: () => _showFileDetailsSheet(context, item, provider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context, NextcloudItem item, ServerProvider provider) {
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
            _showFileDetailsSheet(context, item, provider);
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getIconColor(context, item.type).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getItemIcon(item.type),
                      color: _getIconColor(context, item.type),
                      size: 24,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: item.isFavorite ? Colors.amber.shade700 : colorScheme.outlineVariant,
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

  void _showFileDetailsSheet(BuildContext context, NextcloudItem item, ServerProvider provider) {
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
                      color: _getIconColor(context, item.type).withValues(alpha: 0.12),
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
              ListTile(
                leading: Icon(
                  item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: item.isFavorite ? Colors.amber.shade700 : null,
                ),
                title: Text(item.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
                onTap: () {
                  provider.toggleItemFavorite(item);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                title: Text('Delete from Server', style: TextStyle(color: colorScheme.error)),
                onTap: () async {
                  Navigator.pop(context);
                  final success = await provider.deleteItem(item.path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Deleted ${item.name}' : 'Failed to delete ${item.name}'),
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
                        content: Text(success ? 'Created folder $name' : 'Failed to create folder'),
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

  void _showUploadDialog(BuildContext context, ServerProvider provider) {
    final nameController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Upload Text File'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'File Name',
                  hintText: 'notes.txt',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'File Content',
                  hintText: 'Enter text to upload...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final text = contentController.text;
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  final bytes = Uint8List.fromList(text.codeUnits);
                  final success = await provider.uploadFile(name, bytes);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Uploaded $name to Nextcloud' : 'Failed to upload $name'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
  }
}
