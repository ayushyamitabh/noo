import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';

/// The full-color Noo logo with the website's logo animation
/// (noo.ayushya.dev's `logo-anim.js`), looped as a loading indicator: two
/// balls take turns popping into the bottom of the blue stem, pulling back,
/// and shooting through the "pipes" - the first all the way round to the
/// bottom of the coral stem, the second to the end of the teal arch - then
/// both fade out and it starts over.
///
/// Geometry is in the logo artwork's own pixels (720 x 741, the same
/// coordinates as the website): stems are 247 wide with centers at x 126 /
/// 594, and the arch's inner hole is centered at (360, 347). The balls pull
/// slightly past the artwork's bottom edge; the painter doesn't clip, so
/// leave a little room below.
///
/// Also loops on the sign-in screen as the brand mark, where it's
/// decorative ([semanticLabel] null) rather than announced as loading.
///
/// With reduced motion on it shows the finished frame, standing still.
class NooLogoLoader extends StatefulWidget {
  /// Rendered width; height follows the artwork's 720:741 aspect.
  final double width;

  /// Read out by screen readers; null marks the logo as decorative.
  final String? semanticLabel;

  const NooLogoLoader({
    super.key,
    this.width = 96,
    this.semanticLabel = 'Loading',
  });

  static const asset = 'assets/icon/app_logo.png';

  @override
  State<NooLogoLoader> createState() => _NooLogoLoaderState();
}

class _NooLogoLoaderState extends State<NooLogoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _LogoBalls.cycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = _LogoBalls.settledFraction;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * _LogoBalls.artHeight / _LogoBalls.artWidth;
    final logo = SizedBox(
      width: widget.width,
      height: height,
      child: CustomPaint(
        foregroundPainter: _LogoBalls(_controller),
        child: Image.asset(
          NooLogoLoader.asset,
          width: widget.width,
          height: height,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
    final label = widget.semanticLabel;
    return label == null
        ? ExcludeSemantics(child: logo)
        : Semantics(label: label, child: logo);
  }
}

class _Ball {
  final Color color;
  final double start; // ms into the cycle
  final double travel; // ms spent flying through the pipe
  final Path path;
  late final PathMetric metric = path.computeMetrics().single;

  _Ball({
    required this.color,
    required this.start,
    required this.travel,
    required this.path,
  });

  double get cockAt => start + _LogoBalls.enter + _LogoBalls.hold;
  double get launchAt => cockAt + _LogoBalls.cock + _LogoBalls.aim;
  double get landAt => launchAt + travel;

  Offset pointAt(double t) {
    final p = _easeOutCubic(((t - launchAt) / travel).clamp(0.0, 1.0));
    return metric.getTangentForOffset(p * metric.length)!.position;
  }
}

class _LogoBalls extends CustomPainter {
  final Animation<double> animation;
  _LogoBalls(this.animation) : super(repaint: animation);

  static const artWidth = 720.0;
  static const artHeight = 741.0;

  // Same timings as the website (ms).
  static const radius = 100.0;
  static const restY = 620.0;
  static const pull = 70.0;
  static const enter = 600.0;
  static const hold = 200.0;
  static const cock = 400.0;
  static const aim = 150.0;
  static const land = 260.0;
  static const ghosts = 3;
  static const ghostLag = 55.0;

  // Loader-only: rest on the finished frame, fade the balls out, repeat.
  static const _settle = 700.0;
  static const _fade = 300.0;

  static final _balls = [
    _Ball(
      color: const Color(0xFFFFD6A1),
      start: 350,
      travel: 780,
      path: Path()
        ..moveTo(126, restY + pull)
        ..lineTo(126, 347)
        ..arcToPoint(const Offset(594, 347), radius: const Radius.circular(234))
        ..lineTo(594, restY),
    ),
    _Ball(
      color: const Color(0xFF9DE7EF),
      start: 2850,
      travel: 640,
      // Stops near the teal arch's end, ~25 degrees above horizontal.
      path: Path()
        ..moveTo(126, restY + pull)
        ..lineTo(126, 347)
        ..arcToPoint(
          const Offset(571, 246),
          radius: const Radius.circular(234),
        ),
    ),
  ];

  static final double _landed = _balls
      .map((b) => b.landAt + land + ghosts * ghostLag)
      .reduce(math.max);
  static final double _cycleMs = _landed + _settle + _fade;
  static final Duration cycle = Duration(milliseconds: _cycleMs.round());

  /// Where the finished, fully settled frame sits in the cycle.
  static final double settledFraction = (_landed + _settle / 2) / _cycleMs;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * _cycleMs;
    final fadeOut = 1 - ((t - _landed - _settle) / _fade).clamp(0.0, 1.0);
    if (fadeOut <= 0) return;
    canvas.save();
    canvas.scale(size.width / artWidth);
    for (final ball in _balls) {
      _paintBall(canvas, ball, t, fadeOut);
    }
    canvas.restore();
  }

  void _paintBall(Canvas canvas, _Ball b, double t, double alpha) {
    if (t < b.start) return;

    // Motion trail while (and just after) it travels.
    if (t >= b.launchAt) {
      for (var i = 0; i < ghosts; i++) {
        final gt = t - (i + 1) * ghostLag;
        if (gt > b.landAt) continue;
        _circle(
          canvas,
          b.pointAt(gt),
          1,
          1,
          b.color,
          (0.42 - i * 0.12) * alpha,
        );
      }
    }

    if (t < b.cockAt) {
      // Pop in with an overshoot.
      final s = math.max(
        0.0,
        _easeOutBack(((t - b.start) / enter).clamp(0, 1)),
      );
      _circle(canvas, const Offset(126, restY), s, s, b.color, alpha);
    } else if (t < b.launchAt) {
      // Pull back, squashing a little as it goes.
      final p = _easeInOutCubic(((t - b.cockAt) / cock).clamp(0, 1));
      _circle(
        canvas,
        Offset(126, restY + pull * p),
        1 + 0.06 * p,
        1 - 0.08 * p,
        b.color,
        alpha,
      );
    } else if (t < b.landAt) {
      // Released: stretched along the direction of travel early on.
      final k = 1 - ((t - b.launchAt) / b.travel).clamp(0.0, 1.0);
      _circle(canvas, b.pointAt(t), 1 - 0.08 * k, 1 + 0.1 * k, b.color, alpha);
    } else {
      // Land with a small squash that settles out.
      final p = ((t - b.landAt) / land).clamp(0.0, 1.0);
      final q = math.sin(p * math.pi) * 0.08;
      _circle(canvas, b.pointAt(b.landAt), 1 + q, 1 - q, b.color, alpha);
    }
  }

  void _circle(
    Canvas canvas,
    Offset center,
    double sx,
    double sy,
    Color color,
    double alpha,
  ) {
    if (sx <= 0 || sy <= 0 || alpha <= 0) return;
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 2 * sx,
        height: radius * 2 * sy,
      ),
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_LogoBalls oldDelegate) =>
      oldDelegate.animation != animation;
}

double _easeOutBack(double p) {
  const c1 = 2.2, c3 = c1 + 1;
  return 1 + c3 * math.pow(p - 1, 3) + c1 * math.pow(p - 1, 2);
}

double _easeInOutCubic(double p) =>
    p < 0.5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3) / 2;

double _easeOutCubic(double p) => 1 - math.pow(1 - p, 3).toDouble();
