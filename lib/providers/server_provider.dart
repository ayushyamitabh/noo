import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_tab.dart';
import '../models/move_copy_result.dart';
import '../models/nextcloud_file_version.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../models/nextcloud_sharee.dart';
import '../models/pick_request.dart';
import '../models/saved_account.dart';
import '../models/sync_status.dart';
import '../services/account_store.dart';
import '../services/app_lock_service.dart';
import '../services/login_flow_service.dart';
import '../services/nextcloud_service.dart';
import '../services/pick_intent_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

enum LoginFlowStatus { idle, initiating, awaitingBrowser, error }

enum FileSortField { name, dateCreated, dateModified, size }

/// Which storage a listing shows — always exactly one, like the list/grid
/// view toggle, not an optional filter.
enum StorageScope { cloud, external }

/// What swiping a Files list-view item left/right does, user-configurable
/// in Settings.
enum SwipeAction { none, favorite, delete, share }

/// The Files tab's files/folders/both filter — independent of and applied
/// after [StorageScope]/favorites/hidden filtering.
enum FilesTypeFilter { all, filesOnly, foldersOnly }

/// How aggressively the Files tab's folder listings (not thumbnails/file
/// content - just the list of names/sizes/dates) are reused across
/// navigation instead of refetched from the server every time.
enum CachePolicy {
  /// Every navigation refetches - today's behavior.
  never,

  /// A listing is reused until it's older than [ServerProvider.
  /// cacheIntervalMinutes]; a timer also proactively refreshes the current
  /// folder on that same interval while the app is in the foreground.
  interval,

  /// A listing is reused indefinitely until the user pulls to refresh.
  manual,
}

/// One cached folder listing and when it was fetched.
class _CachedDirectory {
  final List<NextcloudItem> items;
  final DateTime fetchedAt;

  const _CachedDirectory(this.items, this.fetchedAt);
}

/// Thumb/track presets for the video player's seek bar, matching the four
/// combinations offered by other Material You media players: a Material 3
/// slider-style thumb ([classic]), an animated travelling wave with a round
/// thumb ([wavy]), a thin flat bar with no distinct thumb ([slim]), and an
/// animated wave with a tick-mark thumb ([squiggly]).
enum MediaProgressBarStyle { classic, wavy, slim, squiggly }

class ServerProvider extends ChangeNotifier with WidgetsBindingObserver {
  // Cached UI settings/toggles (SharedPreferences keys)
  static const _prefThemeMode = 'ui_theme_mode';
  static const _prefUseDynamicColor = 'ui_use_dynamic_color';
  static const _prefSeedColor = 'ui_seed_color';
  static const _prefBottomBarOpacity = 'ui_bottom_bar_opacity';
  static const _prefBottomBarBlur = 'ui_bottom_bar_blur';
  static const _prefGridView = 'ui_grid_view';
  static const _prefShowFavoritesOnlyPhotos = 'ui_show_favorites_only_photos';
  static const _prefStorageScope = 'ui_storage_scope';
  static const _prefFilesTypeFilter = 'ui_files_type_filter';
  static const _prefShowHiddenFiles = 'ui_show_hidden';
  static const _prefShowHiddenPhotos = 'ui_show_hidden_photos';
  static const _prefSortField = 'ui_sort_field';
  static const _prefSortAscending = 'ui_sort_ascending';
  static const _prefFolderSort = 'ui_folder_sort';
  static const _prefTabOrder = 'ui_tab_order';
  static const _prefHiddenTabs = 'ui_hidden_tabs';
  static const _prefDefaultTab = 'ui_default_tab';
  static const _prefSwipeLeftAction = 'ui_swipe_left_action';
  static const _prefSwipeRightAction = 'ui_swipe_right_action';
  static const _prefAmoledDark = 'ui_amoled_dark';
  static const _prefMediaProgressBarStyle = 'ui_media_progress_bar_style';
  static const _prefCachePolicy = 'ui_cache_policy';
  static const _prefCacheIntervalMinutes = 'ui_cache_interval_minutes';
  static const _prefTapTabToScrollTop = 'ui_tap_tab_to_scroll_top';
  static const _prefLoginLockEnabled = 'ui_login_lock_enabled';
  static const _prefLockAccountSwitching = 'ui_lock_account_switching';
  static const _prefLockHiddenFiles = 'ui_lock_hidden_files';
  static const _prefSyncedFolders = 'ui_synced_folders';
  static const _prefSyncEverything = 'ui_sync_everything';
  static const _prefSyncOnCellular = 'ui_sync_on_cellular';

  final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  String _serverUrl = '';
  String _username = '';
  String _password = '';
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isRestoringSession = true;
  String? _errorMessage;

  // Login flow v2 state
  LoginFlowStatus _loginFlowStatus = LoginFlowStatus.idle;
  Uri? _pendingLoginUrl;
  Timer? _pollTimer;
  Timer? _pollTimeoutTimer;

  // Theme state
  Color _seedColor = AppTheme.defaultNextcloudBlue;
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  MediaProgressBarStyle _mediaProgressBarStyle = MediaProgressBarStyle.wavy;

  // UI settings
  double _bottomBarOpacity = 0.55;
  double _bottomBarBlur = 28;
  bool _tapTabToScrollTop = true;

  // Device sync - which remote paths (files or folders, per account) get
  // mirrored locally by the native SyncWorker, and whether its periodic
  // background runs are allowed on cellular (default Wi-Fi-only). See
  // SyncEngine.kt/server.md.
  List<String> _syncedPaths = [];
  bool _syncEverything = false;
  bool _syncOnCellular = false;

  // Live device-sync status, pushed from SyncStatusBus.kt via
  // SyncService.statusStream (see _subscribeToSyncStatus) - account-wide,
  // not scoped to whatever folder is currently browsed.
  bool _isSyncingNow = false;
  Set<String> _syncingFileIds = {};
  Set<String> _syncedFileIds = {};
  List<SyncConflictInfo> _syncConflicts = [];
  StreamSubscription<SyncStatusSnapshot>? _syncStatusSub;

  // App lock (PIN/biometric via the device's own credential, not our own
  // storage - see AppLockService). Global, not per-account: it guards
  // access to the app/its accounts, not any one account's content.
  bool _loginLockEnabled = false;
  bool _lockAccountSwitching = false;
  bool _lockHiddenFiles = false;
  // Transient (never persisted) - starts locked whenever the app process
  // starts, and re-locks on every backgrounding if a lock is configured;
  // see didChangeAppLifecycleState.
  bool _isUnlocked = false;

  // Navigation state
  String _currentFolderPath = '/';

  // A one-shot request for the shell to switch its active bottom-nav tab
  // (e.g. a search result landing on Files) - consumed and cleared by
  // MainShellView the next time it builds, not a persisted preference.
  AppTab? _requestedTab;

  // Non-null while the app is acting as another app's GET_CONTENT picker
  // (see PickIntentService/MainActivity.kt) - set at startup/onNewPickRequest
  // in MainShellView, cleared once the pick is confirmed or cancelled.
  PickRequest? _pickRequest;
  bool _isDownloadingForPick = false;
  List<String> _pathStack = ['/'];
  bool _isGridView = false;
  bool _showFavoritesOnlyPhotos = false;
  StorageScope _storageScope = StorageScope.cloud;
  FilesTypeFilter _filesTypeFilter = FilesTypeFilter.all;
  bool _showHiddenFiles = false;
  bool _showHiddenPhotos = false;
  // Photos tab sort - a single global setting (Photos has no folder concept,
  // it spans the whole account).
  FileSortField _photosSortField = FileSortField.name;
  bool _photosSortAscending = true;

  // Files tab sort - unlinked from Photos and remembered per folder path
  // (like Windows Explorer's per-folder view settings), so switching
  // folders can restore a different sort than the parent. Falls back to
  // name/ascending for any folder with no saved entry.
  final Map<String, FileSortField> _folderSortField = {};
  final Map<String, bool> _folderSortAscending = {};

  // Bottom nav tab configuration
  List<AppTab> _tabOrder = AppTab.values.toList();
  Set<AppTab> _hiddenTabs = {};
  AppTab _defaultTab = AppTab.files;

  // Files list-view swipe actions
  SwipeAction _swipeLeftAction = SwipeAction.delete;
  SwipeAction _swipeRightAction = SwipeAction.favorite;

  // Folder-listing cache: keyed by folder path, holds nothing but the item
  // list itself (no thumbnails/content) plus when it was fetched.
  CachePolicy _cachePolicy = CachePolicy.never;
  int _cacheIntervalMinutes = 5;
  final Map<String, _CachedDirectory> _directoryCache = {};
  Timer? _cacheRefreshTimer;

  // Data state
  List<NextcloudItem> _items = [];
  NextcloudUserQuota? _quota;
  List<NextcloudActivity> _activities = [];

  // All-account media (the Photos tab) — fetched separately from [_items]
  // since it spans every folder, not just the currently browsed one.
  List<NextcloudItem> _allMedia = [];
  bool _isMediaLoading = false;
  String? _mediaErrorMessage;

  // All-account favorites (the Favorites tab) - same idea as [_allMedia]:
  // a strict filter (only favorited items) but an account-wide *scope*, so
  // a favorited item several folders deep still shows up regardless of
  // whether its parent folders are themselves favorited - which is exactly
  // why this is its own tab (and its own fetch/loading state, kept
  // separate from Files' own [_isLoading]/[_errorMessage] since both tabs
  // are simultaneously mounted in MainShellView's IndexedStack and would
  // otherwise bleed loading/error state into each other) rather than a
  // filter toggle scoped to whatever folder the Files tab happens to be
  // browsing.
  List<NextcloudItem> _allFavorites = [];
  bool _isFavoritesLoading = false;
  String? _favoritesErrorMessage;
  // True once fetchAllFavorites has run at least once (i.e. the Favorites
  // tab has been visited) - delete/rename/move/copy re-sync [_allFavorites]
  // afterward, but only when it's actually been loaded, so those actions
  // don't pay for an extra network round-trip on every Files/Photos edit
  // for an account that's never opened the Favorites tab this session.
  bool _favoritesEverFetched = false;

  // Trash state — kept separate from the regular folder-loading/error state
  // above so a trash-fetch failure can't bleed a stale error into Files.
  List<NextcloudItem> _trashItems = [];
  bool _isTrashLoading = false;
  String? _trashErrorMessage;

  // Shares state — likewise kept separate.
  List<NextcloudShare> _shares = [];
  bool _isSharesLoading = false;
  String? _sharesErrorMessage;
  bool _sharesWithMe = false;

  // Recent-files state — likewise kept separate.
  List<NextcloudItem> _recentItems = [];
  bool _isRecentLoading = false;
  String? _recentErrorMessage;

  NextcloudService? _service;

  // Multi-account state
  final AccountStore _accountStore = AccountStore();
  List<SavedAccount> _accounts = [];
  String? _activeAccountId;
  // Bumped at the start of every account switch/removal/activation so an
  // in-flight fetch from the account being left can recognize it's stale
  // (by comparing against the generation it captured at its own start) and
  // discard its result instead of writing it into the now-active account's
  // state.
  int _sessionGeneration = 0;
  // UI-only signal for whether the in-progress login flow is "add another
  // account" (started from Settings while already logged in) vs. the
  // first/only login - ServerProvider itself doesn't branch persistence
  // behavior on this, only the Add Account screen's own navigation does.
  bool _addAccountFlowActive = false;

  ServerProvider() {
    WidgetsBinding.instance.addObserver(this);
    _init();
    _subscribeToSyncStatus();
  }

  Future<void> _init() async {
    final prefs = await _prefsFuture;
    await _accountStore.migrateLegacyIfNeeded(prefs);
    _accounts = _accountStore.loadAccounts(prefs);
    _activeAccountId = _accountStore.loadActiveAccountId(prefs);
    await Future.wait([_loadPreferences(), _restoreSession()]);
  }

  /// Live device-sync status for the rest of the app's lifetime (not
  /// re-subscribed per account switch - each event carries its own
  /// `accountId`, so events for an account that isn't currently active are
  /// just ignored below). Seeded once via a one-shot snapshot right after
  /// every successful login/account-switch instead (see
  /// `_applyCredentialsForAccount`), since events only arrive on change.
  void _subscribeToSyncStatus() {
    _syncStatusSub = SyncService.statusStream.listen((snapshot) {
      _applySyncStatus(snapshot);
    });
  }

  void _applySyncStatus(SyncStatusSnapshot snapshot) {
    if (snapshot.accountId != null && snapshot.accountId != _activeAccountId) {
      return;
    }
    _isSyncingNow = snapshot.syncing;
    _syncingFileIds = snapshot.syncingFileIds;
    _syncedFileIds = snapshot.syncedFileIds;
    _syncConflicts = snapshot.conflicts;
    notifyListeners();
  }

  /// Starts/stops the periodic folder-listing refresh as the app leaves and
  /// returns to the foreground - only relevant under [CachePolicy.interval].
  /// Also re-locks the app on backgrounding when login lock is set up - a
  /// one-time unlock at cold start would give the feature no real security
  /// value, since the realistic threat is someone else picking up an
  /// already-running, unlocked phone.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startCacheRefreshTimerIfNeeded();
    } else if (state == AppLifecycleState.paused) {
      _cacheRefreshTimer?.cancel();
      if (_loginLockEnabled && _isUnlocked) {
        _isUnlocked = false;
        notifyListeners();
      }
    }
  }

  void _startCacheRefreshTimerIfNeeded() {
    _cacheRefreshTimer?.cancel();
    if (_cachePolicy != CachePolicy.interval || !_isLoggedIn) return;
    _cacheRefreshTimer = Timer.periodic(
      Duration(minutes: _cacheIntervalMinutes),
      (_) => refreshData(),
    );
  }

  // Getters
  String get serverUrl => _serverUrl;
  String get username => _username;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get errorMessage => _errorMessage;

  LoginFlowStatus get loginFlowStatus => _loginFlowStatus;
  Uri? get pendingLoginUrl => _pendingLoginUrl;

  List<SavedAccount> get accounts => List.unmodifiable(_accounts);
  String? get activeAccountId => _activeAccountId;
  SavedAccount? get activeAccount =>
      _accounts.where((a) => a.id == _activeAccountId).firstOrNull;
  bool get isAddAccountFlow => _addAccountFlowActive;

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  MediaProgressBarStyle get mediaProgressBarStyle => _mediaProgressBarStyle;
  double get bottomBarOpacity => _bottomBarOpacity;
  double get bottomBarBlur => _bottomBarBlur;
  bool get tapTabToScrollTop => _tapTabToScrollTop;
  bool get loginLockEnabled => _loginLockEnabled;
  bool get lockAccountSwitching => _lockAccountSwitching;
  bool get lockHiddenFiles => _lockHiddenFiles;
  bool get needsUnlock => _loginLockEnabled && !_isUnlocked;

  List<String> get syncedPaths => List.unmodifiable(_syncedPaths);
  bool get syncEverything => _syncEverything;
  bool get syncOnCellular => _syncOnCellular;

  bool get isSyncingNow => _isSyncingNow;
  List<SyncConflictInfo> get syncConflicts => List.unmodifiable(_syncConflicts);

  SyncHeaderStatus get syncHeaderStatus {
    if (_syncConflicts.isNotEmpty) return SyncHeaderStatus.alert;
    if (_isSyncingNow) return SyncHeaderStatus.syncing;
    if (!_syncEverything && _syncedPaths.isEmpty) return SyncHeaderStatus.off;
    return SyncHeaderStatus.done;
  }

  SyncItemStatus syncStatusFor(NextcloudItem item) {
    if (_syncingFileIds.contains(item.id)) return SyncItemStatus.syncing;
    if (_syncConflicts.any((c) => c.fileId == item.id)) {
      return SyncItemStatus.conflict;
    }
    if (_syncedFileIds.contains(item.id)) return SyncItemStatus.synced;
    return SyncItemStatus.none;
  }

  String get currentFolderPath => _currentFolderPath;
  AppTab? get requestedTab => _requestedTab;

  PickRequest? get pickRequest => _pickRequest;
  bool get isPicking => _pickRequest != null;
  bool get isDownloadingForPick => _isDownloadingForPick;

  /// Whether [item] can be handed back to the app that's currently picking
  /// - always true for folders (still browsable), mime-filtered for files.
  bool itemMatchesPickFilter(NextcloudItem item) {
    if (item.isFolder) return true;
    final request = _pickRequest;
    return request == null || request.matches(item.mimeType);
  }

  /// Called once (from MainShellView) as soon as a pick request is known -
  /// either the cold-start request or one that arrived via onNewPickRequest
  /// while already running.
  void setPickRequest(PickRequest request) {
    _pickRequest = request;
    notifyListeners();
  }

  /// Downloads each selected item to a scratch cache folder, then hands the
  /// local paths back to the caller through PickIntentService, which closes
  /// the picker Activity on success. Left in [_pickRequest] (i.e. picking
  /// mode stays visually active) if the download fails partway, so the user
  /// can see the error and retry rather than the screen finishing under
  /// them with nothing returned to the caller.
  Future<bool> confirmPick(List<NextcloudItem> items) async {
    final service = _service;
    if (_pickRequest == null || service == null || items.isEmpty) {
      return false;
    }
    _isDownloadingForPick = true;
    notifyListeners();
    try {
      final tempDir = await getTemporaryDirectory();
      final pickDir = Directory(p.join(tempDir.path, 'picker'));
      final localPaths = <String>[];
      final mimeTypes = <String>[];
      for (final item in items) {
        // Each item gets its own subfolder (keyed by id, not smashed into
        // the filename) so two different items can share a plain file
        // name without colliding, while the file on disk - and therefore
        // the display name the caller sees via the content:// Uri
        // MainActivity.kt hands back - stays exactly `item.name`.
        final itemDir = Directory(p.join(pickDir.path, item.id));
        await itemDir.create(recursive: true);
        final localPath = p.join(itemDir.path, item.name);
        await service.downloadToFile(item.path, localPath);
        localPaths.add(localPath);
        mimeTypes.add(item.mimeType ?? 'application/octet-stream');
      }
      await PickIntentService.finishPick(localPaths, mimeTypes);
      _pickRequest = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isDownloadingForPick = false;
      notifyListeners();
    }
  }

  /// Backs out of picking mode entirely, telling the caller nothing was
  /// picked and closing the picker Activity.
  Future<void> cancelPick() async {
    if (_pickRequest == null) return;
    _pickRequest = null;
    notifyListeners();
    await PickIntentService.cancelPick();
  }

  /// Asks the shell to switch its active bottom-nav tab to [tab] - e.g. so
  /// tapping a search result lands the user on the Files tab even if they
  /// opened search from somewhere else.
  void requestTab(AppTab tab) {
    _requestedTab = tab;
    notifyListeners();
  }

  /// Called by the shell once it's consumed [requestedTab].
  void consumeRequestedTab() {
    _requestedTab = null;
  }

  List<String> get pathStack => _pathStack;
  bool get isGridView => _isGridView;
  bool get showFavoritesOnlyPhotos => _showFavoritesOnlyPhotos;
  StorageScope get storageScope => _storageScope;
  FilesTypeFilter get filesTypeFilter => _filesTypeFilter;
  bool get showHiddenFiles => _showHiddenFiles;
  bool get showHiddenPhotos => _showHiddenPhotos;
  FileSortField get photosSortField => _photosSortField;
  bool get photosSortAscending => _photosSortAscending;
  FileSortField get filesSortField =>
      _folderSortField[_currentFolderPath] ?? FileSortField.name;
  bool get filesSortAscending =>
      _folderSortAscending[_currentFolderPath] ?? true;
  CachePolicy get cachePolicy => _cachePolicy;
  int get cacheIntervalMinutes => _cacheIntervalMinutes;

  /// Every tab in the user's configured order, including hidden ones — used
  /// by the reorder/visibility settings UI.
  List<AppTab> get tabOrder => _tabOrder;
  Set<AppTab> get hiddenTabs => _hiddenTabs;
  AppTab get defaultTab => _defaultTab;

  /// The tabs the bottom nav bar should actually show, in order.
  List<AppTab> get visibleTabs =>
      _tabOrder.where((t) => !_hiddenTabs.contains(t)).toList();

  SwipeAction get swipeLeftAction => _swipeLeftAction;
  SwipeAction get swipeRightAction => _swipeRightAction;

  /// Exposes the active service so views can build file URLs, auth headers,
  /// and trigger downloads/previews directly.
  NextcloudService? get service => _service;

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

  /// Applies the shared favorites-only/hidden-files/storage-scope toggles.
  /// `showFavoritesOnly` is effectively Photos-only now (`items`/
  /// `favoriteItems` both always pass `false` - see their own doc
  /// comments for why); kept as a parameter here since `photoItems` still
  /// has its own independent favorites-only toggle.
  List<NextcloudItem> _applyCommonFilters(
    List<NextcloudItem> source, {
    required bool showFavoritesOnly,
    required bool showHidden,
  }) {
    var filtered = source;
    if (showFavoritesOnly) {
      filtered = filtered.where((item) => item.isFavorite).toList();
    }
    if (!showHidden) {
      filtered = filtered.where((item) => !_isHiddenItem(item)).toList();
    }
    filtered = filtered
        .where(
          (item) => _storageScope == StorageScope.external
              ? item.isExternalStorage
              : !item.isExternalStorage,
        )
        .toList();
    return filtered;
  }

  List<NextcloudItem> get items => applyFilesDisplayPrefs(_items);

  /// The Favorites tab's content - every favorited item account-wide (see
  /// `fetchAllFavorites`), run through the exact same hidden/type-filter/
  /// sort/storage-scope display prefs as the Files tab (deliberately
  /// shared rather than a separate parallel settings dimension, the same
  /// way the Move/Copy destination picker reuses them). No favorites
  /// filter needed here - the source list is already all-favorites.
  List<NextcloudItem> get favoriteItems =>
      applyFilesDisplayPrefs(_allFavorites);

  /// Applies the Files tab's current sort/filter display prefs (hidden,
  /// type filter, storage scope, sort field/direction) to an arbitrary raw
  /// item list - factored out of the [items] getter so both the Favorites
  /// tab ([favoriteItems]) and the Move/Copy destination picker (which
  /// fetches its own listings via [fetchFolderListing] rather than reading
  /// [items] itself - see that method's doc comment) can render with the
  /// exact same controls/behavior as the Files tab without duplicating
  /// this logic.
  List<NextcloudItem> applyFilesDisplayPrefs(List<NextcloudItem> rawItems) {
    var filtered = _applyCommonFilters(
      rawItems,
      // Files itself no longer filters by favorite - that's the dedicated
      // Favorites tab's job now (see `favoriteItems`/`fetchAllFavorites`).
      showFavoritesOnly: false,
      showHidden: _showHiddenFiles,
    );
    switch (_filesTypeFilter) {
      case FilesTypeFilter.all:
        break;
      case FilesTypeFilter.filesOnly:
        filtered = filtered.where((i) => !i.isFolder).toList();
      case FilesTypeFilter.foldersOnly:
        filtered = filtered.where((i) => i.isFolder).toList();
    }

    final field = filesSortField;
    final folders = filtered.where((i) => i.isFolder).toList()
      ..sort((a, b) => _compareItems(a, b, field));
    final files = filtered.where((i) => !i.isFolder).toList()
      ..sort((a, b) => _compareItems(a, b, field));
    return filesSortAscending
        ? [...folders, ...files]
        : [...folders.reversed, ...files.reversed];
  }

  /// All images/videos across the whole account (not just the currently
  /// browsed folder) — see [fetchAllMedia].
  List<NextcloudItem> get photoItems {
    final media = _allMedia.where((i) => i.isMedia).toList();
    final filtered = _applyCommonFilters(
      media,
      showFavoritesOnly: _showFavoritesOnlyPhotos,
      showHidden: _showHiddenPhotos,
    )..sort((a, b) => _compareItems(a, b, _photosSortField));
    return _photosSortAscending ? filtered : filtered.reversed.toList();
  }

  bool get isMediaLoading => _isMediaLoading;
  String? get mediaErrorMessage => _mediaErrorMessage;
  bool get isFavoritesLoading => _isFavoritesLoading;
  String? get favoritesErrorMessage => _favoritesErrorMessage;

  NextcloudUserQuota? get quota => _quota;
  List<NextcloudActivity> get activities => _activities;

  List<NextcloudItem> get trashItems => _trashItems;
  bool get isTrashLoading => _isTrashLoading;
  String? get trashErrorMessage => _trashErrorMessage;

  List<NextcloudShare> get shares => _shares;
  bool get isSharesLoading => _isSharesLoading;
  String? get sharesErrorMessage => _sharesErrorMessage;
  bool get sharesWithMe => _sharesWithMe;

  List<NextcloudItem> get recentItems => _recentItems;
  bool get isRecentLoading => _isRecentLoading;
  String? get recentErrorMessage => _recentErrorMessage;

  Future<void> _restoreSession() async {
    try {
      final id = _activeAccountId;
      if (id == null) return;
      final account = _accounts.where((a) => a.id == id).firstOrNull;
      if (account == null) return;
      final password = await _accountStore.readPassword(id);
      if (password == null) return;
      await _applyCredentialsForAccount(account, password);
    } catch (e) {
      debugPrint('[ServerProvider] Session restore failed: $e');
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await _prefsFuture;

      final themeModeName = prefs.getString(_prefThemeMode);
      if (themeModeName != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == themeModeName,
          orElse: () => ThemeMode.system,
        );
      }
      _useDynamicColor =
          prefs.getBool(_prefUseDynamicColor) ?? _useDynamicColor;
      _amoledDark = prefs.getBool(_prefAmoledDark) ?? _amoledDark;
      final progressBarStyleName = prefs.getString(_prefMediaProgressBarStyle);
      if (progressBarStyleName != null) {
        _mediaProgressBarStyle = MediaProgressBarStyle.values.firstWhere(
          (s) => s.name == progressBarStyleName,
          orElse: () => _mediaProgressBarStyle,
        );
      }
      final seedColorValue = prefs.getInt(_prefSeedColor);
      if (seedColorValue != null) _seedColor = Color(seedColorValue);
      _bottomBarOpacity =
          prefs.getDouble(_prefBottomBarOpacity) ?? _bottomBarOpacity;
      _bottomBarBlur = prefs.getDouble(_prefBottomBarBlur) ?? _bottomBarBlur;
      _tapTabToScrollTop =
          prefs.getBool(_prefTapTabToScrollTop) ?? _tapTabToScrollTop;
      _loginLockEnabled =
          prefs.getBool(_prefLoginLockEnabled) ?? _loginLockEnabled;
      _lockAccountSwitching =
          prefs.getBool(_prefLockAccountSwitching) ?? _lockAccountSwitching;
      _lockHiddenFiles =
          prefs.getBool(_prefLockHiddenFiles) ?? _lockHiddenFiles;
      _syncOnCellular = prefs.getBool(_prefSyncOnCellular) ?? _syncOnCellular;
      _applyAccountPrefs(prefs, _activeAccountId);

      final savedOrderNames = prefs.getStringList(_prefTabOrder);
      if (savedOrderNames != null) {
        final order = <AppTab>[];
        for (final name in savedOrderNames) {
          final match = AppTab.values.where((t) => t.name == name).firstOrNull;
          if (match != null) order.add(match);
        }
        // Forward-compat: a tab added in a later app update won't be in an
        // older saved order yet, so append anything missing.
        for (final tab in AppTab.values) {
          if (!order.contains(tab)) order.add(tab);
        }
        _tabOrder = order;
      }

      final savedHiddenNames = prefs.getStringList(_prefHiddenTabs);
      if (savedHiddenNames != null) {
        _hiddenTabs = savedHiddenNames
            .map(
              (name) => AppTab.values.where((t) => t.name == name).firstOrNull,
            )
            .whereType<AppTab>()
            .toSet();
        // Never let every tab end up hidden.
        if (_hiddenTabs.length >= AppTab.values.length) {
          _hiddenTabs = {};
        }
      }

      final savedDefaultName = prefs.getString(_prefDefaultTab);
      if (savedDefaultName != null) {
        final match = AppTab.values
            .where((t) => t.name == savedDefaultName)
            .firstOrNull;
        if (match != null) _defaultTab = match;
      }
      if (_hiddenTabs.contains(_defaultTab)) {
        _defaultTab = _tabOrder.firstWhere(
          (t) => !_hiddenTabs.contains(t),
          orElse: () => _tabOrder.first,
        );
      }
      _enforceMaxVisibleTabs();

      final swipeLeftName = prefs.getString(_prefSwipeLeftAction);
      if (swipeLeftName != null) {
        _swipeLeftAction = SwipeAction.values.firstWhere(
          (a) => a.name == swipeLeftName,
          orElse: () => _swipeLeftAction,
        );
      }
      final swipeRightName = prefs.getString(_prefSwipeRightAction);
      if (swipeRightName != null) {
        _swipeRightAction = SwipeAction.values.firstWhere(
          (a) => a.name == swipeRightName,
          orElse: () => _swipeRightAction,
        );
      }
      _startCacheRefreshTimerIfNeeded();

      notifyListeners();
    } catch (e) {
      debugPrint('[ServerProvider] Preference restore failed: $e');
    }
  }

  /// (Re)loads every per-account browsing pref (grid/list view,
  /// favorites-only, storage scope, show-hidden, sort, folder sort, cache
  /// policy) for [accountId] - called once at startup and again on every
  /// account switch. Resets to defaults when [accountId] is null (no saved
  /// account yet).
  void _applyAccountPrefs(SharedPreferences prefs, String? accountId) {
    _folderSortField.clear();
    _folderSortAscending.clear();

    if (accountId == null) {
      _isGridView = false;
      _showFavoritesOnlyPhotos = false;
      _storageScope = StorageScope.cloud;
      _filesTypeFilter = FilesTypeFilter.all;
      _showHiddenFiles = false;
      _showHiddenPhotos = false;
      _photosSortField = FileSortField.name;
      _photosSortAscending = true;
      _cachePolicy = CachePolicy.never;
      _cacheIntervalMinutes = 5;
      _syncedPaths = [];
      _syncEverything = false;
      return;
    }

    String k(String base) => _accountStore.accountPrefKey(accountId, base);

    _isGridView = prefs.getBool(k(_prefGridView)) ?? false;
    _showFavoritesOnlyPhotos =
        prefs.getBool(k(_prefShowFavoritesOnlyPhotos)) ?? false;

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
    _showHiddenPhotos = prefs.getBool(k(_prefShowHiddenPhotos)) ?? false;

    final sortFieldName = prefs.getString(k(_prefSortField));
    _photosSortField = FileSortField.values.firstWhere(
      (f) => f.name == sortFieldName,
      orElse: () => FileSortField.name,
    );
    _photosSortAscending = prefs.getBool(k(_prefSortAscending)) ?? true;

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
          if (ascending != null) _folderSortAscending[entry.key] = ascending;
        }
      } catch (e) {
        debugPrint('[ServerProvider] Folder sort restore failed: $e');
      }
    }

    final cachePolicyName = prefs.getString(k(_prefCachePolicy));
    _cachePolicy = CachePolicy.values.firstWhere(
      (c) => c.name == cachePolicyName,
      orElse: () => CachePolicy.never,
    );
    _cacheIntervalMinutes = prefs.getInt(k(_prefCacheIntervalMinutes)) ?? 5;

    final syncedFoldersJson = prefs.getString(k(_prefSyncedFolders));
    if (syncedFoldersJson != null) {
      try {
        _syncedPaths = (jsonDecode(syncedFoldersJson) as List).cast<String>();
      } catch (e) {
        debugPrint('[ServerProvider] Synced folders restore failed: $e');
        _syncedPaths = [];
      }
    } else {
      _syncedPaths = [];
    }
    _syncEverything = prefs.getBool(k(_prefSyncEverything)) ?? false;
  }

  /// Verifies [appPassword] for [account] and, on success, makes it the
  /// live session. The password is expected to already be durably saved by
  /// the caller (either freshly, via [_completeLoginFlow], or previously,
  /// since this is also how a saved session is restored/switched to) -
  /// this method only writes to [AccountStore] to drop a password that
  /// turns out to no longer work.
  Future<bool> _applyCredentialsForAccount(
    SavedAccount account,
    String appPassword,
  ) async {
    final gen = _sessionGeneration;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _serverUrl = account.serverUrl;
    _username = account.username;
    _password = appPassword;

    _service = NextcloudService(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
    );

    try {
      final success = await _service!.testConnection();
      if (gen != _sessionGeneration) return false;
      if (success) {
        _isLoggedIn = true;
        _currentFolderPath = '/';
        _pathStack = ['/'];
        _startCacheRefreshTimerIfNeeded();
        await refreshData();
        if (gen != _sessionGeneration) return false;
        _isLoading = false;
        notifyListeners();
        unawaited(SyncService.reschedule(this));
        unawaited(SyncService.getStatus().then(_applySyncStatus));
        return true;
      }
    } catch (e) {
      if (gen != _sessionGeneration) return false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      // Only drop the stored password on an actual auth rejection (401) -
      // NextcloudService.testConnection also throws for network-level
      // failures (DNS, timeout, unreachable host), and those are transient:
      // deleting a still-valid password on a dropped connection would
      // permanently log the account out with no way back in short of
      // Login Flow v2 again, since _activeAccountId is never cleared and
      // switchAccount() no-ops when asked to "switch" to the account
      // that's already (nominally) active.
      if (_errorMessage?.contains('401') == true) {
        await _accountStore.deletePassword(account.id);
      }
    }

    if (gen != _sessionGeneration) return false;
    _isLoggedIn = false;
    _service = null;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Starts Nextcloud Login Flow v2: asks the server for a one-time login
  /// URL, then polls until the user authorizes (in LoginWebViewView, pushed
  /// by LoginView once loginFlowStatus flips to awaitingBrowser below) and
  /// the server hands back a scoped app password. The app never sees the
  /// user's real password. [addAccount] only marks the flow as "add
  /// another account" for [isAddAccountFlow] - the pushed Add Account
  /// screen reads that to decide when to pop itself; this method's own
  /// persistence behavior on success ([_completeLoginFlow]) is the same
  /// either way (create-or-refresh the resulting account, then activate
  /// it).
  ///
  /// Every login - first account or an additional one - goes through
  /// LoginWebViewView (`package:webview_flutter`), a screen this app owns,
  /// rather than a Chrome Custom Tab. That used to only be true for
  /// add-account, specifically to avoid a Custom Tab silently reusing
  /// Chrome's existing session for a different account; but a Custom Tab
  /// has real costs even for the first login - no way to close it
  /// automatically on success (the user has to switch back manually), and
  /// it's a separate task outside this app's own navigation entirely. The
  /// only thing it bought over a plain WebView was Chrome's own
  /// autofill/saved-password support, which isn't worth those tradeoffs.
  Future<void> startLoginFlow(
    String serverUrl, {
    bool addAccount = false,
  }) async {
    _addAccountFlowActive = addAccount;
    _loginFlowStatus = LoginFlowStatus.initiating;
    _errorMessage = null;
    notifyListeners();

    try {
      final init = await LoginFlowService.initiate(serverUrl);
      _pendingLoginUrl = init.loginUrl;
      _loginFlowStatus = LoginFlowStatus.awaitingBrowser;
      notifyListeners();

      _pollTimer?.cancel();
      _pollTimeoutTimer?.cancel();

      _pollTimeoutTimer = Timer(const Duration(minutes: 10), () {
        if (_loginFlowStatus == LoginFlowStatus.awaitingBrowser) {
          cancelLoginFlow(errorMessage: 'Login timed out. Please try again.');
        }
      });

      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        try {
          final result = await LoginFlowService.poll(
            init.pollEndpoint,
            init.pollToken,
          );
          if (result != null) {
            timer.cancel();
            _pollTimeoutTimer?.cancel();
            _loginFlowStatus = LoginFlowStatus.idle;
            _pendingLoginUrl = null;
            await _completeLoginFlow(result);
            _addAccountFlowActive = false;
          }
        } on http.ClientException catch (e) {
          // A single dropped connection (e.g. the network briefly
          // reconfiguring right as the login browser opens) used to abort
          // the whole flow, forcing the user to start over even though
          // they'd already granted access - just skip this tick and let
          // the next scheduled poll (2s later) try again. The 10-minute
          // timeout above is still the real ceiling.
          debugPrint('[ServerProvider] Poll network hiccup, retrying: $e');
        } catch (e) {
          timer.cancel();
          _pollTimeoutTimer?.cancel();
          cancelLoginFlow(
            errorMessage: e.toString().replaceAll('Exception: ', ''),
          );
        }
      });
    } catch (e) {
      _loginFlowStatus = LoginFlowStatus.error;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  void cancelLoginFlow({String? errorMessage}) {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    _pendingLoginUrl = null;
    _addAccountFlowActive = false;
    _loginFlowStatus = errorMessage != null
        ? LoginFlowStatus.error
        : LoginFlowStatus.idle;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  /// Turns a completed Login Flow v2 result into a saved account (creating
  /// it, or refreshing its password if it already existed - e.g. an
  /// expired app password re-authenticated) and makes it the active
  /// session. Used for both the first/only login and "add account".
  Future<void> _completeLoginFlow(LoginFlowResult result) async {
    final serverUrl = LoginFlowService.normalizeServerUrl(result.serverUrl);
    final id = SavedAccount.makeId(serverUrl, result.loginName);
    final account = SavedAccount(
      id: id,
      serverUrl: serverUrl,
      username: result.loginName,
    );
    _accounts = [
      for (final a in _accounts)
        if (a.id != id) a,
      account,
    ];

    final prefs = await _prefsFuture;
    await _accountStore.saveAccounts(prefs, _accounts);
    await _accountStore.writePassword(id, result.appPassword);
    await _activateAccount(id);
  }

  /// Clears every field that holds the *content* of whichever account is
  /// currently active (files/photos/trash/shares/recent/service) - shared
  /// by [_activateAccount] (about to load a different account's content)
  /// and [removeAccount]'s "no accounts left" path (nothing left to load).
  /// Deliberately does not touch [_isLoggedIn] - that's the caller's call.
  void _clearActiveContent() {
    _items = [];
    _quota = null;
    _activities = [];
    _allMedia = [];
    _isMediaLoading = false;
    _mediaErrorMessage = null;
    _trashItems = [];
    _isTrashLoading = false;
    _trashErrorMessage = null;
    _shares = [];
    _isSharesLoading = false;
    _sharesErrorMessage = null;
    _sharesWithMe = false;
    _recentItems = [];
    _isRecentLoading = false;
    _recentErrorMessage = null;
    _currentFolderPath = '/';
    _pathStack = ['/'];
    _service = null;
  }

  /// The shared engine behind switching accounts, falling back to another
  /// account after removing the active one, and landing on the newly
  /// created/refreshed account after a login flow completes: tears down
  /// the outgoing account's live content (without ever setting
  /// [isLoggedIn] false - see below), then loads the target account's own
  /// prefs and credentials.
  ///
  /// Non-goal, by design: no simultaneous multi-account state. This is a
  /// full teardown-and-reload of the active session every time, exactly
  /// like today's single-account [logout] already did - just without
  /// touching any *other* saved account's stored credentials/prefs.
  Future<void> _activateAccount(String accountId) async {
    // Invalidates any fetch still in flight for the account being left, so
    // a slow response can't land in the new account's state - see the
    // `gen != _sessionGeneration` checks in refreshData/fetchAllMedia/
    // fetchTrash/fetchShares/fetchRecent/_applyCredentialsForAccount.
    _sessionGeneration++;
    // A pending "add account" flow can't stay pending through a manual
    // switch/cycle - simplicity over blocking the gesture.
    if (_loginFlowStatus != LoginFlowStatus.idle) cancelLoginFlow();

    _cacheRefreshTimer?.cancel();
    _directoryCache.clear();
    _clearActiveContent();
    // Not `_isLoggedIn = false` - that would bounce main.dart's root
    // routing through LoginView mid-switch. Each tab already shows its own
    // spinner from `_isLoading`/`_isXLoading`, so this alone is enough to
    // avoid flashing the outgoing account's stale content.
    _isLoading = true;
    notifyListeners();

    _activeAccountId = accountId;
    final prefs = await _prefsFuture;
    await _accountStore.saveActiveAccountId(prefs, accountId);
    _applyAccountPrefs(prefs, accountId);
    notifyListeners();

    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    final password = account == null
        ? null
        : await _accountStore.readPassword(accountId);
    if (account == null || password == null) {
      _isLoading = false;
      _isLoggedIn = false;
      notifyListeners();
      return;
    }

    await _applyCredentialsForAccount(account, password);
    // The active account's Files listing is loaded synchronously above
    // (inside _applyCredentialsForAccount -> refreshData); the other tabs
    // stay mounted across the switch (MainShellView's IndexedStack) so
    // their one-shot initState fetches won't naturally re-run - kick them
    // off here instead.
    unawaited(fetchAllMedia());
    unawaited(fetchTrash());
    unawaited(fetchShares());
    unawaited(fetchRecent());
  }

  /// Switches to an already-saved account. No-op (returns true) if it's
  /// already active and logged in; no-op (returns false) if unknown - but
  /// if [accountId] is nominally "active" while [isLoggedIn] is false (a
  /// session-restore that failed, e.g. transient network trouble at cold
  /// start), this still retries rather than no-op, since that's exactly the
  /// case LoginView's "Continue as" tile exists to recover from. Gated
  /// behind login lock when [lockAccountSwitching] is on. Returns whether
  /// the account ended up logged in, so callers (LoginView's saved-account
  /// tile) can surface a failure - e.g. a stored app password that no
  /// longer works and needs the account removed/re-added.
  Future<bool> switchAccount(String accountId) async {
    if (accountId == _activeAccountId && _isLoggedIn) return true;
    if (!_accounts.any((a) => a.id == accountId)) return false;
    if (!await _passGate(_lockAccountSwitching, 'Unlock to switch accounts')) {
      return false;
    }
    await _activateAccount(accountId);
    return _isLoggedIn;
  }

  Future<SavedAccount?> _cycleAccount(int direction) async {
    if (_accounts.length < 2) return null;
    if (!await _passGate(_lockAccountSwitching, 'Unlock to switch accounts')) {
      return null;
    }
    final currentIndex = _accounts.indexWhere((a) => a.id == _activeAccountId);
    final targetIndex = currentIndex == -1
        ? 0
        : (currentIndex + direction) % _accounts.length;
    final target =
        _accounts[(targetIndex + _accounts.length) % _accounts.length];
    unawaited(_activateAccount(target.id));
    return target;
  }

  /// Cycles to the next/previous saved account (by the order they were
  /// added) - used by the avatar's swipe-up/down quick-switch gesture.
  /// Returns the account it's switching to once any login-lock gate has
  /// passed (the switch's own network verification is still fire-and-forget
  /// after that, same as before), or null if there's fewer than 2 saved
  /// accounts or the gate was not passed.
  Future<SavedAccount?> cycleToNextAccount() => _cycleAccount(1);
  Future<SavedAccount?> cycleToPreviousAccount() => _cycleAccount(-1);

  /// Removes a saved account entirely: its stored password, its
  /// namespaced prefs, and its entry in the saved-accounts list. If it was
  /// the active account, falls back to another saved account, or - if none
  /// remain - deactivates the session (the only path here that sets
  /// [isLoggedIn] false; unlike [logout], there's nothing left to keep).
  Future<void> removeAccount(String accountId) async {
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index == -1) return;
    final wasActive = accountId == _activeAccountId;

    _accounts = [..._accounts]..removeAt(index);
    final prefs = await _prefsFuture;
    await _accountStore.saveAccounts(prefs, _accounts);
    await _accountStore.deletePassword(accountId);
    for (final key in AccountStore.perAccountPrefKeys) {
      await prefs.remove(_accountStore.accountPrefKey(accountId, key));
    }

    if (!wasActive) {
      notifyListeners();
      return;
    }

    if (_accounts.isEmpty) {
      await _deactivateSession();
      return;
    }

    await _activateAccount(_accounts.first.id);
  }

  /// Clears the active session pointer and tears down its content, without
  /// touching any saved account's own data - shared by [logout] (which
  /// deliberately keeps the account around to resume later, no
  /// re-authentication needed) and [removeAccount]'s "nothing left to fall
  /// back to" branch (where the account's data has already been deleted by
  /// the time this runs).
  Future<void> _deactivateSession() async {
    _sessionGeneration++;
    _cacheRefreshTimer?.cancel();
    _directoryCache.clear();
    _clearActiveContent();
    _isLoggedIn = false;
    _serverUrl = '';
    _username = '';
    _password = '';
    _activeAccountId = null;
    final prefs = await _prefsFuture;
    await _accountStore.saveActiveAccountId(prefs, null);
    _applyAccountPrefs(prefs, null);
    _isSyncingNow = false;
    _syncingFileIds = {};
    _syncedFileIds = {};
    _syncConflicts = [];
    notifyListeners();
    unawaited(SyncService.cancel());
  }

  /// Ends the active session but keeps this account saved - unlike
  /// [removeAccount], nothing is deleted (password, prefs, its entry in
  /// [accounts] all remain), so it's available to resume with a single tap
  /// from the login screen's saved-accounts list, no Login Flow v2 needed.
  /// Always lands on the login screen even if other accounts are saved -
  /// deliberately not the same as switching to one of them.
  Future<void> logout() async {
    if (_activeAccountId == null) return;
    await _deactivateSession();
  }

  Future<void> refreshData() async {
    if (!_isLoggedIn || _service == null) {
      debugPrint(
        '[ServerProvider] refreshData skipped: isLoggedIn=$_isLoggedIn, service=${_service != null}',
      );
      return;
    }
    // Captured so a response landing after an account switch mid-flight
    // can recognize it's for an account the user has already left and
    // discard itself instead of overwriting the new account's content.
    final gen = _sessionGeneration;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    debugPrint(
      '[ServerProvider] Refreshing data for path: $_currentFolderPath',
    );

    try {
      final items = await _service!.fetchDirectory(_currentFolderPath);
      if (gen != _sessionGeneration) return;
      _items = items;
      _directoryCache[_currentFolderPath] = _CachedDirectory(
        _items,
        DateTime.now(),
      );
      debugPrint(
        '[ServerProvider] Loaded ${_items.length} items for $_currentFolderPath',
      );
      try {
        _quota = await _service!.fetchUserQuota();
        debugPrint(
          '[ServerProvider] Loaded quota: used=${_quota?.usedBytes}, total=${_quota?.totalBytes}',
        );
      } catch (e) {
        debugPrint('[ServerProvider] Quota fetch warning: $e');
      }
      try {
        _activities = await _service!.fetchActivities();
        debugPrint(
          '[ServerProvider] Loaded ${_activities.length} activity items',
        );
      } catch (e) {
        debugPrint('[ServerProvider] Activity fetch warning: $e');
      }
    } catch (e) {
      if (gen != _sessionGeneration) return;
      debugPrint('[ServerProvider] Error fetching directory: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == _sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<NextcloudItem>> searchFiles(String query) async {
    if (_service == null) return [];
    return _service!.searchFiles(query);
  }

  /// Loads every image/video across the whole account for the Photos tab.
  Future<void> fetchAllMedia() async {
    if (!_isLoggedIn || _service == null) return;
    final gen = _sessionGeneration;

    _isMediaLoading = true;
    _mediaErrorMessage = null;
    notifyListeners();

    try {
      final media = await _service!.fetchAllMedia();
      if (gen != _sessionGeneration) return;
      _allMedia = media;
      debugPrint('[ServerProvider] Loaded ${_allMedia.length} media items');
    } catch (e) {
      if (gen != _sessionGeneration) return;
      debugPrint('[ServerProvider] Error fetching all media: $e');
      _mediaErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == _sessionGeneration) {
        _isMediaLoading = false;
        notifyListeners();
      }
    }
  }

  /// Loads every favorited item across the whole account for the Favorites
  /// tab - see [_allFavorites]'s doc comment for why this is a separate
  /// account-wide fetch rather than a filter over the currently browsed
  /// folder's [_items].
  Future<void> fetchAllFavorites() async {
    if (!_isLoggedIn || _service == null) return;
    final gen = _sessionGeneration;
    _favoritesEverFetched = true;

    _isFavoritesLoading = true;
    _favoritesErrorMessage = null;
    notifyListeners();

    try {
      final favorites = await _service!.fetchFavorites();
      if (gen != _sessionGeneration) return;
      _allFavorites = favorites;
      debugPrint('[ServerProvider] Loaded ${_allFavorites.length} favorites');
    } catch (e) {
      if (gen != _sessionGeneration) return;
      debugPrint('[ServerProvider] Error fetching favorites: $e');
      _favoritesErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == _sessionGeneration) {
        _isFavoritesLoading = false;
        notifyListeners();
      }
    }
  }

  /// Re-syncs [_allFavorites] after a delete/rename/move/copy elsewhere in
  /// the app (Files, Photos, or Favorites itself) - those operations don't
  /// know how to patch [_allFavorites] in place (a move changes an item's
  /// path; WebDAV COPY's handling of custom properties like `oc:favorite`
  /// isn't reliable enough to assume the copy is still favorited), so this
  /// just refetches - but only if Favorites has actually been loaded this
  /// session, so an account that never opens that tab doesn't pay for an
  /// extra request on every edit.
  Future<void> _syncFavoritesIfLoaded() {
    return _favoritesEverFetched ? fetchAllFavorites() : Future.value();
  }

  Future<void> navigateToFolder(String path) async {
    _pathStack.add(path);
    await _navigateTo(path);
  }

  Future<void> navigateUp() async {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      await _navigateTo(_pathStack.last);
    }
  }

  /// Jumps directly to an ancestor folder by its position in [pathStack]
  /// (as tapped from a breadcrumb), trimming everything below it.
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

  /// True if [path]'s cached listing (if any) is still usable under the
  /// current [CachePolicy] - never for [CachePolicy.never], indefinitely
  /// for [CachePolicy.manual], and until it's older than
  /// [cacheIntervalMinutes] for [CachePolicy.interval].
  bool _isCacheFresh(String path) {
    if (_cachePolicy == CachePolicy.never) return false;
    final cached = _directoryCache[path];
    if (cached == null) return false;
    if (_cachePolicy == CachePolicy.manual) return true;
    return DateTime.now().difference(cached.fetchedAt) <
        Duration(minutes: _cacheIntervalMinutes);
  }

  /// Switches the current folder to [path], serving its listing straight
  /// from the cache when that's still fresh (instant, no network call at
  /// all) and only falling back to [refreshData] otherwise.
  Future<void> _navigateTo(String path) async {
    _currentFolderPath = path;
    final cached = _directoryCache[path];
    if (cached != null && _isCacheFresh(path)) {
      debugPrint('[ServerProvider] Serving cached listing for $path');
      _items = cached.items;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    await refreshData();
  }

  /// Persists a per-account browsing pref under its `acct_<id>_`-namespaced
  /// key. No-op if there's no active account (shouldn't normally happen -
  /// these setters are only reachable from screens that require one).
  void _persistAccountPref(
    String baseKey,
    void Function(SharedPreferences prefs, String key) write,
  ) {
    final id = _activeAccountId;
    if (id == null) return;
    _prefsFuture.then(
      (p) => write(p, _accountStore.accountPrefKey(id, baseKey)),
    );
  }

  void setGridView(bool value) {
    if (_isGridView == value) return;
    _isGridView = value;
    notifyListeners();
    _persistAccountPref(_prefGridView, (p, key) => p.setBool(key, value));
  }

  void toggleFavoritesFilterPhotos() {
    _showFavoritesOnlyPhotos = !_showFavoritesOnlyPhotos;
    notifyListeners();
    _persistAccountPref(
      _prefShowFavoritesOnlyPhotos,
      (p, key) => p.setBool(key, _showFavoritesOnlyPhotos),
    );
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
      if (!await _passGate(_lockHiddenFiles, 'Unlock to show hidden files')) {
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

  Future<void> toggleShowHiddenPhotos() async {
    if (!_showHiddenPhotos) {
      if (!await _passGate(_lockHiddenFiles, 'Unlock to show hidden files')) {
        return;
      }
    }
    _showHiddenPhotos = !_showHiddenPhotos;
    notifyListeners();
    _persistAccountPref(
      _prefShowHiddenPhotos,
      (p, key) => p.setBool(key, _showHiddenPhotos),
    );
  }

  void setPhotosSortField(FileSortField field) {
    if (_photosSortField == field) return;
    _photosSortField = field;
    notifyListeners();
    _persistAccountPref(
      _prefSortField,
      (p, key) => p.setString(key, field.name),
    );
  }

  void togglePhotosSortOrder() {
    _photosSortAscending = !_photosSortAscending;
    notifyListeners();
    _persistAccountPref(
      _prefSortAscending,
      (p, key) => p.setBool(key, _photosSortAscending),
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

  void setFilesSortField(FileSortField field) {
    if (filesSortField == field) return;
    _folderSortField[_currentFolderPath] = field;
    notifyListeners();
    _persistFolderSort();
  }

  void toggleFilesSortOrder() {
    _folderSortAscending[_currentFolderPath] = !filesSortAscending;
    notifyListeners();
    _persistFolderSort();
  }

  void _persistSyncedPaths() {
    _persistAccountPref(
      _prefSyncedFolders,
      (p, key) => p.setString(key, jsonEncode(_syncedPaths)),
    );
  }

  bool isPathSynced(String path) => _syncedPaths.contains(path);

  void addSyncedPath(String path) {
    if (_syncedPaths.contains(path)) return;
    _syncedPaths = [..._syncedPaths, path];
    notifyListeners();
    _persistSyncedPaths();
    unawaited(SyncService.reschedule(this));
  }

  void removeSyncedPath(String path) {
    if (!_syncedPaths.contains(path)) return;
    _syncedPaths = _syncedPaths.where((f) => f != path).toList();
    notifyListeners();
    _persistSyncedPaths();
    unawaited(SyncService.reschedule(this));
  }

  void setSyncEverything(bool value) {
    if (_syncEverything == value) return;
    _syncEverything = value;
    notifyListeners();
    _persistAccountPref(_prefSyncEverything, (p, key) => p.setBool(key, value));
    unawaited(SyncService.reschedule(this));
  }

  void setSyncOnCellular(bool value) {
    if (_syncOnCellular == value) return;
    _syncOnCellular = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefSyncOnCellular, value));
    unawaited(SyncService.reschedule(this));
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
      this,
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
    final id = activeAccountId;
    if (id == null) return null;
    final itemPath = item.path.endsWith('/')
        ? item.path.substring(0, item.path.length - 1)
        : item.path;
    final isSynced =
        _syncEverything ||
        _syncedPaths.any((folder) {
          final f = folder.endsWith('/')
              ? folder.substring(0, folder.length - 1)
              : folder;
          return itemPath == f || itemPath.startsWith('$f/');
        });
    if (!isSynced) return null;
    final base = await getExternalStorageDirectory();
    if (base == null) return null;
    final relPath = item.path.startsWith('/')
        ? item.path.substring(1)
        : item.path;
    final file = File(p.join(base.path, 'sync', id, relPath));
    return file.existsSync() ? file.path : null;
  }

  void setTabOrder(List<AppTab> order) {
    _tabOrder = order;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setStringList(_prefTabOrder, order.map((t) => t.name).toList()),
    );
  }

  /// Shows or hides a tab in the bottom nav bar. Refuses to hide the last
  /// remaining visible tab. If the tab being hidden is the current default,
  /// the default falls back to the next visible tab.
  /// Returns null on success, or a user-facing reason the change was
  /// refused (hiding the last visible tab, or showing a 6th).
  String? setTabHidden(AppTab tab, bool hidden) {
    if (hidden) {
      final remaining = _tabOrder
          .where((t) => t != tab && !_hiddenTabs.contains(t))
          .length;
      if (remaining == 0) return 'At least one tab must stay visible';
      _hiddenTabs = {..._hiddenTabs, tab};
      if (_defaultTab == tab) {
        _defaultTab = _tabOrder.firstWhere((t) => !_hiddenTabs.contains(t));
        _prefsFuture.then(
          (p) => p.setString(_prefDefaultTab, _defaultTab.name),
        );
      }
    } else {
      final currentlyVisible = _tabOrder
          .where((t) => !_hiddenTabs.contains(t))
          .length;
      if (currentlyVisible >= maxVisibleTabs) {
        return 'You can only show up to $maxVisibleTabs tabs at once';
      }
      _hiddenTabs = {..._hiddenTabs}..remove(tab);
    }
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setStringList(
        _prefHiddenTabs,
        _hiddenTabs.map((t) => t.name).toList(),
      ),
    );
    return null;
  }

  /// If more than [maxVisibleTabs] end up visible (e.g. a fresh install, or
  /// an existing saved config from before a new tab was added to the app),
  /// hide the overflow automatically rather than exceeding the cap.
  void _enforceMaxVisibleTabs() {
    final visible = _tabOrder.where((t) => !_hiddenTabs.contains(t)).toList();
    if (visible.length <= maxVisibleTabs) return;
    _hiddenTabs = {..._hiddenTabs, ...visible.sublist(maxVisibleTabs)};
    if (_hiddenTabs.contains(_defaultTab)) {
      _defaultTab = _tabOrder.firstWhere((t) => !_hiddenTabs.contains(t));
    }
  }

  void setDefaultTab(AppTab tab) {
    if (_hiddenTabs.contains(tab) || _defaultTab == tab) return;
    _defaultTab = tab;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefDefaultTab, tab.name));
  }

  void setSwipeLeftAction(SwipeAction action) {
    if (_swipeLeftAction == action) return;
    _swipeLeftAction = action;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefSwipeLeftAction, action.name));
  }

  void setSwipeRightAction(SwipeAction action) {
    if (_swipeRightAction == action) return;
    _swipeRightAction = action;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefSwipeRightAction, action.name));
  }

  void setCachePolicy(CachePolicy policy) {
    if (_cachePolicy == policy) return;
    _cachePolicy = policy;
    notifyListeners();
    _persistAccountPref(
      _prefCachePolicy,
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
      _prefCacheIntervalMinutes,
      (p, key) => p.setInt(key, clamped),
    );
    _startCacheRefreshTimerIfNeeded();
  }

  Future<bool> deleteItem(String itemPath) async {
    if (_service == null) return false;
    final success = await _service!.deleteItem(itemPath);
    if (success) {
      _allMedia = _allMedia.where((i) => i.path != itemPath).toList();
      await refreshData();
      await _syncFavoritesIfLoaded();
    }
    return success;
  }

  Future<bool> renameItem(NextcloudItem item, String newName) async {
    if (_service == null) return false;
    final success = await _service!.renameItem(item.path, newName);
    if (success) {
      await refreshData();
      await _syncFavoritesIfLoaded();
    }
    return success;
  }

  /// A destination-picker-only fetch: the current folder listing state
  /// (`items`/`currentFolderPath`/`pathStack`/`_directoryCache`) belongs to
  /// whichever tab is actively browsing (Files), so the Move/Copy
  /// destination picker deliberately doesn't touch any of it - it fetches
  /// listings for its own local navigation state through this instead,
  /// mirroring `searchFiles`'s identical stateless-pass-through shape.
  Future<List<NextcloudItem>> fetchFolderListing(String path) {
    return _service?.fetchDirectory(path) ?? Future.value([]);
  }

  /// True if [destFolderPath] is [folderPath] itself or one of its own
  /// descendants - moving/copying a folder into itself (or a subfolder of
  /// itself) is nonsensical and rejected client-side rather than left to
  /// the server to (maybe) reject.
  bool _isSelfOrDescendant(String destFolderPath, String folderPath) {
    final dest = destFolderPath.endsWith('/')
        ? destFolderPath
        : '$destFolderPath/';
    final folder = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    return dest == folder || dest.startsWith(folder);
  }

  Future<MoveCopyResult> _moveOrCopyItems(
    List<NextcloudItem> items,
    String destFolderPath, {
    required bool copy,
  }) async {
    if (_service == null || items.isEmpty) return const MoveCopyResult();
    for (final item in items) {
      if (item.isFolder && _isSelfOrDescendant(destFolderPath, item.path)) {
        return const MoveCopyResult(
          blockedReason:
              "Can't move a folder into itself or one of its own subfolders",
        );
      }
    }

    var succeeded = 0;
    var failed = 0;
    final conflicts = <MoveCopyConflict>[];
    for (final item in items) {
      final status = copy
          ? await _service!.copyItem(item.path, destFolderPath)
          : await _service!.moveItem(item.path, destFolderPath);
      if (status == 201 || status == 204) {
        succeeded++;
      } else if (status == 412) {
        conflicts.add(MoveCopyConflict(item));
      } else {
        failed++;
      }
    }
    if (succeeded > 0) {
      _directoryCache.clear();
      await refreshData();
      await _syncFavoritesIfLoaded();
    }
    return MoveCopyResult(
      succeeded: succeeded,
      conflicts: conflicts,
      failed: failed,
    );
  }

  /// Moves every item in [items] into [destFolderPath], keeping each
  /// item's own filename. Items that would collide with something already
  /// there come back in [MoveCopyResult.conflicts] rather than failing
  /// outright - resolve those with [resolveConflicts].
  Future<MoveCopyResult> moveItems(
    List<NextcloudItem> items,
    String destFolderPath,
  ) {
    return _moveOrCopyItems(items, destFolderPath, copy: false);
  }

  /// Same as [moveItems] but duplicates rather than relocates.
  Future<MoveCopyResult> copyItems(
    List<NextcloudItem> items,
    String destFolderPath,
  ) {
    return _moveOrCopyItems(items, destFolderPath, copy: true);
  }

  /// Finds the first `name (n).ext` not already in [existing] - `existing`
  /// is mutated as names are claimed, so a batch of "keep both" resolutions
  /// never picks the same generated name twice.
  String _nextAvailableName(String name, Set<String> existing) {
    if (!existing.contains(name)) return name;
    final dotIndex = name.lastIndexOf('.');
    final hasExtension = dotIndex > 0 && dotIndex < name.length - 1;
    final base = hasExtension ? name.substring(0, dotIndex) : name;
    final ext = hasExtension ? name.substring(dotIndex) : '';
    var n = 2;
    while (existing.contains('$base ($n)$ext')) {
      n++;
    }
    return '$base ($n)$ext';
  }

  /// Resolves a previous [moveItems]/[copyItems] call's conflicts per
  /// [choices] (keyed by `item.id`): overwrite the existing item, keep
  /// both (renamed against a fresh listing of [destFolderPath] so two
  /// "keep both" picks in the same batch can't collide with each other),
  /// or skip (left untouched at the source).
  Future<MoveCopyResult> resolveConflicts(
    List<MoveCopyConflict> conflicts,
    String destFolderPath, {
    required bool copy,
    required Map<String, ConflictChoice> choices,
  }) async {
    if (_service == null || conflicts.isEmpty) return const MoveCopyResult();

    final needsKeepBoth = conflicts.any(
      (c) => choices[c.item.id] == ConflictChoice.keepBoth,
    );
    final existingNames = needsKeepBoth
        ? (await fetchFolderListing(destFolderPath)).map((i) => i.name).toSet()
        : <String>{};

    var succeeded = 0;
    var failed = 0;
    for (final conflict in conflicts) {
      final choice = choices[conflict.item.id] ?? ConflictChoice.skip;
      if (choice == ConflictChoice.skip) continue;

      final int status;
      if (choice == ConflictChoice.overwrite) {
        status = copy
            ? await _service!.copyItem(
                conflict.item.path,
                destFolderPath,
                overwrite: true,
              )
            : await _service!.moveItem(
                conflict.item.path,
                destFolderPath,
                overwrite: true,
              );
      } else {
        final newName = _nextAvailableName(conflict.item.name, existingNames);
        existingNames.add(newName);
        status = copy
            ? await _service!.copyItem(
                conflict.item.path,
                destFolderPath,
                newName: newName,
              )
            : await _service!.moveItem(
                conflict.item.path,
                destFolderPath,
                newName: newName,
              );
      }
      if (status == 201 || status == 204) {
        succeeded++;
      } else {
        failed++;
      }
    }
    if (succeeded > 0) {
      _directoryCache.clear();
      await refreshData();
      await _syncFavoritesIfLoaded();
    }
    return MoveCopyResult(succeeded: succeeded, failed: failed);
  }

  Future<void> fetchTrash() async {
    if (!_isLoggedIn || _service == null) return;
    final gen = _sessionGeneration;

    _isTrashLoading = true;
    _trashErrorMessage = null;
    notifyListeners();

    try {
      final trash = await _service!.fetchTrash();
      if (gen != _sessionGeneration) return;
      _trashItems = trash;
    } catch (e) {
      if (gen != _sessionGeneration) return;
      debugPrint('[ServerProvider] Error fetching trash: $e');
      _trashErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == _sessionGeneration) {
        _isTrashLoading = false;
        notifyListeners();
      }
    }
  }

  /// Restores a trashed item (identified by [NextcloudItem.path], the
  /// trash-relative name) back to where it was deleted from.
  Future<bool> restoreTrashItem(NextcloudItem item) async {
    if (_service == null) return false;
    final success = await _service!.restoreTrashItem(item.path);
    if (success) {
      _trashItems = _trashItems.where((i) => i.id != item.id).toList();
      notifyListeners();
    }
    return success;
  }

  /// Permanently deletes a trashed item. Cannot be undone.
  Future<bool> deleteTrashItemForever(NextcloudItem item) async {
    if (_service == null) return false;
    final success = await _service!.deleteTrashItemForever(item.path);
    if (success) {
      _trashItems = _trashItems.where((i) => i.id != item.id).toList();
      notifyListeners();
    }
    return success;
  }

  Future<void> fetchShares() async {
    if (!_isLoggedIn || _service == null) return;
    final gen = _sessionGeneration;

    _isSharesLoading = true;
    _sharesErrorMessage = null;
    notifyListeners();

    try {
      final shares = await _service!.fetchShares(sharedWithMe: _sharesWithMe);
      if (gen != _sessionGeneration) return;
      _shares = shares;
    } catch (e) {
      if (gen != _sessionGeneration) return;
      debugPrint('[ServerProvider] Error fetching shares: $e');
      _sharesErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == _sessionGeneration) {
        _isSharesLoading = false;
        notifyListeners();
      }
    }
  }

  /// Switches between "shared by me" and "shared with me" and refetches.
  void setSharesWithMe(bool value) {
    if (_sharesWithMe == value) return;
    _sharesWithMe = value;
    notifyListeners();
    fetchShares();
  }

  Future<bool> deleteShare(NextcloudShare share) async {
    if (_service == null) return false;
    final success = await _service!.deleteShare(share.id);
    if (success) {
      _shares = _shares.where((s) => s.id != share.id).toList();
      notifyListeners();
    }
    return success;
  }

  Future<void> fetchRecent() async {
    if (!_isLoggedIn || _service == null) return;
    final gen = _sessionGeneration;

    _isRecentLoading = true;
    _recentErrorMessage = null;
    notifyListeners();

    try {
      final recent = await _service!.fetchRecentFiles();
      if (gen != _sessionGeneration) return;
      _recentItems = recent;
    } catch (e) {
      if (gen != _sessionGeneration) return;
      debugPrint('[ServerProvider] Error fetching recent files: $e');
      _recentErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == _sessionGeneration) {
        _isRecentLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> createFolder(String folderName) async {
    if (_service == null) return false;
    final success = await _service!.createFolder(
      _currentFolderPath,
      folderName,
    );
    if (success) {
      await refreshData();
    }
    return success;
  }

  Future<void> toggleItemFavorite(NextcloudItem item) async {
    if (_service == null) return;
    final success = await _service!.toggleFavorite(item.path, item.isFavorite);
    if (success) {
      final updated = item.copyWith(isFavorite: !item.isFavorite);
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index != -1) _items[index] = updated;
      final mediaIndex = _allMedia.indexWhere((i) => i.id == item.id);
      if (mediaIndex != -1) _allMedia[mediaIndex] = updated;
      // Keeps the Favorites tab's own list in sync in place (cheap enough
      // not to need a full refetch, unlike delete/rename/move/copy - see
      // `_syncFavoritesIfLoaded`) - added if newly favorited, removed if
      // un-favorited, since [_allFavorites] should only ever hold
      // favorited items.
      final favIndex = _allFavorites.indexWhere((i) => i.id == item.id);
      if (updated.isFavorite) {
        if (favIndex != -1) {
          _allFavorites[favIndex] = updated;
        } else {
          _allFavorites = [..._allFavorites, updated];
        }
      } else if (favIndex != -1) {
        _allFavorites = [..._allFavorites]..removeAt(favIndex);
      }
      notifyListeners();
    }
  }

  /// Creates a public link share for [item] and returns its URL, or null on
  /// failure (server error, unsupported item, etc).
  Future<String?> createShareLink(NextcloudItem item) async {
    if (_service == null) return null;
    try {
      return await _service!.createPublicShareLink(item.path);
    } catch (e) {
      debugPrint('[ServerProvider] createShareLink failed: $e');
      return null;
    }
  }

  // --- Details sheet: per-item sharing/activity/versions ---
  //
  // These are thin pass-throughs (no stored state, no notifyListeners) -
  // unlike the flat account-wide lists above (`_shares`, `_trashItems`,
  // ...), the data here is transient and scoped to whichever item's
  // Details sheet happens to be open, so it lives in that sheet's own
  // local widget state rather than bloating this provider.

  Future<List<NextcloudShare>> fetchItemShares(NextcloudItem item) async {
    if (_service == null) return [];
    try {
      return await _service!.fetchSharesForPath(item.path);
    } catch (e) {
      debugPrint('[ServerProvider] fetchItemShares failed: $e');
      return [];
    }
  }

  Future<List<NextcloudShare>> fetchInheritedShares(NextcloudItem item) async {
    if (_service == null) return [];
    return _service!.fetchInheritedShares(item.path);
  }

  Future<List<NextcloudSharee>> searchSharees(String query) async {
    if (_service == null) return [];
    try {
      return await _service!.searchSharees(query);
    } catch (e) {
      debugPrint('[ServerProvider] searchSharees failed: $e');
      return [];
    }
  }

  Future<NextcloudShare?> createShare({
    required String path,
    required int shareType,
    String? shareWith,
    String? password,
    DateTime? expireDate,
  }) async {
    if (_service == null) return null;
    try {
      return await _service!.createShare(
        path: path,
        shareType: shareType,
        shareWith: shareWith,
        password: password,
        expireDate: expireDate,
      );
    } catch (e) {
      debugPrint('[ServerProvider] createShare failed: $e');
      return null;
    }
  }

  Future<List<NextcloudActivity>> fetchFileActivity(NextcloudItem item) async {
    if (_service == null) return [];
    return _service!.fetchFileActivity(item.id);
  }

  Future<List<NextcloudFileVersion>> fetchFileVersions(
    NextcloudItem item,
  ) async {
    if (_service == null) return [];
    return _service!.fetchFileVersions(item.id);
  }

  Future<bool> restoreFileVersion(
    NextcloudItem item,
    String versionLabel,
  ) async {
    if (_service == null) return false;
    try {
      return await _service!.restoreFileVersion(item.id, versionLabel);
    } catch (e) {
      debugPrint('[ServerProvider] restoreFileVersion failed: $e');
      return false;
    }
  }

  Future<bool> downloadVersion(
    NextcloudItem item,
    String versionLabel,
    String savePath,
  ) async {
    if (_service == null) return false;
    try {
      await _service!.downloadVersionToFile(item.id, versionLabel, savePath);
      return true;
    } catch (e) {
      debugPrint('[ServerProvider] downloadVersion failed: $e');
      return false;
    }
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    _useDynamicColor = false;
    notifyListeners();
    _prefsFuture.then((p) {
      p.setInt(_prefSeedColor, color.toARGB32());
      p.setBool(_prefUseDynamicColor, false);
    });
  }

  void setUseDynamicColor(bool value) {
    _useDynamicColor = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefUseDynamicColor, value));
  }

  void setAmoledDark(bool value) {
    _amoledDark = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefAmoledDark, value));
  }

  void setMediaProgressBarStyle(MediaProgressBarStyle style) {
    _mediaProgressBarStyle = style;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setString(_prefMediaProgressBarStyle, style.name),
    );
  }

  void setBottomBarOpacity(double value) {
    _bottomBarOpacity = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setDouble(_prefBottomBarOpacity, value));
  }

  void setBottomBarBlur(double value) {
    _bottomBarBlur = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setDouble(_prefBottomBarBlur, value));
  }

  void setTapTabToScrollTop(bool value) {
    _tapTabToScrollTop = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefTapTabToScrollTop, value));
  }

  /// Confirms the device can do local auth and prompts once to enable login
  /// lock. Returns false (leaving lock disabled) if the device has no
  /// biometric/PIN capability or the user cancels/fails the confirmation.
  Future<bool> setupLoginLock() async {
    if (!await AppLockService.isDeviceSupported()) return false;
    final confirmed = await AppLockService.authenticate(
      'Confirm to turn on login lock',
    );
    if (!confirmed) return false;
    _loginLockEnabled = true;
    // Already just authenticated - don't immediately re-prompt behind it.
    _isUnlocked = true;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefLoginLockEnabled, true));
    return true;
  }

  /// Turns login lock off, along with both of its sub-toggles (meaningless
  /// once the base lock is gone). Requires a successful auth first, same as
  /// turning it on - otherwise anyone with momentary access to an unlocked
  /// phone could just switch it off.
  Future<bool> disableLoginLock() async {
    if (!_loginLockEnabled) return true;
    final confirmed = await AppLockService.authenticate(
      'Confirm to turn off login lock',
    );
    if (!confirmed) return false;
    _loginLockEnabled = false;
    _lockAccountSwitching = false;
    _lockHiddenFiles = false;
    _isUnlocked = false;
    notifyListeners();
    _prefsFuture.then((p) {
      p.setBool(_prefLoginLockEnabled, false);
      p.setBool(_prefLockAccountSwitching, false);
      p.setBool(_prefLockHiddenFiles, false);
    });
    return true;
  }

  void setLockAccountSwitching(bool value) {
    if (!_loginLockEnabled) return;
    _lockAccountSwitching = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefLockAccountSwitching, value));
  }

  void setLockHiddenFiles(bool value) {
    if (!_loginLockEnabled) return;
    _lockHiddenFiles = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefLockHiddenFiles, value));
  }

  /// Called by the lock screen. Returns whether it actually unlocked.
  Future<bool> attemptUnlock() async {
    final success = await AppLockService.authenticate('Unlock Noo');
    if (success) {
      _isUnlocked = true;
      notifyListeners();
    }
    return success;
  }

  /// Prompts for auth if [gate] is on and login lock is configured;
  /// returns true immediately (no prompt) otherwise. Shared by the
  /// account-switching and hidden-files gates below.
  Future<bool> _passGate(bool gate, String reason) async {
    if (!_loginLockEnabled || !gate) return true;
    return AppLockService.authenticate(reason);
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefThemeMode, mode.name));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    _cacheRefreshTimer?.cancel();
    _syncStatusSub?.cancel();
    super.dispose();
  }
}
