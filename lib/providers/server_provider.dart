import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_file_version.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../models/nextcloud_sharee.dart';
import '../services/login_flow_service.dart';
import '../services/nextcloud_service.dart';
import '../theme/app_theme.dart';

enum LoginFlowStatus { idle, initiating, awaitingBrowser, error }

enum FileSortField { name, dateCreated, dateModified, size }

/// Which storage a listing shows — always exactly one, like the list/grid
/// view toggle, not an optional filter.
enum StorageScope { cloud, external }

/// What swiping a Files list-view item left/right does, user-configurable
/// in Settings.
enum SwipeAction { none, favorite, delete, share }

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

/// The two linear progress indicator styles Material 3 offers for the video
/// player's seek bar: an animated travelling-wave line (matching Android's
/// current media player), or a plain flat classic bar.
enum MediaProgressBarStyle { wavy, classic }

class ServerProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _storage = FlutterSecureStorage();
  static const _keyServerUrl = 'nc_server_url';
  static const _keyLoginName = 'nc_login_name';
  static const _keyAppPassword = 'nc_app_password';

  // Cached UI settings/toggles (SharedPreferences keys)
  static const _prefThemeMode = 'ui_theme_mode';
  static const _prefUseDynamicColor = 'ui_use_dynamic_color';
  static const _prefSeedColor = 'ui_seed_color';
  static const _prefBottomBarOpacity = 'ui_bottom_bar_opacity';
  static const _prefBottomBarBlur = 'ui_bottom_bar_blur';
  static const _prefGridView = 'ui_grid_view';
  static const _prefShowFavoritesOnlyFiles = 'ui_show_favorites_only';
  static const _prefShowFavoritesOnlyPhotos = 'ui_show_favorites_only_photos';
  static const _prefStorageScope = 'ui_storage_scope';
  static const _prefShowHiddenFiles = 'ui_show_hidden';
  static const _prefShowHiddenPhotos = 'ui_show_hidden_photos';
  static const _prefSortField = 'ui_sort_field';
  static const _prefSortAscending = 'ui_sort_ascending';
  static const _prefTabOrder = 'ui_tab_order';
  static const _prefHiddenTabs = 'ui_hidden_tabs';
  static const _prefDefaultTab = 'ui_default_tab';
  static const _prefSwipeLeftAction = 'ui_swipe_left_action';
  static const _prefSwipeRightAction = 'ui_swipe_right_action';
  static const _prefAmoledDark = 'ui_amoled_dark';
  static const _prefMediaProgressBarStyle = 'ui_media_progress_bar_style';
  static const _prefCachePolicy = 'ui_cache_policy';
  static const _prefCacheIntervalMinutes = 'ui_cache_interval_minutes';

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

  // Navigation state
  String _currentFolderPath = '/';
  List<String> _pathStack = ['/'];
  bool _isGridView = false;
  bool _showFavoritesOnlyFiles = false;
  bool _showFavoritesOnlyPhotos = false;
  StorageScope _storageScope = StorageScope.cloud;
  bool _showHiddenFiles = false;
  bool _showHiddenPhotos = false;
  FileSortField _sortField = FileSortField.name;
  bool _sortAscending = true;

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

  ServerProvider() {
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
    _loadPreferences();
  }

  /// Starts/stops the periodic folder-listing refresh as the app leaves and
  /// returns to the foreground - only relevant under [CachePolicy.interval].
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startCacheRefreshTimerIfNeeded();
    } else if (state == AppLifecycleState.paused) {
      _cacheRefreshTimer?.cancel();
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

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  MediaProgressBarStyle get mediaProgressBarStyle => _mediaProgressBarStyle;
  double get bottomBarOpacity => _bottomBarOpacity;
  double get bottomBarBlur => _bottomBarBlur;

  String get currentFolderPath => _currentFolderPath;
  List<String> get pathStack => _pathStack;
  bool get isGridView => _isGridView;
  bool get showFavoritesOnlyFiles => _showFavoritesOnlyFiles;
  bool get showFavoritesOnlyPhotos => _showFavoritesOnlyPhotos;
  StorageScope get storageScope => _storageScope;
  bool get showHiddenFiles => _showHiddenFiles;
  bool get showHiddenPhotos => _showHiddenPhotos;
  FileSortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;
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

  int _compareItems(NextcloudItem a, NextcloudItem b) {
    switch (_sortField) {
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

  /// Applies the shared favorites-only/hidden-files/storage-scope toggles,
  /// used by both [items] and [photoItems]. `showFavoritesOnly`/`showHidden`
  /// are passed in separately since Files and Photos each have their own
  /// independent favorites-only and hidden-files toggles.
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

  List<NextcloudItem> get items {
    final filtered = _applyCommonFilters(
      _items,
      showFavoritesOnly: _showFavoritesOnlyFiles,
      showHidden: _showHiddenFiles,
    );

    final folders = filtered.where((i) => i.isFolder).toList()
      ..sort(_compareItems);
    final files = filtered.where((i) => !i.isFolder).toList()
      ..sort(_compareItems);
    return _sortAscending
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
    )..sort(_compareItems);
    return _sortAscending ? filtered : filtered.reversed.toList();
  }

  bool get isMediaLoading => _isMediaLoading;
  String? get mediaErrorMessage => _mediaErrorMessage;

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
      final server = await _storage.read(key: _keyServerUrl);
      final loginName = await _storage.read(key: _keyLoginName);
      final appPassword = await _storage.read(key: _keyAppPassword);

      if (server != null && loginName != null && appPassword != null) {
        await _applyCredentials(server, loginName, appPassword, persist: false);
      }
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
      _isGridView = prefs.getBool(_prefGridView) ?? _isGridView;
      _showFavoritesOnlyFiles =
          prefs.getBool(_prefShowFavoritesOnlyFiles) ?? _showFavoritesOnlyFiles;
      _showFavoritesOnlyPhotos =
          prefs.getBool(_prefShowFavoritesOnlyPhotos) ??
          _showFavoritesOnlyPhotos;
      final storageScopeName = prefs.getString(_prefStorageScope);
      if (storageScopeName != null) {
        _storageScope = StorageScope.values.firstWhere(
          (s) => s.name == storageScopeName,
          orElse: () => StorageScope.cloud,
        );
      }
      _showHiddenFiles =
          prefs.getBool(_prefShowHiddenFiles) ?? _showHiddenFiles;
      _showHiddenPhotos =
          prefs.getBool(_prefShowHiddenPhotos) ?? _showHiddenPhotos;
      final sortFieldName = prefs.getString(_prefSortField);
      if (sortFieldName != null) {
        _sortField = FileSortField.values.firstWhere(
          (f) => f.name == sortFieldName,
          orElse: () => FileSortField.name,
        );
      }
      _sortAscending = prefs.getBool(_prefSortAscending) ?? _sortAscending;

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
      final cachePolicyName = prefs.getString(_prefCachePolicy);
      if (cachePolicyName != null) {
        _cachePolicy = CachePolicy.values.firstWhere(
          (c) => c.name == cachePolicyName,
          orElse: () => _cachePolicy,
        );
      }
      _cacheIntervalMinutes =
          prefs.getInt(_prefCacheIntervalMinutes) ?? _cacheIntervalMinutes;
      _startCacheRefreshTimerIfNeeded();

      notifyListeners();
    } catch (e) {
      debugPrint('[ServerProvider] Preference restore failed: $e');
    }
  }

  Future<void> _persistCredentials(
    String server,
    String loginName,
    String appPassword,
  ) async {
    await _storage.write(key: _keyServerUrl, value: server);
    await _storage.write(key: _keyLoginName, value: loginName);
    await _storage.write(key: _keyAppPassword, value: appPassword);
  }

  Future<void> _clearPersistedCredentials() async {
    await _storage.delete(key: _keyServerUrl);
    await _storage.delete(key: _keyLoginName);
    await _storage.delete(key: _keyAppPassword);
  }

  Future<bool> _applyCredentials(
    String serverUrl,
    String username,
    String appPassword, {
    bool persist = true,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _serverUrl = serverUrl;
    _username = username;
    _password = appPassword;

    _service = NextcloudService(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
    );

    try {
      final success = await _service!.testConnection();
      if (success) {
        _isLoggedIn = true;
        _currentFolderPath = '/';
        _pathStack = ['/'];
        if (persist) {
          await _persistCredentials(_serverUrl, _username, _password);
        }
        _startCacheRefreshTimerIfNeeded();
        await refreshData();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      if (!persist) {
        // A previously-saved app password no longer works; drop it.
        await _clearPersistedCredentials();
      }
    }

    _isLoggedIn = false;
    _service = null;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Starts Nextcloud Login Flow v2: asks the server for a one-time login
  /// URL, opens it in the system browser, then polls until the user
  /// authorizes and the server hands back a scoped app password. The app
  /// never sees the user's real password.
  Future<void> startLoginFlow(String serverUrl) async {
    _loginFlowStatus = LoginFlowStatus.initiating;
    _errorMessage = null;
    notifyListeners();

    try {
      final init = await LoginFlowService.initiate(serverUrl);
      _pendingLoginUrl = init.loginUrl;

      // Chrome Custom Tabs (inAppBrowserView): real Chrome, so the saved
      // passwords/autofill service works normally, unlike Flutter's own
      // embedded web view. The tradeoff is that - like Login Flow v2's
      // grant page itself, which never redirects back into the app on its
      // own (unlike the old nc:// Flow v1) - a Custom Tab belongs to
      // Chrome's own task, not ours, so we have no way to close it
      // automatically once polling below detects success; the user has to
      // switch back manually, same as with the external browser.
      final opened = await launchUrl(
        init.loginUrl,
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) {
        throw Exception('Could not open the browser for login.');
      }

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
            await _applyCredentials(
              result.serverUrl,
              result.loginName,
              result.appPassword,
            );
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

  Future<void> reopenLoginBrowser() async {
    if (_pendingLoginUrl != null) {
      await launchUrl(_pendingLoginUrl!, mode: LaunchMode.inAppBrowserView);
    }
  }

  void cancelLoginFlow({String? errorMessage}) {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    _pendingLoginUrl = null;
    _loginFlowStatus = errorMessage != null
        ? LoginFlowStatus.error
        : LoginFlowStatus.idle;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _serverUrl = '';
    _username = '';
    _password = '';
    _items = [];
    _quota = null;
    _activities = [];
    _allMedia = [];
    _trashItems = [];
    _shares = [];
    _recentItems = [];
    _service = null;
    _directoryCache.clear();
    _cacheRefreshTimer?.cancel();
    await _clearPersistedCredentials();
    notifyListeners();
  }

  Future<void> refreshData() async {
    if (!_isLoggedIn || _service == null) {
      debugPrint(
        '[ServerProvider] refreshData skipped: isLoggedIn=$_isLoggedIn, service=${_service != null}',
      );
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    debugPrint(
      '[ServerProvider] Refreshing data for path: $_currentFolderPath',
    );

    try {
      _items = await _service!.fetchDirectory(_currentFolderPath);
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
      debugPrint('[ServerProvider] Error fetching directory: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<NextcloudItem>> searchFiles(String query) async {
    if (_service == null) return [];
    return _service!.searchFiles(query);
  }

  /// Loads every image/video across the whole account for the Photos tab.
  Future<void> fetchAllMedia() async {
    if (!_isLoggedIn || _service == null) return;

    _isMediaLoading = true;
    _mediaErrorMessage = null;
    notifyListeners();

    try {
      _allMedia = await _service!.fetchAllMedia();
      debugPrint('[ServerProvider] Loaded ${_allMedia.length} media items');
    } catch (e) {
      debugPrint('[ServerProvider] Error fetching all media: $e');
      _mediaErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isMediaLoading = false;
      notifyListeners();
    }
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

  void setGridView(bool value) {
    if (_isGridView == value) return;
    _isGridView = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefGridView, value));
  }

  void toggleFavoritesFilterFiles() {
    _showFavoritesOnlyFiles = !_showFavoritesOnlyFiles;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setBool(_prefShowFavoritesOnlyFiles, _showFavoritesOnlyFiles),
    );
  }

  void toggleFavoritesFilterPhotos() {
    _showFavoritesOnlyPhotos = !_showFavoritesOnlyPhotos;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setBool(_prefShowFavoritesOnlyPhotos, _showFavoritesOnlyPhotos),
    );
  }

  void setStorageScope(StorageScope scope) {
    if (_storageScope == scope) return;
    _storageScope = scope;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefStorageScope, scope.name));
  }

  void toggleShowHiddenFiles() {
    _showHiddenFiles = !_showHiddenFiles;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefShowHiddenFiles, _showHiddenFiles));
  }

  void toggleShowHiddenPhotos() {
    _showHiddenPhotos = !_showHiddenPhotos;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setBool(_prefShowHiddenPhotos, _showHiddenPhotos),
    );
  }

  void setSortField(FileSortField field) {
    if (_sortField == field) return;
    _sortField = field;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefSortField, field.name));
  }

  void toggleSortOrder() {
    _sortAscending = !_sortAscending;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefSortAscending, _sortAscending));
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
    _prefsFuture.then((p) => p.setString(_prefCachePolicy, policy.name));
    _startCacheRefreshTimerIfNeeded();
  }

  void setCacheIntervalMinutes(int minutes) {
    final clamped = minutes.clamp(1, 60);
    if (_cacheIntervalMinutes == clamped) return;
    _cacheIntervalMinutes = clamped;
    notifyListeners();
    _prefsFuture.then((p) => p.setInt(_prefCacheIntervalMinutes, clamped));
    _startCacheRefreshTimerIfNeeded();
  }

  Future<bool> uploadFileFromPath(
    String name,
    String localFilePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (_service == null) return false;
    final success = await _service!.uploadFileFromPath(
      _currentFolderPath,
      name,
      localFilePath,
      onProgress: onProgress,
    );
    if (success) {
      await refreshData();
    }
    return success;
  }

  Future<bool> deleteItem(String itemPath) async {
    if (_service == null) return false;
    final success = await _service!.deleteItem(itemPath);
    if (success) {
      _allMedia = _allMedia.where((i) => i.path != itemPath).toList();
      await refreshData();
    }
    return success;
  }

  Future<void> fetchTrash() async {
    if (!_isLoggedIn || _service == null) return;

    _isTrashLoading = true;
    _trashErrorMessage = null;
    notifyListeners();

    try {
      _trashItems = await _service!.fetchTrash();
    } catch (e) {
      debugPrint('[ServerProvider] Error fetching trash: $e');
      _trashErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isTrashLoading = false;
      notifyListeners();
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

    _isSharesLoading = true;
    _sharesErrorMessage = null;
    notifyListeners();

    try {
      _shares = await _service!.fetchShares(sharedWithMe: _sharesWithMe);
    } catch (e) {
      debugPrint('[ServerProvider] Error fetching shares: $e');
      _sharesErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isSharesLoading = false;
      notifyListeners();
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

    _isRecentLoading = true;
    _recentErrorMessage = null;
    notifyListeners();

    try {
      _recentItems = await _service!.fetchRecentFiles();
    } catch (e) {
      debugPrint('[ServerProvider] Error fetching recent files: $e');
      _recentErrorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isRecentLoading = false;
      notifyListeners();
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
    super.dispose();
  }
}
