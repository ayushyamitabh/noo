import 'dart:async';
import 'package:flutter/material.dart';
import '../models/nextcloud_share.dart';
import 'session_controller.dart';

/// The Shares tab. Kept separate from Files' own loading/error state,
/// likewise.
class SharesController extends ChangeNotifier {
  final SessionController session;

  /// Each scope's own cache - switching `sharedWithMe` no longer refetches
  /// on every switch, only the first time a scope is visited (or on a
  /// pull-to-refresh/retry), since `By you`/`Links` (see shares_view.dart's
  /// client-side split of this same list) and `With you` used to hit the
  /// network again on every single toggle, even switching straight back to
  /// a scope just fetched seconds ago.
  List<NextcloudShare> _withMeShares = [];
  List<NextcloudShare> _byMeShares = [];
  bool _withMeLoaded = false;
  bool _byMeLoaded = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _sharedWithMe = false;

  SharesController(this.session) {
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountActivatedListener(_onAccountActivated);
  }

  List<NextcloudShare> get shares =>
      _sharedWithMe ? _withMeShares : _byMeShares;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get sharedWithMe => _sharedWithMe;

  void _onAccountCleared() {
    _withMeShares = [];
    _byMeShares = [];
    _withMeLoaded = false;
    _byMeLoaded = false;
    _isLoading = false;
    _errorMessage = null;
    _sharedWithMe = false;
    notifyListeners();
  }

  void _onAccountActivated() {
    unawaited(fetchAll());
  }

  /// Fetches the *current* scope fresh, ignoring its cache - the initial
  /// load, pull-to-refresh, and the error-retry button all want a real
  /// round-trip regardless of whether this scope was already loaded.
  Future<void> fetchAll() async {
    final service = session.service;
    if (!session.isLoggedIn || service == null) return;
    final gen = session.sessionGeneration;
    final wantsWithMe = _sharedWithMe;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final shares = await service.fetchShares(sharedWithMe: wantsWithMe);
      if (gen != session.sessionGeneration) return;
      if (wantsWithMe) {
        _withMeShares = shares;
        _withMeLoaded = true;
      } else {
        _byMeShares = shares;
        _byMeLoaded = true;
      }
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

  /// Switches between "shared by me" and "shared with me". Only fetches
  /// when the target scope hasn't been loaded yet - switching back to one
  /// already cached just swaps which list [shares] reads from.
  void setSharedWithMe(bool value) {
    if (_sharedWithMe == value) return;
    _sharedWithMe = value;
    notifyListeners();
    if (!(value ? _withMeLoaded : _byMeLoaded)) fetchAll();
  }

  Future<bool> deleteShare(NextcloudShare share) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.deleteShare(share.id);
    if (success) {
      if (_sharedWithMe) {
        _withMeShares = _withMeShares.where((s) => s.id != share.id).toList();
      } else {
        _byMeShares = _byMeShares.where((s) => s.id != share.id).toList();
      }
      notifyListeners();
    }
    return success;
  }
}
