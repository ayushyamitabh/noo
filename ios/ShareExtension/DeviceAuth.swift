import LocalAuthentication

/// Face ID / Touch ID with the device passcode as the fallback - the same
/// policy the app's lock uses (`local_auth` with `biometricOnly: false`), so
/// the share sheet asks for exactly what the app would.
enum DeviceAuth {
  /// True only if the user actually authenticated; a cancel, a failure, or a
  /// device with nothing to authenticate with all count as "not unlocked".
  static func authenticate(reason: String) async -> Bool {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
    return await withCheckedContinuation { continuation in
      context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
        continuation.resume(returning: success)
      }
    }
  }
}
