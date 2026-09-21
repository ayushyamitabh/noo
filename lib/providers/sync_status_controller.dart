import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import '../models/sync_status.dart';
import '../services/sync_service.dart';
import 'files_controller.dart';
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
///
/// **Keeping synced files current.** Synced folders/files follow the same
/// Files Cache rule (Settings) as folder listings, so nothing needs the
/// "Sync now" button:
///
/// - *Refresh periodically (N min)*: a WorkManager periodic job runs in the
///   background at that interval (Android's floor is 15 min, so shorter
///   values only apply in the foreground), and while the app's open an
///   in-app timer runs a pass every N minutes plus one on resume if it's
///   been longer than that.
/// - *Never cache*: no background schedule; a pass runs each time the app
///   is opened/resumed.
/// - *Refresh manually only*: only pull-to-refresh (any tab's sync header)
///   and "Sync now".
///
/// Every automatic pass is cheap when nothing changed - the native worker
/// checks each synced root's etag (Nextcloud propagates any descendant
/// change up to every ancestor's etag) and skips the full walk if it's
/// unchanged and the local copy is intact. There's no server push: Nextcloud's
/// only push channels (the `notify_push` server app, or FCM via Nextcloud's
/// push proxy) need server-side setup and a persistent connection/registered
/// app identity, so this polls instead.
class SyncStatusController extends ChangeNotifier with WidgetsBindingObserver {
  final SessionController session;
  final FilesController files;

  static const prefSyncedPaths = 'ui_synced_folders';
  static const _prefSyncedPathTypes = 'ui_synced_folder_types';
  static const prefSyncEverything = 'ui_sync_everything';
  static const _prefSyncOnCellular = 'ui_sync_on_cellular';
  static const _prefSyncNotifications = 'ui_sync_notifications';

  List<String> _syncedPaths = [];
  // path -> isFolder, keyed the same as [_syncedPaths] - missing entries
  // (from before this map existed) default to folder, the overwhelmingly
  // common case.
  Map<String, bool> _syncedPathTypes = {};
  bool _syncEverything = false;
  bool _syncOnCellular = false;
  bool _syncNotifications = true;

  bool _isSyncingNow = false;
  Set<String> _syncingFileIds = {};
  Set<String> _syncedFileIds = {};
  List<SyncConflictInfo> _syncConflicts = [];
  StreamSubscription<SyncStatusSnapshot>? _statusSub;

  // Gates addSyncedPaths/removeSyncedPaths (anything that persists
  // _syncedPaths) against running before _onAccountActivated's async
  // prefs load has actually finished - without this, syncing a folder
  // right after opening the app could race the load, overwrite the
  // persisted list with just the one path being added/removed, and
  // silently destroy every previously-synced folder. Deliberately starts
  // *incomplete*, not pre-completed - a mutation is only ever reachable
  // from Files/Offline UI, which requires a completed activation already
  // (Files' own item list depends on the same login event), so there's no
  // real deadlock risk, and starting complete would leave the very first
  // cold-start load completely unprotected (only account *switches*
  // re-arm it, via _onAccountCleared - the bug that actually caused
  // repeated data loss here).
  Completer<void> _accountLoadedGate = Completer<void>();

  // True once _syncedPaths/_syncedPathTypes/_syncEverything have been
  // loaded from prefs for the *current* account - _onAccountActivated can
  // fire more than once per account (e.g. SessionController re-verifying
  // a provisional/offline login once connectivity returns), and a second
  // pass re-reading from storage could clobber an in-memory mutation made
  // between the first load and the second one if its own persist hadn't
  // landed yet. Reset in _onAccountCleared.
  bool _hasLoadedSyncedPathsForAccount = false;

  Timer? _autoSyncTimer;
  bool _foreground = true;
  DateTime? _lastAutoSyncAt;
  CachePolicy? _lastPolicy;
  int? _lastInterval;

  SyncStatusController(this.session, this.files) {
    WidgetsBinding.instance.addObserver(this);
    files.addListener(_onFilesChanged);
    session.addAccountClearedListener(_onAccountCleared);
    // `ready`, not `activated` - this controller's own activation work
    // (loading prefs, calling the native sync channel) is local/native
    // only, so it's safe to run even on a provisional/offline login (see
    // `SessionController.addAccountReadyListener`'s doc comment).
    session.addAccountReadyListener(_onAccountActivated);
    _statusSub = SyncService.statusStream.listen(_applySnapshot);
    _loadGlobalPrefs();
  }

  List<String> get syncedPaths => List.unmodifiable(_syncedPaths);
  bool get syncEverything => _syncEverything;
  bool get syncOnCellular => _syncOnCellular;

  /// Whether background (automatic) sync runs may post progress/summary
  /// notifications. Conflicts and user-initiated "Sync now" always notify.
  bool get syncNotifications => _syncNotifications;

  bool get isSyncingNow => _isSyncingNow;

  bool get _hasSyncScope => _syncEverything || _syncedPaths.isNotEmpty;

  /// How often the background WorkManager job should run, or null for no
  /// background sync at all - only the "refresh periodically" Files Cache
  /// policy schedules one (see the class doc comment).
  int? get backgroundSyncIntervalMinutes =>
      files.cachePolicy == CachePolicy.interval
      ? files.cacheIntervalMinutes
      : null;
  List<SyncConflictInfo> get syncConflicts => List.unmodifiable(_syncConflicts);

  /// How many of [syncedPaths] are folders (as opposed to individual
  /// files) - used by the sync header's expanded summary.
  int get syncedFolderCount =>
      _syncedPaths.where((p) => _syncedPathTypes[p] ?? true).length;

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
    _syncNotifications =
        prefs.getBool(_prefSyncNotifications) ?? _syncNotifications;
    notifyListeners();
  }

  void _onAccountCleared() {
    // Re-armed (not completed) here, not just at construction - an
    // account switch means the *next* activation's load has to finish
    // before any mutation touching _syncedPaths is safe again. Only
    // replace the Completer if nothing's still awaiting the old one -
    // swapping it out from under a pending awaiter would orphan that
    // await forever, since nothing would ever complete the discarded
    // instance.
    if (_accountLoadedGate.isCompleted) _accountLoadedGate = Completer<void>();
    _hasLoadedSyncedPathsForAccount = false;
    _syncedPaths = [];
    _syncedPathTypes = {};
    _syncEverything = false;
    _isSyncingNow = false;
    _syncingFileIds = {};
    _syncedFileIds = {};
    _syncConflicts = [];
    _autoSyncTimer?.cancel();
    _lastAutoSyncAt = null;
    _lastPolicy = null;
    _lastInterval = null;
    notifyListeners();
  }

  Future<void> _onAccountActivated() async {
    final id = session.activeAccountId;
    // Only load _syncedPaths/_syncedPathTypes/_syncEverything once per
    // account, not on every activation - this can fire more than once
    // for the same account (e.g. SessionController re-verifying a
    // provisional/offline login once connectivity returns), and a second
    // read from storage could clobber an in-memory mutation made between
    // the first load and this one if its own persist hadn't landed yet.
    // See _hasLoadedSyncedPathsForAccount's doc comment.
    if (id != null && !_hasLoadedSyncedPathsForAccount) {
      _hasLoadedSyncedPathsForAccount = true;
      // Wrapped so a single bad/mistyped stored pref value can't
      // propagate uncaught out of this method and skip the gate
      // completion below - that would leave every future
      // addSyncedPaths/removeSyncedPaths call awaiting a gate that never
      // completes, hanging forever. See FilesController.
      // _onAccountActivated's identical guard for the real incident this
      // mirrors.
      try {
        final prefs = await session.prefsFuture;
        String k(String base) => session.accountStore.accountPrefKey(id, base);
        final pathsJson = prefs.getString(k(prefSyncedPaths));
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
        _syncEverything = prefs.getBool(k(prefSyncEverything)) ?? false;
        notifyListeners();
      } catch (e) {
        debugPrint('[SyncStatusController] Account-activation prefs restore failed: $e');
      }
    }
    // Only now is it safe for addSyncedPaths/removeSyncedPaths to mutate
    // and persist _syncedPaths - see _accountLoadedGate's doc comment.
    if (!_accountLoadedGate.isCompleted) _accountLoadedGate.complete();
    unawaited(SyncService.getStatus(id).then(_applySnapshot));

    // Scheduling depends on the Files Cache policy, so wait for it to load
    // rather than scheduling from the defaults and correcting a moment later.
    await files.displayPrefsLoaded;
    _lastPolicy = files.cachePolicy;
    _lastInterval = files.cacheIntervalMinutes;
    unawaited(SyncService.reschedule(session, this));
    _restartAutoSyncTimer();
    if (_dueForAutoSync) unawaited(_autoSync());
  }

  // ---- Automatic sync (see the class doc comment) ----

  void _onFilesChanged() {
    // FilesController notifies on every navigation - only the cache rule
    // itself matters here.
    if (_lastPolicy == null) return; // account not activated yet
    final policy = files.cachePolicy;
    final interval = files.cacheIntervalMinutes;
    if (policy == _lastPolicy && interval == _lastInterval) return;
    _lastPolicy = policy;
    _lastInterval = interval;
    unawaited(SyncService.reschedule(session, this));
    _restartAutoSyncTimer();
  }

  /// Whether an app-open/resume should kick off a pass under the current
  /// cache rule.
  bool get _dueForAutoSync {
    switch (files.cachePolicy) {
      case CachePolicy.never:
        return true;
      case CachePolicy.manual:
        return false;
      case CachePolicy.interval:
        final last = _lastAutoSyncAt;
        return last == null ||
            DateTime.now().difference(last) >=
                Duration(minutes: files.cacheIntervalMinutes);
    }
  }

  void _restartAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (!_foreground ||
        !_hasSyncScope ||
        files.cachePolicy != CachePolicy.interval) {
      return;
    }
    _autoSyncTimer = Timer.periodic(
      Duration(minutes: files.cacheIntervalMinutes),
      (_) => unawaited(_autoSync()),
    );
  }

  /// A quiet, network-setting-respecting pass - see [SyncService.syncNow].
  Future<void> _autoSync() async {
    if (!_canSyncQuietly) return;
    _lastAutoSyncAt = DateTime.now();
    try {
      await SyncService.syncNow(
        session,
        this,
        force: false,
        respectNetworkSetting: true,
      );
    } catch (e) {
      debugPrint('[SyncStatusController] Automatic sync failed: $e');
    }
  }

  /// A deliberate pull-to-refresh (any tab's sync header): check for server
  /// changes now, regardless of the cache rule or the Wi-Fi-only setting.
  Future<void> syncOnPull() async {
    if (!_canSyncQuietly) return;
    try {
      await SyncService.syncNow(session, this, force: false);
    } catch (e) {
      debugPrint('[SyncStatusController] Pull-triggered sync failed: $e');
    }
  }

  bool get _canSyncQuietly =>
      _hasSyncScope &&
      !_isSyncingNow &&
      session.isLoggedIn &&
      !session.connectivity.isOffline;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _restartAutoSyncTimer();
      if (_dueForAutoSync) unawaited(_autoSync());
    } else if (state == AppLifecycleState.paused) {
      // The in-app timer only runs while foregrounded; WorkManager owns the
      // background schedule.
      _foreground = false;
      _autoSyncTimer?.cancel();
    }
  }

  void _applySnapshot(SyncStatusSnapshot snapshot) {
    // A null accountId is the bus's initial "nothing has synced in this
    // process yet" emission on subscribe - applying it would wipe the
    // synced-file ids seeded by getStatus(accountId).
    if (snapshot.accountId == null ||
        snapshot.accountId != session.activeAccountId) {
      return;
    }
    _isSyncingNow = snapshot.syncing;
    _syncingFileIds = snapshot.syncingFileIds;
    _syncedFileIds = snapshot.syncedFileIds;
    _syncConflicts = snapshot.conflicts;
    notifyListeners();

    // A synced file/folder deleted on the server has nothing left to sync -
    // drop it from the synced list rather than leaving a dead entry.
    final gone = snapshot.missingRoots.where(_syncedPaths.contains).toList();
    if (gone.isNotEmpty) unawaited(removeSyncedPaths(gone));
  }

  void _persistSyncedPaths() {
    final id = session.activeAccountId;
    if (id == null) return;
    session.prefsFuture.then((p) {
      p.setString(
        session.accountStore.accountPrefKey(id, prefSyncedPaths),
        jsonEncode(_syncedPaths),
      );
      p.setString(
        session.accountStore.accountPrefKey(id, _prefSyncedPathTypes),
        jsonEncode(_syncedPathTypes),
      );
    });
  }

  bool isPathSynced(String path) => _syncedPaths.contains(path);

  Future<void> addSyncedPath(String path, {required bool isFolder}) {
    return addSyncedPaths({path: isFolder});
  }

  /// Adds every path in [entries] (path -> isFolder) to sync in one go -
  /// unlike calling [addSyncedPath] once per item in a loop, this touches
  /// `_syncedPaths`/persists/reschedules/triggers an immediate sync
  /// exactly once no matter how many paths are being added. Looping
  /// `addSyncedPath` from a multi-select "Sync to device" was the actual
  /// bug behind only the first selected item ever actually syncing: each
  /// call fired its own `SyncService.syncNow`, and WorkManager's
  /// `enqueueUniqueWork(..., ExistingWorkPolicy.REPLACE, ...)` policy
  /// meant each later call cancelled the previous item's still-in-flight
  /// sync pass (and could stomp on its `SyncEngine.saveState`, which
  /// overwrites the whole state map rather than merging) instead of
  /// letting it finish.
  Future<void> addSyncedPaths(Map<String, bool> entries) async {
    // Must not mutate/persist _syncedPaths before the per-account load
    // has actually populated it - see _accountLoadedGate's doc comment.
    await _accountLoadedGate.future;
    var changed = false;
    entries.forEach((path, isFolder) {
      if (_syncedPaths.contains(path)) return;
      _syncedPaths = [..._syncedPaths, path];
      _syncedPathTypes = {..._syncedPathTypes, path: isFolder};
      changed = true;
    });
    if (!changed) return;
    notifyListeners();
    _persistSyncedPaths();
    unawaited(SyncService.reschedule(session, this));
    _restartAutoSyncTimer();
    // `reschedule` alone only lines up the *periodic* job, which can be up
    // to an hour away from its first run - without an immediate one-off
    // sync here too, newly-added items would just sit unsynced until the
    // user thought to trigger one manually (e.g. pulling to refresh on
    // the Offline tab).
    unawaited(_syncNowSilently());
  }

  /// Unsyncs [path] and deletes its already-downloaded local mirror (see
  /// `SyncService.removeLocalSync`) - stopping sync alone would leave
  /// whatever had already been downloaded sitting on disk indefinitely.
  Future<void> removeSyncedPath(String path) {
    return removeSyncedPaths([path]);
  }

  /// Batched counterpart to [removeSyncedPath] - see [addSyncedPaths]'s
  /// doc comment for why a multi-item loop of individual calls is unsafe
  /// for `reschedule`/native side effects, even though removal itself
  /// (unlike adding) doesn't trigger a one-off sync to race.
  Future<void> removeSyncedPaths(List<String> paths) async {
    await _accountLoadedGate.future;
    var changed = false;
    for (final path in paths) {
      if (!_syncedPaths.contains(path)) continue;
      _syncedPaths = _syncedPaths.where((f) => f != path).toList();
      _syncedPathTypes = {..._syncedPathTypes}..remove(path);
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    _persistSyncedPaths();
    unawaited(SyncService.reschedule(session, this));
    _restartAutoSyncTimer();
    for (final path in paths) {
      unawaited(SyncService.removeLocalSync(session, path));
    }
  }

  void setSyncEverything(bool value) {
    if (_syncEverything == value) return;
    _syncEverything = value;
    notifyListeners();
    final id = session.activeAccountId;
    if (id != null) {
      session.prefsFuture.then(
        (p) => p.setBool(
          session.accountStore.accountPrefKey(id, prefSyncEverything),
          value,
        ),
      );
    }
    unawaited(SyncService.reschedule(session, this));
    _restartAutoSyncTimer();
    if (value) unawaited(_syncNowSilently());
  }

  void setSyncNotifications(bool value) {
    if (_syncNotifications == value) return;
    _syncNotifications = value;
    notifyListeners();
    session.prefsFuture.then((p) => p.setBool(_prefSyncNotifications, value));
    // Baked into each periodic job's input, so the jobs have to be
    // re-enqueued for the change to reach background runs.
    unawaited(SyncService.reschedule(session, this));
  }

  void setSyncOnCellular(bool value) {
    if (_syncOnCellular == value) return;
    _syncOnCellular = value;
    notifyListeners();
    session.prefsFuture.then((p) => p.setBool(_prefSyncOnCellular, value));
    unawaited(SyncService.reschedule(session, this));
  }

  /// Fire-and-forget immediate sync, swallowing errors - called right
  /// after turning sync on for something (see [addSyncedPath]/
  /// [setSyncEverything]) so it actually starts syncing now instead of
  /// only ever running on the next periodic pass or a manual "Sync now".
  Future<void> _syncNowSilently() async {
    try {
      await SyncService.syncNow(session, this);
    } catch (e) {
      debugPrint('[SyncStatusController] Immediate sync failed: $e');
    }
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
    WidgetsBinding.instance.removeObserver(this);
    files.removeListener(_onFilesChanged);
    _autoSyncTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
