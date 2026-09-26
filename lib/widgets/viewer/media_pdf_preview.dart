import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';

/// Pinch-zoomable PDF page viewer for [FileViewerScreen]'s static (non-
/// swipeable) preview path.
class MediaPdfPreview extends StatefulWidget {
  final NextcloudItem item;
  final SessionController session;

  /// When set, read bytes from the local path it resolves to instead of
  /// fetching from the server - see
  /// `FileViewerScreen.localPathResolver`'s doc comment.
  final Future<String?> Function(NextcloudItem item)? localPathResolver;

  const MediaPdfPreview({
    super.key,
    required this.item,
    required this.session,
    this.localPathResolver,
  });

  @override
  State<MediaPdfPreview> createState() => _MediaPdfPreviewState();
}

class _MediaPdfPreviewState extends State<MediaPdfPreview> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes;
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
        bytes = Uint8List.fromList(
          await widget.session.service!.fetchBytes(widget.item.path),
        );
      }
      if (!mounted) return;
      setState(() {
        _controller = PdfControllerPinch(
          document: PdfDocument.openData(bytes),
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load PDF: $_error',
          style: TextStyle(color: colors.fg2),
        ),
      );
    }
    if (_controller == null) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    // pdfx's own default minScale (1.0 = the page's true/100% size) is
    // often *larger* than the fit-to-width size a wide page first renders
    // at, since that initial render is just normal box layout, not the
    // InteractiveViewer transform pinching engages on first touch - so the
    // moment you touch the page it snaps up to 1.0 and, with the default
    // floor, can never pinch back down past it. A low floor here lets you
    // zoom back out past that to the fit-width view you started at.
    return PdfViewPinch(controller: _controller!, minScale: 0.3);
  }
}
