import 'dart:convert';
import 'package:flutter/services.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import 'native_channel.dart';
import 'share_intent_service.dart';

/// One upload batch finishing - see [UploadService.completions].
class UploadCompletion {
  final String remoteFolder;
  final int succeeded;
  final int failed;

  const UploadCompletion({
    required this.remoteFolder,
    required this.succeeded,
    required this.failed,
  });

  factory UploadCompletion.fromMap(Map<dynamic, dynamic> map) {
    return UploadCompletion(
      remoteFolder: map['remoteFolder'] as String? ?? '/',
      succeeded: (map['succeeded'] as num?)?.toInt() ?? 0,
      failed: (map['failed'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Hands a "Share to Noo" upload off to `ShareUploadService.kt`'s Android
/// foreground service, which does the actual prepare+upload entirely on its
/// own from there - including surviving the app being closed - with a
/// single cancellable progress notification for the whole batch. See that
/// service's doc comment for why this isn't done in Dart/Dio: a Dart
/// isolate doesn't keep running once the Flutter engine is gone, only a
/// real Android Service does.
class UploadService {
  static const _channel = MethodChannel('dev.ayushya.noo/upload_service');
  static const _statusChannel = EventChannel(
    'dev.ayushya.noo/upload_service/status',
  );

  /// Starts uploading [files] into the active account's current folder.
  /// Fire-and-forget from Dart's perspective - once this returns, the
  /// service owns the rest and reports progress/completion/cancellation
  /// through its own notification, not back to the app. [completions] is
  /// the one thing it does report back, for `FilesController` to act on.
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

    await invokeOrExplain(_channel, 'startUpload', 'Uploading', {
      ...args,
      'files': filesJson,
      'remoteFolder': files.currentFolderPath,
    });
  }

  /// Fires once per finished batch (at least one file uploaded) from
  /// `UploadEventBus` (Kotlin) - lets `FilesController` refresh the
  /// destination folder if it's the one currently on screen, instead of the
  /// list only updating on a manual pull-to-refresh. One shared stream,
  /// deliberately: see `SyncService.statusStream`'s identical doc comment -
  /// `EventChannel.receiveBroadcastStream()` opens its own native
  /// subscription per call, and the native side only keeps the latest one.
  static final Stream<UploadCompletion> completions = quietEvents(
    _statusChannel,
    (event) => UploadCompletion.fromMap(event as Map<dynamic, dynamic>),
  );
}
