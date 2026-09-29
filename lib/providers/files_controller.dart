import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nextcloud_item.dart';
import 'folder_browser.dart';
import 'session_controller.dart';

enum FileSortField { name, dateCreated, dateModified, size }

/// Which storage a listing shows — always exactly one, like the list/grid
/// view toggle, not an optional filter. Shared across Files/Photos/
/// Favorites (see [applyCommonFilters]'s doc comment).
enum StorageScope { cloud, external }

/// The Files tab's files/folders/both filter — independent of and applied
/// after [StorageScope]/favorites/hidden filtering.
enum FilesTypeFilter { all, filesOnly, foldersOnly }

/// How aggressively the Files tab's folder listings (not thumbnails/file
/// content - just the list of names/sizes/dates) are reused across
/// navigation instead of refetched from the server every time.
enum CachePolicy {
  /// Every navigation refetches. Synced files are checked each time the app
  /// opens (and on pull-to-refresh), but not on a background schedule.
  never,

  /// A listing is reused until it's older than [FilesController.
  /// cacheIntervalMinutes]; a timer also proactively refreshes the current
  /// folder on that same interval while the app is in the foreground.
  interval,

  /// A listing is reused indefinitely until the user pulls to refresh.
  /// Synced files likewise only update on pull-to-refresh / "Sync now".
  manual,
}

/// New accounts (and anyone who's never touched the setting) refresh
/// periodically - the Files Cache rule also drives how often synced
/// folders/files are brought in line with the server, see
/// `SyncStatusController`.
const defaultCachePolicy = CachePolicy.interval;
const defaultCacheIntervalMinutes = 15;

/// One cached folder listing and when it was fetched.
class _CachedDirectory {
  final List<NextcloudItem> items;
  final DateTime fetchedAt;

  const _CachedDirectory(this.items, this.fetchedAt);
}

/// The Files tab: current folder/browsing state, display prefs (grid/list,
/// hidden, type filter, storage scope, sort), the directory-listing cache,
/// and - piggybacked onto the same fetch cycle as the original single
/// provider did - account quota and the Activity tab's feed (neither is
/// really "Files" data, but both were always fetched alongside the current
/// folder's listing, not independently; preserved here as-is rather than
/// invented a home for them, since untangling that wasn't asked for). Also
/// the shared [storageScope]/[applyCommonFilters]/[applyFilesDisplayPrefs]
/// logic Photos/Favorites both reuse - see their own controllers' doc
/// comments for why they depend on this one.
///
/// Split out of the former single `ServerProvider` god object.
class FilesController extends ChangeNotifier
    with WidgetsBindingObserver
    implements FolderBrowser {
  final SessionController session;

  static const _prefGridView = 'ui_grid_view';
  static const _prefStorageScope = 'ui_storage_scope';
  static const _prefFilesTypeFilter = 'ui_files_type_filter';
  static const _prefShowHiddenFiles = 'ui_show_hidden';
  static const _prefFolderSort = 'ui_folder_sort';
  static const prefCachePolicy = 'ui_cache_policy';
  static const prefCacheIntervalMinutes = 'ui_cache_interval_minutes';

  String _currentFolderPath = '/';
  List<String> _pathStack = ['/'];

  bool _isGridView = false;
  StorageScope _storageScope = StorageScope.cloud;
  FilesTypeFilter _filesTypeFilter = FilesTypeFilter.all;
  bool _showHiddenFiles = false;

  final Map<String, FileSortField> _folderSortField = {};
  final Map<String, bool> _folderSortAscending = {};

  CachePolicy _cachePolicy = defaultCachePolicy;
  int _cacheIntervalMinutes = defaultCacheIntervalMinutes;
  final Map<String, _CachedDirectory> _directoryCache = {};
  Timer? _cacheRefreshTimer;

  // Auto-retry of a failed (not in-place) load that looks like a network
  // hiccup - see [_scheduleNetworkRetry].
  Timer? _retryTimer;
  int _retryAttempt = 0;

  List<NextcloudItem> _items = [];
  NextcloudUserQuota? _quota;
  List<NextcloudActivity> _activities = [];
  bool _isLoading = false;
  String? _errorMessage;

  FilesController(this.session) {
    WidgetsBinding.instance.addObserver(this);
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
    session.addAccountReadyListener(_restoreDisplayPrefs);
  }

  // Getters
  @override
  String get currentFolderPath => _currentFolderPath;
  @override
  List<String> get pathStack => _pathStack;
  bool get isGridView => _isGridView;
  StorageScope get storageScope => _storageScope;
  FilesTypeFilter get filesTypeFilter => _filesTypeFilter;
  bool get showHiddenFiles => _showHiddenFiles;
  FileSortField get filesSortField => sortFieldFor(_currentFolderPath);
  bool get filesSortAscending => sortAscendingFor(_currentFolderPath);

  /// Per-folder sort prefs keyed by remote path - also what the Offline tab
  /// reads for the same path in the local mirror, so a folder sorts the
  /// same in both places.
  FileSortField sortFieldFor(String path) =>
      _folderSortField[path] ?? FileSortField.name;
  bool sortAscendingFor(String path) => _folderSortAscending[path] ?? true;
  CachePolicy get cachePolicy => _cachePolicy;
  int get cacheIntervalMinutes => _cacheIntervalMinutes;
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;
  NextcloudUserQuota? get quota => _quota;
  List<NextcloudActivity> get activities => _activities;

  @override
  List<NextcloudItem> get items => applyFilesDisplayPrefs(_items);

  int _compareItems(NextcloudItem a, NextcloudItem b, FileSortField field) {
    switch (field) {
      case FileSortField.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case FileSortField.dateCreated:
        return a.dateCreated.compareTo(b.dateCreated);
      case FileSortField.dateModified:
        return a.lastModified.compareTo(b.lastModified);
      case FileSortField.size:
        return a.size.compareTo(b.size);
    }
  }

  /// True if [item] or any ancestor folder in its path is a dotfile/dotfolder.
  bool _isHiddenItem(NextcloudItem item) {
    return item.path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .any((segment) => segment.startsWith('.'));
  }

  /// Applies the shared favorites-only/hidden-files/storage-scope toggles -
  /// shared by Files' own [items], Photos' `photoItems` (its own favorites-
  /// only/hidden toggles, but [storageScope] here), and Favorites'
  /// `favoriteItems` (via [applyFilesDisplayPrefs]).
  List<NextcloudItem> applyCommonFilters(
    List<NextcloudItem> source, {
    required bool showFavoritesOnly,
    required bool showHidden,
    bool applyStorageScope = true,
  }) {
    var filtered = source;
    if (showFavoritesOnly) {
      filtered = filtered.where((item) => item.isFavorite).toList();
    }
    if (!showHidden) {
      filtered = filtered.where((item) => !_isHiddenItem(item)).toList();
    }
    if (applyStorageScope) {
      filtered = filtered
          .where(
            (item) => _storageScope == StorageScope.external
                ? item.isExternalStorage
                : !item.isExternalStorage,
          )
          .toList();
    }
    return filtered;
  }

  /// Applies the Files tab's current sort/filter display prefs (hidden,
  /// type filter, storage scope, sort field/direction) to an arbitrary raw
  /// item list - factored out of the [items] getter so both the Favorites
  /// tab and the Move/Copy destination picker (which fetches its own
  /// listings via [fetchFolderListing] rather than reading [items] itself)
  /// can render with the exact same controls/behavior as the Files tab
  /// without duplicating this logic.
  ///
  /// [folderPath] picks which folder's sort prefs apply (default: the
  /// Files tab's current folder). [applyStorageScope] is off for the
  /// Offline tab, whose local mirror has no cloud/external distinction.
  List<NextcloudItem> applyFilesDisplayPrefs(
    List<NextcloudItem> rawItems, {
    String? folderPath,
    bool applyStorageScope = true,
  }) {
    var filtered = applyCommonFilters(
      rawItems,
      // Files itself doesn't filter by favorite - that's the dedicated
      // Favorites tab's job.
      showFavoritesOnly: false,
      showHidden: _showHiddenFiles,
      applyStorageScope: applyStorageScope,
    );
    switch (_filesTypeFilter) {
      case FilesTypeFilter.all:
        break;
      case FilesTypeFilter.filesOnly:
        filtered = filtered.where((i) => !i.isFolder).toList();
      case FilesTypeFilter.foldersOnly:
        filtered = filtered.where((i) => i.isFolder).toList();
    }

    final path = folderPath ?? _currentFolderPath;
    final field = sortFieldFor(path);
    final folders = filtered.where((i) => i.isFolder).toList()
      ..sort((a, b) => _compareItems(a, b, field));
    final files = filtered.where((i) => !i.isFolder).toList()
      ..sort((a, b) => _compareItems(a, b, field));
    return sortAscendingFor(path)
        ? [...folders, ...files]
        : [...folders.reversed, ...files.reversed];
  }

  void _onAccountCleared() {
    _prefsRestore = null;
    _retryTimer?.cancel();
    _retryAttempt = 0;
    _cacheRefreshTimer?.cancel();
    _directoryCache.clear();
    _folderSortField.clear();
    _folderSortAscending.clear();
    _items = [];
    _quota = null;
    _activities = [];
    _currentFolderPath = '/';
    _pathStack = ['/'];
    _isGridView = false;
    _storageScope = StorageScope.cloud;
    _filesTypeFilter = FilesTypeFilter.all;
    _showHiddenFiles = false;
    _cachePolicy = defaultCachePolicy;
    _cacheIntervalMinutes = defaultCacheIntervalMinutes;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  // Memoized per account (reset in _onAccountCleared) so the ready-event
  // and activated-event paths below share one restore instead of racing
  // two reads of the same prefs.
  Future<void>? _prefsRestore;

  /// Loads this account's display prefs (grid/list, hidden, type filter,
  /// sort, cache policy) - hooked to `addAccountReadyListener` as well as
  /// activation so the Offline tab, which reads these same prefs, respects
  /// them even on a provisional/offline login where activation never fires.
  Future<void> _restoreDisplayPrefs() =>
      _prefsRestore ??= _doRestoreDisplayPrefs();

  /// Completes once this account's cache policy/display prefs have been
  /// loaded from storage - lets `SyncStatusController` schedule background
  /// sync from the user's real policy instead of the defaults.
  Future<void> get displayPrefsLoaded => _restoreDisplayPrefs();

  Future<void> _doRestoreDisplayPrefs() async {
    final id = session.activeAccountId;
    if (id != null) {
      // The whole prefs-restore block is wrapped, not just the JSON
      // decode below - a single bad/mistyped stored value here (an
      // unguarded `prefs.getBool`/`getString`/`getInt` throws if the
      // key holds a different runtime type than requested) would
      // otherwise propagate uncaught out of this method entirely,
      // silently skipping `refreshData()` below and leaving the Files
      // tab permanently empty on this activation with no error surfaced
      // anywhere - exactly what happened before this was guarded.
      try {
        final prefs = await session.prefsFuture;
        String k(String base) => session.accountStore.accountPrefKey(id, base);

        _isGridView = prefs.getBool(k(_prefGridView)) ?? false;
        final storageScopeName = prefs.getString(k(_prefStorageScope));
        _storageScope = StorageScope.values.firstWhere(
          (s) => s.name == storageScopeName,
          orElse: () => StorageScope.cloud,
        );
        final filesTypeFilterName = prefs.getString(k(_prefFilesTypeFilter));
        _filesTypeFilter = FilesTypeFilter.values.firstWhere(
          (f) => f.name == filesTypeFilterName,
          orElse: () => FilesTypeFilter.all,
        );
        _showHiddenFiles = prefs.getBool(k(_prefShowHiddenFiles)) ?? false;

        final folderSortJson = prefs.getString(k(_prefFolderSort));
        if (folderSortJson != null) {
          try {
            final decoded = jsonDecode(folderSortJson) as Map<String, dynamic>;
            for (final entry in decoded.entries) {
              final value = entry.value as Map<String, dynamic>;
              final fieldName = value['field'] as String?;
              if (fieldName != null) {
                _folderSortField[entry.key] = FileSortField.values.firstWhere(
                  (f) => f.name == fieldName,
                  orElse: () => FileSortField.name,
                );
              }
              final ascending = value['ascending'] as bool?;
              if (ascending != null) {
                _folderSortAscending[entry.key] = ascending;
              }
            }
          } catch (e) {
            debugPrint('[FilesController] Folder sort restore failed: $e');
          }
        }

        final cachePolicyName = prefs.getString(k(prefCachePolicy));
        _cachePolicy = CachePolicy.values.firstWhere(
          (c) => c.name == cachePolicyName,
          orElse: () => defaultCachePolicy,
        );
        _cacheIntervalMinutes =
            prefs.getInt(k(prefCacheIntervalMinutes)) ??
            defaultCacheIntervalMinutes;
        notifyListeners();
      } catch (e) {
        debugPrint(
          '[FilesController] Account-activation prefs restore failed: $e',
        );
      }
    }
  }

  Future<void> _onAccountActivated() async {
    await _restoreDisplayPrefs();
    _startCacheRefreshTimerIfNeeded();
    await refreshData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only relevant under CachePolicy.interval.
    if (state == AppLifecycleState.resumed) {
      _startCacheRefreshTimerIfNeeded();
    } else if (state == AppLifecycleState.paused) {
      _cacheRefreshTimer?.cancel();
    }
  }

  void _startCacheRefreshTimerIfNeeded() {
    _cacheRefreshTimer?.cancel();
    if (_cachePolicy != CachePolicy.interval || !session.isLoggedIn) return;
    _cacheRefreshTimer = Timer.periodic(
      Duration(minutes: _cacheIntervalMinutes),
      (_) => refreshData(),
    );
  }

  bool _isCacheFresh(String path) {
    if (_cachePolicy == CachePolicy.never) return false;
    final cached = _directoryCache[path];
    if (cached == null) return false;
    if (_cachePolicy == CachePolicy.manual) return true;
    return DateTime.now().difference(cached.fetchedAt) <
        Duration(minutes: _cacheIntervalMinutes);
  }

  Future<void> refreshData() async {
    final service = session.service;
    if (!session.isLoggedIn || service == null) {
      debugPrint(
        '[FilesController] refreshData skipped: isLoggedIn=${session.isLoggedIn}, service=${service != null}',
      );
      return;
    }
    // Captured so a response landing after an account switch mid-flight
    // can recognize it's for an account the user has already left and
    // discard itself instead of overwriting the new account's content.
    final gen = session.sessionGeneration;
    _retryTimer?.cancel();

    // Refreshing a folder that's already on screen (pull-to-refresh, the
    // periodic cache refresh) swaps the listing in place once the server
    // answers - blanking the list to a spinner first made every refresh
    // look like the files vanished and reappeared. The spinner is only for
    // when there's nothing to show yet (first load, just navigated into a
    // new folder - see [_navigateTo], which clears the outgoing folder's
    // items - or retrying after an error).
    final inPlace = _items.isNotEmpty && _errorMessage == null;
    if (!inPlace) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    debugPrint(
      '[FilesController] Refreshing data for path: $_currentFolderPath',
    );

    try {
      final items = await service.fetchDirectory(_currentFolderPath);
      if (gen != session.sessionGeneration) return;
      _items = items;
      _directoryCache[_currentFolderPath] = _CachedDirectory(
        _items,
        DateTime.now(),
      );
      // Show the new listing now rather than after the quota/activity
      // fetches below - they're unrelated to what the list displays.
      _isLoading = false;
      _retryAttempt = 0;
      notifyListeners();
      debugPrint(
        '[FilesController] Loaded ${_items.length} items for $_currentFolderPath',
      );
      try {
        _quota = await service.fetchUserQuota();
      } catch (e) {
        debugPrint('[FilesController] Quota fetch warning: $e');
      }
      try {
        _activities = await service.fetchActivities();
      } catch (e) {
        debugPrint('[FilesController] Activity fetch warning: $e');
      }
    } catch (e) {
      if (gen != session.sessionGeneration) return;
      debugPrint('[FilesController] Error fetching directory: $e');
      // A failed in-place refresh keeps the (slightly stale) listing on
      // screen instead of replacing it with an error page.
      if (!inPlace) {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _scheduleNetworkRetry(e);
      }
    } finally {
      if (gen == session.sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// The OS reports "connected" a moment before the route actually works,
  /// so the first request after regaining Wi-Fi/data can fail with "Network
  /// is unreachable" - leaving the Files tab on an error page until the
  /// user taps Retry. Quietly retry a few times (2s, 4s, 8s, 15s) when the
  /// failure is network-level and the device is online; a real server error
  /// (auth, 5xx) isn't retried.
  void _scheduleNetworkRetry(Object error) {
    final text = error.toString();
    final isNetworkError =
        text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('TimeoutException') ||
        text.contains('Network is unreachable');
    if (!isNetworkError ||
        _retryAttempt >= 4 ||
        session.connectivity.isOffline) {
      return;
    }
    final delays = [2, 4, 8, 15];
    final delay = Duration(seconds: delays[_retryAttempt]);
    _retryAttempt++;
    _retryTimer = Timer(delay, () => unawaited(refreshData()));
  }

  Future<List<NextcloudItem>> searchFiles(String query) async {
    final service = session.service;
    if (service == null) return [];
    return service.searchFiles(query);
  }

  @override
  Future<void> reload() => refreshData();

  @override
  Future<void> navigateToFolder(String path) async {
    _pathStack.add(path);
    await _navigateTo(path);
  }

  @override
  Future<void> navigateUp() async {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      await _navigateTo(_pathStack.last);
    }
  }

  /// Jumps directly to an ancestor folder by its position in [pathStack]
  /// (as tapped from a breadcrumb), trimming everything below it.
  @override
  Future<void> navigateToPathIndex(int index) async {
    if (index < 0 || index >= _pathStack.length - 1) return;
    _pathStack = _pathStack.sublist(0, index + 1);
    await _navigateTo(_pathStack.last);
  }

  /// Navigates directly to an arbitrary absolute folder path (e.g. from a
  /// search result) - unlike [navigateToFolder], which assumes [path] is a
  /// child of wherever the user is currently browsing and just appends it,
  /// this rebuilds the whole breadcrumb trail from root so it's correct
  /// regardless of where the user was before.
  Future<void> navigateToAbsoluteFolder(String path) async {
    final normalized = path.trim().replaceAll(RegExp(r'/+$'), '');
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    final stack = <String>['/'];
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      stack.add(current);
    }
    _pathStack = stack;
    await _navigateTo(stack.last);
  }

  /// Switches the current folder to [path], serving its listing straight
  /// from the cache when that's still fresh (instant, no network call at
  /// all) and only falling back to [refreshData] otherwise.
  Future<void> _navigateTo(String path) async {
    _currentFolderPath = path;
    final cached = _directoryCache[path];
    if (cached != null && _isCacheFresh(path)) {
      debugPrint('[FilesController] Serving cached listing for $path');
      _items = cached.items;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    // Don't leave the folder just left on screen under the new breadcrumb
    // while this one loads - clearing it is what makes [refreshData] show
    // its spinner (rather than refreshing in place) for a navigation.
    _items = [];
    await refreshData();
  }

  /// A destination-picker-only fetch: the current folder listing state
  /// (`items`/`currentFolderPath`/`pathStack`/the directory cache) belongs
  /// to whichever tab is actively browsing (Files), so the Move/Copy
  /// destination picker deliberately doesn't touch any of it - it fetches
  /// listings for its own local navigation state through this instead.
  Future<List<NextcloudItem>> fetchFolderListing(String path) {
    return session.service?.fetchDirectory(path) ?? Future.value([]);
  }

  /// Finds the single item at [path] by listing its parent folder and
  /// matching on the exact path - there's no WebDAV call here for stat'ing
  /// one path directly outside a directory PROPFIND. Used by the Shares tab
  /// to open the full Share sheet for a [NextcloudShare], which only carries
  /// enough metadata for its own row, not the size/dates `ShareSheet`'s
  /// header needs.
  Future<NextcloudItem?> fetchItemAtPath(String path) async {
    final normalized = path.startsWith('/') ? path : '/$path';
    final lastSlash = normalized.lastIndexOf('/');
    final parent = lastSlash <= 0 ? '/' : normalized.substring(0, lastSlash);
    final items = await fetchFolderListing(parent);
    return items.where((i) => i.path == normalized).firstOrNull;
  }

  void invalidateCache() => _directoryCache.clear();

  /// Persists a per-account browsing pref under its `acct_<id>_`-namespaced
  /// key. No-op if there's no active account (shouldn't normally happen -
  /// these setters are only reachable from screens that require one).
  void _persistAccountPref(
    String baseKey,
    void Function(SharedPreferences prefs, String key) write,
  ) {
    final id = session.activeAccountId;
    if (id == null) return;
    session.prefsFuture.then(
      (p) => write(p, session.accountStore.accountPrefKey(id, baseKey)),
    );
  }

  void setGridView(bool value) {
    if (_isGridView == value) return;
    _isGridView = value;
    notifyListeners();
    _persistAccountPref(_prefGridView, (p, key) => p.setBool(key, value));
  }

  void setStorageScope(StorageScope scope) {
    if (_storageScope == scope) return;
    _storageScope = scope;
    notifyListeners();
    _persistAccountPref(
      _prefStorageScope,
      (p, key) => p.setString(key, scope.name),
    );
  }

  void setFilesTypeFilter(FilesTypeFilter filter) {
    if (_filesTypeFilter == filter) return;
    _filesTypeFilter = filter;
    notifyListeners();
    _persistAccountPref(
      _prefFilesTypeFilter,
      (p, key) => p.setString(key, filter.name),
    );
  }

  /// Only *enabling* hidden-files visibility is gated - hiding them again
  /// never exposes anything, so that direction is always allowed instantly.
  Future<void> toggleShowHiddenFiles() async {
    if (!_showHiddenFiles) {
      if (!await session.passGate(
        session.lockHiddenFiles,
        'Unlock to show hidden files',
      )) {
        return;
      }
    }
    _showHiddenFiles = !_showHiddenFiles;
    notifyListeners();
    _persistAccountPref(
      _prefShowHiddenFiles,
      (p, key) => p.setBool(key, _showHiddenFiles),
    );
  }

  void _persistFolderSort() {
    final combined = <String, dynamic>{};
    for (final path in {
      ..._folderSortField.keys,
      ..._folderSortAscending.keys,
    }) {
      combined[path] = {
        'field': _folderSortField[path]?.name,
        'ascending': _folderSortAscending[path],
      };
    }
    _persistAccountPref(
      _prefFolderSort,
      (p, key) => p.setString(key, jsonEncode(combined)),
    );
  }

  void setFilesSortField(FileSortField field) =>
      setSortFieldFor(_currentFolderPath, field);

  void toggleFilesSortOrder() => toggleSortOrderFor(_currentFolderPath);

  void setSortFieldFor(String path, FileSortField field) {
    if (sortFieldFor(path) == field) return;
    _folderSortField[path] = field;
    notifyListeners();
    _persistFolderSort();
  }

  void toggleSortOrderFor(String path) {
    _folderSortAscending[path] = !sortAscendingFor(path);
    notifyListeners();
    _persistFolderSort();
  }

  void setCachePolicy(CachePolicy policy) {
    if (_cachePolicy == policy) return;
    _cachePolicy = policy;
    notifyListeners();
    _persistAccountPref(
      prefCachePolicy,
      (p, key) => p.setString(key, policy.name),
    );
    _startCacheRefreshTimerIfNeeded();
  }

  void setCacheIntervalMinutes(int minutes) {
    final clamped = minutes.clamp(1, 60);
    if (_cacheIntervalMinutes == clamped) return;
    _cacheIntervalMinutes = clamped;
    notifyListeners();
    _persistAccountPref(
      prefCacheIntervalMinutes,
      (p, key) => p.setInt(key, clamped),
    );
    _startCacheRefreshTimerIfNeeded();
  }

  Future<bool> createFolder(String folderName) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.createFolder(_currentFolderPath, folderName);
    if (success) {
      await refreshData();
    }
    return success;
  }

  /// Patches a favorite-toggle result into [items] in place (no refetch) -
  /// called by `ItemOperations.toggleItemFavorite` after a successful
  /// server call.
  void applyFavoriteToggle(NextcloudItem updated) {
    final index = _items.indexWhere((i) => i.id == updated.id);
    if (index != -1) _items[index] = updated;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cacheRefreshTimer?.cancel();
    super.dispose();
  }
}
