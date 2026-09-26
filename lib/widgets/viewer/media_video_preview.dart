import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../frosted_glass_container.dart';
import '../seek_bar_painter.dart';
import 'viewer_icon_button.dart';

/// Playing video page for [FileViewerScreen]'s swipeable `PageView`, plus
/// its floating transport controls (play/pause, position, mute, seek bar).
class MediaVideoPreview extends StatefulWidget {
  final String? url;
  final Map<String, String> headers;
  final bool isActive;

  /// When set, read the video from this on-disk path instead of [url] -
  /// already-resolved by the caller (see
  /// `FileViewerScreen.localPathResolver`'s doc comment).
  final String? localPath;

  /// Distance from the bottom of the screen the transport controls should
  /// sit at. Passed in by the parent so the controls can track the floating
  /// action bar: resting just above it when visible, sliding down to hug
  /// the screen edge when the bar (and rest of the chrome) is hidden.
  final double controlsBottomOffset;

  const MediaVideoPreview({
    super.key,
    required this.url,
    required this.headers,
    this.localPath,
    this.isActive = true,
    this.controlsBottomOffset = 24,
  });

  @override
  State<MediaVideoPreview> createState() => _MediaVideoPreviewState();
}

class _MediaVideoPreviewState extends State<MediaVideoPreview> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = widget.localPath != null
          ? VideoPlayerController.file(File(widget.localPath!))
          : VideoPlayerController.networkUrl(
              Uri.parse(widget.url!),
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
  void didUpdateWidget(covariant MediaVideoPreview oldWidget) {
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
    final colors = context.nooColors;
    final progressBarStyle = context
        .watch<SettingsController>()
        .mediaProgressBarStyle;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not play video: $_error',
          style: TextStyle(color: colors.fg2),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
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
                final fg = colors.fg1;
                // Same frosted-glass treatment (and user opacity/blur
                // settings) as the back button and media action bar, so the
                // transport controls match the rest of the app's chrome.
                return FrostedGlassContainer(
                  borderRadius: 24,
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
                            ViewerIconButton(
                              icon: controller.value.isPlaying
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
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
                                style: NooText.meta.copyWith(color: fg),
                              ),
                            ),
                            ViewerIconButton(
                              icon: controller.value.volume == 0
                                  ? LucideIcons.volumeX
                                  : LucideIcons.volume2,
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
                          child: WavySeekBar(
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
/// anywhere on it to seek. Still driven by [SeekBarPainter] (shared with the
/// Settings style picker's preview) - only [playedColor]/[trackColor] come
/// from [NooColors] now instead of `ColorScheme`.
class WavySeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final Color playedColor;
  final Color trackColor;
  final MediaProgressBarStyle style;

  const WavySeekBar({
    super.key,
    required this.controller,
    required this.playedColor,
    required this.trackColor,
    required this.style,
  });

  @override
  State<WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<WavySeekBar>
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
