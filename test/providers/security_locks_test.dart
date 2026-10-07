import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noo/providers/connectivity_controller.dart';
import 'package:noo/providers/session_controller.dart';
import 'package:noo/services/app_lock_service.dart';

/// The three Settings -> Security locks (open the app, switch accounts, reveal
/// hidden files) each work on their own - none needs or implies another. The
/// device prompt is replaced with a recorder so the gates can be exercised.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['none'] : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  late List<String> prompts;
  var authSucceeds = true;
  var deviceSupported = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prompts = [];
    authSucceeds = true;
    deviceSupported = true;
    AppLockService.debugAuthenticate = (reason) async {
      prompts.add(reason);
      return authSucceeds;
    };
    AppLockService.debugIsDeviceSupported = () async => deviceSupported;
  });

  tearDown(() {
    AppLockService.debugAuthenticate = null;
    AppLockService.debugIsDeviceSupported = null;
  });

  SessionController build() => SessionController(ConnectivityController());

  test(
    'hidden files and account switching can be locked without login lock',
    () async {
      final session = build();

      expect(await session.setLockHiddenFiles(true), isTrue);
      expect(await session.setLockAccountSwitching(true), isTrue);

      expect(session.lockHiddenFiles, isTrue);
      expect(session.lockAccountSwitching, isTrue);
      expect(session.loginLockEnabled, isFalse);
      expect(
        session.needsUnlock,
        isFalse,
        reason: 'opening the app stays open',
      );
    },
  );

  test('a gate prompts on its own, with login lock off', () async {
    final session = build();

    expect(await session.passGate(false, 'unused'), isTrue);
    expect(prompts, isEmpty, reason: 'a gate that is off never prompts');

    expect(await session.passGate(true, 'Unlock to show hidden files'), isTrue);
    expect(prompts, ['Unlock to show hidden files']);

    authSucceeds = false;
    expect(await session.passGate(true, 'again'), isFalse);
  });

  test(
    'turning a lock on needs a capable device and a successful auth',
    () async {
      final session = build();

      deviceSupported = false;
      expect(await session.setLockHiddenFiles(true), isFalse);
      expect(session.lockHiddenFiles, isFalse);

      deviceSupported = true;
      authSucceeds = false;
      expect(await session.setLockHiddenFiles(true), isFalse);
      expect(session.lockHiddenFiles, isFalse);

      authSucceeds = true;
      expect(await session.setLockHiddenFiles(true), isTrue);
      expect(session.lockHiddenFiles, isTrue);
    },
  );

  test(
    'turning a lock off needs auth, so it cannot just be flipped away',
    () async {
      final session = build();
      await session.setLockAccountSwitching(true);
      prompts.clear();

      authSucceeds = false;
      expect(await session.setLockAccountSwitching(false), isFalse);
      expect(session.lockAccountSwitching, isTrue);

      authSucceeds = true;
      expect(await session.setLockAccountSwitching(false), isTrue);
      expect(session.lockAccountSwitching, isFalse);
      expect(prompts, hasLength(2));
    },
  );

  test('setting a lock to its current value does not prompt', () async {
    final session = build();
    expect(await session.setLockHiddenFiles(false), isTrue);
    expect(prompts, isEmpty);
  });

  test('turning login lock off leaves the other two locks alone', () async {
    final session = build();
    await session.setupLoginLock();
    await session.setLockAccountSwitching(true);
    await session.setLockHiddenFiles(true);
    expect(session.loginLockEnabled, isTrue);

    expect(await session.disableLoginLock(), isTrue);

    expect(session.loginLockEnabled, isFalse);
    expect(session.lockAccountSwitching, isTrue);
    expect(session.lockHiddenFiles, isTrue);
  });

  test('each lock is saved on its own and restored', () async {
    final first = build();
    await first.setLockHiddenFiles(true);
    // Let the fire-and-forget pref write land.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final second = build();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(second.lockHiddenFiles, isTrue);
    expect(second.lockAccountSwitching, isFalse);
    expect(second.loginLockEnabled, isFalse);
  });
}
