import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../providers/settings_controller.dart';

/// Draws a video seek bar in one of the four [MediaProgressBarStyle]
/// presets. Shared by the actual in-player seek bar and the small previews
/// in the style picker, so a preview always looks exactly like the real
/// thing.
class SeekBarPainter extends CustomPainter {
  final MediaProgressBarStyle style;
  final double progress;
  final double phase;
  final bool animate;
  final Color playedColor;
  final Color trackColor;

  static const _waveLength = 16.0;
  static const _amplitude = 3.5;

  SeekBarPainter({
    required this.style,
    required this.progress,
    required this.phase,
    required this.animate,
    required this.playedColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case MediaProgressBarStyle.classic:
        _paintClassic(canvas, size);
      case MediaProgressBarStyle.slim:
        _paintSlim(canvas, size);
      case MediaProgressBarStyle.wavy:
        _paintWave(canvas, size, tickThumb: false);
      case MediaProgressBarStyle.squiggly:
        _paintWave(canvas, size, tickThumb: true);
    }
  }

  /// Material 3 slider look: a thick rounded active track, a small gap, a
  /// pill-shaped thumb, another gap, then a thin inactive track ending in a
  /// small stop-indicator dot.
  void _paintClassic(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final playedX = size.width * progress;
    const thumbWidth = 4.0;
    const thumbHeight = 16.0;
    const gap = 5.0;

    final activeEnd = (playedX - thumbWidth / 2 - gap).clamp(0.0, size.width);
    final inactiveStart = (playedX + thumbWidth / 2 + gap).clamp(
      0.0,
      size.width,
    );

    if (activeEnd > 0) {
      final activePaint = Paint()
        ..color = playedColor
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(3, midY), Offset(activeEnd, midY), activePaint);
    }

    const dotRadius = 2.0;
    final inactiveEnd = size.width - dotRadius * 2 - 2;
    if (inactiveStart < inactiveEnd) {
      final inactivePaint = Paint()
        ..color = trackColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(inactiveStart, midY),
        Offset(inactiveEnd, midY),
        inactivePaint,
      );
    }
    if (progress < 1) {
      canvas.drawCircle(
        Offset(size.width - dotRadius, midY),
        dotRadius,
        Paint()..color = trackColor,
      );
    }

    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(playedX, midY),
        width: thumbWidth,
        height: thumbHeight,
      ),
      const Radius.circular(thumbWidth / 2),
    );
    canvas.drawRRect(thumbRect, Paint()..color = playedColor);
  }

  /// A single continuous flat bar with no distinct thumb - just a filled
  /// rounded-rect progress fill over a rounded-rect track, like a thicker
  /// [LinearProgressIndicator].
  void _paintSlim(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final playedX = size.width * progress;
    const thickness = 6.0;
    const radius = Radius.circular(thickness / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          0,
          midY - thickness / 2,
          size.width,
          midY + thickness / 2,
        ),
        radius,
      ),
      Paint()..color = trackColor,
    );
    if (playedX > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, midY - thickness / 2, playedX, midY + thickness / 2),
          radius,
        ),
        Paint()..color = playedColor,
      );
    }
  }

  /// The played portion animates as a travelling sine wave while playing and
  /// settles flat when paused; the remaining track is a thin straight line.
  /// The thumb is either a round dot ([MediaProgressBarStyle.wavy]) or a
  /// vertical tick ([MediaProgressBarStyle.squiggly]).
  void _paintWave(Canvas canvas, Size size, {required bool tickThumb}) {
    final midY = size.height / 2;
    final playedX = size.width * progress;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (playedX < size.width) {
      canvas.drawLine(
        Offset(playedX, midY),
        Offset(size.width, midY),
        trackPaint,
      );
    }

    final playedPaint = Paint()
      ..color = playedColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    var started = false;
    for (var x = 0.0; x <= playedX; x += 2) {
      final y = animate
          ? midY +
                _amplitude * math.sin((x / _waveLength) * 2 * math.pi + phase)
          : midY;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, playedPaint);

    if (tickThumb) {
      final tickPaint = Paint()
        ..color = playedColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(playedX, midY - 7),
        Offset(playedX, midY + 7),
        tickPaint,
      );
    } else {
      canvas.drawCircle(Offset(playedX, midY), 6, Paint()..color = playedColor);
    }
  }

  @override
  bool shouldRepaint(covariant SeekBarPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.animate != animate ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.trackColor != trackColor;
  }
}

/// A small, perpetually-looping demo of [SeekBarPainter] - sweeps the
/// "played" position back and forth and keeps the wave phase animating, so
/// the four [MediaProgressBarStyle] presets are easy to tell apart at a
/// glance in Settings without needing a real video playing.
class SeekBarPreview extends StatefulWidget {
  final MediaProgressBarStyle style;
  final Color playedColor;
  final Color trackColor;

  const SeekBarPreview({
    super.key,
    required this.style,
    required this.playedColor,
    required this.trackColor,
  });

  @override
  State<SeekBarPreview> createState() => _SeekBarPreviewState();
}

class _SeekBarPreviewState extends State<SeekBarPreview>
    with TickerProviderStateMixin {
  // Ping-pongs 0->1->0 so the sweep never snaps back - a smooth, continuous
  // demo loop rather than an indeterminate-loader-style reset.
  late final AnimationController _progressController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);
  late final Animation<double> _progress = CurvedAnimation(
    parent: _progressController,
    curve: Curves.easeInOut,
  );

  // Matches the real in-player wave's ~900ms cycle so the demo motion looks
  // consistent with actual playback (see _WavySeekBarState).
  late final AnimationController _phaseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _progressController.dispose();
    _phaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_progress, _phaseController]),
      builder: (context, _) {
        return CustomPaint(
          painter: SeekBarPainter(
            style: widget.style,
            progress: _progress.value,
            phase: _phaseController.value * 2 * math.pi,
            animate: true,
            playedColor: widget.playedColor,
            trackColor: widget.trackColor,
          ),
        );
      },
    );
  }
}
