import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../services/download_service.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/frosted_glass_container.dart';
import '../widgets/marquee_title.dart';
import '../widgets/seek_bar_painter.dart';
import '../widgets/share_sheet.dart';

const _textPreviewExtensions = {
  '.txt',
  '.md',
  '.json',
  '.yaml',
  '.yml',
  '.xml',
  '.log',
  '.csv',
  '.dart',
  '.js',
  '.ts',
  '.py',
  '.java',
  '.kt',
  '.swift',
  '.c',
  '.cpp',
  '.h',
  '.sh',
  '.bat',
  '.ini',
  '.conf',
  '.gradle',
  '.html',
  '.css',
};

class FileViewerScreen extends StatefulWidget {
  final NextcloudItem item;

  /// The other items in the same folder/album, so images and videos can be
  /// swiped through without leaving the viewer. Non-media items in this list
  /// are ignored. If omitted (or the item isn't an image/video), the viewer
  /// just shows [item] on its own.
  final List<NextcloudItem>? siblings;

  const FileViewerScreen({super.key, required this.item, this.siblings});

  /// Opens the viewer with no page transition — media should appear
  /// instantly, not fade/zoom in the way MaterialPageRoute normally would.
  /// Going *back* still uses the theme's normal (predictive-back-capable)
  /// transition, via [_InstantOpenPageRoute] below.
  static Route<void> route({
    required NextcloudItem item,
    List<NextcloudItem>? siblings,
  }) {
    return _InstantOpenPageRoute<void>(
      pageBuilder: (context) =>
          FileViewerScreen(item: item, siblings: siblings),
    );
  }

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

/// A [PageRoute] that opens instantly (zero-duration forward transition)
/// but still delegates to the app's [PageTransitionsTheme] for the reverse
/// transition — unlike a plain [PageRouteBuilder] with no transitionsBuilder,
/// which never consults the theme and so can't participate in Android's
/// predictive-back gesture at all.
class _InstantOpenPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _InstantOpenPageRoute({required this.pageBuilder, super.settings});

  final WidgetBuilder pageBuilder;

  @override
  Widget buildContent(BuildContext context) => pageBuilder(context);

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  double? _downloadProgress;
  bool _isBusy = false;
  bool _controlsVisible = true;

  late final bool _isSwipeable;
  late final List<NextcloudItem> _mediaItems;
  late int _currentIndex;
  late final PageController _pageController;

  NextcloudItem get _currentItem => _mediaItems[_currentIndex];

  bool get _isPdf => _currentItem.name.toLowerCase().endsWith('.pdf');
  bool get _isText => _textPreviewExtensions.contains(
    p.extension(_currentItem.name).toLowerCase(),
  );

  @override
  void initState() {
    super.initState();
    _isSwipeable =
        widget.item.type == NextcloudItemType.image ||
        widget.item.type == NextcloudItemType.video;

    if (_isSwipeable) {
      final source = widget.siblings ?? [widget.item];
      _mediaItems = source
          .where(
            (i) =>
                i.type == NextcloudItemType.image ||
                i.type == NextcloudItemType.video,
          )
          .toList();
      if (_mediaItems.isEmpty) _mediaItems = [widget.item];
      final idx = _mediaItems.indexWhere((i) => i.path == widget.item.path);
      _currentIndex = idx >= 0 ? idx : 0;
    } else {
      _mediaItems = [widget.item];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String> _downloadToTemp(
    ServerProvider provider,
    NextcloudItem item,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final savePath = p.join(tempDir.path, item.name);
    setState(() => _downloadProgress = 0);
    await provider.service!.downloadToFile(
      item.path,
      savePath,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      },
    );
    if (mounted) setState(() => _downloadProgress = null);
    return savePath;
  }

  Future<void> _openExternally(ServerProvider provider) async {
    final item = _currentItem;
    setState(() => _isBusy = true);
    try {
      final path = await _downloadToTemp(provider, item);
      final result = await OpenFile.open(path);
      if (mounted && result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open ${item.name}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Hands off to `DownloadService.kt` (see its doc comment) rather than
  /// downloading in Dart then prompting `file_saver` - same reasoning as
  /// `UploadService`/`ShareUploadService.kt` on the upload side: a real
  /// Android Service survives the app being closed mid-download, and one
  /// notification covers progress/cancel instead of blocking this screen.
  Future<void> _downloadToDevice(ServerProvider provider) async {
    final item = _currentItem;
    try {
      await DownloadService.startDownload(provider, [item]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloading ${item.name} - see the notification for progress',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _toggleFavorite(ServerProvider provider) async {
    final item = _currentItem;
    await provider.toggleItemFavorite(item);
    if (!mounted) return;
    setState(() {
      _mediaItems[_currentIndex] = item.copyWith(isFavorite: !item.isFavorite);
    });
  }

  Future<void> _deleteCurrentItem(ServerProvider provider) async {
    final item = _currentItem;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete file'),
          content: Text(
            'Delete "${item.name}" from the server? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final success = await provider.deleteItem(item.path);
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete ${item.name}')));
      return;
    }

    setState(() {
      _mediaItems.removeAt(_currentIndex);
      if (_mediaItems.isNotEmpty && _currentIndex >= _mediaItems.length) {
        _currentIndex = _mediaItems.length - 1;
      }
    });

    if (_mediaItems.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (_isSwipeable && _pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ServerProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: colorScheme.surface,
                child: _buildBody(context, provider),
              ),
            ),
            if (_downloadProgress != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.onSurface.withValues(
                    alpha: 0.16,
                  ),
                ),
              ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              offset: _controlsVisible ? Offset.zero : const Offset(0, -1.4),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: FrostedGlassContainer(
                      opacity: provider.bottomBarOpacity,
                      blurSigma: provider.bottomBarBlur,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            _ActionIconButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: 'Back',
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: MarqueeTitle(
                                text: _currentItem.name,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                offset: _controlsVisible ? Offset.zero : const Offset(0, 1.4),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _MediaActionBar(
                    isFavorite: _currentItem.isFavorite,
                    isBusy: _isBusy,
                    opacity: provider.bottomBarOpacity,
                    blurSigma: provider.bottomBarBlur,
                    onShare: () => ShareSheet.show(context, _currentItem),
                    onFavorite: () => _toggleFavorite(provider),
                    onDelete: () => _deleteCurrentItem(provider),
                    onOpenExternally: () => _openExternally(provider),
                    onDownload: () => _downloadToDevice(provider),
                    onDetails: () => DetailsSheet.show(context, _currentItem),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ServerProvider provider) {
    if (!_isSwipeable) {
      return _buildStaticPreview(context, provider);
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _mediaItems.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: (context, index) {
        final mediaItem = _mediaItems[index];
        if (mediaItem.type == NextcloudItemType.image) {
          return _ImagePreview(
            key: ValueKey(mediaItem.id),
            url: provider.service!.fileUrl(mediaItem.path),
            headers: provider.service!.authHeaders,
          );
        }
        return _VideoPreview(
          key: ValueKey(mediaItem.id),
          url: provider.service!.fileUrl(mediaItem.path),
          headers: provider.service!.authHeaders,
          isActive: index == _currentIndex,
          controlsBottomOffset: _controlsVisible ? 108 : 24,
          opacity: provider.bottomBarOpacity,
          blurSigma: provider.bottomBarBlur,
        );
      },
    );
  }

  Widget _buildStaticPreview(BuildContext context, ServerProvider provider) {
    switch (widget.item.type) {
      case NextcloudItemType.image:
      case NextcloudItemType.video:
        // Unreachable: these types are always handled by the swipeable path.
        return const SizedBox.shrink();
      default:
        if (_isPdf) {
          return _PdfPreview(item: widget.item, provider: provider);
        }
        if (_isText) {
          return _TextPreview(item: widget.item, provider: provider);
        }
        return _UnsupportedPreview(
          item: widget.item,
          isBusy: _isBusy,
          onOpenExternally: () => _openExternally(provider),
          onOpenDetails: () => DetailsSheet.show(context, widget.item),
        );
    }
  }
}

/// The floating action bar (share/favorite/open/download/delete), sized and
/// positioned to match the app-wide frosted-glass bottom navigation bar.
class _MediaActionBar extends StatelessWidget {
  final bool isFavorite;
  final bool isBusy;
  final double opacity;
  final double blurSigma;
  final VoidCallback onShare;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onOpenExternally;
  final VoidCallback onDownload;
  final VoidCallback onDetails;

  const _MediaActionBar({
    required this.isFavorite,
    required this.isBusy,
    required this.opacity,
    required this.blurSigma,
    required this.onShare,
    required this.onFavorite,
    required this.onDelete,
    required this.onOpenExternally,
    required this.onDownload,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FrostedGlassContainer(
            opacity: opacity,
            blurSigma: blurSigma,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionIconButton(
                    icon: Icons.share_rounded,
                    tooltip: 'Share',
                    onTap: isBusy ? null : onShare,
                  ),
                  _ActionIconButton(
                    icon: isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    tooltip: 'Favorite',
                    color: isFavorite ? Colors.red : null,
                    onTap: onFavorite,
                  ),
                  _ActionIconButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Open externally',
                    onTap: isBusy ? null : onOpenExternally,
                  ),
                  _ActionIconButton(
                    icon: Icons.download_rounded,
                    tooltip: 'Download',
                    onTap: isBusy ? null : onDownload,
                  ),
                  _ActionIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    color: colorScheme.error,
                    onTap: isBusy ? null : onDelete,
                  ),
                  _ActionIconButton(
                    icon: Icons.info_outline_rounded,
                    tooltip: 'Details',
                    onTap: onDetails,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = onTap == null
        ? colorScheme.onSurface.withValues(alpha: 0.4)
        : (color ?? colorScheme.onSurface);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Icon(icon, color: fg, size: 22),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatefulWidget {
  final String url;
  final Map<String, String> headers;

  const _ImagePreview({super.key, required this.url, required this.headers});

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview>
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
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: GestureDetector(
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: Image.network(
              widget.url,
              headers: widget.headers,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(color: colorScheme.primary),
                );
              },
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: colorScheme.onSurfaceVariant,
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

class _VideoPreview extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final bool isActive;

  /// Distance from the bottom of the screen the transport controls should
  /// sit at. Passed in by the parent so the controls can track the floating
  /// action bar: resting just above it when visible, sliding down to hug
  /// the screen edge when the bar (and rest of the chrome) is hidden.
  final double controlsBottomOffset;

  /// Opacity/blur for the transport controls' frosted-glass background,
  /// matching the app-wide bottom bar and media action bar styling.
  final double opacity;
  final double blurSigma;

  const _VideoPreview({
    super.key,
    required this.url,
    required this.headers,
    this.isActive = true,
    this.controlsBottomOffset = 24,
    this.opacity = 0.55,
    this.blurSigma = 28,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: widget.headers,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (widget.isActive) controller.play();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progressBarStyle = context
        .watch<ServerProvider>()
        .mediaProgressBarStyle;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not play video: $_error',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            left: 16,
            right: 16,
            bottom: widget.controlsBottomOffset,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final colorScheme = Theme.of(context).colorScheme;
                final fg = colorScheme.onSurface;
                // Same frosted-glass treatment (and user opacity/blur
                // settings) as the back button and media action bar, so the
                // transport controls match the rest of the app's chrome.
                return FrostedGlassContainer(
                  borderRadius: 24,
                  opacity: widget.opacity,
                  blurSigma: widget.blurSigma,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _ActionIconButton(
                              icon: controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              tooltip: controller.value.isPlaying
                                  ? 'Pause'
                                  : 'Play',
                              onTap: () => controller.value.isPlaying
                                  ? controller.pause()
                                  : controller.play(),
                            ),
                            Expanded(
                              child: Text(
                                '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: fg, fontSize: 13),
                              ),
                            ),
                            _ActionIconButton(
                              icon: controller.value.volume == 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              tooltip: controller.value.volume == 0
                                  ? 'Unmute'
                                  : 'Mute',
                              onTap: () => controller.setVolume(
                                controller.value.volume == 0 ? 1 : 0,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _WavySeekBar(
                            controller: controller,
                            playedColor: fg,
                            trackColor: fg.withValues(alpha: 0.3),
                            style: progressBarStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A Material You "expressive" wavy seek bar: the played portion of the
/// track animates as a travelling sine wave while playing and settles flat
/// when paused, matching the Android 16+ media player style. Drag or tap
/// anywhere on it to seek.
class _WavySeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final Color playedColor;
  final Color trackColor;
  final MediaProgressBarStyle style;

  const _WavySeekBar({
    required this.controller,
    required this.playedColor,
    required this.trackColor,
    required this.style,
  });

  @override
  State<_WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<_WavySeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  double? _dragRatio;

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _seekToRatio(double ratio) {
    final duration = widget.controller.value.duration;
    widget.controller.seekTo(duration * ratio.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final animatesWave =
        widget.style == MediaProgressBarStyle.wavy ||
        widget.style == MediaProgressBarStyle.squiggly;
    final isPlaying = animatesWave && value.isPlaying && _dragRatio == null;
    if (isPlaying && !_waveController.isAnimating) {
      _waveController.repeat();
    } else if (!isPlaying && _waveController.isAnimating) {
      _waveController.stop();
    }

    final durationMs = value.duration.inMilliseconds;
    final baseRatio = durationMs > 0
        ? value.position.inMilliseconds / durationMs
        : 0.0;
    final ratio = (_dragRatio ?? baseRatio).clamp(0.0, 1.0);

    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void updateFromDx(double dx) {
            setState(
              () => _dragRatio = (dx / constraints.maxWidth).clamp(0.0, 1.0),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) =>
                updateFromDx(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                updateFromDx(details.localPosition.dx),
            onHorizontalDragEnd: (_) {
              if (_dragRatio != null) _seekToRatio(_dragRatio!);
              setState(() => _dragRatio = null);
            },
            onTapUp: (details) =>
                _seekToRatio(details.localPosition.dx / constraints.maxWidth),
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, 28),
                  painter: SeekBarPainter(
                    style: widget.style,
                    progress: ratio,
                    phase: _waveController.value * 2 * math.pi,
                    animate: isPlaying,
                    playedColor: widget.playedColor,
                    trackColor: widget.trackColor,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _PdfPreview extends StatefulWidget {
  final NextcloudItem item;
  final ServerProvider provider;

  const _PdfPreview({required this.item, required this.provider});

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.provider.service!.fetchBytes(widget.item.path);
      if (!mounted) return;
      setState(() {
        _controller = PdfControllerPinch(
          document: PdfDocument.openData(Uint8List.fromList(bytes)),
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
    final colorScheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load PDF: $_error',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_controller == null) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
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

class _TextPreview extends StatefulWidget {
  final NextcloudItem item;
  final ServerProvider provider;

  const _TextPreview({required this.item, required this.provider});

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.provider.service!.fetchBytes(widget.item.path);
      if (mounted) {
        setState(() => _content = utf8.decode(bytes, allowMalformed: true));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load file: $_error',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_content == null) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: SelectableText(
          _content!,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _UnsupportedPreview extends StatelessWidget {
  final NextcloudItem item;
  final bool isBusy;
  final VoidCallback onOpenExternally;
  final VoidCallback onOpenDetails;

  const _UnsupportedPreview({
    required this.item,
    required this.isBusy,
    required this.onOpenExternally,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 72,
            ),
            const SizedBox(height: 16),
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No inline preview for this file type.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: isBusy ? null : onOpenExternally,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open with...'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenDetails,
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('Details'),
            ),
          ],
        ),
      ),
    );
  }
}
