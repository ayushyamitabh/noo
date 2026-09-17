import 'dart:convert';
import 'package:flutter/services.dart';
import '../providers/server_provider.dart';
import 'share_intent_service.dart';

/// Hands a "Share to Noo" upload off to `ShareUploadService.kt`'s Android
/// foreground service, which does the actual prepare+upload entirely on its
/// own from there - including surviving the app being closed - with a
/// single cancellable progress notification for the whole batch. See that
/// service's doc comment for why this isn't done in Dart/Dio: a Dart
/// isolate doesn't keep running once the Flutter engine is gone, only a
/// real Android Service does.
class UploadService {
  static const _channel = MethodChannel('dev.ayushya.noo/upload_service');

  /// Starts uploading [files] into the active account's current folder.
  /// Fire-and-forget from Dart's perspective - once this returns, the
  /// service owns the rest and reports progress/completion/cancellation
  /// through its own notification, not back to the app.
  static Future<void> startUpload(
    ServerProvider provider,
    List<SharedFileRef> files,
  ) async {
    final service = provider.service;
    final authHeader = service?.authHeaders['Authorization'];
    if (service == null || authHeader == null) {
      throw Exception('Not logged in.');
    }

    final filesJson = jsonEncode(
      files.map((f) => {'uri': f.uri, 'name': f.name, 'size': f.size}).toList(),
    );

    await _channel.invokeMethod('startUpload', {
      'files': filesJson,
      'serverUrl': provider.serverUrl,
      'username': provider.username,
      'authHeader': authHeader,
      'remoteFolder': provider.currentFolderPath,
    });
  }
}
