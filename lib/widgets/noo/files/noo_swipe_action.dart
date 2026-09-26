import 'package:flutter/material.dart';
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
  /// -1 = end action fully revealed, 0 = closed, 1 = start action revealed
  /// (in visual left/right terms after [_dir] is applied).
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    lowerBound: -1,
    upperBound: 1,
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
    final min = widget.endAction != null ? -1.0 : 0.0;
    final max = widget.startAction != null ? 1.0 : 0.0;
    _ctrl.value = (_ctrl.value + delta).clamp(min, max);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = _ctrl.value;
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
  final VoidCallback onTap;

  const _ActionBlock({
    required this.spec,
    required this.colors,
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
        width: NooSwipeAction.actionWidth,
        color: bg,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white),
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
