import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/sync_status.dart';
import '../providers/session_controller.dart';
import '../providers/sync_status_controller.dart';

/// A snapshot of native device-sync status - see `SyncStatusBus.kt` (the
/// in-process pub/sub it mirrors) and `MainActivity.kt`'s `syncStatusMap`.
class SyncStatusSnapshot {
  final String? accountId;
  final bool syncing;
  final Set<String> syncingFileIds;
  final Set<String> syncedFileIds;
  final List<SyncConflictInfo> conflicts;

  const SyncStatusSnapshot({
    required this.accountId,
    required this.syncing,
    required this.syncingFileIds,
    required this.syncedFileIds,
    required this.conflicts,
  });

  factory SyncStatusSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return SyncStatusSnapshot(
      accountId: map['accountId'] as String?,
      syncing: map['syncing'] as bool? ?? false,
      syncingFileIds: ((map['syncingFileIds'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      syncedFileIds: ((map['syncedFileIds'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      conflicts: ((map['conflicts'] as List?) ?? const [])
          .cast<Map<dynamic, dynamic>>()
          .map(SyncConflictInfo.fromMap)
          .toList(),
    );
  }
}

/// Talks to `SyncWorker`/`SyncEngine.kt`'s Android WorkManager-based device
/// sync (see `server.md`'s "Device sync" section for the full design) -
/// Dart's job here is only to gather what the native side needs, push a
/// fresh config whenever it changes, and listen for live status; the actual
/// PROPFIND-walk/diff/GET/PUT engine runs entirely in Kotlin, independent
/// of the Flutter engine. Takes [SessionController]/[SyncStatusController]
/// directly rather than a single god-object provider, since those are the
/// only two domains this ever needs.
class SyncService {
  static const _channel = MethodChannel('dev.ayushya.noo/sync_service');
  static const _statusChannel = EventChannel(
    'dev.ayushya.noo/sync_service/status',
  );

  /// Cancels (if [SyncStatusController.syncedPaths] is now empty) or
  /// re-enqueues the periodic sync job with fresh account/credentials/
  /// path-list/network-constraint data - call this any time one of those
  /// changes, since a periodic `WorkRequest`'s input is fixed at enqueue
  /// time and can only be updated by re-enqueueing.
  static Future<void> reschedule(
    SessionController session,
    SyncStatusController sync,
  ) async {
    final accountId = session.activeAccountId;
    final authHeader = session.service?.authHeaders['Authorization'];
    if (accountId == null || authHeader == null) {
      return cancel();
    }

    final paths = sync.syncEverything ? ['/'] : sync.syncedPaths;
    await _channel.invokeMethod('reschedule', {
      'accountId': accountId,
      'serverUrl': session.serverUrl,
      'username': session.username,
      'authHeader': authHeader,
      'folders': jsonEncode(paths),
      'wifiOnly': !sync.syncOnCellular,
    });
  }

  static Future<void> cancel() async {
    await _channel.invokeMethod('cancel');
  }

  /// Runs a one-off sync pass immediately (Settings' "Sync now"),
  /// independent of the periodic schedule.
  static Future<void> syncNow(
    SessionController session,
    SyncStatusController sync,
  ) async {
    final accountId = session.activeAccountId;
    final authHeader = session.service?.authHeaders['Authorization'];
    if (accountId == null || authHeader == null) {
      throw Exception('Not logged in.');
    }

    final paths = sync.syncEverything ? ['/'] : sync.syncedPaths;
    await _channel.invokeMethod('syncNow', {
      'accountId': accountId,
      'serverUrl': session.serverUrl,
      'username': session.username,
      'authHeader': authHeader,
      'folders': jsonEncode(paths),
    });
  }

  /// One-shot status snapshot - used to seed [SyncStatusController]'s state
  /// right after login/account-switch, before the first [statusStream]
  /// event arrives.
  static Future<SyncStatusSnapshot> getStatus() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getSyncStatus',
    );
    return SyncStatusSnapshot.fromMap(result ?? const {});
  }

  /// Live status updates pushed from `SyncStatusBus` (Kotlin) - syncing
  /// started/stopped, per-file progress, new/resolved conflicts.
  static Stream<SyncStatusSnapshot> get statusStream {
    return _statusChannel.receiveBroadcastStream().map(
      (event) => SyncStatusSnapshot.fromMap(event as Map<dynamic, dynamic>),
    );
  }

  /// In-app conflict resolution (the header's "Keep local"/"Use server"
  /// buttons) - shares the exact same native `ConflictResolveWorker`
  /// enqueue path the notification actions use, just triggered from Dart
  /// instead of a `PendingIntent`.
  static Future<void> resolveConflict(
    SessionController session,
    SyncConflictInfo conflict,
    String resolution,
  ) async {
    final authHeader = session.service?.authHeaders['Authorization'];
    if (authHeader == null) throw Exception('Not logged in.');
    await _channel.invokeMethod('resolveConflict', {
      'accountId': conflict.accountId,
      'serverUrl': session.serverUrl,
      'username': session.username,
      'authHeader': authHeader,
      'fileId': conflict.fileId,
      'remotePath': conflict.remotePath,
      'relPath': conflict.relPath,
      'resolution': resolution,
    });
  }

  /// Deletes [path]'s local mirror and its recorded sync state - called
  /// when the user turns sync off for a path, so the on-device copy
  /// actually goes away instead of just stopping future updates. See
  /// `SyncEngine.removeLocalSync`'s doc comment for why the state also has
  /// to be cleared, not just the files.
  static Future<void> removeLocalSync(
    SessionController session,
    String path,
  ) async {
    final accountId = session.activeAccountId;
    if (accountId == null) return;
    await _channel.invokeMethod('removeLocalSync', {
      'accountId': accountId,
      'path': path,
    });
  }

  /// The deterministic local mirror path for [remoteItemPath] under
  /// account [accountId] - mirrors `SyncEngine.kt#syncRoot`'s
  /// `<externalFilesDir>/sync/<accountId>/...` layout exactly, so this
  /// never needs to read native sync state. Returns null if nothing's
  /// actually been synced there yet.
  static Future<String?> localSyncedFilePath(
    String accountId,
    String remoteItemPath,
  ) async {
    final base = await getExternalStorageDirectory();
    if (base == null) return null;
    final relPath = remoteItemPath.startsWith('/')
        ? remoteItemPath.substring(1)
        : remoteItemPath;
    final file = File(p.join(base.path, 'sync', accountId, relPath));
    return file.existsSync() ? file.path : null;
  }
}
