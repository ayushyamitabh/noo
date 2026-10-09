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

  /// Height the overlaid top bar covers. Only a document taller than the
  /// screen uses it - as leading space that scrolls away with the first
  /// page - so the bar never leaves a fixed, unusable band once it's
  /// dismissed. A document that fits is centered in the full screen instead.
  final double topInset;

  const MediaPdfPreview({
    super.key,
    this.topInset = 0,
    required this.item,
    required this.session,
    this.localPathResolver,
  });

  @override
  State<MediaPdfPreview> createState() => _MediaPdfPreviewState();
}

class _MediaPdfPreviewState extends State<MediaPdfPreview> {
  // Only the first few pages are measured; longer documents are assumed
  // taller than any screen.
  static const _sizedPages = 3;

  PdfControllerPinch? _controller;
  String? _error;
  List<Size> _pageSizes = const [];
  int _pageCount = 0;

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
      final document = await PdfDocument.openData(bytes);
      final sizes = <Size>[];
      for (var i = 1; i <= document.pagesCount && i <= _sizedPages; i++) {
        // autoCloseAndroid closes the previous page itself; closing here too throws.
        final page = await document.getPage(i, autoCloseAndroid: true);
        sizes.add(Size(page.width, page.height));
      }
      if (!mounted) {
        await document.close();
        return;
      }
      setState(() {
        _pageSizes = sizes;
        _pageCount = document.pagesCount;
        _controller = PdfControllerPinch(document: Future.value(document));
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
    // Keep minScale at (not below) 1.0: pdfx's PdfViewPinch hard-codes an
    // *infinite* boundaryMargin whenever minScale < 1 (its own
    // pdf_view_pinch.dart), meaning the page could be panned arbitrarily
    // far off-screen with no way back short of reopening the viewer, even
    // without ever pinching to zoom. There's no way to override that
    // margin from here - it isn't an exposed parameter - so this avoids
    // the branch that sets it instead of fighting it.
    //
    // The page fills the whole screen (behind the overlaid bars) rather than
    // the area below the top bar: PdfViewPinch wraps its pages in a SafeArea
    // *inside* its InteractiveViewer, so MediaQuery padding becomes part of
    // the pannable content, not a fixed band. Splitting the leftover height
    // evenly above and below a document that fits centers it, and once
    // zoomed the page can still be panned across the full screen.
    //
    // The padding also has to bring the content up to the viewport height:
    // pdfx's InteractiveViewer refuses to zoom out past
    // `viewport.height / document.height`, so for a document shorter than
    // the screen (e.g. a one-page PDF) fit-width (scale 1) would otherwise
    // become unreachable after pinching in.
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        var padding = media.padding.copyWith(top: widget.topInset);
        if (_pageSizes.isNotEmpty && _pageSizes.length == _pageCount) {
          const pagePadding = 10.0; // PdfViewPinch's default `padding`
          final maxWidth = _pageSizes.fold<double>(
            0,
            (m, s) => s.width > m ? s.width : m,
          );
          final ratio = (constraints.maxWidth - pagePadding * 2) / maxWidth;
          final docHeight = _pageSizes.fold<double>(
            pagePadding,
            (h, s) => h + s.height * ratio + pagePadding,
          );
          final spare = constraints.maxHeight - docHeight;
          if (spare > 0) {
            padding = padding.copyWith(top: spare / 2, bottom: spare / 2);
          }
        }
        return MediaQuery(
          data: media.copyWith(padding: padding),
          child: PdfViewPinch(controller: _controller!),
        );
      },
    );
  }
}
