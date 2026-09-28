import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/nextcloud_item.dart';
import '../providers/trash_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/files/noo_file_tile.dart';
import '../widgets/noo/lists/noo_banner.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/tabs/tab_location.dart';
import '../widgets/tabs/tab_state_slivers.dart';

/// The Trash tab: a retention banner (`NooBanner`, with "Empty trash" as
/// its danger action) then the trashed-items list, per `DESIGN_SYSTEM.md`
/// §4. There's no dedicated "empty trash" endpoint anywhere in
/// [TrashController]/`NextcloudService` - [_emptyTrash] composes it from
/// the existing per-item [TrashController.deleteForever], the same way
/// `FavoritesView._confirmDeleteSelected` builds its bulk delete from a
/// per-item call.
class TrashView extends StatefulWidget {
  final ScrollController scrollController;

  const TrashView({super.key, required this.scrollController});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final trashController = context.watch<TrashController>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => trashController.fetchAll(),
      );
    }

    final trash = trashController.items;
    final isDesktop = NooLayout.isDesktop(context);

    final List<Widget> contentSlivers = [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          NooLayout.gutter(context),
          NooSpace.md,
          NooLayout.gutter(context),
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: NooBanner(
            actionLabel: trash.isEmpty ? null : 'Empty trash',
            onAction: trash.isEmpty ? null : () => _confirmEmptyTrash(context, trash),
            child: const Text('Deleted items are kept for 30 days, then removed automatically.'),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: NooSpace.md)),
      if (trashController.isLoading && trash.isEmpty)
        tabLoadingSliver
      else if (trashController.errorMessage != null)
        tabErrorSliver(
          context,
          title: 'Could not load trash',
          message: trashController.errorMessage!,
          onRetry: trashController.fetchAll,
        )
      else if (trash.isEmpty)
        tabEmptySliver(
          context,
          icon: LucideIcons.trash2,
          message: 'Trash is empty',
        )
      else if (isDesktop)
        _buildDesktopTable(context, trash)
      else
        _buildMobileList(context, trash),
      ...tabBottomInsetSlivers,
    ];

    return ColoredBox(
      color: colors.bg,
      child: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.surface,
        onRefresh: trashController.fetchAll,
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: contentSlivers,
        ),
      ),
    );
  }

  // A lazily-built `SliverList`, not `NooGroupedList` (its own `Column`
  // isn't lazy - see files_view.dart's `_buildMobileRow` doc comment for
  // the same reasoning): Trash can hold hundreds of items, and building
  // every row eagerly up front is what made this tab laggy. Each row still
  // reads as one continuous radius-20 card via per-row corner rounding +
  // a 1px `line` divider, matching `NooGroupedList`'s look.
  Widget _buildMobileList(BuildContext context, List<NextcloudItem> trash) {
    final colors = context.nooColors;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = trash[index];
          final row = NooFileRow(
            kind: NooFileKind.from(
              name: item.name,
              mimeType: item.mimeType,
              isDirectory: item.isFolder,
            ),
            name: item.name,
            meta: _meta(item),
            iosStyle: NooLayout.iosStyle(context),
            trailing: SizedBox.square(
              dimension: 40,
              child: Semantics(
                button: true,
                label: 'Restore',
                child: InkResponse(
                  onTap: () => _restore(context, item),
                  radius: 20,
                  child: const Icon(LucideIcons.rotateCcw),
                ),
              ),
            ),
            onMore: () => _confirmDeleteForever(context, item),
          );
          final isFirst = index == 0;
          final isLast = index == trash.length - 1;
          return Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: isFirst
                      ? const Radius.circular(NooRadii.card)
                      : Radius.zero,
                  bottom: isLast
                      ? const Radius.circular(NooRadii.card)
                      : Radius.zero,
                ),
                child: row,
              ),
              if (!isLast) Container(height: 1, color: colors.line),
            ],
          );
        }, childCount: trash.length),
      ),
    );
  }

  Widget _buildDesktopTable(BuildContext context, List<NextcloudItem> trash) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: NooSpace.xl,
        vertical: NooSpace.xs,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == 0) {
            return const NooFileTableHeader(
              col2Label: 'Deleted',
              col3Label: 'Original location',
            );
          }
          final item = trash[index - 1];
          return _TrashDesktopRow(
            kind: NooFileKind.from(
              name: item.name,
              mimeType: item.mimeType,
              isDirectory: item.isFolder,
            ),
            name: item.name,
            col2: _deletedLabel(item),
            col3: item.originalLocation ?? 'Unknown location',
            onRestore: () => _restore(context, item),
            onMore: () => _confirmDeleteForever(context, item),
          );
        }, childCount: trash.length + 1),
      ),
    );
  }

  String _meta(NextcloudItem item) =>
      'Deleted ${_deletedLabel(item)} · ${tabLocationLabel(item.originalLocation ?? item.path, item.name)}';

  String _deletedLabel(NextcloudItem item) =>
      item.deletedAt != null ? DateFormat.yMMMd().format(item.deletedAt!) : 'recently';

  Future<void> _restore(BuildContext context, NextcloudItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await context.read<TrashController>().restore(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Restored ${item.name}' : 'Failed to restore ${item.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDeleteForever(
    BuildContext context,
    NextcloudItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete forever'),
          content: Text(
            'Permanently delete "${item.name}"? This cannot be undone.',
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
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await context.read<TrashController>().deleteForever(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Deleted ${item.name}' : 'Failed to delete ${item.name}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmEmptyTrash(
    BuildContext context,
    List<NextcloudItem> trash,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Empty trash'),
          content: Text(
            'Permanently delete all ${trash.length} item(s) in trash? This cannot be undone.',
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
              child: const Text('Empty trash'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final controller = context.read<TrashController>();
    final messenger = ScaffoldMessenger.of(context);
    var succeeded = 0;
    for (final item in trash) {
      if (await controller.deleteForever(item)) succeeded++;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted $succeeded of ${trash.length} item(s)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Desktop trash row: like `NooFileTableRow`, but its 120px last column
/// holds a tonal "Restore" button plus the overflow button (permanent
/// delete) instead of status icons - `NooFileTableRow` has no slot for
/// screen-specific actions there. Column widths (180/160/120) are matched
/// by hand to `NooFileTableHeader`'s (private in `noo_file_table.dart`) so
/// this still lines up under it; promoting an optional `actions` slot onto
/// `NooFileTableRow` would let this fold back into the shared component.
class _TrashDesktopRow extends StatelessWidget {
  final NooFileKind kind;
  final String name;
  final String col2;
  final String col3;
  final VoidCallback onRestore;
  final VoidCallback onMore;

  const _TrashDesktopRow({
    required this.kind,
    required this.name,
    required this.col2,
    required this.col3,
    required this.onRestore,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final metaStyle = NooText.meta.copyWith(color: colors.fg3);

    return SizedBox(
      height: NooSizes.rowDesktop,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  NooFileTile(kind: kind, size: NooFileTileSize.desktop),
                  const SizedBox(width: NooSpace.sm),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.fg1,
                      ),
                    ),
                  ),
                  const SizedBox(width: NooSpace.md),
                ],
              ),
            ),
            SizedBox(
              width: 180,
              child: Text(col2, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
            ),
            SizedBox(
              width: 160,
              child: Text(col3, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
            ),
            SizedBox(
              width: 120,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NooButton(
                      variant: NooButtonVariant.tonal,
                      size: NooButtonSize.xs,
                      onTap: onRestore,
                      child: const Text('Restore'),
                    ),
                    const SizedBox(width: 4),
                    NooOverflowButton(size: 24, onTap: onMore),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
