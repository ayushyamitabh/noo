import '../providers/session_controller.dart';

/// The "get this account's auth header, or bail" guard every native-
/// MethodChannel service (`UploadService`/`DownloadService`/`SyncService`)
/// needs before handing a batch off to Kotlin - was independently repeated
/// in each of them.
String requireAuthHeader(SessionController session) {
  final authHeader = session.service?.authHeaders['Authorization'];
  if (session.service == null || authHeader == null) {
    throw Exception('Not logged in.');
  }
  return authHeader;
}

/// The `{serverUrl, username, authHeader}` trio every one of those
/// services' `invokeMethod` argument maps includes.
Map<String, String> baseChannelArgs(SessionController session) {
  return {
    'serverUrl': session.serverUrl,
    'username': session.username,
    'authHeader': requireAuthHeader(session),
  };
}
