import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'nextcloud_item.dart';

/// The words (and icon) for the "Delete" action on [items].
///
/// On Nextcloud, a DELETE on a received share's mount root
/// ([NextcloudItem.isSharedWithMe]) doesn't delete anything - it removes the
/// share for the recipient and the owner keeps the originals. Calling that
/// "Delete" (with a "cannot be undone" warning) is wrong, so a selection made
/// only of share roots reads "Leave share". Items *inside* a shared folder
/// really are deleted, so they keep the delete wording; a mix gets a neutral
/// "Remove". The request itself is the same `deleteItem` either way.
class RemoveWording {
  final IconData icon;

  /// Action/menu label, e.g. "Leave share".
  final String label;

  /// Confirmation dialog title.
  final String title;

  /// Confirmation dialog body.
  final String message;

  /// Confirmation button label.
  final String confirmLabel;

  final RemoveKind kind;
  final int total;
  final String? singleName;

  const RemoveWording._({
    required this.icon,
    required this.label,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.kind,
    required this.total,
    this.singleName,
  });

  factory RemoveWording.of(List<NextcloudItem> items) {
    final shared = items.where((i) => i.isSharedWithMe).length;
    final total = items.length;
    final single = total == 1 ? items.single.name : null;
    if (shared == total && total > 0) {
      return RemoveWording._(
        icon: LucideIcons.logOut,
        label: 'Leave share',
        title: total == 1 ? 'Leave share' : 'Leave shares',
        message: total == 1
            ? 'Leave "$single"? It will be removed from your files, but the '
                  'owner keeps the original.'
            : 'Leave $total shared items? They will be removed from your '
                  'files, but their owners keep the originals.',
        confirmLabel: 'Leave',
        kind: RemoveKind.leave,
        total: total,
        singleName: single,
      );
    }
    if (shared == 0) {
      return RemoveWording._(
        icon: LucideIcons.trash2,
        label: 'Delete',
        title: total == 1 ? 'Delete Item' : 'Delete Items',
        message: total == 1
            ? 'Delete "$single" from the server? This cannot be undone.'
            : 'Delete $total item(s) from the server? This cannot be '
                  'undone.',
        confirmLabel: 'Delete',
        kind: RemoveKind.delete,
        total: total,
        singleName: single,
      );
    }
    return RemoveWording._(
      icon: LucideIcons.trash2,
      label: 'Remove',
      title: 'Remove Items',
      message:
          'Delete ${total - shared} item(s) from the server and leave '
          '$shared shared item(s)? Deleting cannot be undone; leaving only '
          'removes the share for you.',
      confirmLabel: 'Remove',
      kind: RemoveKind.mixed,
      total: total,
    );
  }

  /// The snackbar text after [succeeded] of the items went through.
  String result(int succeeded) {
    final failed = succeeded < total;
    if (total == 1 && singleName != null) {
      return switch (kind) {
        RemoveKind.leave =>
          failed ? 'Failed to leave $singleName' : 'Left $singleName',
        _ => failed ? 'Failed to delete $singleName' : 'Deleted $singleName',
      };
    }
    return switch (kind) {
      RemoveKind.leave => 'Left $succeeded of $total shared item(s)',
      RemoveKind.delete => 'Deleted $succeeded of $total item(s)',
      RemoveKind.mixed => 'Removed $succeeded of $total item(s)',
    };
  }
}

enum RemoveKind { delete, leave, mixed }
