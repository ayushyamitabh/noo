import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_item.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../services/share_intent_service.dart';
import '../services/upload_service.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/item_icon.dart';
import '../widgets/marquee_title.dart';
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
      if (mounted) context.read<FilesController>().navigateToAbsoluteFolder('/');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _uploadHere(SessionController session) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final files = context.read<FilesController>();
    final settings = context.read<SettingsController>();
    try {
      await UploadService.startUpload(session, files, widget.files);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not start upload: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    settings.requestTab(AppTab.files);
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
                  icon: Icons.select_all_rounded,
                  isSelected: files.filesTypeFilter == FilesTypeFilter.all,
                  onTap: () => files.setFilesTypeFilter(FilesTypeFilter.all),
                  tooltip: 'Files & folders',
                ),
                ToggleIconButton(
                  icon: Icons.insert_drive_file_outlined,
                  isSelected:
                      files.filesTypeFilter == FilesTypeFilter.filesOnly,
                  onTap: () =>
                      files.setFilesTypeFilter(FilesTypeFilter.filesOnly),
                  tooltip: 'Files only',
                ),
                ToggleIconButton(
                  icon: Icons.folder_outlined,
                  isSelected:
                      files.filesTypeFilter == FilesTypeFilter.foldersOnly,
                  onTap: () =>
                      files.setFilesTypeFilter(FilesTypeFilter.foldersOnly),
                  tooltip: 'Folders only',
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

  // Only folders are valid upload destinations - files still show (so the
  // listing matches what the Files tab itself would show for this folder)
  // but are visually dimmed and inert rather than hidden outright.
  Widget _buildListTile(BuildContext context, NextcloudItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final files = context.read<FilesController>();
    final session = context.watch<SessionController>();
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
              onTap: isFolder ? () => files.navigateToFolder(item.path) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ItemThumbnail(
                      item: item,
                      service: session.service,
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

  Widget _buildGridCard(BuildContext context, NextcloudItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final files = context.read<FilesController>();
    final isFolder = item.isFolder;
    final iconColor = getIconColor(context, item.type);

    return Opacity(
      opacity: isFolder ? 1 : 0.5,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isFolder ? () => files.navigateToFolder(item.path) : null,
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
    final files = context.watch<FilesController>();
    final session = context.watch<SessionController>();
    final hasBreadcrumbs = files.pathStack.length > 1;
    final currentPath = files.pathStack.last;
    final currentLabel = currentPath == '/'
        ? 'Home'
        : currentPath.split('/').where((s) => s.isNotEmpty).last;
    final items = files.items;

    // Mirrors FilesView's own controls-row + breadcrumbs sticky header
    // exactly (padding, heights) so this reads as the same browser, just
    // reached from a share intent instead of the Files tab.
    final controlsColumn = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControlsRow(files),
          if (hasBreadcrumbs) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: Breadcrumbs(
                pathStack: files.pathStack,
                onTap: (index) => files.navigateToPathIndex(index),
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
      if (files.isLoading)
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
      else if (files.isGridView)
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
              return _buildGridCard(context, items[index]);
            }, childCount: items.length),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildListTile(context, items[index]);
            }, childCount: items.length),
          ),
        ),
      // So the last row isn't hidden behind the bottom "Upload to..." bar.
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return Scaffold(
      body: SyncedHeaderScaffold(
        scrollController: _scrollController,
        // Same trailing actions as every other tab except "More tabs" -
        // there's nowhere useful for it to go while mid-upload (jumping to
        // Trash/Shares/etc. would abandon this destination picker), so the
        // top chrome is identical to every other tab minus that one entry.
        // Backing out is still the system back gesture/button, same as any
        // other pushed screen.
        actions: const [ProfileAvatarButton()],
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
                    onPressed: () => _uploadHere(session),
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
