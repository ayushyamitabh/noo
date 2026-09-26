import 'package:flutter/material.dart';
import '../models/move_copy_result.dart';
import '../theme/design_tokens.dart';
import 'noo/core/noo_button.dart';
import 'noo/core/noo_segmented_control.dart';
import 'noo/files/noo_file_kind.dart';
import 'noo/files/noo_file_tile.dart';
import 'noo/lists/noo_grouped_list.dart';
import 'noo/noo_layout.dart';
import 'noo/overlays/noo_dialog.dart';
import 'noo/overlays/noo_overlay_header.dart';
import 'noo/overlays/noo_sheet.dart';

/// Shown after a Move/Copy batch comes back with `MoveCopyResult.conflicts`
/// non-empty (an item with the same name already exists at the
/// destination) - summarizes every conflict at once rather than prompting
/// per item as they're hit, and lets the user resolve them all the same
/// way (overwrite/keep both) or open a per-item breakdown. Returns the
/// `ConflictChoice` map `ItemOperations.resolveConflicts` expects, or null
/// if dismissed without choosing. A `showNooDialog` (desktop) / `showNooSheet`
/// (mobile) instead of the old `showGradualBottomSheet` - the content never
/// grows past a couple of screens, so the drag-to-resize sheet that needed
/// isn't worth it here.
class MoveCopyConflictSheet extends StatefulWidget {
  final List<MoveCopyConflict> conflicts;

  const MoveCopyConflictSheet({super.key, required this.conflicts});

  static Future<Map<String, ConflictChoice>?> show(
    BuildContext context,
    List<MoveCopyConflict> conflicts,
  ) {
    final content = MoveCopyConflictSheet(conflicts: conflicts);
    final count = conflicts.length;
    final title = count == 1
        ? '1 item already exists'
        : '$count items already exist';

    if (NooLayout.isDesktop(context)) {
      return showNooDialog<Map<String, ConflictChoice>>(
        context,
        title: title,
        subtitle: 'Choose how to handle the conflicts',
        children: [content],
      );
    }
    return showNooSheet<Map<String, ConflictChoice>>(
      context,
      children: [content],
    );
  }

  @override
  State<MoveCopyConflictSheet> createState() => _MoveCopyConflictSheetState();
}

class _MoveCopyConflictSheetState extends State<MoveCopyConflictSheet> {
  bool _decidingPerItem = false;
  late final Map<String, ConflictChoice> _perItemChoices = {
    for (final conflict in widget.conflicts)
      conflict.item.id: ConflictChoice.keepBoth,
  };

  void _resolveAll(ConflictChoice choice) {
    Navigator.pop(context, {
      for (final conflict in widget.conflicts) conflict.item.id: choice,
    });
  }

  void _confirmPerItem() {
    Navigator.pop(context, _perItemChoices);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = NooLayout.isDesktop(context);
    final count = widget.conflicts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The dialog already renders this title/subtitle in its own header
        // (see `show` above); the sheet has no header of its own, so it
        // needs one here.
        if (!isDesktop) ...[
          NooOverlayHeader(
            title: count == 1
                ? '1 item already exists'
                : '$count items already exist',
            subtitle: 'Choose how to handle the conflicts',
            onClose: () => Navigator.pop(context),
          ),
          const SizedBox(height: NooSpace.lg),
        ],
        if (!_decidingPerItem) ...[
          NooButton(
            variant: NooButtonVariant.primary,
            size: NooButtonSize.card,
            fullWidth: true,
            onTap: () => _resolveAll(ConflictChoice.overwrite),
            child: const Text('Overwrite all'),
          ),
          const SizedBox(height: NooSpace.xs),
          NooButton(
            variant: NooButtonVariant.tonal,
            size: NooButtonSize.card,
            fullWidth: true,
            onTap: () => _resolveAll(ConflictChoice.keepBoth),
            child: const Text('Keep both (rename)'),
          ),
          const SizedBox(height: NooSpace.xs),
          NooButton(
            variant: NooButtonVariant.outline,
            size: NooButtonSize.card,
            fullWidth: true,
            onTap: () => setState(() => _decidingPerItem = true),
            child: const Text('Decide per item'),
          ),
          const SizedBox(height: NooSpace.lg),
        ],
        NooGroupedList(
          label: _decidingPerItem ? 'Items' : null,
          children: [
            for (final conflict in widget.conflicts)
              _ConflictRow(
                conflict: conflict,
                decidingPerItem: _decidingPerItem,
                choice: _perItemChoices[conflict.item.id]!,
                onChoiceChanged: (choice) => setState(() {
                  _perItemChoices[conflict.item.id] = choice;
                }),
              ),
          ],
        ),
        if (_decidingPerItem) ...[
          const SizedBox(height: NooSpace.lg),
          NooButton(
            variant: NooButtonVariant.primary,
            size: NooButtonSize.card,
            fullWidth: true,
            onTap: _confirmPerItem,
            child: const Text('Confirm'),
          ),
        ],
      ],
    );
  }
}

/// One conflicting item: its file-type tile and name, plus (once "Decide
/// per item" is active) a segmented overwrite/keep both/skip choice.
class _ConflictRow extends StatelessWidget {
  final MoveCopyConflict conflict;
  final bool decidingPerItem;
  final ConflictChoice choice;
  final ValueChanged<ConflictChoice> onChoiceChanged;

  const _ConflictRow({
    required this.conflict,
    required this.decidingPerItem,
    required this.choice,
    required this.onChoiceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final item = conflict.item;
    final kind = NooFileKind.from(name: item.name, isDirectory: item.isFolder);

    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NooSpace.md,
          vertical: NooSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NooFileTile(kind: kind),
                const SizedBox(width: NooSpace.sm),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.bodyL.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.fg1,
                    ),
                  ),
                ),
              ],
            ),
            if (decidingPerItem) ...[
              const SizedBox(height: NooSpace.xs),
              NooSegmentedControl<ConflictChoice>(
                fill: true,
                onSurface: true,
                value: choice,
                onChanged: onChoiceChanged,
                options: const [
                  NooSegmentOption(
                    value: ConflictChoice.overwrite,
                    label: 'Overwrite',
                  ),
                  NooSegmentOption(
                    value: ConflictChoice.keepBoth,
                    label: 'Keep both',
                  ),
                  NooSegmentOption(value: ConflictChoice.skip, label: 'Skip'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
