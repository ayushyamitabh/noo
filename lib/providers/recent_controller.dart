import 'dart:async';
import 'package:flutter/material.dart';
import '../models/nextcloud_item.dart';
import 'session_controller.dart';

/// The Recent Files tab. Kept separate from Files' own loading/error
/// state, likewise.
class RecentController extends ChangeNotifier {
  final SessionController session;

  List<NextcloudItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  RecentController(this.session) {
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
      final recent = await service.fetchRecentFiles();
      if (gen != session.sessionGeneration) return;
      _items = recent;
    } catch (e) {
      if (gen != session.sessionGeneration) return;
      debugPrint('[RecentController] Error fetching recent files: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == session.sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
}
