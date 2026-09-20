import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/nextcloud_item.dart';
import '../models/pick_request.dart';
import '../services/pick_intent_service.dart';
import 'session_controller.dart';

/// State for Noo acting as *another* app's GET_CONTENT picker (see
/// `PickIntentService`/`MainActivity.kt`) - non-null [pickRequest] while
/// active, set at startup/onNewPickRequest in `MainShellView`, cleared
/// once the pick is confirmed or cancelled. Cross-cutting (both Files and
/// Photos need to know when picking mode is active and route taps through
/// [confirmPick] instead of their normal open/select behavior), so this is
/// its own small controller rather than living on any one tab's.
class PickController extends ChangeNotifier {
  final SessionController session;

  PickController(this.session);

  PickRequest? _pickRequest;
  bool _isDownloadingForPick = false;

  PickRequest? get pickRequest => _pickRequest;
  bool get isPicking => _pickRequest != null;
  bool get isDownloadingForPick => _isDownloadingForPick;

  /// Whether [item] can be handed back to the app that's currently picking
  /// - always true for folders (still browsable), mime-filtered for files.
  bool itemMatchesPickFilter(NextcloudItem item) {
    if (item.isFolder) return true;
    final request = _pickRequest;
    return request == null || request.matches(item.mimeType);
  }

  /// Called once (from MainShellView) as soon as a pick request is known -
  /// either the cold-start request or one that arrived via onNewPickRequest
  /// while already running.
  void setPickRequest(PickRequest request) {
    _pickRequest = request;
    notifyListeners();
  }

  /// Downloads each selected item to a scratch cache folder, then hands the
  /// local paths back to the caller through PickIntentService, which closes
  /// the picker Activity on success. Left in [pickRequest] (i.e. picking
  /// mode stays visually active) if the download fails partway, so the user
  /// can see the error and retry rather than the screen finishing under
  /// them with nothing returned to the caller.
  Future<bool> confirmPick(List<NextcloudItem> items) async {
    final service = session.service;
    if (_pickRequest == null || service == null || items.isEmpty) {
      return false;
    }
    _isDownloadingForPick = true;
    notifyListeners();
    try {
      final tempDir = await getTemporaryDirectory();
      final pickDir = Directory(p.join(tempDir.path, 'picker'));
      final localPaths = <String>[];
      final mimeTypes = <String>[];
      for (final item in items) {
        // Each item gets its own subfolder (keyed by id, not smashed into
        // the filename) so two different items can share a plain file
        // name without colliding, while the file on disk - and therefore
        // the display name the caller sees via the content:// Uri
        // MainActivity.kt hands back - stays exactly `item.name`.
        final itemDir = Directory(p.join(pickDir.path, item.id));
        await itemDir.create(recursive: true);
        final localPath = p.join(itemDir.path, item.name);
        await service.downloadToFile(item.path, localPath);
        localPaths.add(localPath);
        mimeTypes.add(item.mimeType ?? 'application/octet-stream');
      }
      await PickIntentService.finishPick(localPaths, mimeTypes);
      _pickRequest = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isDownloadingForPick = false;
      notifyListeners();
    }
  }

  /// Backs out of picking mode entirely, telling the caller nothing was
  /// picked and closing the picker Activity.
  Future<void> cancelPick() async {
    if (_pickRequest == null) return;
    _pickRequest = null;
    notifyListeners();
    await PickIntentService.cancelPick();
  }
}
