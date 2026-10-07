import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../seek_bar_painter.dart';
import 'viewer_icon_button.dart';

/// Playing video page for [FileViewerScreen]'s swipeable `PageView`. Just
/// the video surface - the transport controls ([VideoTransportControls])
/// are built by the parent, inside the same bottom panel as
/// [MediaActionBar], once this reports its controller up via
/// [onController]. Keeping playback lifecycle (`initState`/`dispose`) here
/// and the controls' *presentation* in the parent is what lets both sit in
/// one continuous panel without the parent owning playback.
class MediaVideoPreview extends StatefulWidget {
  final String? url;
  final Map<String, String> headers;
  final bool isActive;

  /// When set, read the video from this on-disk path instead of [url] -
  /// already-resolved by the caller (see
  /// `FileViewerScreen.localPathResolver`'s doc comment).
  final String? localPath;

  /// Reports the live controller once initialized, and `null` on dispose,
  /// so the parent can render [VideoTransportControls] for it. The parent
  /// only passes this for the *active* page (see `file_viewer_screen.dart`'s
  /// `_buildBody`) - a neighboring, inactive `PageView` page never reports
  /// up, so an adjacent video can't steal the transport row.
  final ValueChanged<VideoPlayerController?>? onController;

  const MediaVideoPreview({
    super.key,
    required this.url,
    required this.headers,
    this.localPath,
    this.isActive = true,
    this.onController,
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
      widget.onController?.call(controller);
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
    // Newly given a callback (this page just became active) and already
    // initialized: report it, but not synchronously - `didUpdateWidget`
    // runs as part of the *parent's* own widget-tree update (the
    // `onPageChanged` setState that made this page active), and the
    // parent's `onController` calls `setState` itself, which would trip
    // "setState called during build" if invoked in the same pass. Defer to
    // the next frame instead of waiting for `_init` (which won't run again).
    if (oldWidget.onController == null &&
        widget.onController != null &&
        _controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onController!(_controller);
      });
    }
  }

  @override
  void dispose() {
    widget.onController?.call(null);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
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
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// The transport row content (play/pause, position, mute, seek bar) for
/// [controller] - no panel chrome of its own. Rendered by
/// `file_viewer_screen.dart` inside the same bottom panel as
/// [MediaActionBar], directly above the action row, once
/// [MediaVideoPreview.onController] reports a live controller.
class VideoTransportControls extends StatelessWidget {
  final VideoPlayerController controller;

  const VideoTransportControls({super.key, required this.controller});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progressBarStyle = context
        .watch<SettingsController>()
        .mediaProgressBarStyle;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final fg = context.nooColors.fg1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ViewerIconButton(
                    icon: controller.value.isPlaying
                        ? LucideIcons.pause
                        : LucideIcons.play,
                    tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
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
                    tooltip: controller.value.volume == 0 ? 'Unmute' : 'Mute',
                    onTap: () => controller.setVolume(
                      controller.value.volume == 0 ? 1 : 0,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Theme.of(context).platform == TargetPlatform.iOS
                    ? IosSeekBar(controller: controller, color: fg)
                    : WavySeekBar(
                        controller: controller,
                        playedColor: fg,
                        trackColor: fg.withValues(alpha: 0.3),
                        style: progressBarStyle,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class IosSeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final Color color;
  const IosSeekBar({super.key, required this.controller, required this.color});

  @override
  State<IosSeekBar> createState() => _IosSeekBarState();
}

class _IosSeekBarState extends State<IosSeekBar> {
  double? _dragRatio;
  bool _resumeAfterScrubbing = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final durationMs = value.duration.inMilliseconds;
    final ratio =
        (_dragRatio ??
                (durationMs > 0
                    ? value.position.inMilliseconds / durationMs
                    : 0.0))
            .clamp(0.0, 1.0);
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlider(
        value: ratio,
        activeColor: widget.color,
        thumbColor: CupertinoColors.white,
        onChangeStart: durationMs <= 0
            ? null
            : (_) {
                _resumeAfterScrubbing = value.isPlaying;
                if (_resumeAfterScrubbing) widget.controller.pause();
              },
        onChanged: durationMs <= 0
            ? null
            : (ratio) {
                setState(() => _dragRatio = ratio);
                widget.controller.seekTo(value.duration * ratio);
              },
        onChangeEnd: durationMs <= 0
            ? null
            : (ratio) async {
                await widget.controller.seekTo(value.duration * ratio);
                if (!mounted) return;
                setState(() => _dragRatio = null);
                if (_resumeAfterScrubbing) widget.controller.play();
              },
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
