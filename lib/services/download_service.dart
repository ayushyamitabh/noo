import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/nextcloud_item.dart';
import '../providers/session_controller.dart';
import 'native_channel.dart';

/// Hands a download off to `DownloadService.kt`'s Android foreground
/// service - the download counterpart of `UploadService`/
/// `ShareUploadService.kt` (see that pair's doc comments for why this
/// isn't done in Dart/Dio: only a real Android Service survives the
/// Flutter engine/Activity being gone, the same guarantee a real
/// file-manager app's download notification gives you). Saves straight
/// into the device's public Downloads folder with one cancellable
/// progress notification for the whole batch, instead of the old
/// download-to-app-cache-then-`file_saver`-prompt flow.
class DownloadService {
  static const _channel = MethodChannel('dev.ayushya.noo/download_service');

  /// Starts downloading [items]. Fire-and-forget from Dart's perspective -
  /// once this returns, the service owns the rest and reports
  /// progress/completion/cancellation through its own notification, not
  /// back to the app.
  static Future<void> startDownload(
    SessionController session,
    List<NextcloudItem> items,
  ) async {
    final args = baseChannelArgs(session);
    final filesJson = jsonEncode(
      items
          .map(
            (i) => {
              'path': i.path,
              'name': i.name,
              'mimeType': i.mimeType,
              'size': i.size,
            },
          )
          .toList(),
    );

    await _channel.invokeMethod('startDownload', {...args, 'files': filesJson});
  }
}
