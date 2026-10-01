import 'package:flutter/material.dart';
import '../providers/files_controller.dart';
import '../theme/design_tokens.dart';

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

  /// An extra control (e.g. an ascending/descending toggle) shown inside
  /// the same pill, between the label and the menu's own dropdown chevron -
  /// visually one "Name ↑" chip (DESIGN_SYSTEM.md's sort chip) even though
  /// the two behaviors (pick a field / flip direction) stay separate taps.
  final Widget? trailing;

  const SortMenuButton({
    super.key,
    required this.field,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return PopupMenuButton<FileSortField>(
      initialValue: field,
      onSelected: onChanged,
      offset: const Offset(0, 36),
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => FileSortField.values.map((f) {
        return PopupMenuItem(
          value: f,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: f == field
                    ? Icon(Icons.check_rounded, size: 18, color: colors.accentText)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(sortFieldLabel(f), style: NooText.body.copyWith(color: colors.fg1)),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(NooRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 16, color: colors.fg1),
            const SizedBox(width: 6),
            // A plain Text child in a Row always takes its full intrinsic
            // width no matter what maxLines/overflow say - Flexible is what
            // actually lets it shrink to whatever space this row has left
            // (it's squeezed by hidden/storage/list-grid toggles alongside
            // it) so the ellipsis can kick in instead of overflowing.
            Flexible(
              child: Text(
                sortFieldLabel(field),
                style: NooText.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.fg1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?trailing,
            Icon(Icons.arrow_drop_down_rounded, color: colors.fg1),
          ],
        ),
      ),
    );
  }
}
