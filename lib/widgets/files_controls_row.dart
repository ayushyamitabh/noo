import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../providers/files_controller.dart';
import 'segmented_icon_toggle.dart';
import 'sort_menu_button.dart';

/// The Files tab's sort/hidden/scope/type-filter/view-mode controls row,
/// shared with the Offline tab so both read and write the exact same
/// [FilesController] prefs. [folderPath] picks which folder's sort applies
/// (the Files tab's current folder, or the folder being browsed offline).
/// [showStorageScope] is off for Offline - a local mirror has no
/// cloud/external distinction.
class FilesControlsRow extends StatelessWidget {
  final String folderPath;
  final bool showStorageScope;
  final ScrollController? scrollController;

  const FilesControlsRow({
    super.key,
    required this.folderPath,
    this.showStorageScope = true,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final files = context.watch<FilesController>();

    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                files.sortAscendingFor(folderPath)
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: files.sortAscendingFor(folderPath)
                  ? 'Ascending'
                  : 'Descending',
              onPressed: () => files.toggleSortOrderFor(folderPath),
            ),
            // A plain width, not Expanded - this row scrolls horizontally,
            // which gives every control unbounded width to lay out in, so a
            // flex child would throw.
            SizedBox(
              width: 130,
              child: SortMenuButton(
                field: files.sortFieldFor(folderPath),
                onChanged: (field) => files.setSortFieldFor(folderPath, field),
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
            if (showStorageScope) ...[
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
            ],
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
}
