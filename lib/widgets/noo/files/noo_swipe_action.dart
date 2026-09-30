import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// The two swipe actions the design system defines (`DESIGN_SYSTEM.md` 2,
/// "Swipe action"); which one sits on which side is a user setting
/// (Settings -> Swipe on a file).
enum NooSwipeActionKind { delete, favorite }

/// One side's action for [NooSwipeAction].
class NooSwipeActionSpec {
  final NooSwipeActionKind kind;
  final VoidCallback onTriggered;

  /// Overrides the default label ("Delete" / "Favorite"), e.g.
  /// "Unfavorite" for an already-starred file.
  final String? label;

  /// Overrides the default icon (`trash-2` / `star`).
  final IconData? icon;

  const NooSwipeActionSpec({
    required this.kind,
    required this.onTriggered,
    this.label,
    this.icon,
  });
}

/// Wraps a row (normally a `NooFileRow`) so dragging it horizontally slides
/// it aside to uncover a 96px action block: delete is white on
/// `danger-fill`, favorite is white on `accent`, each a 20px icon over a
/// 12/600 label. Releasing past half the block snaps it open, otherwise it
/// springs shut - both on [NooMotion.base] / [NooMotion.ease], no bounce.
/// Tapping the block fires the action and closes it; tapping the row while
/// open just closes it.
///
/// Dragging further still - past [_kTriggerExtent] of the block's own
/// width, the block growing to fill the extra reveal so there's no gap -
/// arms the action (a [HapticFeedback.mediumImpact] marks the crossing);
/// releasing while armed fires it immediately instead of just leaving it
/// open, so a single swipe-through gesture can do the whole thing without a
/// second tap.
class NooSwipeAction extends StatefulWidget {
  final Widget child;

  /// Revealed on the leading edge (swipe toward the trailing edge).
  final NooSwipeActionSpec? startAction;

  /// Revealed on the trailing edge (swipe toward the leading edge).
  final NooSwipeActionSpec? endAction;

  const NooSwipeAction({
    super.key,
    required this.child,
    this.startAction,
    this.endAction,
  });

  /// Width of the uncovered action block.
  static const double actionWidth = 96;

  @override
  State<NooSwipeAction> createState() => _NooSwipeActionState();
}

class _NooSwipeActionState extends State<NooSwipeAction>
    with SingleTickerProviderStateMixin {
  /// How far past the fully-revealed block (1.0) a drag has to go before
  /// releasing fires the action outright rather than just snapping open -
  /// "swipe through" in one gesture instead of open-then-tap.
  static const double _kTriggerExtent = 1.8;

  /// Hard ceiling on the controller's value - past [_kTriggerExtent] there's
  /// nothing more for further drag to *do*, but a little extra travel still
  /// gives the gesture room to keep moving under the finger instead of
  /// hitting a dead stop right at the trigger point.
  static const double _kMaxDrag = 2.4;

  /// -1 = end action fully revealed, 0 = closed, 1 = start action revealed
  /// (in visual left/right terms after [_dir] is applied) - and on past
  /// either bound up to [_kMaxDrag] while armed for [_kTriggerExtent].
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    lowerBound: -_kMaxDrag,
    upperBound: _kMaxDrag,
    value: 0,
  );

  double get _dir => Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _ctrl.animateTo(target, duration: NooMotion.base, curve: NooMotion.ease);
  }

  void _close() => _animateTo(0);

  void _onDragUpdate(DragUpdateDetails d) {
    // Positive = revealing the start action.
    final delta = d.primaryDelta! * _dir / NooSwipeAction.actionWidth;
    final min = widget.endAction != null ? -_kMaxDrag : 0.0;
    final max = widget.startAction != null ? _kMaxDrag : 0.0;
    final next = (_ctrl.value + delta).clamp(min, max);
    final wasArmed = _ctrl.value.abs() >= _kTriggerExtent;
    final nowArmed = next.abs() >= _kTriggerExtent;
    if (nowArmed && !wasArmed) HapticFeedback.mediumImpact();
    _ctrl.value = next;
  }

  void _onDragEnd(DragEndDetails d) {
    final v = _ctrl.value;
    if (v.abs() >= _kTriggerExtent) {
      _trigger(v > 0 ? widget.startAction! : widget.endAction!);
      return;
    }
    final velocity = d.primaryVelocity! * _dir;
    double target;
    if (velocity.abs() > 700) {
      final opening = velocity.sign == v.sign || v == 0;
      target = opening ? velocity.sign : 0;
    } else {
      target = v.abs() >= 0.5 ? v.sign : 0;
    }
    if (target > 0 && widget.startAction == null) target = 0;
    if (target < 0 && widget.endAction == null) target = 0;
    _animateTo(target);
  }

  void _trigger(NooSwipeActionSpec spec) {
    _close();
    spec.onTriggered();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    if (widget.startAction == null && widget.endAction == null) {
      return widget.child;
    }

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final v = _ctrl.value;
            // Only the side being uncovered is painted, so the opposite
            // block never peeks out from behind a translucent row.
            final showing = v > 0
                ? widget.startAction
                : (v < 0 ? widget.endAction : null);
            return Stack(
              children: [
                if (showing != null)
                  Positioned.fill(
                    child: Align(
                      alignment: v > 0
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.centerEnd,
                      child: _ActionBlock(
                        spec: showing,
                        colors: colors,
                        // Grows past its own min width to fill the extra
                        // reveal once dragged further than a plain "open"
                        // - otherwise the row's translated edge would pull
                        // away from the block and expose bare space behind
                        // it.
                        width: v.abs() * NooSwipeAction.actionWidth,
                        armed: v.abs() >= _kTriggerExtent,
                        onTap: () => _trigger(showing),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(v * NooSwipeAction.actionWidth * _dir, 0),
                  child: child,
                ),
              ],
            );
          },
          child: _OpenAwareChild(
            controller: _ctrl,
            onCloseTap: _close,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Swallows taps on the row while it's swiped open (closing it instead),
/// so an open row doesn't also navigate.
class _OpenAwareChild extends AnimatedWidget {
  final Widget child;
  final VoidCallback onCloseTap;

  const _OpenAwareChild({
    required AnimationController controller,
    required this.onCloseTap,
    required this.child,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final open = (listenable as AnimationController).value != 0;
    return Stack(
      children: [
        child,
        if (open)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCloseTap,
            ),
          ),
      ],
    );
  }
}

class _ActionBlock extends StatelessWidget {
  final NooSwipeActionSpec spec;
  final NooColors colors;

  /// The block's own width - grows past [NooSwipeAction.actionWidth] once
  /// dragged further than a plain reveal, so it always fills exactly what's
  /// exposed behind the row.
  final double width;

  /// True once the drag has gone far enough that releasing now fires the
  /// action - bumps the icon up a touch as a "you're past the point of no
  /// return" cue, on top of the haptic tick that fired at the same moment.
  final bool armed;

  final VoidCallback onTap;

  const _ActionBlock({
    required this.spec,
    required this.colors,
    required this.width,
    required this.armed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDelete = spec.kind == NooSwipeActionKind.delete;
    final bg = isDelete ? colors.dangerFill : colors.accent;
    final icon =
        spec.icon ?? (isDelete ? LucideIcons.trash2 : LucideIcons.star);
    final label = spec.label ?? (isDelete ? 'Delete' : 'Favorite');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width.clamp(NooSwipeAction.actionWidth, double.infinity),
        color: bg,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: armed ? 1.15 : 1,
              duration: NooMotion.fast,
              curve: NooMotion.ease,
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NooText.label.copyWith(
                fontSize: 12,
                height: 1,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
