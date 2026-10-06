import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/services/share_account_service.dart';

/// What the iOS Share Extension is given - the contract with
/// `ios/Shared/SharedAccount.swift`'s `SharedAccounts`.
void main() {
  const alice = ShareAccountEntry(
    id: 'cloud_example_com__alice',
    serverUrl: 'https://cloud.example.com',
    username: 'alice',
    password: 's3cret',
    hiddenFilter: 'include',
  );
  const bob = ShareAccountEntry(
    id: 'nc_home_lan__bob',
    serverUrl: 'https://nc.home.lan:8443/nextcloud',
    username: 'bob',
    password: 'pw',
    hiddenFilter: 'hide',
  );

  Map<String, dynamic> build({
    List<ShareAccountEntry> accounts = const [alice, bob],
    String? activeId = 'nc_home_lan__bob',
    bool login = true,
    bool switching = true,
    bool hidden = false,
  }) => jsonDecode(
    ShareAccountService.buildPayload(
      accounts: accounts,
      activeId: activeId,
      loginLockEnabled: login,
      lockAccountSwitching: switching,
      lockHiddenFiles: hidden,
    ),
  );

  test('basic auth header matches what the app sends', () {
    expect(
      ShareAccountService.basicAuth('alice', 's3cret'),
      'Basic ${base64Encode(utf8.encode('alice:s3cret'))}',
    );
  });

  test('every account is listed with its own header, name and filter', () {
    final accounts = (build()['accounts'] as List).cast<Map<String, dynamic>>();
    expect(accounts.map((a) => a['id']), [alice.id, bob.id]);
    expect(
      accounts[0]['authHeader'],
      ShareAccountService.basicAuth('alice', 's3cret'),
    );
    expect(accounts[0]['displayName'], 'alice@cloud.example.com');
    expect(accounts[0]['hiddenFilter'], 'include');
    // The display name uses the host only - not the port or sub-path.
    expect(accounts[1]['displayName'], 'bob@nc.home.lan');
    expect(accounts[1]['serverUrl'], 'https://nc.home.lan:8443/nextcloud');
    expect(accounts[1]['hiddenFilter'], 'hide');
  });

  test('the active account and the lock settings are passed through', () {
    final payload = build(login: true, switching: false, hidden: true);
    expect(payload['activeId'], 'nc_home_lan__bob');
    expect(payload['loginLockEnabled'], true);
    expect(payload['lockAccountSwitching'], false);
    expect(payload['lockHiddenFiles'], true);
  });

  test('no active account is a null activeId, not a missing key', () {
    expect(build(activeId: null).containsKey('activeId'), true);
    expect(build(activeId: null)['activeId'], isNull);
  });
}
