import 'dart:async';
import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import 'session_controller.dart';

/// The Trash tab. Kept separate from Files' own loading/error state so a
/// trash-fetch failure can't bleed a stale error into Files.
class TrashController extends ChangeNotifier {
  final SessionController session;

  List<NextcloudItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  TrashController(this.session) {
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
  }

  List<NextcloudItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _onAccountCleared() {
    _items = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _onAccountActivated() {
    unawaited(fetchAll());
  }

  Future<void> fetchAll() async {
    final service = session.service;
    if (!session.isLoggedIn || service == null) return;
    final gen = session.sessionGeneration;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final trash = await service.fetchTrash();
      if (gen != session.sessionGeneration) return;
      _items = trash;
    } catch (e) {
      if (gen != session.sessionGeneration) return;
      debugPrint('[TrashController] Error fetching trash: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == session.sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Restores a trashed item (identified by [NextcloudItem.path], the
  /// trash-relative name) back to where it was deleted from.
  Future<bool> restore(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.restoreTrashItem(item.path);
    if (success) {
      _items = _items.where((i) => i.id != item.id).toList();
      notifyListeners();
    }
    return success;
  }

  /// Permanently deletes a trashed item. Cannot be undone.
  Future<bool> deleteForever(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.deleteTrashItemForever(item.path);
    if (success) {
      _items = _items.where((i) => i.id != item.id).toList();
      notifyListeners();
    }
    return success;
  }
}
