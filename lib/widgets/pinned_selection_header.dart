import 'package:flutter/material.dart';
import 'sticky_header_delegate.dart';

/// The pinned header at the top of the Files / Photos / Favorites lists: the
/// filter row (and breadcrumbs), plus the multi-select action bar while
/// selecting.
///
/// With [keepControls] (the default - "Keep filters visible" in Settings →
/// Action bar) the filter row never leaves: in the top position the action
/// bar slides in *above* it, growing the header smoothly, so the filters
/// stay on screen and nothing pops in or out. In the bottom position the
/// caller passes no [selectionBar] and the header doesn't change at all.
///
/// Without it the bar replaces the filter row in the same slot, like it used
/// to - no animation, the header just changes height.
class PinnedSelectionHeader extends StatefulWidget {
  /// Height the action bar needs: its 48px card plus 4px above and below.
  static const barHeight = 56.0;

  /// The filter row, already padded and sized to [controlsHeight].
  final Widget controls;
  final double controlsHeight;

  /// The action bar while it lives in the header (top position); null when
  /// not selecting or when the bar is at the bottom.
  final Widget? selectionBar;
  final bool keepControls;

  const PinnedSelectionHeader({
    super.key,
    required this.controls,
    required this.controlsHeight,
    this.selectionBar,
    this.keepControls = true,
  });

  @override
  State<PinnedSelectionHeader> createState() => _PinnedSelectionHeaderState();
}

class _PinnedSelectionHeaderState extends State<PinnedSelectionHeader> {
  /// The bar to keep drawing while it slides back out, after the caller has
  /// already stopped passing one (its selection is gone by then).
  Widget? _leavingBar;

  @override
  Widget build(BuildContext context) {
    final bar = widget.selectionBar;
    if (bar != null) _leavingBar = bar;

    if (!widget.keepControls) {
      return SliverPersistentHeader(
        pinned: true,
        delegate: StickyHeaderDelegate(
          floating: bar != null,
          height: bar != null
              ? PinnedSelectionHeader.barHeight
              : widget.controlsHeight,
          child: bar ?? widget.controls,
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(end: bar != null ? 1.0 : 0.0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      onEnd: () {
        if (widget.selectionBar == null && _leavingBar != null) {
          setState(() => _leavingBar = null);
        }
      },
      builder: (context, t, _) {
        final barExtent = PinnedSelectionHeader.barHeight * t;
        return SliverPersistentHeader(
          pinned: true,
          // Opaque over the whole header (bar included): the list scrolls
          // under a pinned header, and rows must not show through the bar's
          // margins or around the filter row.
          delegate: StickyHeaderDelegate(
            floating: false,
            height: widget.controlsHeight + barExtent,
            child: Column(
              children: [
                if (_leavingBar != null && barExtent > 0)
                  SizedBox(
                    height: barExtent,
                    child: ClipRect(
                      child: Opacity(
                        opacity: t,
                        child: OverflowBox(
                          alignment: Alignment.bottomCenter,
                          minHeight: PinnedSelectionHeader.barHeight,
                          maxHeight: PinnedSelectionHeader.barHeight,
                          child: _leavingBar,
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: widget.controlsHeight, child: widget.controls),
              ],
            ),
          ),
        );
      },
    );
  }
}
