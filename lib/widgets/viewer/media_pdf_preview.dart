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

  /// Stable space reserved above the page for the overlaid top bar.
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
    // pdfx's InteractiveViewer also refuses to zoom out past
    // `viewport.height / document.height`. When the whole document is
    // shorter than the screen (e.g. a one-page PDF) that ratio is above 1, so
    // after pinching in, fit-width (scale 1) becomes unreachable. PdfViewPinch
    // wraps its content in a SafeArea, which counts MediaQuery padding toward
    // that document height, so padding the bottom up to the viewport height
    // keeps the ratio at or below 1 without shrinking the gesture area.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      padding: EdgeInsets.only(top: widget.topInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          var padding = media.padding.copyWith(top: 0);
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
            final needed = constraints.maxHeight - docHeight;
            if (needed > padding.bottom) {
              padding = padding.copyWith(bottom: needed);
            }
          }
          return MediaQuery(
            data: media.copyWith(padding: padding),
            child: PdfViewPinch(controller: _controller!),
          );
        },
      ),
    );
  }
}
