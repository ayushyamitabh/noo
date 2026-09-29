import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/files_controller.dart';
import '../theme/design_tokens.dart';
import 'noo/core/noo_chip.dart';
import 'noo/core/noo_segmented_control.dart';
import 'noo/core/noo_toggle.dart';
import 'noo/lists/noo_grouped_list.dart';
import 'noo/lists/noo_settings_row.dart';
import 'noo/overlays/noo_sheet.dart';
import 'sort_menu_button.dart' show sortFieldLabel;

String _typeFilterLabel(FilesTypeFilter filter) {
  switch (filter) {
    case FilesTypeFilter.all:
      return 'Filters';
    case FilesTypeFilter.filesOnly:
      return 'Files only';
    case FilesTypeFilter.foldersOnly:
      return 'Folders only';
  }
}

/// The Files tab's sort/filter/view-mode row (Noo Design System project's
/// Files screen: a sort chip, a filter chip, a spacer, then the list/grid
/// segmented toggle) - shared with the Offline tab, which reads and writes
/// the exact same [FilesController] prefs. [folderPath] picks which
/// folder's sort applies. [showStorageScope] is off for Offline - a local
/// mirror has no cloud/external distinction.
///
/// Hidden-files and storage-scope, which have no home in the mockup's
/// simple two-chip row, live inside the filter chip's sheet instead of as
/// their own row controls.
///
/// A plain `Row`, not a horizontally-scrolling one - it used to wrap in a
/// `SingleChildScrollView`, which gives its child unbounded width, silently
/// breaking the trailing `Spacer` (a flex child needs a bounded width to
/// size against) and leaving the List/Grid toggle sitting right after the
/// filter chip instead of pinned to the row's right edge. The two chips
/// plus an icon-only toggle never come close to needing to scroll anyway.
class FilesControlsRow extends StatelessWidget {
  final String folderPath;
  final bool showStorageScope;

  const FilesControlsRow({
    super.key,
    required this.folderPath,
    this.showStorageScope = true,
  });

  @override
  Widget build(BuildContext context) {
    final files = context.watch<FilesController>();
    final filtersActive =
        files.filesTypeFilter != FilesTypeFilter.all ||
        files.showHiddenFiles ||
        (showStorageScope && files.storageScope != StorageScope.cloud);

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          NooChip(
            icon: files.sortAscendingFor(folderPath)
                ? LucideIcons.arrowUp
                : LucideIcons.arrowDown,
            onTap: () => _showSortSheet(context, files),
            child: Text(sortFieldLabel(files.sortFieldFor(folderPath))),
          ),
          const SizedBox(width: 8),
          NooChip(
            icon: LucideIcons.filter,
            trailing: NooChipTrailing.menu,
            selected: filtersActive,
            onTap: () => _showFilterSheet(context, files),
            child: Text(_typeFilterLabel(files.filesTypeFilter)),
          ),
          const Spacer(),
          NooSegmentedControl<bool>(
            iconOnly: true,
            value: files.isGridView,
            onChanged: files.setGridView,
            options: const [
              NooSegmentOption(value: false, icon: LucideIcons.list),
              NooSegmentOption(value: true, icon: LucideIcons.grid),
            ],
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context, FilesController files) {
    showNooSheet(
      context,
      children: [
        // `showNooSheet`'s `children` are built once, up front - a bare
        // checkmark/value here would freeze at whatever it was when the
        // sheet opened, since tapping a row calls `files.set...` and
        // notifies the controller, not this already-built widget tree.
        // `ListenableBuilder` re-runs its `builder` on every
        // `FilesController.notifyListeners()` instead, so the selection
        // updates live - see the identical fix in `_showFilterSheet`.
        ListenableBuilder(
          listenable: files,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NooSegmentedControl<bool>(
                fill: true,
                value: files.sortAscendingFor(folderPath),
                onChanged: (asc) {
                  if (asc != files.sortAscendingFor(folderPath)) {
                    files.toggleSortOrderFor(folderPath);
                  }
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
                      trailing: field == files.sortFieldFor(folderPath)
                          ? Icon(
                              LucideIcons.check,
                              size: 18,
                              color: context.nooColors.accentText,
                            )
                          : null,
                      onTap: () {
                        files.setSortFieldFor(folderPath, field);
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

  void _showFilterSheet(BuildContext context, FilesController files) {
    showNooSheet(
      context,
      children: [
        // See `_showSortSheet`'s comment: without this, none of the
        // checkmarks/toggles below would move until the sheet is closed
        // and reopened.
        ListenableBuilder(
          listenable: files,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NooGroupedList(
                label: 'Show',
                children: [
                  NooSettingsRow(
                    label: const Text('Files and folders'),
                    trailing: files.filesTypeFilter == FilesTypeFilter.all
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: context.nooColors.accentText,
                          )
                        : null,
                    onTap: () => files.setFilesTypeFilter(FilesTypeFilter.all),
                  ),
                  NooSettingsRow(
                    label: const Text('Files only'),
                    trailing: files.filesTypeFilter == FilesTypeFilter.filesOnly
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: context.nooColors.accentText,
                          )
                        : null,
                    onTap: () =>
                        files.setFilesTypeFilter(FilesTypeFilter.filesOnly),
                  ),
                  NooSettingsRow(
                    label: const Text('Folders only'),
                    trailing:
                        files.filesTypeFilter == FilesTypeFilter.foldersOnly
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: context.nooColors.accentText,
                          )
                        : null,
                    onTap: () =>
                        files.setFilesTypeFilter(FilesTypeFilter.foldersOnly),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              NooGroupedList(
                children: [
                  NooSettingsRow(
                    icon: LucideIcons.eye,
                    label: const Text('Show hidden files'),
                    trailing: NooToggle(
                      checked: files.showHiddenFiles,
                      onChanged: (_) => files.toggleShowHiddenFiles(),
                    ),
                  ),
                  if (showStorageScope)
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
      ],
    );
  }
}
