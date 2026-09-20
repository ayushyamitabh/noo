import 'nextcloud_item.dart';

/// A resolution choice for one conflicting item in a Move/Copy batch -
/// keyed by `item.id` in [ConflictChoice] maps passed to
/// `ItemOperations.resolveConflicts`.
enum ConflictChoice { overwrite, keepBoth, skip }

/// One item that couldn't be moved/copied because something with the same
/// name already exists at the destination (a WebDAV 412 response).
class MoveCopyConflict {
  final NextcloudItem item;

  const MoveCopyConflict(this.item);
}

/// Outcome of a Move/Copy batch (an initial attempt via
/// `ItemOperations.moveItems`/`copyItems`, or a follow-up
/// `resolveConflicts` call). [blockedReason] is set instead of attempting
/// anything at all when the destination itself is invalid (e.g. moving a
/// folder into its own subfolder).
class MoveCopyResult {
  final int succeeded;
  final List<MoveCopyConflict> conflicts;
  final int failed;
  final String? blockedReason;

  const MoveCopyResult({
    this.succeeded = 0,
    this.conflicts = const [],
    this.failed = 0,
    this.blockedReason,
  });
}
