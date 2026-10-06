import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/services/native_channel.dart';
import 'package:noo/services/share_intent_service.dart';

/// iOS has no handler for the `dev.ayushya.noo/*` channels yet, so these use
/// channels with nothing registered - the same `MissingPluginException` the
/// simulator showed at startup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/no_native_side');
  const events = EventChannel('test/no_native_side/events');

  test(
    'invokeIfAvailable returns null when nothing implements the channel',
    () {
      expect(
        invokeIfAvailable<String>(channel, 'anything'),
        completion(isNull),
      );
    },
  );

  test('invokeIfAvailable still returns a real result', () async {
    const live = MethodChannel('test/live');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(live, (call) async => 'pong');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(live, null),
    );
    expect(await invokeIfAvailable<String>(live, 'ping'), 'pong');
  });

  test('invokeOrExplain names the feature the user asked for', () {
    expect(
      invokeOrExplain(channel, 'startUpload', 'Uploading'),
      throwsA(
        isA<NativeServiceUnavailable>().having(
          (e) => e.toString(),
          'message',
          "Uploading isn't available on this platform yet.",
        ),
      ),
    );
  });

  test('quietEvents swallows the missing-implementation error', () async {
    final errors = <Object>[];
    final values = <int>[];
    final done = Completer<void>();
    quietEvents<int>(
      events,
      (e) => e as int,
    ).listen(values.add, onError: errors.add, onDone: done.complete);
    // Give the (failing) native `listen` call time to come back.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(errors, isEmpty);
    expect(values, isEmpty);
  });

  test('ShareIntentService has nothing to report without a native side', () {
    expect(ShareIntentService.getInitialShare(), completion(isEmpty));
  });
}
