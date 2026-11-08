import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../../theme/design_tokens.dart';

/// Overlays [child] (the Android Upload FAB) bottom-right of the body and
/// keeps it *above* any visible snackbar.
///
/// `Scaffold` always stacks a floating snackbar above its own
/// `floatingActionButton` slot, which pushed the snackbar up over the
/// content with the FAB sitting underneath it. Here the Scaffold is given
/// no FAB at all - so the snackbar takes its normal spot just above the
/// bottom bar - and this widget measures that snackbar's slot each frame
/// and slides the FAB up by as much as it needs to clear it, then back
/// down once it goes away.
///
/// Must be placed inside the `Scaffold`'s `body` (the measurement walks up
/// to the Scaffold's layout render object). Body-relative `bottom` works
/// for both bar styles: attached shrinks the body above the bar, floating
/// (`extendBody`) reports the bar's height in `MediaQuery.padding.bottom`.
class SnackBarAwareFab extends StatefulWidget {
  final Widget child;

  /// Distance from the bar (or body bottom) to the FAB when no snackbar is
  /// showing.
  final double restingGap;

  /// Space kept between the FAB and the snackbar's top edge.
  final double snackBarGap;

  const SnackBarAwareFab({
    super.key,
    required this.child,
    this.restingGap = 16,
    this.snackBarGap = 8,
  });

  @override
  State<SnackBarAwareFab> createState() => _SnackBarAwareFabState();
}

class _SnackBarAwareFabState extends State<SnackBarAwareFab> {
  double _snackBarHeight = 0;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  // Re-armed every frame: a snackbar appearing/disappearing always drives
  // frames (its own slide animation), and the check itself is a walk over
  // the Scaffold layout's ~8 direct children.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final height = _measureSnackBar();
      if (height != _snackBarHeight) {
        setState(() => _snackBarHeight = height);
      }
      _schedule();
    });
    // A post-frame callback alone doesn't request a frame; do so while a
    // snackbar is showing or the FAB is still lifted so the loop keeps
    // going until the FAB has settled back down.
    if (_snackBarHeight > 0) SchedulerBinding.instance.ensureVisualUpdate();
  }

  double _measureSnackBar() {
    RenderObject? node = context.findRenderObject();
    while (node != null && node is! RenderCustomMultiChildLayoutBox) {
      node = node.parent;
    }
    if (node is! RenderCustomMultiChildLayoutBox) return 0;
    var height = 0.0;
    node.visitChildren((child) {
      final data = child.parentData;
      if (data is MultiChildLayoutParentData &&
          data.id.toString().contains('snackBar') &&
          child is RenderBox &&
          child.hasSize) {
        height = child.size.height;
      }
    });
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final lift = _snackBarHeight > 0
        ? (_snackBarHeight + widget.snackBarGap - widget.restingGap).clamp(
            0.0,
            double.infinity,
          )
        : 0.0;
    return Stack(
      children: [
        AnimatedPositioned(
          duration: NooMotion.base,
          curve: Curves.easeOutCubic,
          right: 16,
          bottom: bottomInset + widget.restingGap + lift,
          child: widget.child,
        ),
      ],
    );
  }
}
