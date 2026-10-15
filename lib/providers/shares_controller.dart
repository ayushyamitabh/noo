import 'dart:async';
import 'package:flutter/material.dart';
import '../models/nextcloud_share.dart';
import 'session_controller.dart';

/// The Shares tab. Kept separate from Files' own loading/error state,
/// likewise.
class SharesController extends ChangeNotifier {
  final SessionController session;

  /// Both scopes are held and fetched together, so the view picks which
  /// list to show by its own scope - there is no controller-side "current
  /// scope" that can drift out of sync with the view (that mismatch once
  /// showed "With you" shares under "By you").
  List<NextcloudShare> _withMeShares = [];
  List<NextcloudShare> _byMeShares = [];
  bool _isLoading = false;
  String? _errorMessage;

  SharesController(this.session) {
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
  }

  List<NextcloudShare> get withMeShares => _withMeShares;
  List<NextcloudShare> get byMeShares => _byMeShares;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _onAccountCleared() {
    _withMeShares = [];
    _byMeShares = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _onAccountActivated() {
    unawaited(fetchAll());
  }

  /// Fetches both scopes fresh - the initial load, pull-to-refresh, and the
  /// error-retry button.
  Future<void> fetchAll() async {
    final service = session.service;
    if (!session.isLoggedIn || service == null) return;
    final gen = session.sessionGeneration;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        service.fetchShares(sharedWithMe: true),
        service.fetchShares(sharedWithMe: false),
      ]);
      if (gen != session.sessionGeneration) return;
      _withMeShares = results[0];
      _byMeShares = results[1];
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

  Future<bool> deleteShare(NextcloudShare share) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.deleteShare(share.id);
    if (success) {
      _withMeShares = _withMeShares.where((s) => s.id != share.id).toList();
      _byMeShares = _byMeShares.where((s) => s.id != share.id).toList();
      notifyListeners();
    }
    return success;
  }
}
