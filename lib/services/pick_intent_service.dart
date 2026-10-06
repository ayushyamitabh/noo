import 'package:flutter/services.dart';
import '../models/pick_request.dart';
import 'native_channel.dart';

/// Talks to `MainActivity.kt`'s hand-rolled GET_CONTENT picker handling
/// (mirrors `ShareIntentService`'s split between a cold-start check and a
/// stream for an intent arriving while the app is already running - the
/// same `singleTask` launch mode applies here).
class PickIntentService {
  static const _methodChannel = MethodChannel('dev.ayushya.noo/pick_intent');
  static const _newPickChannel = EventChannel(
    'dev.ayushya.noo/pick_intent/new',
  );

  /// Non-null if the app was launched cold as another app's file/photo
  /// picker.
  static Future<PickRequest?> getPickRequest() async {
    final result = await invokeIfAvailable<Map<dynamic, dynamic>>(
      _methodChannel,
      'getPickRequest',
    );
    return result == null ? null : PickRequest.fromMap(result);
  }

  /// Emits whenever the app is asked to act as a picker while already
  /// running.
  static Stream<PickRequest> get onNewPickRequest {
    return quietEvents(
      _newPickChannel,
      (event) => PickRequest.fromMap(event as Map<dynamic, dynamic>),
    );
  }

  /// Hands the already-downloaded local files back to the caller and closes
  /// the picker. [mimeTypes] is parallel to [localPaths].
  static Future<void> finishPick(
    List<String> localPaths,
    List<String> mimeTypes,
  ) {
    return invokeIfAvailable(_methodChannel, 'finishPick', {
      'paths': localPaths,
      'mimeTypes': mimeTypes,
    });
  }

  /// Backs out of picking mode with no result, closing the picker.
  static Future<void> cancelPick() {
    return invokeIfAvailable(_methodChannel, 'cancelPick');
  }
}
