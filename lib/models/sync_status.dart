/// A pending device-sync conflict (a file changed both locally and on the
/// server since the last sync) - mirrors `SyncStatusBus.Conflict` on the
/// native side exactly, see `SyncEngine.kt`/`server.md`'s "Device sync"
/// section.
class SyncConflictInfo {
  final String accountId;
  final String fileId;
  final String remotePath;
  final String relPath;
  final String name;

  const SyncConflictInfo({
    required this.accountId,
    required this.fileId,
    required this.remotePath,
    required this.relPath,
    required this.name,
  });

  factory SyncConflictInfo.fromMap(Map<dynamic, dynamic> map) {
    return SyncConflictInfo(
      accountId: map['accountId'] as String? ?? '',
      fileId: map['fileId'] as String? ?? '',
      remotePath: map['remotePath'] as String? ?? '',
      relPath: map['relPath'] as String? ?? '',
      name: map['name'] as String? ?? '',
    );
  }
}

/// A single item's device-sync status, used to badge its tile in the
/// Files view.
enum SyncItemStatus { none, syncing, synced, conflict }

/// The persistent header chip/panel's overall status (account-wide, not
/// scoped to whatever folder is currently browsed) - see
/// `SyncStatusController.syncHeaderStatus`.
enum SyncHeaderStatus { off, syncing, done, alert }

/// A sync pass that stopped because what it had to download wouldn't fit on
/// the device (with a little room to spare). [serial] changes with every new
/// occurrence, so a screen can alert once per event.
class StorageShortfall {
  final int neededBytes;
  final int availableBytes;
  final int serial;

  /// What the pass was syncing for the first time was dropped, exactly as if
  /// the user had cancelled it (removed from the synced list, partial files
  /// deleted) - see `SyncStatusController.cancelSync`.
  final bool removedFromSync;

  const StorageShortfall({
    required this.neededBytes,
    required this.availableBytes,
    required this.serial,
    this.removedFromSync = false,
  });
}
