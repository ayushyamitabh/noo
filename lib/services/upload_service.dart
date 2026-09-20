import 'dart:convert';
import 'package:flutter/services.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import 'native_channel.dart';
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
    SessionController session,
    FilesController files,
    List<SharedFileRef> sharedFiles,
  ) async {
    final args = baseChannelArgs(session);
    final filesJson = jsonEncode(
      sharedFiles
          .map((f) => {'uri': f.uri, 'name': f.name, 'size': f.size})
          .toList(),
    );

    await _channel.invokeMethod('startUpload', {
      ...args,
      'files': filesJson,
      'remoteFolder': files.currentFolderPath,
    });
  }
}
