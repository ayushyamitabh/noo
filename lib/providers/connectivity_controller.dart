import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device currently has *any* network route (Wi-Fi, mobile
/// data, ethernet - not a guarantee the Nextcloud server itself is
/// reachable, just OS-level connectivity). The single source of truth
/// other controllers/views consult before attempting a network request or
/// deciding whether to fall back to offline-only behavior - see
/// `SessionController` (skips its login-restore HTTP call entirely while
/// offline) and `MainShellView` (restricts the bottom nav to just the
/// Offline tab while offline).
class ConnectivityController extends ChangeNotifier {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _recheckTimer;

  bool get isOffline => _isOffline;

  ConnectivityController() {
    Connectivity().checkConnectivity().then(_apply);
    _sub = Connectivity().onConnectivityChanged.listen(_apply);
    // The very first check can spuriously report "no network" while the
    // OS's connectivity stack is still attaching callbacks to this
    // just-started process - a real Android cold-start quirk, not a
    // genuine transition. That matters here specifically because
    // onConnectivityChanged only fires on actual transitions, so a false
    // initial "offline" read would otherwise stick for the rest of the
    // session (SessionController would keep treating every login as
    // provisional, and every network-fetching controller would never get
    // its real activation signal - see addAccountReadyListener's doc
    // comment) even though the device was online the whole time. Re-
    // verify once, shortly after, to correct it.
    _recheckTimer = Timer(const Duration(seconds: 2), () {
      Connectivity().checkConnectivity().then(_apply);
    });
  }

  void _apply(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline == _isOffline) return;
    _isOffline = offline;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recheckTimer?.cancel();
    super.dispose();
  }
}
