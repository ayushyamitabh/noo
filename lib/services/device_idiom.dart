import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this iOS device is an iPhone rather than an iPad (or an Apple
/// silicon Mac running the iPad app), read once at startup from the native
/// `dev.ayushya.noo/device` channel (`ios/Runner/Native/NativeServices.swift`).
///
/// Flutter exposes no fold information on iOS, but no iPhone has a
/// tablet-class window except an unfolded foldable - so `NooLayout` uses this
/// to tell a foldable iPhone's inner screen from an iPad.
class DeviceIdiom {
  const DeviceIdiom._();

  static const _channel = MethodChannel('dev.ayushya.noo/device');

  /// False until [load] completes, and everywhere but iOS.
  static bool isIPhone = false;

  static Future<void> load() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      isIPhone = await _channel.invokeMethod<bool>('isPhone') ?? false;
    } on MissingPluginException {
      // Older native side: treat as not an iPhone (no fold split).
    } on PlatformException {
      // Same.
    }
  }
}
