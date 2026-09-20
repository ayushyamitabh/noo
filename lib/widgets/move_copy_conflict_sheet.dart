import 'package:flutter/material.dart';
import '../models/move_copy_result.dart';
import 'gradual_bottom_sheet.dart';

/// Shown after a Move/Copy batch comes back with `MoveCopyResult.conflicts`
/// non-empty (an item with the same name already exists at the
/// destination) - summarizes every conflict at once rather than prompting
/// per item as they're hit, and lets the user resolve them all the same
/// way (overwrite/keep both) or open a per-item breakdown. Returns the
/// `ConflictChoice` map `ItemOperations.resolveConflicts` expects, or null
/// if dismissed without choosing.
class MoveCopyConflictSheet extends StatefulWidget {
  final List<MoveCopyConflict> conflicts;
  final ScrollController? scrollController;

  const MoveCopyConflictSheet({
    super.key,
    required this.conflicts,
    this.scrollController,
  });

  static Future<Map<String, ConflictChoice>?> show(
    BuildContext context,
    List<MoveCopyConflict> conflicts,
  ) {
    return showGradualBottomSheet<Map<String, ConflictChoice>>(
      context,
      builder: (context, scrollController) => MoveCopyConflictSheet(
        conflicts: conflicts,
        scrollController: scrollController,
      ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = widget.conflicts.length;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          count == 1
              ? '1 item already exists at the destination'
              : '$count items already exist at the destination',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose how to handle the conflicts.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (!_decidingPerItem) ...[
          FilledButton(
            onPressed: () => _resolveAll(ConflictChoice.overwrite),
            child: const Text('Overwrite all'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => _resolveAll(ConflictChoice.keepBoth),
            child: const Text('Keep both (rename)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() => _decidingPerItem = true),
            child: const Text('Decide per item'),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
        ],
        for (final conflict in widget.conflicts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      conflict.item.isFolder
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        conflict.item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_decidingPerItem) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ConflictChoice>(
                      segments: const [
                        ButtonSegment(
                          value: ConflictChoice.overwrite,
                          label: Text('Overwrite'),
                        ),
                        ButtonSegment(
                          value: ConflictChoice.keepBoth,
                          label: Text('Keep both'),
                        ),
                        ButtonSegment(
                          value: ConflictChoice.skip,
                          label: Text('Skip'),
                        ),
                      ],
                      selected: {_perItemChoices[conflict.item.id]!},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) => setState(() {
                        _perItemChoices[conflict.item.id] = selection.first;
                      }),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_decidingPerItem) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _confirmPerItem,
              child: const Text('Confirm'),
            ),
          ),
        ],
      ],
    );
  }
}
