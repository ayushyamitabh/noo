import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_account.dart';
import '../services/account_store.dart';
import '../services/app_lock_service.dart';
import '../services/login_flow_service.dart';
import '../services/nextcloud_service.dart';
import '../services/sync_service.dart';

enum LoginFlowStatus { idle, initiating, awaitingBrowser, error }

/// Owns everything about *which* account is live and whether it's actually
/// authenticated: the saved-accounts list, the active account, Login Flow
/// v2, the live [NextcloudService] instance, the session-generation guard
/// every other controller's fetches check against, and app lock. Doesn't
/// hold a single byte of any tab's *content* - that's what
/// [FilesController]/`PhotosController`/etc. own, each reacting to this
/// controller's account-activated/cleared signals (below) rather than this
/// controller reaching into them directly, since this is constructed
/// before them (they depend on it, not the other way around).
///
/// Split out of the former single `ServerProvider` god object - see
/// `.claude/context/architecture.md`'s "State management" section for the
/// full rationale.
class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  final Future<SharedPreferences> prefsFuture =
      SharedPreferences.getInstance();
  final AccountStore accountStore = AccountStore();

  String _serverUrl = '';
  String _username = '';
  String _password = '';
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isRestoringSession = true;
  String? _errorMessage;

  LoginFlowStatus _loginFlowStatus = LoginFlowStatus.idle;
  Uri? _pendingLoginUrl;
  Timer? _pollTimer;
  Timer? _pollTimeoutTimer;
  bool _addAccountFlowActive = false;

  NextcloudService? _service;

  List<SavedAccount> _accounts = [];
  String? _activeAccountId;
  // Bumped at the start of every account switch/removal/activation so an
  // in-flight fetch from the account being left can recognize it's stale
  // (by comparing against the generation it captured at its own start) and
  // discard its result instead of writing it into the now-active account's
  // state. Every other controller's fetch methods check this too.
  int _sessionGeneration = 0;

  bool _loginLockEnabled = false;
  bool _lockAccountSwitching = false;
  bool _lockHiddenFiles = false;
  // Transient (never persisted) - starts locked whenever the app process
  // starts, and re-locks on every backgrounding if a lock is configured;
  // see didChangeAppLifecycleState.
  bool _isUnlocked = false;

  static const _prefLoginLockEnabled = 'ui_login_lock_enabled';
  static const _prefLockAccountSwitching = 'ui_lock_account_switching';
  static const _prefLockHiddenFiles = 'ui_lock_hidden_files';

  // Sibling controllers (Files/Photos/Favorites/Trash/Shares/Recent/Sync)
  // register here instead of this controller holding forward references to
  // them - it's constructed first, they depend on it. `cleared` fires
  // wherever `_clearActiveContent()` used to run (about to switch/log out -
  // reset your own state); `activated` fires only once credentials are
  // actually verified (fetch your own data now).
  final List<VoidCallback> _accountClearedListeners = [];
  final List<VoidCallback> _accountActivatedListeners = [];
  void addAccountClearedListener(VoidCallback cb) =>
      _accountClearedListeners.add(cb);
  void addAccountActivatedListener(VoidCallback cb) =>
      _accountActivatedListeners.add(cb);
  void _notifyAccountCleared() {
    for (final cb in _accountClearedListeners) {
      cb();
    }
  }

  void _notifyAccountActivated() {
    for (final cb in _accountActivatedListeners) {
      cb();
    }
  }

  SessionController() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final prefs = await prefsFuture;
    await accountStore.migrateLegacyIfNeeded(prefs);
    _accounts = accountStore.loadAccounts(prefs);
    _activeAccountId = accountStore.loadActiveAccountId(prefs);
    await Future.wait([_loadPreferences(), _restoreSession()]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-locks the app on backgrounding when login lock is set up - a
    // one-time unlock at cold start would give the feature no real
    // security value, since the realistic threat is someone else picking
    // up an already-running, unlocked phone.
    if (state == AppLifecycleState.paused &&
        _loginLockEnabled &&
        _isUnlocked) {
      _isUnlocked = false;
      notifyListeners();
    }
  }

  // Getters
  String get serverUrl => _serverUrl;
  String get username => _username;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get errorMessage => _errorMessage;
  int get sessionGeneration => _sessionGeneration;
  NextcloudService? get service => _service;

  LoginFlowStatus get loginFlowStatus => _loginFlowStatus;
  Uri? get pendingLoginUrl => _pendingLoginUrl;

  List<SavedAccount> get accounts => List.unmodifiable(_accounts);
  String? get activeAccountId => _activeAccountId;
  SavedAccount? get activeAccount =>
      _accounts.where((a) => a.id == _activeAccountId).firstOrNull;
  bool get isAddAccountFlow => _addAccountFlowActive;

  bool get loginLockEnabled => _loginLockEnabled;
  bool get lockAccountSwitching => _lockAccountSwitching;
  bool get lockHiddenFiles => _lockHiddenFiles;
  bool get needsUnlock => _loginLockEnabled && !_isUnlocked;

  Future<void> _restoreSession() async {
    try {
      final id = _activeAccountId;
      if (id == null) return;
      final account = _accounts.where((a) => a.id == id).firstOrNull;
      if (account == null) return;
      final password = await accountStore.readPassword(id);
      if (password == null) return;
      await _applyCredentialsForAccount(account, password);
    } catch (e) {
      debugPrint('[SessionController] Session restore failed: $e');
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await prefsFuture;
      _loginLockEnabled =
          prefs.getBool(_prefLoginLockEnabled) ?? _loginLockEnabled;
      _lockAccountSwitching =
          prefs.getBool(_prefLockAccountSwitching) ?? _lockAccountSwitching;
      _lockHiddenFiles =
          prefs.getBool(_prefLockHiddenFiles) ?? _lockHiddenFiles;
      notifyListeners();
    } catch (e) {
      debugPrint('[SessionController] Preference restore failed: $e');
    }
  }

  /// Verifies [appPassword] for [account] and, on success, makes it the
  /// live session, firing [_notifyAccountActivated] so every other
  /// controller fetches its own data. The password is expected to already
  /// be durably saved by the caller (either freshly, via
  /// [_completeLoginFlow], or previously, since this is also how a saved
  /// session is restored/switched to) - this method only writes to
  /// [AccountStore] to drop a password that turns out to no longer work.
  Future<bool> _applyCredentialsForAccount(
    SavedAccount account,
    String appPassword,
  ) async {
    final gen = _sessionGeneration;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _serverUrl = account.serverUrl;
    _username = account.username;
    _password = appPassword;

    _service = NextcloudService(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
    );

    try {
      final success = await _service!.testConnection();
      if (gen != _sessionGeneration) return false;
      if (success) {
        _isLoggedIn = true;
        _isLoading = false;
        notifyListeners();
        _notifyAccountActivated();
        return true;
      }
    } catch (e) {
      if (gen != _sessionGeneration) return false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      // Only drop the stored password on an actual auth rejection (401) -
      // testConnection also throws for network-level failures (DNS,
      // timeout, unreachable host), and those are transient: deleting a
      // still-valid password on a dropped connection would permanently
      // log the account out with no way back in short of Login Flow v2
      // again, since activeAccountId is never cleared and switchAccount()
      // no-ops when asked to "switch" to the account that's already
      // (nominally) active.
      if (_errorMessage?.contains('401') == true) {
        await accountStore.deletePassword(account.id);
      }
    }

    if (gen != _sessionGeneration) return false;
    _isLoggedIn = false;
    _service = null;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Starts Nextcloud Login Flow v2: asks the server for a one-time login
  /// URL, then polls until the user authorizes (in LoginWebViewView, pushed
  /// by LoginView once loginFlowStatus flips to awaitingBrowser below) and
  /// the server hands back a scoped app password. The app never sees the
  /// user's real password. [addAccount] only marks the flow as "add
  /// another account" for [isAddAccountFlow] - the pushed Add Account
  /// screen reads that to decide when to pop itself; this method's own
  /// persistence behavior on success ([_completeLoginFlow]) is the same
  /// either way (create-or-refresh the resulting account, then activate
  /// it).
  Future<void> startLoginFlow(
    String serverUrl, {
    bool addAccount = false,
  }) async {
    _addAccountFlowActive = addAccount;
    _loginFlowStatus = LoginFlowStatus.initiating;
    _errorMessage = null;
    notifyListeners();

    try {
      final init = await LoginFlowService.initiate(serverUrl);
      _pendingLoginUrl = init.loginUrl;
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
            await _completeLoginFlow(result);
            _addAccountFlowActive = false;
          }
        } on http.ClientException catch (e) {
          // A single dropped connection (e.g. the network briefly
          // reconfiguring right as the login browser opens) used to abort
          // the whole flow, forcing the user to start over even though
          // they'd already granted access - just skip this tick and let
          // the next scheduled poll (2s later) try again. The 10-minute
          // timeout above is still the real ceiling.
          debugPrint('[SessionController] Poll network hiccup, retrying: $e');
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

  void cancelLoginFlow({String? errorMessage}) {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    _pendingLoginUrl = null;
    _addAccountFlowActive = false;
    _loginFlowStatus = errorMessage != null
        ? LoginFlowStatus.error
        : LoginFlowStatus.idle;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  /// Turns a completed Login Flow v2 result into a saved account (creating
  /// it, or refreshing its password if it already existed - e.g. an
  /// expired app password re-authenticated) and makes it the active
  /// session. Used for both the first/only login and "add account".
  Future<void> _completeLoginFlow(LoginFlowResult result) async {
    final serverUrl = LoginFlowService.normalizeServerUrl(result.serverUrl);
    final id = SavedAccount.makeId(serverUrl, result.loginName);
    final account = SavedAccount(
      id: id,
      serverUrl: serverUrl,
      username: result.loginName,
    );
    _accounts = [
      for (final a in _accounts)
        if (a.id != id) a,
      account,
    ];

    final prefs = await prefsFuture;
    await accountStore.saveAccounts(prefs, _accounts);
    await accountStore.writePassword(id, result.appPassword);
    await _activateAccount(id);
  }

  /// The shared engine behind switching accounts, falling back to another
  /// account after removing the active one, and landing on the newly
  /// created/refreshed account after a login flow completes: tears down
  /// the outgoing account's live content (without ever setting
  /// [isLoggedIn] false - see below), then loads the target account's
  /// credentials.
  ///
  /// Non-goal, by design: no simultaneous multi-account state. This is a
  /// full teardown-and-reload of the active session every time, exactly
  /// like [logout] already did - just without touching any *other* saved
  /// account's stored credentials/prefs.
  Future<void> _activateAccount(String accountId) async {
    // Invalidates any fetch still in flight for the account being left, so
    // a slow response can't land in the new account's state.
    _sessionGeneration++;
    // A pending "add account" flow can't stay pending through a manual
    // switch/cycle - simplicity over blocking the gesture.
    if (_loginFlowStatus != LoginFlowStatus.idle) cancelLoginFlow();

    _notifyAccountCleared();
    // Not `_isLoggedIn = false` - that would bounce main.dart's root
    // routing through LoginView mid-switch. Each tab already shows its own
    // spinner from its own loading state, so this alone is enough to
    // avoid flashing the outgoing account's stale content.
    _isLoading = true;
    notifyListeners();

    _activeAccountId = accountId;
    final prefs = await prefsFuture;
    await accountStore.saveActiveAccountId(prefs, accountId);
    notifyListeners();

    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    final password = account == null
        ? null
        : await accountStore.readPassword(accountId);
    if (account == null || password == null) {
      _isLoading = false;
      _isLoggedIn = false;
      notifyListeners();
      return;
    }

    await _applyCredentialsForAccount(account, password);
  }

  /// Switches to an already-saved account. No-op (returns true) if it's
  /// already active and logged in; no-op (returns false) if unknown - but
  /// if [accountId] is nominally "active" while [isLoggedIn] is false (a
  /// session-restore that failed, e.g. transient network trouble at cold
  /// start), this still retries rather than no-op, since that's exactly the
  /// case LoginView's "Continue as" tile exists to recover from. Gated
  /// behind login lock when [lockAccountSwitching] is on. Returns whether
  /// the account ended up logged in, so callers (LoginView's saved-account
  /// tile) can surface a failure - e.g. a stored app password that no
  /// longer works and needs the account removed/re-added.
  Future<bool> switchAccount(String accountId) async {
    if (accountId == _activeAccountId && _isLoggedIn) return true;
    if (!_accounts.any((a) => a.id == accountId)) return false;
    if (!await passGate(_lockAccountSwitching, 'Unlock to switch accounts')) {
      return false;
    }
    await _activateAccount(accountId);
    return _isLoggedIn;
  }

  Future<SavedAccount?> _cycleAccount(int direction) async {
    if (_accounts.length < 2) return null;
    if (!await passGate(_lockAccountSwitching, 'Unlock to switch accounts')) {
      return null;
    }
    final currentIndex = _accounts.indexWhere((a) => a.id == _activeAccountId);
    final targetIndex = currentIndex == -1
        ? 0
        : (currentIndex + direction) % _accounts.length;
    final target =
        _accounts[(targetIndex + _accounts.length) % _accounts.length];
    unawaited(_activateAccount(target.id));
    return target;
  }

  /// Cycles to the next/previous saved account (by the order they were
  /// added) - used by the avatar's swipe-up/down quick-switch gesture.
  Future<SavedAccount?> cycleToNextAccount() => _cycleAccount(1);
  Future<SavedAccount?> cycleToPreviousAccount() => _cycleAccount(-1);

  /// Removes a saved account entirely: its stored password, its
  /// namespaced prefs, and its entry in the saved-accounts list. If it was
  /// the active account, falls back to another saved account, or - if none
  /// remain - deactivates the session (the only path here that sets
  /// [isLoggedIn] false; unlike [logout], there's nothing left to keep).
  Future<void> removeAccount(String accountId) async {
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index == -1) return;
    final wasActive = accountId == _activeAccountId;

    _accounts = [..._accounts]..removeAt(index);
    final prefs = await prefsFuture;
    await accountStore.saveAccounts(prefs, _accounts);
    await accountStore.deletePassword(accountId);
    for (final key in AccountStore.perAccountPrefKeys) {
      await prefs.remove(accountStore.accountPrefKey(accountId, key));
    }

    if (!wasActive) {
      notifyListeners();
      return;
    }

    if (_accounts.isEmpty) {
      await _deactivateSession();
      return;
    }

    await _activateAccount(_accounts.first.id);
  }

  /// Clears the active session pointer and tears down its content, without
  /// touching any saved account's own data - shared by [logout] (which
  /// deliberately keeps the account around to resume later, no
  /// re-authentication needed) and [removeAccount]'s "nothing left to fall
  /// back to" branch (where the account's data has already been deleted by
  /// the time this runs).
  Future<void> _deactivateSession() async {
    _sessionGeneration++;
    _notifyAccountCleared();
    _isLoggedIn = false;
    _serverUrl = '';
    _username = '';
    _password = '';
    _activeAccountId = null;
    final prefs = await prefsFuture;
    await accountStore.saveActiveAccountId(prefs, null);
    notifyListeners();
    unawaited(SyncService.cancel());
  }

  /// Ends the active session but keeps this account saved - unlike
  /// [removeAccount], nothing is deleted (password, prefs, its entry in
  /// [accounts] all remain), so it's available to resume with a single tap
  /// from the login screen's saved-accounts list, no Login Flow v2 needed.
  /// Always lands on the login screen even if other accounts are saved -
  /// deliberately not the same as switching to one of them.
  Future<void> logout() async {
    if (_activeAccountId == null) return;
    await _deactivateSession();
  }

  /// Confirms the device can do local auth and prompts once to enable login
  /// lock. Returns false (leaving lock disabled) if the device has no
  /// biometric/PIN capability or the user cancels/fails the confirmation.
  Future<bool> setupLoginLock() async {
    if (!await AppLockService.isDeviceSupported()) return false;
    final confirmed = await AppLockService.authenticate(
      'Confirm to turn on login lock',
    );
    if (!confirmed) return false;
    _loginLockEnabled = true;
    // Already just authenticated - don't immediately re-prompt behind it.
    _isUnlocked = true;
    notifyListeners();
    prefsFuture.then((p) => p.setBool(_prefLoginLockEnabled, true));
    return true;
  }

  /// Turns login lock off, along with both of its sub-toggles (meaningless
  /// once the base lock is gone). Requires a successful auth first, same as
  /// turning it on - otherwise anyone with momentary access to an unlocked
  /// phone could just switch it off.
  Future<bool> disableLoginLock() async {
    if (!_loginLockEnabled) return true;
    final confirmed = await AppLockService.authenticate(
      'Confirm to turn off login lock',
    );
    if (!confirmed) return false;
    _loginLockEnabled = false;
    _lockAccountSwitching = false;
    _lockHiddenFiles = false;
    _isUnlocked = false;
    notifyListeners();
    prefsFuture.then((p) {
      p.setBool(_prefLoginLockEnabled, false);
      p.setBool(_prefLockAccountSwitching, false);
      p.setBool(_prefLockHiddenFiles, false);
    });
    return true;
  }

  void setLockAccountSwitching(bool value) {
    if (!_loginLockEnabled) return;
    _lockAccountSwitching = value;
    notifyListeners();
    prefsFuture.then((p) => p.setBool(_prefLockAccountSwitching, value));
  }

  void setLockHiddenFiles(bool value) {
    if (!_loginLockEnabled) return;
    _lockHiddenFiles = value;
    notifyListeners();
    prefsFuture.then((p) => p.setBool(_prefLockHiddenFiles, value));
  }

  /// Called by the lock screen. Returns whether it actually unlocked.
  Future<bool> attemptUnlock() async {
    final success = await AppLockService.authenticate('Unlock Noo');
    if (success) {
      _isUnlocked = true;
      notifyListeners();
    }
    return success;
  }

  /// Prompts for auth if [gate] is on and login lock is configured;
  /// returns true immediately (no prompt) otherwise. Shared by the
  /// account-switching gate above and [FilesController]'s/`PhotosController`'s
  /// hidden-files gates.
  Future<bool> passGate(bool gate, String reason) async {
    if (!_loginLockEnabled || !gate) return true;
    return AppLockService.authenticate(reason);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    super.dispose();
  }
}
