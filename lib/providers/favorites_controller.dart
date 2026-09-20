import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import 'files_controller.dart';
import 'session_controller.dart';

/// The Favorites tab: every favorited item across the whole account (not
/// scoped to any one folder - a favorited item several folders deep still
/// shows up regardless of whether its parent folders are themselves
/// favorited, which is exactly why this is its own account-wide fetch
/// rather than a filter toggle over whatever folder Files happens to be
/// browsing - see `server.md`'s Favorites section for the full history of
/// why a filter-toggle approach was tried and reverted). Depends on
/// [FilesController] to reuse its exact
/// display prefs (hidden/type-filter/sort/storage-scope) via
/// [FilesController.applyFilesDisplayPrefs] - deliberately shared rather
/// than a second parallel settings dimension.
class FavoritesController extends ChangeNotifier {
  final SessionController session;
  final FilesController files;

  List<NextcloudItem> _allFavorites = [];
  bool _isLoading = false;
  String? _errorMessage;
  // True once fetchAll has run at least once (i.e. the Favorites tab has
  // been visited) - delete/rename/move/copy re-sync afterward, but only
  // when it's actually been loaded, so those actions don't pay for an
  // extra network round-trip on every Files/Photos edit for an account
  // that's never opened the Favorites tab this session.
  bool _everFetched = false;

  FavoritesController(this.session, this.files) {
    session.addAccountClearedListener(_onAccountCleared);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// The Favorites tab's content, run through the exact same hidden/type-
  /// filter/sort/storage-scope display prefs as the Files tab. No
  /// favorites filter needed here - the source list is already
  /// all-favorites.
  List<NextcloudItem> get items => files.applyFilesDisplayPrefs(_allFavorites);

  void _onAccountCleared() {
    _allFavorites = [];
    _isLoading = false;
    _errorMessage = null;
    _everFetched = false;
    notifyListeners();
  }

  /// Loads every favorited item across the whole account for the Favorites
  /// tab.
  Future<void> fetchAll() async {
    final service = session.service;
    if (!session.isLoggedIn || service == null) return;
    final gen = session.sessionGeneration;
    _everFetched = true;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final favorites = await service.fetchFavorites();
      if (gen != session.sessionGeneration) return;
      _allFavorites = favorites;
      debugPrint('[FavoritesController] Loaded ${_allFavorites.length} favorites');
    } catch (e) {
      if (gen != session.sessionGeneration) return;
      debugPrint('[FavoritesController] Error fetching favorites: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == session.sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Re-syncs [_allFavorites] after a delete/rename/move/copy elsewhere in
  /// the app - those operations don't know how to patch this list in place
  /// (a move changes an item's path; WebDAV COPY's handling of custom
  /// properties like `oc:favorite` isn't reliable enough to assume the
  /// copy is still favorited), so this just refetches - but only if
  /// Favorites has actually been loaded this session. Called by
  /// `ItemOperations` after delete/rename/move/copy.
  Future<void> syncIfLoaded() {
    return _everFetched ? fetchAll() : Future.value();
  }

  /// Patches a favorite-toggle result into [_allFavorites] in place (added
  /// if newly favorited, removed if un-favorited, updated otherwise) -
  /// called by `ItemOperations.toggleItemFavorite` after a successful
  /// server call. Cheap enough not to need a full refetch, unlike
  /// [syncIfLoaded].
  void applyFavoriteToggle(NextcloudItem updated) {
    final index = _allFavorites.indexWhere((i) => i.id == updated.id);
    if (updated.isFavorite) {
      if (index != -1) {
        _allFavorites[index] = updated;
      } else {
        _allFavorites = [..._allFavorites, updated];
      }
    } else if (index != -1) {
      _allFavorites = [..._allFavorites]..removeAt(index);
    }
    notifyListeners();
  }
}
