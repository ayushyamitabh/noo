/// Another app asking Noo (via Android's GET_CONTENT chooser) to pick a
/// file/photo and hand it back - see `PickIntentService`/`MainActivity.kt`.
class PickRequest {
  final String mimeType;
  final bool allowMultiple;
  final String? callerLabel;

  const PickRequest({
    required this.mimeType,
    required this.allowMultiple,
    this.callerLabel,
  });

  factory PickRequest.fromMap(Map<dynamic, dynamic> map) {
    return PickRequest(
      mimeType: map['mimeType'] as String? ?? '*/*',
      allowMultiple: map['allowMultiple'] as bool? ?? false,
      callerLabel: map['callerLabel'] as String?,
    );
  }

  /// Whether an item's mime type satisfies this request's filter (which may
  /// be a wildcard like `image/*` or the catch-all `*/*`).
  bool matches(String? itemMimeType) {
    if (mimeType == '*/*') return true;
    if (itemMimeType == null) return false;
    if (mimeType.endsWith('/*')) {
      return itemMimeType.startsWith(
        mimeType.substring(0, mimeType.length - 1),
      );
    }
    return itemMimeType == mimeType;
  }
}
