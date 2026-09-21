import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nextcloud_item.dart';
import 'files_controller.dart';
import 'session_controller.dart';

/// The Photos tab: every image/video across the whole account (not just
/// the currently browsed folder - see [fetchAllMedia]). Depends on
/// [FilesController] only for the shared [StorageScope] toggle and
/// [FilesController.applyCommonFilters] - Photos' own favorites-only/
/// hidden toggles are independent of Files', but the storage-scope split
/// (cloud vs external) is one shared setting across every tab.
class PhotosController extends ChangeNotifier {
  final SessionController session;
  final FilesController files;

  static const _prefShowFavoritesOnlyPhotos = 'ui_show_favorites_only_photos';
  static const _prefShowHiddenPhotos = 'ui_show_hidden_photos';
  static const _prefSortField = 'ui_sort_field';
  static const _prefSortAscending = 'ui_sort_ascending';

  List<NextcloudItem> _allMedia = [];
  bool _isLoading = false;
  String? _errorMessage;

  bool _showFavoritesOnly = false;
  bool _showHidden = false;
  FileSortField _sortField = FileSortField.name;
  bool _sortAscending = true;

  PhotosController(this.session, this.files) {
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get showFavoritesOnly => _showFavoritesOnly;
  bool get showHidden => _showHidden;
  FileSortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;

  /// All images/videos across the whole account (not just the currently
  /// browsed folder) — see [fetchAllMedia].
  List<NextcloudItem> get items {
    final media = _allMedia.where((i) => i.isMedia).toList();
    final filtered = files.applyCommonFilters(
      media,
      showFavoritesOnly: _showFavoritesOnly,
      showHidden: _showHidden,
    )..sort((a, b) => _compare(a, b));
    return _sortAscending ? filtered : filtered.reversed.toList();
  }

  int _compare(NextcloudItem a, NextcloudItem b) {
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

  void _onAccountCleared() {
    _allMedia = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _onAccountActivated() async {
    final id = session.activeAccountId;
    if (id != null) {
      // Wrapped so a single bad/mistyped stored pref value can't
      // silently skip fetchAllMedia() below and leave Photos permanently
      // empty on this activation with no error surfaced anywhere - see
      // FilesController._onAccountActivated's identical guard for the
      // real incident this mirrors.
      try {
        final prefs = await session.prefsFuture;
        String k(String base) => session.accountStore.accountPrefKey(id, base);
        _showFavoritesOnly =
            prefs.getBool(k(_prefShowFavoritesOnlyPhotos)) ?? false;
        _showHidden = prefs.getBool(k(_prefShowHiddenPhotos)) ?? false;
        final sortFieldName = prefs.getString(k(_prefSortField));
        _sortField = FileSortField.values.firstWhere(
          (f) => f.name == sortFieldName,
          orElse: () => FileSortField.name,
        );
        _sortAscending = prefs.getBool(k(_prefSortAscending)) ?? true;
        notifyListeners();
      } catch (e) {
        debugPrint('[PhotosController] Account-activation prefs restore failed: $e');
      }
    }
    unawaited(fetchAllMedia());
  }

  /// Loads every image/video across the whole account for the Photos tab.
  Future<void> fetchAllMedia() async {
    final service = session.service;
    if (!session.isLoggedIn || service == null) return;
    final gen = session.sessionGeneration;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final media = await service.fetchAllMedia();
      if (gen != session.sessionGeneration) return;
      _allMedia = media;
      debugPrint('[PhotosController] Loaded ${_allMedia.length} media items');
    } catch (e) {
      if (gen != session.sessionGeneration) return;
      debugPrint('[PhotosController] Error fetching all media: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == session.sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

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

  void toggleFavoritesFilter() {
    _showFavoritesOnly = !_showFavoritesOnly;
    notifyListeners();
    _persistAccountPref(
      _prefShowFavoritesOnlyPhotos,
      (p, key) => p.setBool(key, _showFavoritesOnly),
    );
  }

  Future<void> toggleShowHidden() async {
    if (!_showHidden) {
      if (!await session.passGate(
        session.lockHiddenFiles,
        'Unlock to show hidden files',
      )) {
        return;
      }
    }
    _showHidden = !_showHidden;
    notifyListeners();
    _persistAccountPref(
      _prefShowHiddenPhotos,
      (p, key) => p.setBool(key, _showHidden),
    );
  }

  void setSortField(FileSortField field) {
    if (_sortField == field) return;
    _sortField = field;
    notifyListeners();
    _persistAccountPref(_prefSortField, (p, key) => p.setString(key, field.name));
  }

  void toggleSortOrder() {
    _sortAscending = !_sortAscending;
    notifyListeners();
    _persistAccountPref(
      _prefSortAscending,
      (p, key) => p.setBool(key, _sortAscending),
    );
  }

  /// Removes an item by path (a delete elsewhere in the app) - called by
  /// `ItemOperations.deleteItem` after a successful server call.
  void applyDelete(String path) {
    _allMedia = _allMedia.where((i) => i.path != path).toList();
    notifyListeners();
  }

  /// Patches a favorite-toggle result into [items]' source list in place -
  /// called by `ItemOperations.toggleItemFavorite` after a successful
  /// server call.
  void applyFavoriteToggle(NextcloudItem updated) {
    final index = _allMedia.indexWhere((i) => i.id == updated.id);
    if (index != -1) _allMedia[index] = updated;
    notifyListeners();
  }
}
