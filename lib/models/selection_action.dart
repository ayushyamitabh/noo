import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A bulk action's identity, stable across the dynamic icon/label a
/// [SelectionAction] actually renders (e.g. `favorite` covers both
/// "Favorite" and "Remove from favorites"). This is what the user's
/// configured [order] - Settings' "Action bar" reorder list - and
/// [NooSelectionBar]'s inline/overflow split key off, since the live
/// [SelectionAction] list is rebuilt fresh on every selection change and
/// can't be compared by icon/label alone.
///
/// Not every screen offers every kind (e.g. Favorites has no `rename` or
/// `sync`) - [orderSelectionActions] just skips whatever kind a screen
/// didn't build.
enum SelectionActionKind {
  favorite,
  share,
  download,
  delete,
  copy,
  move,
  rename,
  sync,
  details;

  /// Generic label for the Settings reorder row - the live bar uses each
  /// screen's own contextual label (e.g. "Remove from favorites") instead.
  String get label => switch (this) {
    SelectionActionKind.favorite => 'Favorite',
    SelectionActionKind.share => 'Share',
    SelectionActionKind.download => 'Download',
    SelectionActionKind.delete => 'Delete',
    SelectionActionKind.copy => 'Copy',
    SelectionActionKind.move => 'Move',
    SelectionActionKind.rename => 'Rename',
    SelectionActionKind.sync => 'Sync to device',
    SelectionActionKind.details => 'Details',
  };

  IconData get icon => switch (this) {
    SelectionActionKind.favorite => LucideIcons.star,
    SelectionActionKind.share => LucideIcons.share2,
    SelectionActionKind.download => LucideIcons.download,
    SelectionActionKind.delete => LucideIcons.trash2,
    SelectionActionKind.copy => LucideIcons.copy,
    SelectionActionKind.move => LucideIcons.folderInput,
    SelectionActionKind.rename => LucideIcons.filePen,
    SelectionActionKind.sync => LucideIcons.hardDriveDownload,
    SelectionActionKind.details => LucideIcons.info,
  };
}

/// One bulk action available for the current multi-selection (e.g. favorite,
/// download, delete), shown as an icon button in the sticky selection
/// toolbar each tab (Files, Photos, ...) renders inline in its own content.
class SelectionAction {
  final SelectionActionKind kind;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SelectionAction({
    required this.kind,
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Reorders [actions] to match the user's configured [order] (Settings'
/// "Action bar" section, [SelectionActionKind] values) - this is what makes
/// that setting take effect, since it's [order] that decides which actions
/// land in `NooSelectionBar`'s inline slots vs. behind "More". A kind in
/// [order] the caller didn't build (e.g. `rename` on a multi-item
/// selection) is just skipped; a kind [actions] has that [order] doesn't
/// mention (e.g. a kind added in a later app update, before the saved
/// order is migrated - see [SettingsController.selectionActionOrder]) is
/// appended at the end in its original position.
List<SelectionAction> orderSelectionActions(
  List<SelectionAction> actions,
  List<SelectionActionKind> order,
) {
  final byKind = {for (final a in actions) a.kind: a};
  final ordered = <SelectionAction>[];
  for (final kind in order) {
    final action = byKind.remove(kind);
    if (action != null) ordered.add(action);
  }
  ordered.addAll(byKind.values);
  return ordered;
}
