import 'package:flutter/material.dart';
import '../providers/server_provider.dart';

String sortFieldLabel(FileSortField field) {
  switch (field) {
    case FileSortField.name:
      return 'Name';
    case FileSortField.dateCreated:
      return 'Date created';
    case FileSortField.dateModified:
      return 'Date modified';
    case FileSortField.size:
      return 'Size';
  }
}

/// Dropdown trigger for choosing which field a list/grid is sorted by,
/// shared by the Files and Photos tabs.
class SortMenuButton extends StatelessWidget {
  final FileSortField field;
  final ValueChanged<FileSortField> onChanged;

  const SortMenuButton({
    super.key,
    required this.field,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopupMenuButton<FileSortField>(
      initialValue: field,
      onSelected: onChanged,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => FileSortField.values.map((f) {
        return PopupMenuItem(
          value: f,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: f == field
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(sortFieldLabel(f)),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          // A plain Text child in a Row always takes its full intrinsic
          // width no matter what maxLines/overflow say - Flexible is what
          // actually lets it shrink to whatever space this row has left
          // (it's squeezed by favorite/hidden/storage/list-grid toggles
          // alongside it) so the ellipsis can kick in instead of
          // overflowing.
          children: [
            Flexible(
              child: Text(
                sortFieldLabel(field),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
