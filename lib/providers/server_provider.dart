import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/nextcloud_item.dart';
import '../services/login_flow_service.dart';
import '../services/nextcloud_service.dart';
import '../theme/app_theme.dart';

enum LoginFlowStatus { idle, initiating, awaitingBrowser, error }

enum FileSortField { name, dateCreated, dateModified, size }

class ServerProvider extends ChangeNotifier {
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
  static const _prefShowFavoritesOnly = 'ui_show_favorites_only';
  static const _prefShowExternalOnly = 'ui_show_external_only';
  static const _prefShowHidden = 'ui_show_hidden';
  static const _prefSortField = 'ui_sort_field';
  static const _prefSortAscending = 'ui_sort_ascending';

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

  // UI settings
  double _bottomBarOpacity = 0.55;
  double _bottomBarBlur = 28;

  // Navigation state
  String _currentFolderPath = '/';
  List<String> _pathStack = ['/'];
  bool _isGridView = false;
  bool _showFavoritesOnly = false;
  bool _showExternalOnly = false;
  bool _showHidden = false;
  FileSortField _sortField = FileSortField.name;
  bool _sortAscending = true;

  // Data state
  List<NextcloudItem> _items = [];
  NextcloudUserQuota? _quota;
  List<NextcloudActivity> _activities = [];

  NextcloudService? _service;

  ServerProvider() {
    _restoreSession();
    _loadPreferences();
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
  double get bottomBarOpacity => _bottomBarOpacity;
  double get bottomBarBlur => _bottomBarBlur;

  String get currentFolderPath => _currentFolderPath;
  List<String> get pathStack => _pathStack;
  bool get isGridView => _isGridView;
  bool get showFavoritesOnly => _showFavoritesOnly;
  bool get showExternalOnly => _showExternalOnly;
  bool get showHidden => _showHidden;
  FileSortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;

  /// Exposes the active service so views can build file URLs, auth headers,
  /// and trigger downloads/previews directly.
  NextcloudService? get service => _service;

  List<NextcloudItem> get items {
    var filtered = _items;
    if (_showFavoritesOnly) {
      filtered = filtered.where((item) => item.isFavorite).toList();
    }
    if (_showExternalOnly) {
      filtered = filtered.where((item) => item.isExternalStorage).toList();
    }
    if (!_showHidden) {
      filtered = filtered.where((item) => !item.name.startsWith('.')).toList();
    }

    int compare(NextcloudItem a, NextcloudItem b) {
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

    final folders = filtered.where((i) => i.isFolder).toList()..sort(compare);
    final files = filtered.where((i) => !i.isFolder).toList()..sort(compare);
    return _sortAscending
        ? [...folders, ...files]
        : [...folders.reversed, ...files.reversed];
  }

  List<NextcloudItem> get photoItems {
    return _items
        .where((i) => i.isMedia || i.type == NextcloudItemType.image)
        .toList();
  }

  NextcloudUserQuota? get quota => _quota;
  List<NextcloudActivity> get activities => _activities;

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
      final seedColorValue = prefs.getInt(_prefSeedColor);
      if (seedColorValue != null) _seedColor = Color(seedColorValue);
      _bottomBarOpacity =
          prefs.getDouble(_prefBottomBarOpacity) ?? _bottomBarOpacity;
      _bottomBarBlur = prefs.getDouble(_prefBottomBarBlur) ?? _bottomBarBlur;
      _isGridView = prefs.getBool(_prefGridView) ?? _isGridView;
      _showFavoritesOnly =
          prefs.getBool(_prefShowFavoritesOnly) ?? _showFavoritesOnly;
      _showExternalOnly =
          prefs.getBool(_prefShowExternalOnly) ?? _showExternalOnly;
      _showHidden = prefs.getBool(_prefShowHidden) ?? _showHidden;
      final sortFieldName = prefs.getString(_prefSortField);
      if (sortFieldName != null) {
        _sortField = FileSortField.values.firstWhere(
          (f) => f.name == sortFieldName,
          orElse: () => FileSortField.name,
        );
      }
      _sortAscending = prefs.getBool(_prefSortAscending) ?? _sortAscending;

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

      final opened = await launchUrl(
        init.loginUrl,
        mode: LaunchMode.externalApplication,
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
      await launchUrl(_pendingLoginUrl!, mode: LaunchMode.externalApplication);
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
    _service = null;
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

  Future<void> navigateToFolder(String path) async {
    _currentFolderPath = path;
    _pathStack.add(path);
    await refreshData();
  }

  Future<void> navigateUp() async {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      _currentFolderPath = _pathStack.last;
      await refreshData();
    }
  }

  /// Jumps directly to an ancestor folder by its position in [pathStack]
  /// (as tapped from a breadcrumb), trimming everything below it.
  Future<void> navigateToPathIndex(int index) async {
    if (index < 0 || index >= _pathStack.length - 1) return;
    _pathStack = _pathStack.sublist(0, index + 1);
    _currentFolderPath = _pathStack.last;
    await refreshData();
  }

  void setGridView(bool value) {
    if (_isGridView == value) return;
    _isGridView = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefGridView, value));
  }

  void toggleFavoritesFilter() {
    _showFavoritesOnly = !_showFavoritesOnly;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setBool(_prefShowFavoritesOnly, _showFavoritesOnly),
    );
  }

  void toggleExternalStorageFilter() {
    _showExternalOnly = !_showExternalOnly;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setBool(_prefShowExternalOnly, _showExternalOnly),
    );
  }

  void toggleShowHidden() {
    _showHidden = !_showHidden;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefShowHidden, _showHidden));
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
      await refreshData();
    }
    return success;
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
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        _items[index] = item.copyWith(isFavorite: !item.isFavorite);
        notifyListeners();
      }
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
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    super.dispose();
  }
}
