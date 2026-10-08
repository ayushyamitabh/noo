import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/sync_status.dart';
import '../models/saved_account.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import '../providers/sync_status_controller.dart';
import 'native_channel.dart';

/// A snapshot of native device-sync status - see `SyncStatusBus.kt` (the
/// in-process pub/sub it mirrors) and `MainActivity.kt`'s `syncStatusMap`.
class SyncStatusSnapshot {
  final String? accountId;
  final bool syncing;
  final Set<String> syncingFileIds;
  final Set<String> syncedFileIds;
  final List<SyncConflictInfo> conflicts;

  /// Configured sync paths the server says no longer exist (deleted on the
  /// web) - the app drops them from its synced list.
  final Set<String> missingRoots;

  const SyncStatusSnapshot({
    required this.accountId,
    required this.syncing,
    required this.syncingFileIds,
    required this.syncedFileIds,
    required this.conflicts,
    this.missingRoots = const {},
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
      missingRoots: ((map['missingRoots'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
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

  /// Brings the background periodic sync jobs in line with every saved
  /// account's current settings - one job per account with sync enabled
  /// (paths or "sync everything", and the Files Cache policy set to refresh
  /// periodically), cancelled for accounts without and for accounts the
  /// user logged out of. Background sync is deliberately not limited to the
  /// active account: each account's job carries that account's own
  /// credentials, paths and interval, so switching accounts doesn't stop the
  /// others.
  ///
  /// Call whenever any of that changes - a periodic `WorkRequest`'s input is
  /// fixed at enqueue time and can only be updated by re-enqueueing. The
  /// active account's settings come from [sync]/its live state (they may not
  /// have been persisted yet); every other account's are read from storage.
  static Future<void> reschedule(
    SessionController session,
    SyncStatusController sync,
  ) async {
    final prefs = await session.prefsFuture;
    final store = session.accountStore;
    final wifiOnly = !sync.syncOnCellular;
    final signedOut = store.loadSignedOut(prefs);

    for (final account in session.accounts) {
      try {
        if (signedOut.contains(account.id)) {
          await cancelAccount(account.id);
          continue;
        }
        final isActive = account.id == session.activeAccountId;
        final config = isActive
            ? _SyncConfig(
                paths: sync.syncEverything ? ['/'] : sync.syncedPaths,
                intervalMinutes: sync.backgroundSyncIntervalMinutes,
              )
            : _SyncConfig.fromPrefs(prefs, store.accountPrefKey, account.id);
        final password = await store.readPassword(account.id);
        if (password == null || config.paths.isEmpty) {
          await cancelAccount(account.id);
          continue;
        }
        if (config.intervalMinutes == null) {
          // Background sync is off, but this account still has paths to sync
          // by hand: keep its credentials (native uses them for "Sync now"
          // and conflict notification actions).
          await cancelAccount(account.id, forget: false);
          continue;
        }
        await invokeIfAvailable(_channel, 'reschedule', {
          'accountId': account.id,
          'serverUrl': account.serverUrl,
          'username': account.username,
          'authHeader': _basicAuth(account, password),
          'folders': jsonEncode(config.paths),
          'wifiOnly': wifiOnly,
          'intervalMinutes': config.intervalMinutes,
          'notify': sync.syncNotifications,
        });
      } catch (e) {
        debugPrint('[SyncService] Could not schedule ${account.id}: $e');
      }
    }
  }

  static String _basicAuth(SavedAccount account, String password) =>
      'Basic ${base64Encode(utf8.encode('${account.username}:$password'))}';

  /// Stops [accountId]'s periodic job (the account was removed, or has
  /// nothing left to sync).
  ///
  /// [forget] (the default) is for an account that was signed out or removed:
  /// native also drops its stored credentials. Pass false when only the
  /// background job is being turned off - the account's paths are still
  /// synced by hand ("Sync now"), and a conflict notification's actions
  /// still need its credentials.
  static Future<void> cancelAccount(String accountId, {bool forget = true}) async {
    await invokeIfAvailable(_channel, 'cancel', {
      'accountId': accountId,
      'forget': forget,
    });
  }

  /// Runs a one-off sync pass immediately, independent of the periodic
  /// schedule.
  ///
  /// [force] (Settings' "Sync now", a newly-added path): full walk of every
  /// synced root, visible progress notification, supersedes any run already
  /// in flight. Without it (pull-to-refresh, foreground timer, app resume)
  /// the pass is a quiet check that uses the cheap root-etag shortcut and
  /// never interrupts a run already in progress. [respectNetworkSetting]
  /// makes such a pass wait for Wi-Fi when "Sync on cellular" is off (the
  /// automatic triggers do; a deliberate pull doesn't).
  static Future<void> syncNow(
    SessionController session,
    SyncStatusController sync, {
    bool force = true,
    bool respectNetworkSetting = false,
  }) async {
    final accountId = session.activeAccountId;
    final authHeader = session.service?.authHeaders['Authorization'];
    if (accountId == null || authHeader == null) {
      throw Exception('Not logged in.');
    }

    final paths = sync.syncEverything ? ['/'] : sync.syncedPaths;
    await invokeOrExplain(_channel, 'syncNow', 'Syncing', {
      'accountId': accountId,
      'serverUrl': session.serverUrl,
      'username': session.username,
      'authHeader': authHeader,
      'folders': jsonEncode(paths),
      'force': force,
      'notify': sync.syncNotifications,
      if (respectNetworkSetting) 'wifiOnly': !sync.syncOnCellular,
    });
  }

  /// One-shot status snapshot - used to seed [SyncStatusController]'s state
  /// right after login/account-switch, before the first [statusStream]
  /// event arrives.
  ///
  /// [accountId] is required for `syncedFileIds` to be populated on a fresh
  /// app start - the native bus only knows an account once a sync pass has
  /// run in this process.
  static Future<SyncStatusSnapshot> getStatus(String? accountId) async {
    final result = await invokeIfAvailable<Map<dynamic, dynamic>>(
      _channel,
      'getSyncStatus',
      {'accountId': accountId},
    );
    return SyncStatusSnapshot.fromMap(result ?? const {});
  }

  /// Live status updates pushed from `SyncStatusBus` (Kotlin) - syncing
  /// started/stopped, per-file progress, new/resolved conflicts.
  ///
  /// One shared stream, deliberately: every call to
  /// `EventChannel.receiveBroadcastStream()` opens its *own* native
  /// subscription, and the native side only keeps one listener - a second
  /// subscriber (the Offline tab's controller, once it became eagerly
  /// created) silently took the events away from the first
  /// (`SyncStatusController`), so sync badges stopped updating until the app
  /// was restarted. This is a broadcast stream, so any number of Dart
  /// listeners share the one native subscription.
  static final Stream<SyncStatusSnapshot> statusStream = quietEvents(
    _statusChannel,
    (event) => SyncStatusSnapshot.fromMap(event as Map<dynamic, dynamic>),
  );

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
    await invokeOrExplain(_channel, 'resolveConflict', 'Resolving conflicts', {
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
    await invokeIfAvailable(_channel, 'removeLocalSync', {
      'accountId': accountId,
      'path': path,
    });
  }

  /// Where the `sync/<accountId>/...` mirror lives: Android's app-specific
  /// external files dir (what `SyncEngine.kt` writes to); everywhere else -
  /// iOS has no external storage, `getExternalStorageDirectory` throws
  /// there - the app's private support directory.
  static Future<Directory?> baseDirectory() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return getExternalStorageDirectory();
    }
    return getApplicationSupportDirectory();
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
    final base = await baseDirectory();
    if (base == null) return null;
    final relPath = remoteItemPath.startsWith('/')
        ? remoteItemPath.substring(1)
        : remoteItemPath;
    final file = File(p.join(base.path, 'sync', accountId, relPath));
    return file.existsSync() ? file.path : null;
  }
}

/// One account's background-sync settings, as far as scheduling is
/// concerned.
class _SyncConfig {
  final List<String> paths;

  /// Null = background sync off for this account.
  final int? intervalMinutes;

  const _SyncConfig({required this.paths, required this.intervalMinutes});

  /// Reads a *non-active* account's persisted settings - the same per-account
  /// keys `SyncStatusController`/`FilesController` write. Malformed values
  /// fall back to "nothing to sync" rather than throwing.
  factory _SyncConfig.fromPrefs(
    SharedPreferences prefs,
    String Function(String accountId, String baseKey) key,
    String accountId,
  ) {
    var paths = <String>[];
    try {
      final everything =
          prefs.getBool(
            key(accountId, SyncStatusController.prefSyncEverything),
          ) ??
          false;
      final json = prefs.getString(
        key(accountId, SyncStatusController.prefSyncedPaths),
      );
      if (everything) {
        paths = ['/'];
      } else if (json != null) {
        paths = (jsonDecode(json) as List).cast<String>();
      }
    } catch (e) {
      debugPrint('[SyncService] Unreadable sync paths for $accountId: $e');
    }

    var policy = defaultCachePolicy;
    var minutes = defaultCacheIntervalMinutes;
    try {
      final policyName = prefs.getString(
        key(accountId, FilesController.prefCachePolicy),
      );
      policy = CachePolicy.values.firstWhere(
        (c) => c.name == policyName,
        orElse: () => defaultCachePolicy,
      );
      minutes =
          prefs.getInt(
            key(accountId, FilesController.prefCacheIntervalMinutes),
          ) ??
          defaultCacheIntervalMinutes;
    } catch (e) {
      debugPrint('[SyncService] Unreadable cache rule for $accountId: $e');
    }

    return _SyncConfig(
      paths: paths,
      intervalMinutes: policy == CachePolicy.interval ? minutes : null,
    );
  }
}
