import 'package:flutter/services.dart';
import '../providers/session_controller.dart';
import 'native_channel.dart';

/// Tells the native side which account is active, so iOS's Share Extension -
/// a separate process with no Flutter engine - can list folders and upload as
/// it without opening the app (`ios/Runner/Native/NativeServices.swift`'s
/// `share_account`, stored in a Keychain group shared with the extension).
/// Android has no equivalent (its share intent opens the app itself), so
/// there the channel simply doesn't exist and both calls are no-ops.
class ShareAccountService {
  static const _channel = MethodChannel('dev.ayushya.noo/share_account');

  /// Publishes the active account (call whenever one becomes active).
  static Future<void> publish(SessionController session) async {
    final authHeader = session.service?.authHeaders['Authorization'];
    if (authHeader == null || session.serverUrl.isEmpty) return;
    final host = Uri.tryParse(session.serverUrl)?.host ?? session.serverUrl;
    await invokeIfAvailable(_channel, 'setAccount', {
      'serverUrl': session.serverUrl,
      'username': session.username,
      'authHeader': authHeader,
      'displayName': '${session.username}@$host',
    });
  }

  /// Forgets it (sign-out / switching away) so the extension stops offering
  /// uploads to an account that's no longer signed in.
  static Future<void> clear() => invokeIfAvailable(_channel, 'clearAccount');
}
