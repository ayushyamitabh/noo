import 'package:flutter/material.dart';
import 'noo/noo_layout.dart';

/// Wraps [child] as a sliver that pins to the top of the scroll view when
/// used with `SliverPersistentHeader(pinned: true, ...)`, or scrolls away
/// normally with `pinned: false`. [height] must match the child's actual
/// rendered height - Flutter's sliver protocol needs an extent up front,
/// not one measured after layout, so callers own getting this right for
/// whatever fixed-height content they pass in.
class StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  final bool floating;

  const StickyHeaderDelegate({
    required this.height,
    required this.child,
    this.floating = false,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Match the pane so pinned controls preserve its rounded silhouette.
    return Material(
      color: floating
          ? Colors.transparent
          : NooLayout.contentBackground(context),
      surfaceTintColor: Colors.transparent,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.child != child ||
        oldDelegate.floating != floating;
  }
}
