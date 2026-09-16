import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_account.dart';

/// Persists the list of saved accounts, which one is active, and each
/// account's app password - plus a one-shot migration from the app's
/// original single-account storage schema (3 flat secure-storage keys and
/// a handful of un-namespaced SharedPreferences keys) into this one.
class AccountStore {
  static const _storage = FlutterSecureStorage();

  // Legacy single-account keys (pre-multi-account).
  static const _keyLegacyServerUrl = 'nc_server_url';
  static const _keyLegacyLoginName = 'nc_login_name';
  static const _keyLegacyAppPassword = 'nc_app_password';

  static const _passwordKeyPrefix = 'nc_app_password_';

  static const _prefAccountsList = 'accounts_list';
  static const _prefActiveAccountId = 'active_account_id';
  static const _prefMigrationDone = 'account_migration_v1_done';

  /// The per-account browsing prefs that get namespaced under
  /// `acct_<id>_<key>` on migration/save - everything else (theme, tab
  /// order, seek bar style, etc.) stays a global/app-wide pref, untouched
  /// by account switching.
  static const perAccountPrefKeys = [
    'ui_grid_view',
    'ui_show_favorites_only',
    'ui_show_favorites_only_photos',
    'ui_storage_scope',
    'ui_show_hidden',
    'ui_show_hidden_photos',
    'ui_sort_field',
    'ui_sort_ascending',
    'ui_folder_sort',
    'ui_files_type_filter',
    'ui_cache_policy',
    'ui_cache_interval_minutes',
  ];

  String accountPrefKey(String accountId, String baseKey) =>
      'acct_${accountId}_$baseKey';

  /// Runs once, ever: if a legacy single-account login is found and this
  /// hasn't already migrated, turns it into the first saved (and active)
  /// account, copies its browsing prefs to their namespaced keys, and
  /// deletes the legacy keys. Safe to call on every launch - it's a no-op
  /// once the migration marker is set, including on a fresh install with
  /// nothing to migrate.
  Future<void> migrateLegacyIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_prefMigrationDone) == true) return;
    try {
      final serverUrl = await _storage.read(key: _keyLegacyServerUrl);
      final username = await _storage.read(key: _keyLegacyLoginName);
      final appPassword = await _storage.read(key: _keyLegacyAppPassword);

      if (serverUrl != null && username != null && appPassword != null) {
        final id = SavedAccount.makeId(serverUrl, username);
        await _storage.write(key: '$_passwordKeyPrefix$id', value: appPassword);

        for (final key in perAccountPrefKeys) {
          final value = prefs.get(key);
          if (value == null) continue;
          final namespacedKey = accountPrefKey(id, key);
          if (value is bool) {
            await prefs.setBool(namespacedKey, value);
          } else if (value is int) {
            await prefs.setInt(namespacedKey, value);
          } else if (value is double) {
            await prefs.setDouble(namespacedKey, value);
          } else if (value is String) {
            await prefs.setString(namespacedKey, value);
          } else if (value is List<String>) {
            await prefs.setStringList(namespacedKey, value);
          }
          await prefs.remove(key);
        }

        await saveAccounts(prefs, [
          SavedAccount(id: id, serverUrl: serverUrl, username: username),
        ]);
        await saveActiveAccountId(prefs, id);

        await _storage.delete(key: _keyLegacyServerUrl);
        await _storage.delete(key: _keyLegacyLoginName);
        await _storage.delete(key: _keyLegacyAppPassword);
      }
    } finally {
      // Set unconditionally, even when there was nothing to migrate, so
      // this block truly never runs again.
      await prefs.setBool(_prefMigrationDone, true);
    }
  }

  List<SavedAccount> loadAccounts(SharedPreferences prefs) {
    final json = prefs.getString(_prefAccountsList);
    if (json == null) return [];
    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAccounts(
    SharedPreferences prefs,
    List<SavedAccount> accounts,
  ) async {
    await prefs.setString(
      _prefAccountsList,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  String? loadActiveAccountId(SharedPreferences prefs) =>
      prefs.getString(_prefActiveAccountId);

  Future<void> saveActiveAccountId(SharedPreferences prefs, String? id) async {
    if (id == null) {
      await prefs.remove(_prefActiveAccountId);
    } else {
      await prefs.setString(_prefActiveAccountId, id);
    }
  }

  Future<String?> readPassword(String accountId) =>
      _storage.read(key: '$_passwordKeyPrefix$accountId');

  Future<void> writePassword(String accountId, String password) =>
      _storage.write(key: '$_passwordKeyPrefix$accountId', value: password);

  Future<void> deletePassword(String accountId) =>
      _storage.delete(key: '$_passwordKeyPrefix$accountId');
}
