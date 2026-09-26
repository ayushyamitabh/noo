import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/design_tokens.dart';

/// Pinch-zoom/pan/double-tap-to-zoom image page for [FileViewerScreen]'s
/// swipeable `PageView` - one instance per image, from either a server URL
/// or an on-disk path (offline mode).
class MediaImagePreview extends StatefulWidget {
  final String? url;
  final Map<String, String> headers;

  /// When set, read the image from this on-disk path instead of [url] -
  /// already-resolved by the caller (see
  /// `FileViewerScreen.localPathResolver`'s doc comment).
  final String? localPath;

  const MediaImagePreview({
    super.key,
    required this.url,
    required this.headers,
    this.localPath,
  });

  @override
  State<MediaImagePreview> createState() => _MediaImagePreviewState();
}

class _MediaImagePreviewState extends State<MediaImagePreview>
    with SingleTickerProviderStateMixin {
  static const _doubleTapScale = 3.0;

  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (_animation != null) {
            _transformController.value = _animation!.value;
          }
        });
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    final isZoomedIn = _transformController.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 endMatrix;
    if (isZoomedIn) {
      endMatrix = Matrix4.identity();
    } else {
      final p = _doubleTapPosition;
      endMatrix = Matrix4.identity()
        ..translateByDouble(
          -p.dx * (_doubleTapScale - 1),
          -p.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
    }
    _animation = Matrix4Tween(
      begin: _transformController.value,
      end: endMatrix,
    ).animate(CurveTween(curve: Curves.easeOut).animate(_animController));
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return SizedBox.expand(
      child: GestureDetector(
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: widget.localPath != null
                ? Image.file(
                    File(widget.localPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Center(
                      child: Icon(
                        LucideIcons.imageOff,
                        color: colors.fg3,
                        size: 64,
                      ),
                    ),
                  )
                : Image.network(
                    widget.url!,
                    headers: widget.headers,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(color: colors.accent),
                      );
                    },
                    errorBuilder: (context, error, stack) => Center(
                      child: Icon(
                        LucideIcons.imageOff,
                        color: colors.fg3,
                        size: 64,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
