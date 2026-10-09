import 'package:flutter_test/flutter_test.dart';
import 'package:noo/models/saved_account.dart';

void main() {
  test('display name survives persistence without changing login identity', () {
    const account = SavedAccount(
      id: 'id',
      serverUrl: 'https://cloud.example',
      username: 'alice123',
      displayName: ' Alice Smith ',
    );
    final restored = SavedAccount.fromJson(account.toJson());
    expect(restored.label, 'Alice Smith');
    expect(restored.username, 'alice123');
    expect(restored.id, 'id');
  });
  test('legacy accounts and blank names fall back to username', () {
    final legacy = SavedAccount.fromJson({
      'id': 'id',
      'serverUrl': 'https://cloud.example',
      'username': 'alice123',
    });
    expect(legacy.label, 'alice123');
    expect(
      const SavedAccount(
        id: 'id',
        serverUrl: '',
        username: 'alice123',
        displayName: ' ',
      ).label,
      'alice123',
    );
  });
}
