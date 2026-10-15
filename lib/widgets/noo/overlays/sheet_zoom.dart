import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../noo_layout.dart';

/// The "zoom out" behind a bottom sheet: while a [showNooSheet] sheet is
/// open the page underneath shrinks a little, rounds its corners and sits on
/// black, and grows back as the sheet closes.
///
/// Each sheet hands its route a dedicated [AnimationController]
/// ([SheetZoom.open]), so the zoom is driven by the sheet's own entrance/exit
/// animation - including the user dragging it down to dismiss - instead of a
/// second, separately timed animation. Pages pick the value up through
/// [ZoomOutOnSheet], wrapped around every route by `AppTheme`'s page
/// transitions (a sheet is a route above the page, so the page - not the
/// whole navigator - is what can be scaled without scaling the sheet too).
class SheetZoom extends ChangeNotifier {
  SheetZoom._();
  static final SheetZoom instance = SheetZoom._();

  /// How far the page shrinks at full zoom (0.09 = 91% of its size).
  static const double shrink = 0.09;
  static const double _cornerRadius = 28;

  final List<AnimationController> _active = [];
  final Set<AnimationController> _seenForward = {};

  /// 0 (no sheet) to 1 (fully open) - the furthest-open sheet wins, so a
  /// sheet opened from another sheet leaves the page zoomed.
  double get value {
    var max = 0.0;
    for (final controller in _active) {
      if (controller.value > max) max = controller.value;
    }
    return max;
  }

  /// A controller for a sheet's route to animate with, or null where the
  /// effect doesn't apply (tablet-class layouts, reduced motion). Pass it as
  /// `transitionAnimationController`, then call [release] with the sheet's
  /// future.
  static AnimationController? open(BuildContext context) {
    if (NooLayout.isDesktop(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return null;
    }
    final controller = AnimationController(
      vsync: const _SheetVsync(),
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 260),
    );
    instance._attach(controller);
    return controller;
  }

  /// Call once the sheet's future completes. The route is still sliding out
  /// at that point, so the controller is only disposed once it has finished.
  static void release(AnimationController controller) {
    if (controller.isDismissed) instance._finish(controller);
  }

  void _attach(AnimationController controller) {
    _active.add(controller);
    controller.addListener(notifyListeners);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.completed) {
        _seenForward.add(controller);
      } else if (status == AnimationStatus.dismissed &&
          _seenForward.contains(controller)) {
        _finish(controller);
      }
    });
  }

  void _finish(AnimationController controller) {
    if (!_active.remove(controller)) return;
    _seenForward.remove(controller);
    controller.removeListener(notifyListeners);
    notifyListeners();
    // Not during the frame that just ended the animation.
    SchedulerBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}

class _SheetVsync implements TickerProvider {
  const _SheetVsync();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Shrinks [child] (a whole page) while a sheet is open - see [SheetZoom].
/// The tree shape never changes with the zoom, so the page keeps its state.
class ZoomOutOnSheet extends StatelessWidget {
  final Widget child;
  const ZoomOutOnSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SheetZoom.instance,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(
          SheetZoom.instance.value.clamp(0.0, 1.0),
        );
        return Transform.scale(
          scale: 1 - SheetZoom.shrink * t,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SheetZoom._cornerRadius * t),
            clipBehavior: t > 0 ? Clip.antiAlias : Clip.none,
            child: child,
          ),
        );
      },
    );
  }
}
