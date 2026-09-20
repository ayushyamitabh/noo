import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import '../models/sync_status.dart';
import '../services/sync_service.dart';
import 'session_controller.dart';

/// Device-sync state and settings: which remote paths (files or folders,
/// per account) get mirrored locally by the native `SyncWorker`, whether
/// its periodic background runs are allowed on cellular, and live status
/// pushed from `SyncStatusBus.kt` (syncing-now/per-file-syncing/synced/
/// conflicts) - see `server.md`'s "Device sync" section. Split out of the
/// former single `ServerProvider` god object specifically because this
/// state used to reach directly into Files/Photos/Favorites item lists
/// (`syncStatusFor`) despite living in an unrelated domain; now it's a
/// second, focused provider those views read alongside their own tab
/// controller.
class SyncStatusController extends ChangeNotifier {
  final SessionController session;

  static const _prefSyncedPaths = 'ui_synced_folders';
  static const _prefSyncedPathTypes = 'ui_synced_folder_types';
  static const _prefSyncEverything = 'ui_sync_everything';
  static const _prefSyncOnCellular = 'ui_sync_on_cellular';

  List<String> _syncedPaths = [];
  // path -> isFolder, keyed the same as [_syncedPaths] - missing entries
  // (from before this map existed) default to folder, the overwhelmingly
  // common case.
  Map<String, bool> _syncedPathTypes = {};
  bool _syncEverything = false;
  bool _syncOnCellular = false;

  bool _isSyncingNow = false;
  Set<String> _syncingFileIds = {};
  Set<String> _syncedFileIds = {};
  List<SyncConflictInfo> _syncConflicts = [];
  StreamSubscription<SyncStatusSnapshot>? _statusSub;

  SyncStatusController(this.session) {
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
    _statusSub = SyncService.statusStream.listen(_applySnapshot);
    _loadGlobalPrefs();
  }

  List<String> get syncedPaths => List.unmodifiable(_syncedPaths);
  bool get syncEverything => _syncEverything;
  bool get syncOnCellular => _syncOnCellular;

  bool get isSyncingNow => _isSyncingNow;
  List<SyncConflictInfo> get syncConflicts => List.unmodifiable(_syncConflicts);

  /// How many of [syncedPaths] are folders (as opposed to individual
  /// files) - used by the sync header's expanded summary.
  int get syncedFolderCount =>
      _syncedPaths.where((p) => _syncedPathTypes[p] ?? true).length;

  /// How many individual files have actually been mirrored locally so far
  /// - distinct from [syncedFolderCount]/[syncedPaths], which are just the
  /// configured *targets*, not what's actually landed on disk yet.
  int get syncedItemCount => _syncedFileIds.length;

  SyncHeaderStatus get syncHeaderStatus {
    if (_syncConflicts.isNotEmpty) return SyncHeaderStatus.alert;
    if (_isSyncingNow) return SyncHeaderStatus.syncing;
    if (!_syncEverything && _syncedPaths.isEmpty) return SyncHeaderStatus.off;
    return SyncHeaderStatus.done;
  }

  /// True if [path] itself, or an ancestor of it, is covered by device
  /// sync - either explicitly (one of [_syncedPaths]) or via
  /// [_syncEverything]. Shared by [syncStatusFor] (folders) and
  /// [localSyncedFilePath] (files).
  bool _isPathInSyncScope(String path) {
    if (_syncEverything) return true;
    final normalized = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return _syncedPaths.any((folder) {
      final f = folder.endsWith('/')
          ? folder.substring(0, folder.length - 1)
          : folder;
      return normalized == f || normalized.startsWith('$f/');
    });
  }

  /// True if any pending conflict falls under [folderPath].
  bool _folderHasConflict(String folderPath) {
    final normalized = folderPath.endsWith('/')
        ? folderPath.substring(0, folderPath.length - 1)
        : folderPath;
    return _syncConflicts.any((c) {
      final p = c.remotePath.endsWith('/')
          ? c.remotePath.substring(0, c.remotePath.length - 1)
          : c.remotePath;
      return p == normalized || p.startsWith('$normalized/');
    });
  }

  /// Folders don't get their own entry in [_syncedFileIds] (only individual
  /// files do - see `SyncEngine.diffFolder`'s `if (entry.isFolder) continue`),
  /// so a folder's status is derived from whether it's in sync scope at all
  /// rather than tracked per-item like a file's is.
  SyncItemStatus syncStatusFor(NextcloudItem item) {
    if (item.isFolder) {
      if (!_isPathInSyncScope(item.path)) return SyncItemStatus.none;
      if (_folderHasConflict(item.path)) return SyncItemStatus.conflict;
      if (_isSyncingNow) return SyncItemStatus.syncing;
      return SyncItemStatus.synced;
    }
    if (_syncingFileIds.contains(item.id)) return SyncItemStatus.syncing;
    if (_syncConflicts.any((c) => c.fileId == item.id)) {
      return SyncItemStatus.conflict;
    }
    if (_syncedFileIds.contains(item.id)) return SyncItemStatus.synced;
    return SyncItemStatus.none;
  }

  Future<void> _loadGlobalPrefs() async {
    final prefs = await session.prefsFuture;
    _syncOnCellular = prefs.getBool(_prefSyncOnCellular) ?? _syncOnCellular;
    notifyListeners();
  }

  void _onAccountCleared() {
    _syncedPaths = [];
    _syncedPathTypes = {};
    _syncEverything = false;
    _isSyncingNow = false;
    _syncingFileIds = {};
    _syncedFileIds = {};
    _syncConflicts = [];
    notifyListeners();
  }

  Future<void> _onAccountActivated() async {
    final id = session.activeAccountId;
    if (id != null) {
      final prefs = await session.prefsFuture;
      String k(String base) => session.accountStore.accountPrefKey(id, base);
      final pathsJson = prefs.getString(k(_prefSyncedPaths));
      if (pathsJson != null) {
        try {
          _syncedPaths = (jsonDecode(pathsJson) as List).cast<String>();
        } catch (e) {
          debugPrint('[SyncStatusController] Synced paths restore failed: $e');
          _syncedPaths = [];
        }
      } else {
        _syncedPaths = [];
      }
      final typesJson = prefs.getString(k(_prefSyncedPathTypes));
      if (typesJson != null) {
        try {
          _syncedPathTypes = (jsonDecode(typesJson) as Map).map(
            (k, v) => MapEntry(k as String, v as bool),
          );
        } catch (e) {
          debugPrint('[SyncStatusController] Synced path types restore failed: $e');
          _syncedPathTypes = {};
        }
      } else {
        _syncedPathTypes = {};
      }
      _syncEverything = prefs.getBool(k(_prefSyncEverything)) ?? false;
      notifyListeners();
    }
    unawaited(SyncService.reschedule(session, this));
    unawaited(SyncService.getStatus().then(_applySnapshot));
  }

  void _applySnapshot(SyncStatusSnapshot snapshot) {
    if (snapshot.accountId != null &&
        snapshot.accountId != session.activeAccountId) {
      return;
    }
    _isSyncingNow = snapshot.syncing;
    _syncingFileIds = snapshot.syncingFileIds;
    _syncedFileIds = snapshot.syncedFileIds;
    _syncConflicts = snapshot.conflicts;
    notifyListeners();
  }

  void _persistSyncedPaths() {
    final id = session.activeAccountId;
    if (id == null) return;
    session.prefsFuture.then((p) {
      p.setString(
        session.accountStore.accountPrefKey(id, _prefSyncedPaths),
        jsonEncode(_syncedPaths),
      );
      p.setString(
        session.accountStore.accountPrefKey(id, _prefSyncedPathTypes),
        jsonEncode(_syncedPathTypes),
      );
    });
  }

  bool isPathSynced(String path) => _syncedPaths.contains(path);

  void addSyncedPath(String path, {required bool isFolder}) {
    if (_syncedPaths.contains(path)) return;
    _syncedPaths = [..._syncedPaths, path];
    _syncedPathTypes = {..._syncedPathTypes, path: isFolder};
    notifyListeners();
    _persistSyncedPaths();
    unawaited(SyncService.reschedule(session, this));
  }

  /// Unsyncs [path] and deletes its already-downloaded local mirror (see
  /// `SyncService.removeLocalSync`) - stopping sync alone would leave
  /// whatever had already been downloaded sitting on disk indefinitely.
  void removeSyncedPath(String path) {
    if (!_syncedPaths.contains(path)) return;
    _syncedPaths = _syncedPaths.where((f) => f != path).toList();
    _syncedPathTypes = {..._syncedPathTypes}..remove(path);
    notifyListeners();
    _persistSyncedPaths();
    unawaited(SyncService.reschedule(session, this));
    unawaited(SyncService.removeLocalSync(session, path));
  }

  void setSyncEverything(bool value) {
    if (_syncEverything == value) return;
    _syncEverything = value;
    notifyListeners();
    final id = session.activeAccountId;
    if (id != null) {
      session.prefsFuture.then(
        (p) => p.setBool(
          session.accountStore.accountPrefKey(id, _prefSyncEverything),
          value,
        ),
      );
    }
    unawaited(SyncService.reschedule(session, this));
  }

  void setSyncOnCellular(bool value) {
    if (_syncOnCellular == value) return;
    _syncOnCellular = value;
    notifyListeners();
    session.prefsFuture.then((p) => p.setBool(_prefSyncOnCellular, value));
    unawaited(SyncService.reschedule(session, this));
  }

  /// In-app conflict resolution (the sync header's "Keep local"/"Use
  /// server" buttons) - see `SyncService.resolveConflict`'s doc comment
  /// for why this shares the exact same native path the notification
  /// actions use.
  Future<void> resolveSyncConflict(
    SyncConflictInfo conflict, {
    required bool useLocal,
  }) {
    return SyncService.resolveConflict(
      session,
      conflict,
      useLocal ? 'local' : 'server',
    );
  }

  /// The local mirror path for [item] if it falls under a synced folder
  /// *and* has actually been synced down already - a pure function of the
  /// remote path once a folder's marked synced (mirrors
  /// `SyncEngine.kt#syncRoot`'s `<externalFilesDir>/sync/<accountId>/...`
  /// layout exactly), so this never needs to read the native sync-state
  /// SharedPreferences from Dart. Callers (Share/Download) use this to
  /// skip a fresh WebDAV fetch when a local copy already exists.
  Future<String?> localSyncedFilePath(NextcloudItem item) async {
    final id = session.activeAccountId;
    if (id == null) return null;
    if (!_isPathInSyncScope(item.path)) return null;
    return SyncService.localSyncedFilePath(id, item.path);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
