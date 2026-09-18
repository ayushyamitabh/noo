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
import '../widgets/marquee_title.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/segmented_icon_toggle.dart';
import '../widgets/sort_menu_button.dart';
import '../widgets/sticky_header_delegate.dart';
import '../widgets/synced_header_scaffold.dart';

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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Shared files have no relationship to wherever the user was last
    // browsing, so start the destination picker fresh at the root.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ServerProvider>().navigateToAbsoluteFolder('/');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

    // Mirrors FilesView's own controls-row + breadcrumbs sticky header
    // exactly (padding, heights) so this reads as the same browser, just
    // reached from a share intent instead of the Files tab.
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
                pathStack: provider.pathStack,
                onTap: (index) => provider.navigateToPathIndex(index),
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
      if (provider.isLoading)
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
              return _buildGridCard(context, items[index], provider);
            }, childCount: items.length),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildListTile(context, items[index], provider);
            }, childCount: items.length),
          ),
        ),
      // So the last row isn't hidden behind the bottom "Upload to..." bar.
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return Scaffold(
      body: SyncedHeaderScaffold(
        scrollController: _scrollController,
        provider: provider,
        // Same trailing actions as every other tab - no bespoke close
        // button here, so the top chrome is identical regardless of how
        // this screen was reached. Backing out is still the system
        // back gesture/button, same as any other pushed screen.
        actions: const [MoreTabsButton(), ProfileAvatarButton()],
        contentSlivers: contentSlivers,
      ),
      // A rounded-top, elevated bar "peeking" up from the bottom edge - the
      // uploading-file summary (marqueed if it doesn't fit on one line)
      // sits directly above the destination button, both inside the one
      // sheet, rather than the summary living up in the scrolling content
      // far away from the action it describes.
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
                // Same pill/chip look and exact same duller background
                // color as the filter toggles' shared background
                // (SegmentedIconGroup's `surfaceContainerHigh`), so it reads
                // as part of the same visual language rather than a new
                // accent color. Sized to the text itself (like a real chip)
                // up to the row's available width - MarqueeTitle needs a
                // concrete (not just loose) width to know whether/how far
                // to scroll, so this measures the text once up front rather
                // than leaving the chip unconstrained.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final uploadingText = widget.files.length == 1
                        ? 'Uploading ${widget.files.first.name}'
                        : 'Uploading ${widget.files.length} files';
                    final chipTextStyle = theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    );
                    const horizontalPadding = 28.0;
                    final painter = TextPainter(
                      text: TextSpan(text: uploadingText, style: chipTextStyle),
                      maxLines: 1,
                      textDirection: Directionality.of(context),
                    )..layout(maxWidth: double.infinity);
                    final chipWidth = (painter.width + horizontalPadding).clamp(
                      0.0,
                      constraints.maxWidth,
                    );

                    return Container(
                      width: chipWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SizedBox(
                        height: 20,
                        child: MarqueeTitle(
                          text: uploadingText,
                          style: chipTextStyle,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _uploadHere(provider),
                    icon: const Icon(Icons.upload_rounded),
                    label: Text('Upload to $currentLabel'),
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
