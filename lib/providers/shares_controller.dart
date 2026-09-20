import 'dart:async';
import 'package:flutter/material.dart';
import '../models/nextcloud_share.dart';
import 'session_controller.dart';

/// The Shares tab. Kept separate from Files' own loading/error state,
/// likewise.
class SharesController extends ChangeNotifier {
  final SessionController session;

  List<NextcloudShare> _shares = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _sharedWithMe = false;

  SharesController(this.session) {
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
  }

  List<NextcloudShare> get shares => _shares;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get sharedWithMe => _sharedWithMe;

  void _onAccountCleared() {
    _shares = [];
    _isLoading = false;
    _errorMessage = null;
    _sharedWithMe = false;
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
      final shares = await service.fetchShares(sharedWithMe: _sharedWithMe);
      if (gen != session.sessionGeneration) return;
      _shares = shares;
    } catch (e) {
      if (gen != session.sessionGeneration) return;
      debugPrint('[SharesController] Error fetching shares: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (gen == session.sessionGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Switches between "shared by me" and "shared with me" and refetches.
  void setSharedWithMe(bool value) {
    if (_sharedWithMe == value) return;
    _sharedWithMe = value;
    notifyListeners();
    fetchAll();
  }

  Future<bool> deleteShare(NextcloudShare share) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.deleteShare(share.id);
    if (success) {
      _shares = _shares.where((s) => s.id != share.id).toList();
      notifyListeners();
    }
    return success;
  }
}
