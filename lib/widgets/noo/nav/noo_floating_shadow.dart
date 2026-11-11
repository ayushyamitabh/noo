import 'package:flutter/material.dart';

/// A soft two-layer drop shadow for the floating bottom bar and its round
/// satellites (Search, avatar) - what they use instead of a border.
///
/// Painted only *outside* [radius]'s shape: a normal `BoxShadow` also draws
/// underneath its box, which shows straight through a translucent (frosted /
/// glass) fill as a dark smudge. Clipping the shape itself out of the shadow
/// keeps a frosted bar clean while a solid bar looks identical to one with
/// an ordinary shadow.
class NooFloatingShadow extends StatelessWidget {
  final BorderRadius radius;
  final Widget child;

  const NooFloatingShadow({
    super.key,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _OuterShadowPainter(radius: radius, dark: dark),
      child: child,
    );
  }
}

class _OuterShadowPainter extends CustomPainter {
  final BorderRadius radius;
  final bool dark;

  const _OuterShadowPainter({required this.radius, required this.dark});

  // (blur radius, y offset, alpha). A wide ambient layer plus a tight contact
  // layer; stronger in dark mode, where a shadow needs more density to read
  // against an already-dark backdrop.
  List<(double, double, double)> get _layers => dark
      ? const [(32, 12, 0.5), (10, 3, 0.38)]
      : const [(30, 10, 0.2), (8, 2, 0.12)];

  @override
  void paint(Canvas canvas, Size size) {
    final shape = radius.toRRect(Offset.zero & size);
    canvas.save();
    // Everything except the shape itself.
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(120))
        ..addRRect(shape),
    );
    for (final (blur, dy, alpha) in _layers) {
      canvas.drawRRect(
        shape.shift(Offset(0, dy)),
        Paint()
          ..color = Colors.black.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.dark != dark;
}
