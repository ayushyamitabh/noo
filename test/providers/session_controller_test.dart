import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/models/saved_account.dart';
import 'package:noo/providers/connectivity_controller.dart';
import 'package:noo/providers/session_controller.dart';

/// Regression coverage for the "empty list on first load" bug class: a
/// controller built by a *lazy* `ChangeNotifierProvider` (FilesController,
/// PhotosController, ...) can be constructed after
/// [SessionController]'s one-shot account-activated/ready event already
/// fired - e.g. `ConnectivityController` misreporting offline for a couple
/// of seconds right after a cold Android start hides the Files tab from
/// `main.dart`'s bottom nav, delaying `FilesController`'s construction
/// until after login already finished. `addAccountActivatedListener`/
/// `addAccountReadyListener` must call back immediately for a listener
/// that registers after the fact, not only fire for the *next* login.
void main() {
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  const connectivityStatusChannel = EventChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );

  const accountId = 'server_example_com__alice';
  const passwordKey = 'nc_app_password_$accountId';
  const password = 'app-password';

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'readAll') {
            return <String, String>{passwordKey: password};
          }
          if (call.method == 'read') {
            final key = (call.arguments as Map)['key'] as String?;
            return key == passwordKey ? password : null;
          }
          return null;
        });
    // Reports no network on every `checkConnectivity()` call, so
    // `ConnectivityController` deterministically settles into `isOffline`
    // and `SessionController` never attempts a real (and, in this
    // sandboxed test environment, unreachable) HTTP call.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return <String>['none'];
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          connectivityStatusChannel,
          MockStreamHandler.inline(onListen: (arguments, events) {}),
        );
  });

  Future<void> pumpUntil(bool Function() condition) async {
    for (var i = 0; i < 50 && !condition(); i++) {
      await Future.delayed(Duration.zero);
    }
  }

  test('addAccountReadyListener calls back immediately for a listener that '
      'registers after a provisional/offline login already happened', () async {
    SharedPreferences.setMockInitialValues({
      'account_migration_v1_done': true,
      'accounts_list': jsonEncode([
        const SavedAccount(
          id: accountId,
          serverUrl: 'https://server.example.com',
          username: 'alice',
        ).toJson(),
      ]),
      'active_account_id': accountId,
    });

    final connectivity = ConnectivityController();
    await pumpUntil(() => connectivity.isOffline);
    expect(connectivity.isOffline, true);

    final session = SessionController(connectivity);
    await pumpUntil(() => session.isLoggedIn);
    expect(session.isLoggedIn, true);

    // The fix under test: this mirrors what FilesController's/
    // OfflineController's own constructor does, but simulated as
    // happening *after* the event above already fired - exactly the
    // lazy-Provider race this test guards against.
    var readyCalls = 0;
    session.addAccountReadyListener(() => readyCalls++);
    expect(readyCalls, 1);

    connectivity.dispose();
    session.dispose();
  });

  test('addAccountReadyListener does not call back before any account is '
      'active', () async {
    SharedPreferences.setMockInitialValues({'account_migration_v1_done': true});

    final connectivity = ConnectivityController();
    final session = SessionController(connectivity);
    await pumpUntil(() => !session.isRestoringSession);
    expect(session.isLoggedIn, false);

    var readyCalls = 0;
    session.addAccountReadyListener(() => readyCalls++);
    expect(readyCalls, 0);

    connectivity.dispose();
    session.dispose();
  });
  for (final fails in [false, true]) {
    test('account removal awaits native cleanup (failure: $fails)', () async {
      SharedPreferences.setMockInitialValues({
        'account_migration_v1_done': true,
        'accounts_list': jsonEncode([
          const SavedAccount(
            id: accountId,
            serverUrl: 'https://server.example.com',
            username: 'alice',
          ).toJson(),
        ]),
        'active_account_id': accountId,
        'acct_${accountId}_ui_synced_folders': ['/Photos'],
      });
      final connectivity = ConnectivityController();
      await pumpUntil(() => connectivity.isOffline);
      final session = SessionController(connectivity);
      await pumpUntil(() => session.isLoggedIn);
      const channel = MethodChannel('dev.ayushya.noo/sync_service');
      var cleanupCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'removeAccountData') {
              expect(call.arguments['accountId'], accountId);
              expect(session.accounts, isNotEmpty);
              cleanupCalled = true;
              if (fails) throw PlatformException(code: 'cleanup_failed');
            }
            return null;
          });
      try {
        if (fails) {
          await expectLater(
            session.removeAccount(accountId),
            throwsA(isA<PlatformException>()),
          );
          expect(session.accounts, isNotEmpty);
          expect(
            (await SharedPreferences.getInstance()).getStringList(
              'acct_${accountId}_ui_synced_folders',
            ),
            ['/Photos'],
          );
        } else {
          await session.removeAccount(accountId);
          expect(session.accounts, isEmpty);
          expect(session.isLoggedIn, false);
          expect(
            (await SharedPreferences.getInstance()).containsKey(
              'acct_${accountId}_ui_synced_folders',
            ),
            false,
          );
        }
        expect(cleanupCalled, true);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        session.dispose();
        connectivity.dispose();
      }
    });
  }
}
