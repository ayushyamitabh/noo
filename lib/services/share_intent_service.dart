import 'package:flutter/services.dart';

/// A file shared to Noo from another app's "Share to..." sheet, before its
/// bytes have been touched - just the `content://` Uri and whatever cheap
/// metadata Android will hand over without reading the file itself.
class SharedFileRef {
  final String uri;
  final String name;
  final String? mimeType;
  final int? size;

  const SharedFileRef({
    required this.uri,
    required this.name,
    this.mimeType,
    this.size,
  });

  factory SharedFileRef.fromMap(Map<dynamic, dynamic> map) {
    return SharedFileRef(
      uri: map['uri'] as String,
      name: map['name'] as String? ?? 'shared_file',
      mimeType: map['mimeType'] as String?,
      size: (map['size'] as num?)?.toInt(),
    );
  }
}

/// Talks to `MainActivity.kt`'s hand-rolled share-intent handling (see its
/// doc comment for why this isn't the receive_sharing_intent plugin): it
/// only ever exposes cheap Uri metadata up front. Actually reading a shared
/// file's bytes - preparing and uploading it - is [UploadService]'s job
/// (`ShareUploadService.kt`'s Android foreground service), not this one.
class ShareIntentService {
  static const _methodChannel = MethodChannel('dev.ayushya.noo/share_intent');
  static const _newShareChannel = EventChannel(
    'dev.ayushya.noo/share_intent/new',
  );

  /// Whatever was shared to launch the app cold (empty if it was launched
  /// normally, not via a share).
  static Future<List<SharedFileRef>> getInitialShare() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>(
      'getInitialShare',
    );
    return (result ?? [])
        .cast<Map<dynamic, dynamic>>()
        .map(SharedFileRef.fromMap)
        .toList();
  }

  /// Emits whenever another share arrives while the app is already running.
  static Stream<List<SharedFileRef>> get onNewShare {
    return _newShareChannel.receiveBroadcastStream().map((event) {
      return (event as List<dynamic>)
          .cast<Map<dynamic, dynamic>>()
          .map(SharedFileRef.fromMap)
          .toList();
    });
  }
}
