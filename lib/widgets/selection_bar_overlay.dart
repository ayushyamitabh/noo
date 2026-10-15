import 'package:flutter/material.dart';

/// Pins selection actions above the shell navigation. Scaffold supplies its
/// navigation footprint through MediaQuery padding when the body extends
/// behind navigation; otherwise the body already ends above it.
///
/// The bar slides in from the left edge (and back out the same way) as [bar]
/// becomes non-null/null; the shell's FAB slides out to the right in step.
class SelectionBarOverlay extends StatefulWidget {
  static const clearance = 64.0;

  final Widget child;
  final Widget? bar;

  const SelectionBarOverlay({super.key, required this.child, this.bar});

  @override
  State<SelectionBarOverlay> createState() => _SelectionBarOverlayState();
}

class _SelectionBarOverlayState extends State<SelectionBarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.bar != null ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Kept while the bar slides back out, after the caller stopped passing it.
  Widget? _lastBar;

  @override
  void initState() {
    super.initState();
    _lastBar = widget.bar;
  }

  @override
  void didUpdateWidget(SelectionBarOverlay old) {
    super.didUpdateWidget(old);
    if (widget.bar != null) {
      _lastBar = widget.bar;
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = _lastBar;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (bar != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 8,
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, child) {
                if (_controller.isDismissed) return const SizedBox.shrink();
                final width = MediaQuery.sizeOf(context).width;
                return Transform.translate(
                  offset: Offset(-width * (1 - _curve.value), 0),
                  child: IgnorePointer(
                    ignoring: widget.bar == null,
                    child: SizedBox(height: 56, child: child),
                  ),
                );
              },
              child: bar,
            ),
          ),
      ],
    );
  }
}
