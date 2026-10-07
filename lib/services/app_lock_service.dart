import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around `local_auth`. Deliberately doesn't implement its own
/// PIN storage/hashing - `authenticate` delegates to whatever the OS
/// already has configured (fingerprint/face, or the device's own PIN/
/// pattern/password as a fallback when `biometricOnly` is false), which is
/// both simpler and more secure than reimplementing credential storage.
class AppLockService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Replace the platform prompt in tests (null = the real one).
  @visibleForTesting
  static Future<bool> Function(String reason)? debugAuthenticate;

  @visibleForTesting
  static Future<bool> Function()? debugIsDeviceSupported;

  /// Whether this device can do *some* form of local auth - biometric
  /// enrolled, or at minimum a device PIN/pattern/password set up.
  static Future<bool> isDeviceSupported() async {
    if (debugIsDeviceSupported != null) return debugIsDeviceSupported!();
    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      if (canCheckBiometrics) return true;
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts for biometric or device-credential auth. Returns false (never
  /// throws) on cancellation, failure, or any platform error, so callers
  /// can treat every non-true result the same way: stay locked/blocked.
  static Future<bool> authenticate(String reason) async {
    if (debugAuthenticate != null) return debugAuthenticate!(reason);
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          // Default (true) requires an extra manual confirmation tap after
          // a *passive* modality like face/iris recognizes you - Android's
          // own guidance reserves that for confirming risky actions
          // (a purchase); unlocking the app is exactly the "lower-risk"
          // case they say to pass false for, and on some devices/Android
          // versions it also determines whether face is offered as an
          // option in the prompt at all, not just whether it needs a
          // second tap to accept.
          sensitiveTransaction: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
