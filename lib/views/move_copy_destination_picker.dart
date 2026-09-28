import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/move_copy_result.dart';
import '../models/nextcloud_item.dart';
import '../providers/files_controller.dart';
import '../providers/item_operations.dart';
import '../theme/design_tokens.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/files_controls_row.dart';
import '../widgets/more_tabs_button.dart';
import '../widgets/move_copy_conflict_sheet.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/media/noo_grid_card.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/nav/noo_toolbar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/tabs/tab_state_slivers.dart';

/// Destination-folder browser for moving/copying [items] (a multi-select
/// batch from Files or Photos). Visually mirrors `ShareUploadView`'s
/// browser (same chrome/controls/listing), but deliberately does **not**
/// reuse `FilesController`'s shared `currentFolderPath`/`pathStack`/`items`
/// navigation state the way that screen does - this is pushed mid-browsing
/// session (the user was already looking at a specific Files-tab folder
/// when they selected items and tapped Move/Copy), so clobbering that
/// shared state here would strand the Files tab in whatever folder this
/// picker last visited. Instead it owns its own local navigation state and
/// fetches through `FilesController.fetchFolderListing`, a stateless
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
    final raw = await context.read<FilesController>().fetchFolderListing(path);
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

  /// Client-side mirror of `ItemOperations`' own authoritative check (see
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

  Future<void> _confirm(ItemOperations ops) async {
    setState(() => _isSubmitting = true);
    final result = widget.copy
        ? await ops.copyItems(widget.items, _currentPath)
        : await ops.moveItems(widget.items, _currentPath);
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
        final resolved = await ops.resolveConflicts(
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

  // Only folders are valid Move/Copy destinations, so the listing - unlike
  // Files' own - never shows plain files at all.
  Widget _buildRow(NextcloudItem item, int index, int count) {
    final colors = context.nooColors;
    final row = NooFileRow(
      kind: NooFileKind.folder,
      name: item.name,
      meta: 'Folder',
      iosStyle: NooLayout.iosStyle(context),
      onTap: () => _navigateToFolder(item.path),
    );

    final isFirst = index == 0;
    final isLast = index == count - 1;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(NooRadii.card) : Radius.zero,
            bottom: isLast ? const Radius.circular(NooRadii.card) : Radius.zero,
          ),
          child: row,
        ),
        if (!isLast) Container(height: 1, color: colors.line),
      ],
    );
  }

  Widget _buildDesktopRow(NextcloudItem item) {
    return NooFileTableRow(
      kind: NooFileKind.folder,
      name: item.name,
      onTap: () => _navigateToFolder(item.path),
    );
  }

  Widget _buildGridCard(NextcloudItem item) {
    final colors = context.nooColors;
    return NooGridCard(
      name: item.name,
      meta: 'Folder',
      placeholderColor: colors.accentSoft,
      icon: LucideIcons.folder,
      iconColor: colors.accentText,
      thumbnailHeight: NooLayout.isDesktop(context) ? 118 : 104,
      onTap: () => _navigateToFolder(item.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);
    final files = context.watch<FilesController>();
    final ops = context.read<ItemOperations>();
    final hasBreadcrumbs = _pathStack.length > 1;
    final folders = files
        .applyFilesDisplayPrefs(_rawItems)
        .where((item) => item.isFolder)
        .toList();
    final invalidDestination = _destinationIsInvalid();
    final gutter = NooLayout.gutter(context);
    final verb = widget.copy ? 'Copying' : 'Moving';
    final itemCount = widget.items.length;

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            NooSpace.md,
            gutter,
            NooSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: FilesControlsRow(
                  folderPath: _currentPath,
                  showStorageScope: false,
                ),
              ),
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
        ),
      ),
      if (_isLoading)
        tabLoadingSliver
      else if (folders.isEmpty)
        tabEmptySliver(
          context,
          icon: LucideIcons.folder,
          message: 'No folders here',
        )
      else if (files.isGridView)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: desktop ? 5 : 2,
              childAspectRatio: desktop ? 1.05 : 0.92,
              crossAxisSpacing: desktop ? 16 : 10,
              mainAxisSpacing: desktop ? 16 : 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildGridCard(folders[index]),
              childCount: folders.length,
            ),
          ),
        )
      else if (desktop)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildDesktopRow(folders[index]),
              childCount: folders.length,
            ),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildRow(folders[index], index, folders.length),
              childCount: folders.length,
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: NooSpace.xl)),
    ];

    final title = widget.copy ? 'Copy to...' : 'Move to...';

    return PopScope(
      canPop: _pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _navigateUp();
      },
      child: Scaffold(
        backgroundColor: colors.bg,
        appBar: desktop
            ? NooToolbar(
                title: title,
                actions: [
                  const MoreTabsButton(),
                  const SizedBox(width: NooSpace.xs),
                  NooButton(
                    variant: NooButtonVariant.secondary,
                    size: NooButtonSize.toolbar,
                    onTap: () => Navigator.maybePop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              )
            : NooTopBar(
                style: NooLayout.navStyle(context),
                title: title,
                leading: const NooTopBarBack(label: 'Cancel'),
                // Stacks a hidden tab's own screen on top rather than
                // jumping the shell there, so it doesn't abandon this
                // picker - safe to keep, unlike ShareUploadView's chrome.
                actions: const [MoreTabsButton()],
              ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: colors.accent,
            backgroundColor: colors.surface,
            onRefresh: () => _fetch(_currentPath),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: slivers,
            ),
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NooSpace.lg,
                NooSpace.md,
                NooSpace.lg,
                NooSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    invalidDestination
                        ? "Can't ${widget.copy ? 'copy' : 'move'} a folder into "
                              "itself or one of its own subfolders"
                        : '$verb $itemCount item${itemCount == 1 ? '' : 's'}',
                    textAlign: TextAlign.center,
                    style: NooText.meta.copyWith(
                      color: invalidDestination ? colors.danger : colors.fg3,
                    ),
                  ),
                  const SizedBox(height: NooSpace.sm),
                  NooButton(
                    variant: NooButtonVariant.primary,
                    size: NooButtonSize.cta,
                    fullWidth: true,
                    disabled: invalidDestination || _isSubmitting,
                    icon: _isSubmitting
                        ? null
                        : (widget.copy
                              ? LucideIcons.copy
                              : LucideIcons.folderInput),
                    onTap: invalidDestination || _isSubmitting
                        ? null
                        : () => _confirm(ops),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(widget.copy ? 'Copy here' : 'Move here'),
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
