import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

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
    // `context.nooColors.bg`, not `Theme.of(context).colorScheme.surface` -
    // the latter is Flutter's own Material 3 scheme, seeded from the user's
    // accent color choice (see AppTheme.light/dark), so it carried a faint
    // hue of whatever accent is picked, and didn't match the plain
    // `colors.bg` every one of these screens' own `ColoredBox` background
    // uses. `bg`, not `surface`, so the sort/filter chips and List/Grid
    // toggle riding on top of this (each already `colors.surface`-filled)
    // still pop against it, the same as they do everywhere else in the app
    // - matching `surface` here would make this pinned header the one place
    // they'd flatten into their background instead. `surfaceTintColor:
    // Colors.transparent` guards against the same M3 elevation-tint
    // behavior even if this ever gets a non-zero elevation.
    return Material(
      color: floating ? Colors.transparent : context.nooColors.bg,
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
