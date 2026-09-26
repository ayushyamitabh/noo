import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// File-type buckets from `DESIGN_SYSTEM.md` 1.2 (`KIND` in `noo-kit.js`).
/// Drives the tile tint + icon in `NooFileTile`, `NooFileRow` and
/// `NooFileTableRow`. [other] isn't in the spec table - it's the neutral
/// fallback (archive colors, plain `file` icon) for anything the table
/// doesn't cover (audio, binaries, unknown extensions) so those don't
/// masquerade as an archive or a document.
enum NooFileKind {
  folder,
  pdf,
  doc,
  sheet,
  video,
  image,
  archive,
  other;

  /// Lucide icon for this kind.
  IconData get icon {
    switch (this) {
      case NooFileKind.folder:
        return LucideIcons.folder;
      case NooFileKind.pdf:
      case NooFileKind.doc:
        return LucideIcons.fileText;
      case NooFileKind.sheet:
        return LucideIcons.sheet;
      case NooFileKind.video:
        return LucideIcons.film;
      case NooFileKind.image:
        return LucideIcons.image;
      case NooFileKind.archive:
        return LucideIcons.fileArchive;
      case NooFileKind.other:
        return LucideIcons.file;
    }
  }

  /// Tile background - the soft half of the pair.
  Color background(NooColors colors) {
    switch (this) {
      case NooFileKind.folder:
        return colors.accentSoft;
      case NooFileKind.pdf:
        return colors.dangerSoft;
      case NooFileKind.doc:
      case NooFileKind.image:
        return colors.infoSoft;
      case NooFileKind.sheet:
        return colors.successSoft;
      case NooFileKind.video:
        return colors.warningSoft;
      case NooFileKind.archive:
      case NooFileKind.other:
        return colors.surface3;
    }
  }

  /// Icon color - always the strong half of [background]'s pair.
  Color foreground(NooColors colors) {
    switch (this) {
      case NooFileKind.folder:
        return colors.accentText;
      case NooFileKind.pdf:
        return colors.danger;
      case NooFileKind.doc:
      case NooFileKind.image:
        return colors.info;
      case NooFileKind.sheet:
        return colors.success;
      case NooFileKind.video:
        return colors.warning;
      case NooFileKind.archive:
      case NooFileKind.other:
        return colors.fg2;
    }
  }

  /// Derives a kind from whatever the caller has: [isDirectory] wins, then
  /// [mimeType] (e.g. WebDAV `getcontenttype`), then [name]'s extension.
  static NooFileKind from({
    String? name,
    String? mimeType,
    bool isDirectory = false,
  }) {
    final mime = mimeType?.toLowerCase().trim();
    if (isDirectory || mime == 'httpd/unix-directory') {
      return NooFileKind.folder;
    }
    if (mime != null && mime.isNotEmpty) {
      final byMime = _fromMime(mime);
      if (byMime != null) return byMime;
    }
    if (name != null) {
      final dot = name.lastIndexOf('.');
      if (dot >= 0 && dot < name.length - 1) {
        final byExt = _extensions[name.substring(dot + 1).toLowerCase()];
        if (byExt != null) return byExt;
      }
    }
    return NooFileKind.other;
  }

  static NooFileKind? _fromMime(String mime) {
    if (mime == 'application/pdf') return NooFileKind.pdf;
    if (mime.startsWith('image/')) return NooFileKind.image;
    if (mime.startsWith('video/')) return NooFileKind.video;
    if (mime.contains('spreadsheet') ||
        mime.contains('ms-excel') ||
        mime == 'text/csv') {
      return NooFileKind.sheet;
    }
    if (mime.contains('zip') ||
        mime.contains('compressed') ||
        mime.contains('x-tar') ||
        mime.contains('x-7z') ||
        mime.contains('x-rar') ||
        mime.contains('gzip')) {
      return NooFileKind.archive;
    }
    if (mime.startsWith('text/') ||
        mime.contains('wordprocessing') ||
        mime.contains('msword') ||
        mime.contains('opendocument.text') ||
        mime.contains('presentation') ||
        mime.contains('powerpoint') ||
        mime == 'application/rtf') {
      return NooFileKind.doc;
    }
    // Generic types (application/octet-stream etc.) fall through to the
    // extension check.
    return null;
  }

  static const _extensions = <String, NooFileKind>{
    'pdf': NooFileKind.pdf,
    // doc / text
    'doc': NooFileKind.doc,
    'docx': NooFileKind.doc,
    'odt': NooFileKind.doc,
    'rtf': NooFileKind.doc,
    'txt': NooFileKind.doc,
    'md': NooFileKind.doc,
    'ppt': NooFileKind.doc,
    'pptx': NooFileKind.doc,
    'odp': NooFileKind.doc,
    'pages': NooFileKind.doc,
    // sheet
    'xls': NooFileKind.sheet,
    'xlsx': NooFileKind.sheet,
    'ods': NooFileKind.sheet,
    'csv': NooFileKind.sheet,
    'numbers': NooFileKind.sheet,
    // video
    'mp4': NooFileKind.video,
    'mov': NooFileKind.video,
    'mkv': NooFileKind.video,
    'webm': NooFileKind.video,
    'avi': NooFileKind.video,
    'm4v': NooFileKind.video,
    '3gp': NooFileKind.video,
    // image
    'jpg': NooFileKind.image,
    'jpeg': NooFileKind.image,
    'png': NooFileKind.image,
    'gif': NooFileKind.image,
    'webp': NooFileKind.image,
    'heic': NooFileKind.image,
    'heif': NooFileKind.image,
    'bmp': NooFileKind.image,
    'svg': NooFileKind.image,
    'tif': NooFileKind.image,
    'tiff': NooFileKind.image,
    'dng': NooFileKind.image,
    // archive
    'zip': NooFileKind.archive,
    'tar': NooFileKind.archive,
    'gz': NooFileKind.archive,
    'tgz': NooFileKind.archive,
    'bz2': NooFileKind.archive,
    'xz': NooFileKind.archive,
    '7z': NooFileKind.archive,
    'rar': NooFileKind.archive,
  };
}
