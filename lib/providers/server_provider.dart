import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import '../services/nextcloud_service.dart';
import '../theme/app_theme.dart';

class ServerProvider extends ChangeNotifier {
  String _serverUrl = '';
  String _username = '';
  String _password = '';
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Theme state
  Color _seedColor = AppTheme.defaultNextcloudBlue;
  ThemeMode _themeMode = ThemeMode.system;

  // Navigation state
  String _currentFolderPath = '/';
  List<String> _pathStack = ['/'];
  bool _isGridView = false;
  String _searchQuery = '';
  bool _showFavoritesOnly = false;

  // Data state
  List<NextcloudItem> _items = [];
  NextcloudUserQuota? _quota;
  List<NextcloudActivity> _activities = [];

  NextcloudService? _service;

  ServerProvider() {
    _loadSavedSession();
  }

  // Getters
  String get serverUrl => _serverUrl;
  String get username => _username;
  String get password => _password;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  String get currentFolderPath => _currentFolderPath;
  List<String> get pathStack => _pathStack;
  bool get isGridView => _isGridView;
  String get searchQuery => _searchQuery;
  bool get showFavoritesOnly => _showFavoritesOnly;

  List<NextcloudItem> get items {
    var filtered = _items;
    if (_showFavoritesOnly) {
      filtered = filtered.where((item) => item.isFavorite).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((item) => item.name.toLowerCase().contains(query)).toList();
    }
    return filtered;
  }

  List<NextcloudItem> get photoItems {
    final allMedia = _items.where((i) => i.isMedia || i.type == NextcloudItemType.image).toList();
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      return allMedia.where((i) => i.name.toLowerCase().contains(query)).toList();
    }
    return allMedia;
  }

  NextcloudUserQuota? get quota => _quota;
  List<NextcloudActivity> get activities => _activities;

  Future<void> _loadSavedSession() async {
    try {
      final file = File('.nextcloud_session.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data['serverUrl'] != null && data['username'] != null && data['password'] != null) {
          final sUrl = data['serverUrl'].toString();
          final uName = data['username'].toString();
          final pWord = data['password'].toString();

          if (sUrl.isNotEmpty && uName.isNotEmpty && pWord.isNotEmpty) {
            await login(serverUrl: sUrl, username: uName, password: pWord, saveSession: false);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSession() async {
    try {
      final file = File('.nextcloud_session.json');
      final data = {
        'serverUrl': _serverUrl,
        'username': _username,
        'password': _password,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _clearSavedSession() async {
    try {
      final file = File('.nextcloud_session.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
    bool saveSession = true,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _serverUrl = serverUrl;
    _username = username;
    _password = password;

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
        if (saveSession) {
          await _saveSession();
        }
        await refreshData();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    }

    _isLoggedIn = false;
    _isLoading = false;
    notifyListeners();
    return false;
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
    await _clearSavedSession();
    notifyListeners();
  }

  Future<void> refreshData() async {
    if (!_isLoggedIn || _service == null) {
      debugPrint('[ServerProvider] refreshData skipped: isLoggedIn=$_isLoggedIn, service=${_service != null}');
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    debugPrint('[ServerProvider] Refreshing data for path: $_currentFolderPath');

    try {
      _items = await _service!.fetchDirectory(_currentFolderPath);
      debugPrint('[ServerProvider] Loaded ${_items.length} items for $_currentFolderPath');
      try {
        _quota = await _service!.fetchUserQuota();
        debugPrint('[ServerProvider] Loaded quota: used=${_quota?.usedBytes}, total=${_quota?.totalBytes}');
      } catch (e) {
        debugPrint('[ServerProvider] Quota fetch warning: $e');
      }
      try {
        _activities = await _service!.fetchActivities();
        debugPrint('[ServerProvider] Loaded ${_activities.length} activity items');
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

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleFavoritesFilter() {
    _showFavoritesOnly = !_showFavoritesOnly;
    notifyListeners();
  }

  Future<bool> uploadFile(String name, Uint8List bytes) async {
    if (_service == null) return false;
    final success = await _service!.uploadFile(_currentFolderPath, name, bytes);
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
    final success = await _service!.createFolder(_currentFolderPath, folderName);
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
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}
