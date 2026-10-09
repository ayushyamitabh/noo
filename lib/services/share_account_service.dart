import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import 'native_channel.dart';

/// One account as the iOS Share Extension needs it - plain data, so the
/// payload builder is testable without a session.
class ShareAccountEntry {
  final String id;
  final String serverUrl;
  final String username;
  final String? displayName;
  final String password;

  /// The account's Files "hidden files" filter: `hide`, `only` or `include`.
  final String hiddenFilter;

  /// The account's Files storage scope: `cloud`, `external` or `all`.
  final String storageScope;

  const ShareAccountEntry({
    required this.id,
    required this.serverUrl,
    required this.username,
    this.displayName,
    required this.password,
    required this.hiddenFilter,
    required this.storageScope,
  });
}

/// Tells the native side which accounts can upload, which one is active, and
/// the app-lock settings, so iOS's Share Extension - a separate process with
/// no Flutter engine - can offer an account picker, list folders and upload
/// as them without opening the app (`ios/Runner/Native/NativeServices.swift`'s
/// `share_account`, stored in a Keychain group shared with the extension).
/// Android has no equivalent (its share intent opens the app itself), so there
/// the channel simply doesn't exist and everything here is a no-op.
class ShareAccountService {
  static const _channel = MethodChannel('dev.ayushya.noo/share_account');

  static String basicAuth(String username, String password) =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// The JSON `SharedAccounts` (`ios/Shared/SharedAccount.swift`) decodes.
  static String buildPayload({
    required List<ShareAccountEntry> accounts,
    required String? activeId,
    required bool loginLockEnabled,
    required bool lockAccountSwitching,
    required bool lockHiddenFiles,
  }) {
    return jsonEncode({
      'accounts': [
        for (final a in accounts)
          {
            'id': a.id,
            'serverUrl': a.serverUrl,
            'username': a.username,
            'authHeader': basicAuth(a.username, a.password),
            'displayName':
                '${a.displayName?.trim().isNotEmpty == true ? a.displayName!.trim() : a.username}@${Uri.tryParse(a.serverUrl)?.host ?? a.serverUrl}',
            'hiddenFilter': a.hiddenFilter,
            'storageScope': a.storageScope,
          },
      ],
      'activeId': activeId,
      'loginLockEnabled': loginLockEnabled,
      'lockAccountSwitching': lockAccountSwitching,
      'lockHiddenFiles': lockHiddenFiles,
    });
  }

  /// Publishes every saved account that can actually upload (has a stored
  /// password and isn't signed out), with the active one's hidden-files
  /// filter and storage scope taken live from [files] - the saved prefs are
  /// written asynchronously, so they can lag a change that just happened.
  static Future<void> publish(
    SessionController session,
    FilesController files,
  ) async {
    final activeId = session.activeAccountId;
    if (activeId == null) return clear();

    final prefs = await session.prefsFuture;
    final store = session.accountStore;
    final signedOut = store.loadSignedOut(prefs);
    final entries = <ShareAccountEntry>[];
    for (final account in session.accounts) {
      if (signedOut.contains(account.id)) {
        debugPrint('[ShareAccounts] skipping ${account.id}: signed out');
        continue;
      }
      final password = await store.readPassword(account.id);
      if (password == null) {
        debugPrint(
          '[ShareAccounts] skipping ${account.id}: no stored password',
        );
        continue;
      }
      final isActive = account.id == activeId;
      final filter = isActive
          ? files.hiddenFilter
          : FilesController.savedHiddenFilter(
              prefs,
              store.accountPrefKey,
              account.id,
            );
      final scope = isActive
          ? files.storageScope
          : FilesController.savedStorageScope(
              prefs,
              store.accountPrefKey,
              account.id,
            );
      entries.add(
        ShareAccountEntry(
          id: account.id,
          serverUrl: account.serverUrl,
          username: account.username,
          displayName: account.label,
          password: password,
          hiddenFilter: filter.name,
          storageScope: scope.name,
        ),
      );
    }
    debugPrint(
      '[ShareAccounts] publishing ${entries.length} of '
      '${session.accounts.length} saved accounts, active=$activeId '
      '(${signedOut.length} signed out)',
    );
    if (entries.isEmpty) return clear();

    await invokeIfAvailable(_channel, 'setAccounts', {
      'accounts': buildPayload(
        accounts: entries,
        activeId: activeId,
        loginLockEnabled: session.loginLockEnabled,
        lockAccountSwitching: session.lockAccountSwitching,
        lockHiddenFiles: session.lockHiddenFiles,
      ),
    });
  }

  /// Forgets everything (sign-out) so the extension stops offering uploads.
  static Future<void> clear() => invokeIfAvailable(_channel, 'clearAccount');
}

/// Keeps [ShareAccountService]'s published data current while the app is
/// running: republishes when an account becomes ready or when anything the
/// extension depends on changes - the account list or active account, the
/// lock settings, or the active account's hidden-files filter.
class ShareAccountSync {
  final SessionController session;
  final FilesController files;

  String? _lastSignature;
  bool _disposed = false;
  Future<void> _queue = Future.value();

  ShareAccountSync(this.session, this.files);

  void start() {
    session.addAccountReadyListener(_publish);
    session.addListener(_onChange);
    files.addListener(_onChange);
  }

  void dispose() {
    _disposed = true;
    session.removeListener(_onChange);
    files.removeListener(_onChange);
  }

  String _signature() => [
    session.activeAccountId,
    session.accounts.map((a) => a.id).join(','),
    session.loginLockEnabled,
    session.lockAccountSwitching,
    session.lockHiddenFiles,
    files.hiddenFilter.name,
    files.storageScope.name,
  ].join('|');

  void _onChange() {
    if (_signature() != _lastSignature) _publish();
  }

  /// Runs one at a time, in order, so a slow publish can't land after a
  /// newer one and leave the extension with stale data.
  void _publish() {
    if (_disposed) return;
    _lastSignature = _signature();
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await ShareAccountService.publish(session, files);
      } catch (_) {
        // Best effort: the extension just keeps the previous data.
      }
    });
  }
}
