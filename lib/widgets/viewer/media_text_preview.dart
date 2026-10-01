import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';

/// Plain monospace text-file preview for [FileViewerScreen]'s static (non-
/// swipeable) preview path (`_textPreviewExtensions`).
class MediaTextPreview extends StatefulWidget {
  final NextcloudItem item;
  final SessionController session;

  /// When set, read bytes from the local path it resolves to instead of
  /// fetching from the server - see
  /// `FileViewerScreen.localPathResolver`'s doc comment.
  final Future<String?> Function(NextcloudItem item)? localPathResolver;

  const MediaTextPreview({
    super.key,
    required this.item,
    required this.session,
    this.localPathResolver,
  });

  @override
  State<MediaTextPreview> createState() => _MediaTextPreviewState();
}

class _MediaTextPreviewState extends State<MediaTextPreview> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<int> bytes;
      if (widget.localPathResolver != null) {
        final localPath = await widget.localPathResolver!(widget.item);
        if (localPath == null) {
          if (mounted) {
            setState(() => _error = 'No longer available offline');
          }
          return;
        }
        bytes = await File(localPath).readAsBytes();
      } else {
        bytes = await widget.session.service!.fetchBytes(widget.item.path);
      }
      if (mounted) {
        setState(() => _content = utf8.decode(bytes, allowMalformed: true));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load file: $_error',
          style: TextStyle(color: colors.fg2),
        ),
      );
    }
    if (_content == null) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: SelectableText(
          _content!,
          style: NooText.mono.copyWith(color: colors.fg1, height: 1.5),
        ),
      ),
    );
  }
}
