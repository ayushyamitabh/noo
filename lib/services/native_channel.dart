import 'package:flutter/services.dart';
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

/// Thrown by user-triggered native services (upload, download, sync now...)
/// on a platform whose native side isn't implemented yet - the message is
/// shown to the user as-is, e.g. in a snackbar.
class NativeServiceUnavailable implements Exception {
  final String feature;

  const NativeServiceUnavailable(this.feature);

  @override
  String toString() => "$feature isn't available on this platform yet.";
}

/// Calls [method], treating a missing native implementation (no
/// `MethodChannel` handler registered, as on iOS until each service is
/// built there) as "nothing to report": returns null instead of throwing
/// `MissingPluginException`. For cold-start checks, scheduling and other
/// calls nobody is waiting on.
Future<T?> invokeIfAvailable<T>(
  MethodChannel channel,
  String method, [
  Object? arguments,
]) async {
  try {
    return await channel.invokeMethod<T>(method, arguments);
  } on MissingPluginException {
    return null;
  }
}

/// Like [invokeIfAvailable], but for an action the user just asked for:
/// throws [NativeServiceUnavailable] naming [feature] rather than silently
/// doing nothing.
Future<T?> invokeOrExplain<T>(
  MethodChannel channel,
  String method,
  String feature, [
  Object? arguments,
]) async {
  try {
    return await channel.invokeMethod<T>(method, arguments);
  } on MissingPluginException {
    throw NativeServiceUnavailable(feature);
  }
}

/// [channel]'s broadcast stream mapped through [convert], with the
/// "no native implementation" error dropped - the stream just never emits.
Stream<T> quietEvents<T>(EventChannel channel, T Function(dynamic) convert) {
  return channel
      .receiveBroadcastStream()
      .handleError((Object _) {}, test: (e) => e is MissingPluginException)
      .map(convert);
}
