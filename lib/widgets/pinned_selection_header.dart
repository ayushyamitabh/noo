import 'package:flutter/material.dart';
import 'sticky_header_delegate.dart';

/// The pinned header at the top of the Files / Photos / Favorites lists: the
/// filter row (and breadcrumbs), plus the multi-select action bar while
/// selecting.
///
/// With [keepControls] (the default - "Keep filters visible" in Settings →
/// Action bar) the filter row never leaves and this is just the controls; in
/// the top position the caller adds a [PinnedSelectionBar] after it, which
/// floats over the top of the list. In the bottom position nothing changes.
///
/// Without it the bar replaces the filter row in the same slot, like it used
/// to - no animation, the header just changes height.
class PinnedSelectionHeader extends StatefulWidget {
  /// Height the action bar needs: its 48px card plus 4px above and below.
  static const barHeight = 56.0;

  /// The filter row, already padded and sized to [controlsHeight].
  final Widget controls;
  final double controlsHeight;

  /// The action bar that replaces the controls when [keepControls] is off
  /// (top position); unused otherwise - see [PinnedSelectionBar].
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
  @override
  Widget build(BuildContext context) {
    final bar = widget.selectionBar;

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

    // Keep-filters mode: the header is just the controls. The action bar is
    // the separate [PinnedSelectionBar] sliver that follows it.
    return SliverPersistentHeader(
      pinned: true,
      delegate: StickyHeaderDelegate(
        floating: false,
        height: widget.controlsHeight,
        child: widget.controls,
      ),
    );
  }
}

/// The multi-select action bar in the top position with "Keep filters
/// visible" on: a pinned sliver right after the [PinnedSelectionHeader]'s
/// filter row. Its background is transparent, so the bar reads as a card
/// floating over the files list - rows scroll underneath its margins - while
/// still reserving its own height at the top of the list (nothing is hidden
/// at scroll offset 0).
///
/// Keep it in the sliver list for as long as the top position is in use and
/// pass [bar] only while selecting: it slides down into place when [bar]
/// appears and back up under the filter row when it goes null (the last bar
/// is kept drawing for the exit).
class PinnedSelectionBar extends StatefulWidget {
  final Widget? bar;
  const PinnedSelectionBar({super.key, this.bar});

  @override
  State<PinnedSelectionBar> createState() => _PinnedSelectionBarState();
}

class _PinnedSelectionBarState extends State<PinnedSelectionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.bar != null ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Widget? _lastBar;

  @override
  void initState() {
    super.initState();
    _lastBar = widget.bar;
  }

  @override
  void didUpdateWidget(PinnedSelectionBar old) {
    super.didUpdateWidget(old);
    final instant = MediaQuery.disableAnimationsOf(context);
    if (widget.bar != null) {
      _lastBar = widget.bar;
      instant ? _controller.value = 1 : _controller.forward();
    } else {
      instant ? _controller.value = 0 : _controller.reverse();
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
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        if (bar == null || _controller.isDismissed) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverPersistentHeader(
          pinned: true,
          delegate: StickyHeaderDelegate(
            floating: true,
            height: PinnedSelectionHeader.barHeight * t,
            child: ClipRect(
              child: Opacity(
                opacity: t,
                child: OverflowBox(
                  // Bottom-aligned inside the growing, clipped slot, so the
                  // bar slides down into place from under the filter row.
                  alignment: Alignment.bottomCenter,
                  minHeight: PinnedSelectionHeader.barHeight,
                  maxHeight: PinnedSelectionHeader.barHeight,
                  child: bar,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
