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
  static const prefSyncExternal = 'ui_sync_external';
  static const _prefSyncOnCellular = 'ui_sync_on_cellular';
  static const _prefSyncNotifications = 'ui_sync_notifications';
  static const _prefAutoDelete = 'ui_sync_auto_delete';

  List<String> _syncedPaths = [];
  // path -> isFolder, keyed the same as [_syncedPaths] - missing entries
  // (from before this map existed) default to folder, the overwhelmingly
  // common case.
  Map<String, bool> _syncedPathTypes = {};
  bool _syncEverything = false;
  // Whether "Sync everything" also mirrors external storage (it doesn't by
  // default - cloud files only). Folders picked by hand always sync.
  bool _syncExternal = false;
  bool _isCancellingSync = false;
  StorageShortfall? _storageShortfall;
  // The stop native last reported and the app already dealt with (dropped
  // the item / the user cancelled) - native keeps reporting it until the next
  // run starts, so it's remembered here to not show it again.
  int? _ackedNeeded;
  int? _ackedAvailable;
  int _shortfallSerial = 0;
  // What the run in progress is syncing *for the first time* - paths added
  // since the last pass finished, and "Sync everything" if it was just turned
  // on. Cancelling drops exactly these (a cancelled refresh of something
  // already synced just stops), so a cancelled item can't start again on the
  // next refresh. Cleared whenever a pass finishes on its own.
  final Set<String> _pendingPaths = {};
  bool _everythingPending = false;
  bool _syncOnCellular = false;
  bool _syncNotifications = true;
  // Whether files are deleted from the device once they stop being synced
  // (a path removed, "Sync everything" / external storage turned off). Off
  // keeps them as leftovers, listed under "On this device" to remove by hand.
  bool _autoDeleteRemoved = true;

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
  bool get syncExternal => _syncExternal;

  /// A cancel was requested and the run hasn't wound down yet.
  bool get isCancellingSync => _isCancellingSync;

  /// Set while the last pass's "not enough space" stop is unresolved;
  /// cleared when the next pass starts.
  StorageShortfall? get storageShortfall => _storageShortfall;
  bool get syncOnCellular => _syncOnCellular;

  /// Whether background (automatic) sync runs may post progress/summary
  /// notifications. Conflicts and user-initiated "Sync now" always notify.
  bool get syncNotifications => _syncNotifications;

  /// See [_autoDeleteRemoved].
  bool get autoDeleteRemoved => _autoDeleteRemoved;

  bool get isSyncingNow => _isSyncingNow;

  /// How many files native sync currently records as synced - changes as a
  /// long run progresses, so lists of what's on the device know to re-read.
  int get syncedFileCount => _syncedFileIds.length;

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
  ///
  /// "Sync everything" is cloud files only unless [syncExternal] is on, so
  /// [externalMountRoot] (an external-storage mount's root folder) isn't
  /// covered by it otherwise - only by an explicit synced folder.
  bool _isPathInSyncScope(String path, {bool externalMountRoot = false}) {
    if (_syncEverything && (_syncExternal || !externalMountRoot)) return true;
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

  /// Whether [path] is kept on the device by sync - itself picked, inside a
  /// picked folder, or covered by "Sync everything".
  bool isPathCoveredBySync(String path) => _isPathInSyncScope(path);

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
      if (!_isPathInSyncScope(
        item.path,
        externalMountRoot: item.isExternalStorage,
      )) {
        return SyncItemStatus.none;
      }
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
    _autoDeleteRemoved = prefs.getBool(_prefAutoDelete) ?? _autoDeleteRemoved;
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
    _syncExternal = false;
    _isCancellingSync = false;
    _storageShortfall = null;
    _pendingPaths.clear();
    _everythingPending = false;
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
            debugPrint(
              '[SyncStatusController] Synced paths restore failed: $e',
            );
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
            debugPrint(
              '[SyncStatusController] Synced path types restore failed: $e',
            );
            _syncedPathTypes = {};
          }
        } else {
          _syncedPathTypes = {};
        }
        _syncEverything = prefs.getBool(k(prefSyncEverything)) ?? false;
        _syncExternal = prefs.getBool(k(prefSyncExternal)) ?? false;
        notifyListeners();
      } catch (e) {
        debugPrint(
          '[SyncStatusController] Account-activation prefs restore failed: $e',
        );
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
    final needed = snapshot.storageNeededBytes;
    final available = snapshot.storageAvailableBytes;
    if (needed == null || available == null) {
      _storageShortfall = null;
      _ackedNeeded = _ackedAvailable = null;
    } else if (needed == _ackedNeeded && available == _ackedAvailable) {
      _storageShortfall = null;
    } else if (_storageShortfall?.neededBytes != needed ||
        _storageShortfall?.availableBytes != available) {
      // Not enough room: behave exactly like a cancel - what this pass was
      // syncing for the first time is dropped and its partial files removed,
      // so it isn't retried on every refresh just to fail again.
      final dropPaths = _pendingPaths.where(_syncedPaths.contains).toList();
      final dropEverything = _everythingPending && _syncEverything;
      _pendingPaths.clear();
      _everythingPending = false;
      final drops = dropPaths.isNotEmpty || dropEverything;
      _storageShortfall = StorageShortfall(
        neededBytes: needed,
        availableBytes: available,
        serial: ++_shortfallSerial,
        removedFromSync: drops,
      );
      if (drops) {
        unawaited(
          _dropPending(
            dropPaths,
            dropEverything,
          ).then((_) => _clearShortfall()),
        );
      }
    }
    final wasSyncing = _isSyncingNow;
    _isSyncingNow = snapshot.syncing;
    if (wasSyncing && !snapshot.syncing && !_isCancellingSync) {
      // The pass finished by itself: everything it was syncing is done.
      _pendingPaths.clear();
      _everythingPending = false;
    }
    if (!snapshot.syncing) _isCancellingSync = false;
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
      _pendingPaths.add(path);
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
  ///
  /// [deleteFiles] says whether their local copies are deleted too; it
  /// defaults to the "Delete files when removed from sync" setting. Either way
  /// native stops tracking them, so their "synced" badges clear.
  Future<void> removeSyncedPaths(
    List<String> paths, {
    bool? deleteFiles,
  }) async {
    final delete = deleteFiles ?? _autoDeleteRemoved;
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
    // The native side forgets these files' synced state without announcing
    // it, so fetch a fresh snapshot once it's done - otherwise their "synced"
    // badges would stay until some later sync event happened to refresh them.
    unawaited(
      Future.wait([
        for (final path in paths)
          SyncService.removeLocalSync(session, path, deleteFiles: delete),
      ]).then((_) => _refreshStatus()),
    );
  }

  Future<void> _refreshStatus() async {
    final id = session.activeAccountId;
    if (id == null) return;
    try {
      _applySnapshot(await SyncService.getStatus(id));
    } catch (e) {
      debugPrint('[SyncStatusController] Status refresh failed: $e');
    }
  }

  void setSyncEverything(bool value) {
    if (_syncEverything == value) return;
    _syncEverything = value;
    notifyListeners();
    _persistAccountBool(prefSyncEverything, value);
    _everythingPending = value;
    if (!value) {
      // Whatever "everything" run is in flight must stop now - left alone it
      // keeps downloading into a mirror nothing is configured to own, which
      // is how files ended up on the device that couldn't be un-synced.
      unawaited(_cancelRunSilently().then((_) => _handleLeftovers()));
    }
    unawaited(SyncService.reschedule(session, this));
    _restartAutoSyncTimer();
    // On: start mirroring. Off: only a hand-picked path left to refresh.
    if (_hasSyncScope) unawaited(_syncNowSilently());
  }

  /// Whether "Sync everything" also mirrors external storage. Changing it
  /// restarts a running "everything" pass so it picks the new scope up.
  void setSyncExternal(bool value) {
    if (_syncExternal == value) return;
    _syncExternal = value;
    notifyListeners();
    _persistAccountBool(prefSyncExternal, value);
    if (!_syncEverything) return;
    unawaited(
      _cancelRunSilently().then((_) async {
        if (!value) await _handleExternalLeftovers();
      }),
    );
    unawaited(SyncService.reschedule(session, this));
    unawaited(_syncNowSilently());
  }

  /// "Sync everything" was turned off: what it put on the device that no
  /// picked path keeps is no longer synced. Deleted, or (setting off) just
  /// forgotten so it stays as a leftover.
  Future<void> _handleLeftovers() async {
    await _waitUntilIdle();
    try {
      for (final item in await deviceOnlyItems()) {
        await SyncService.removeLocalSync(
          session,
          item.path,
          deleteFiles: _autoDeleteRemoved,
        );
      }
      await _refreshStatus();
    } catch (e) {
      debugPrint('[SyncStatusController] Leftover cleanup failed: $e');
    }
  }

  /// "Sync external storage" was turned off while syncing everything: the
  /// external mounts' copies stop being synced - same treatment as above,
  /// except for any mount a picked path still covers.
  Future<void> _handleExternalLeftovers() async {
    await _waitUntilIdle();
    try {
      for (final root in files.externalMountRoots) {
        if (_syncedPaths.any((p) => root == p || root.startsWith('$p/'))) {
          continue;
        }
        await SyncService.removeLocalSync(
          session,
          root,
          deleteFiles: _autoDeleteRemoved,
        );
      }
      await _refreshStatus();
    } catch (e) {
      debugPrint('[SyncStatusController] External cleanup failed: $e');
    }
  }

  void _persistAccountBool(String key, bool value) {
    final id = session.activeAccountId;
    if (id == null) return;
    session.prefsFuture.then(
      (p) => p.setBool(session.accountStore.accountPrefKey(id, key), value),
    );
  }

  /// The "Cancel" button while "Syncing...": stops the run in progress and
  /// drops whatever it was syncing for the first time - those paths leave the
  /// synced list (so the next refresh doesn't start them again) and their
  /// partly downloaded files are deleted. A cancelled refresh of something
  /// that was already synced just stops; nothing is removed. Returns how many
  /// items were dropped.
  Future<int> cancelSync() async {
    if (!_isSyncingNow || _isCancellingSync) return 0;
    _isCancellingSync = true;
    notifyListeners();
    final dropPaths = _pendingPaths.where(_syncedPaths.contains).toList();
    final dropEverything = _everythingPending && _syncEverything;
    _pendingPaths.clear();
    _everythingPending = false;
    var dropped = 0;
    try {
      await SyncService.cancelSync(session);
      dropped = await _dropPending(dropPaths, dropEverything);
      // Cancelled: whatever "not enough storage" stop came before is moot.
      _clearShortfall();
    } catch (e) {
      debugPrint('[SyncStatusController] Cancel failed: $e');
    } finally {
      _isCancellingSync = false;
      notifyListeners();
    }
    return dropped;
  }

  /// The "not enough storage" state is dealt with - hides it (until native
  /// reports a different one) instead of leaving it on screen.
  void _clearShortfall() {
    final shortfall = _storageShortfall;
    if (shortfall == null) return;
    _ackedNeeded = shortfall.neededBytes;
    _ackedAvailable = shortfall.availableBytes;
    _storageShortfall = null;
    notifyListeners();
  }

  /// Drops what a cancelled (or storage-starved) pass was syncing for the
  /// first time: [paths] leave the synced list and their partly downloaded
  /// files are deleted (native waits for the stopped run to finish saving),
  /// and - if [everything] - "Sync everything" is turned off and what it put
  /// on the device that no picked path keeps is removed. Returns how many
  /// items were dropped.
  Future<int> _dropPending(List<String> paths, bool everything) async {
    var dropped = 0;
    try {
      if (paths.isNotEmpty) {
        await removeSyncedPaths(paths, deleteFiles: true);
        dropped += paths.length;
      }
      if (everything) {
        setSyncEverything(false);
        await _waitUntilIdle();
        final leftovers = await deviceOnlyItems();
        for (final item in leftovers) {
          await SyncService.removeLocalSync(session, item.path);
        }
        await _refreshStatus();
        dropped += 1;
      }
    } catch (e) {
      debugPrint('[SyncStatusController] Dropping pending sync failed: $e');
    }
    return dropped;
  }

  /// Completes once no sync run is in progress (or after a timeout).
  Future<void> _waitUntilIdle() async {
    if (!_isSyncingNow) return;
    final idle = Completer<void>();
    void check() {
      if (!_isSyncingNow && !idle.isCompleted) idle.complete();
    }

    addListener(check);
    try {
      await idle.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Give up waiting; removal below is still safe (native serialises it).
    } finally {
      removeListener(check);
    }
  }

  Future<void> _cancelRunSilently() async {
    try {
      await SyncService.cancelSync(session);
    } catch (e) {
      debugPrint('[SyncStatusController] Cancel failed: $e');
    }
  }

  /// Files and folders in the on-device mirror that nothing is configured to
  /// sync - see [DeviceOnlyItem]; while "Sync everything" is on, the
  /// mirror's top level instead (it owns the whole mirror).
  Future<List<DeviceOnlyItem>> deviceOnlyItems() async {
    final id = session.activeAccountId;
    if (id == null) return const [];
    // "Sync everything" owns the whole mirror: show what it has put there.
    if (_syncEverything) return SyncService.mirrorTopLevel(id);
    return SyncService.deviceOnlyItems(id, _syncedPaths);
  }

  /// Deletes [path]'s copy from the device (and its recorded sync state)
  /// without it being - or needing to be - a configured synced path.
  Future<void> removeDeviceCopy(String path) async {
    await SyncService.removeLocalSync(session, path);
    await _refreshStatus();
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

  void setAutoDeleteRemoved(bool value) {
    if (_autoDeleteRemoved == value) return;
    _autoDeleteRemoved = value;
    notifyListeners();
    session.prefsFuture.then((p) => p.setBool(_prefAutoDelete, value));
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
