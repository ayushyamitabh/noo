import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/sync_status.dart';
import '../providers/server_provider.dart';

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
/// of the Flutter engine.
class SyncService {
  static const _channel = MethodChannel('dev.ayushya.noo/sync_service');
  static const _statusChannel = EventChannel(
    'dev.ayushya.noo/sync_service/status',
  );

  /// Cancels (if [ServerProvider.syncedPaths] is now empty) or re-enqueues
  /// the periodic sync job with fresh account/credentials/path-list/
  /// network-constraint data - call this any time one of those changes,
  /// since a periodic `WorkRequest`'s input is fixed at enqueue time and
  /// can only be updated by re-enqueueing.
  static Future<void> reschedule(ServerProvider provider) async {
    final accountId = provider.activeAccountId;
    final service = provider.service;
    final authHeader = service?.authHeaders['Authorization'];
    if (accountId == null || service == null || authHeader == null) {
      return cancel();
    }

    final paths = provider.syncEverything ? ['/'] : provider.syncedPaths;
    await _channel.invokeMethod('reschedule', {
      'accountId': accountId,
      'serverUrl': provider.serverUrl,
      'username': provider.username,
      'authHeader': authHeader,
      'folders': jsonEncode(paths),
      'wifiOnly': !provider.syncOnCellular,
    });
  }

  static Future<void> cancel() async {
    await _channel.invokeMethod('cancel');
  }

  /// Runs a one-off sync pass immediately (Settings' "Sync now"),
  /// independent of the periodic schedule.
  static Future<void> syncNow(ServerProvider provider) async {
    final accountId = provider.activeAccountId;
    final service = provider.service;
    final authHeader = service?.authHeaders['Authorization'];
    if (accountId == null || service == null || authHeader == null) {
      throw Exception('Not logged in.');
    }

    final paths = provider.syncEverything ? ['/'] : provider.syncedPaths;
    await _channel.invokeMethod('syncNow', {
      'accountId': accountId,
      'serverUrl': provider.serverUrl,
      'username': provider.username,
      'authHeader': authHeader,
      'folders': jsonEncode(paths),
    });
  }

  /// One-shot status snapshot - used to seed [ServerProvider]'s state right
  /// after login/account-switch, before the first [statusStream] event
  /// arrives.
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
    ServerProvider provider,
    SyncConflictInfo conflict,
    String resolution,
  ) async {
    final service = provider.service;
    final authHeader = service?.authHeaders['Authorization'];
    if (service == null || authHeader == null) {
      throw Exception('Not logged in.');
    }
    await _channel.invokeMethod('resolveConflict', {
      'accountId': conflict.accountId,
      'serverUrl': provider.serverUrl,
      'username': provider.username,
      'authHeader': authHeader,
      'fileId': conflict.fileId,
      'remotePath': conflict.remotePath,
      'relPath': conflict.relPath,
      'resolution': resolution,
    });
  }
}
