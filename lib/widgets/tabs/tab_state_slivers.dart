import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_button.dart';
import '../noo/nav/noo_bottom_bar.dart';
import '../noo/noo_layout.dart';

/// Shared loading/error/empty slivers for Recent/Activity/Trash/Shares (and
/// any future tab shaped like them: a `CustomScrollView` over one flat
/// list), restyled with noo tokens instead of each screen hand-rolling the
/// same centered column - see `FilesView`'s identical error/empty layout,
/// which this mirrors.

/// Centered spinner for a tab's first load (list still empty).
const Widget tabLoadingSliver = SliverFillRemaining(
  hasScrollBody: false,
  child: Center(child: CircularProgressIndicator()),
);

/// Centered error state: icon, title, message, and a Retry button.
Widget tabErrorSliver(
  BuildContext context, {
  required String title,
  required String message,
  required VoidCallback onRetry,
}) {
  final colors = context.nooColors;
  return SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 56, color: colors.danger),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: NooText.cardTitle.copyWith(color: colors.danger),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: NooText.body.copyWith(color: colors.fg3),
            ),
            const SizedBox(height: 20),
            NooButton(
              variant: NooButtonVariant.secondary,
              size: NooButtonSize.field,
              icon: LucideIcons.refreshCw,
              onTap: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Centered empty state: an icon over a message.
Widget tabEmptySliver(
  BuildContext context, {
  required IconData icon,
  required String message,
}) {
  final colors = context.nooColors;
  return SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: colors.fg3),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: NooText.cardTitle.copyWith(color: colors.fg2),
            ),
          ],
        ),
      ),
    ),
  );
}

/// How much bottom padding a tab's scrollable list needs to clear
/// [NooBottomBar] and not just butt up against it. [NooBottomBarStyle.
/// attached] bars aren't drawn behind (no `Scaffold.extendBody`), so
/// Scaffold already shrinks the body above them - this is then pure
/// breathing room, not overlap prevention. [NooBottomBarStyle.floating]
/// and frosted bars (see [NooBottomBar.drawsBehindBody]) draw over an
/// extended body instead, so nothing reserves space for
/// them automatically: the clearance has to cover the bar's own footprint
/// (see [NooBottomBar.rowHeight]/[NooBottomBar.floatingBottomMargin]) plus
/// the safe-area inset below it, or the last row ends up hidden under it.
double bottomBarClearance(BuildContext context) {
  final settings = context.watch<SettingsController>();
  final barStyle = settings.bottomBarStyle;
  if (!NooBottomBar.drawsBehindBody(barStyle, settings.bottomBarFrosted)) {
    return 100;
  }
  final barHeight = NooBottomBar.rowHeight(
    NooLayout.navStyle(context),
    barStyle,
  );
  final margin = barStyle == NooBottomBarStyle.floating
      ? NooBottomBar.floatingBottomMargin
      : 0;
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  return barHeight + margin + safeBottom + 24;
}

/// Bottom padding sliver so the last row/card clears the bottom nav/FAB -
/// same trailing pair every rebuilt tab list ends on.
List<Widget> tabBottomInsetSlivers(BuildContext context) => [
  SliverToBoxAdapter(child: SizedBox(height: bottomBarClearance(context))),
  const SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
];

/// Wraps a tab's shell top bar ([AppTopBar], passed in as the generic
/// [PreferredSizeWidget] it implements - this file can't import
/// `app_top_bar.dart` without a cycle) as that tab's own first sliver,
/// living inside its `CustomScrollView` instead of `Scaffold.appBar`. Gives
/// it Material's native "floating app bar" behavior, via the framework's own
/// [SliverFloatingHeader]: it scrolls away as the list scrolls down, and -
/// unlike a plain `SliverToBoxAdapter`, which only reappears once scrolled
/// all the way back to the top - reappears immediately on any upward
/// scroll, following the finger while dragging and settling fully open or
/// fully closed once the gesture ends.
///
/// [SliverFloatingHeader] sizes itself from [topBar]'s own natural layout
/// (like `SliverToBoxAdapter`) rather than a fixed extent declared up
/// front - so [topBar]'s own internal `SafeArea` (see `NooTopBar`'s doc
/// comment) already accounts for the status-bar inset correctly while
/// [topBar] itself is visible, with no extra height math needed here
/// (unlike building this on the general-purpose `SliverPersistentHeader`
/// would have required).
///
/// Sits above a tab's own pinned in-content header (built with
/// [StickyHeaderDelegate] - the sort/filter controls row, or the selection
/// bar that replaces it) - put this sliver first in `contentSlivers` so
/// that header stays exactly where it already is, independent of whether
/// [topBar] is currently shown or scrolled away.
///
/// That pinned header needs its OWN protection from the status bar too,
/// though: [topBar]'s `SafeArea` only reserves space while [topBar] has
/// some height to put it in - once it's fully collapsed (0 height, [topBar]
/// scrolled all the way away), that reservation disappears with it, and
/// the pinned header would ride up underneath the status bar instead of
/// stopping below it (a real bug this shipped with once already - caught
/// by `tab_state_slivers_test.dart`'s regression test for it). Every tab
/// view wraps its whole `CustomScrollView` (this sliver, the pinned header,
/// and everything else) in `SafeArea(top: true, bottom: false, ...)` to
/// fix this - that reserves the inset outside the scrolling/collapsing
/// region entirely, so it's never implicated in this sliver's own
/// collapse math regardless of [topBar]'s current state. Flutter's
/// `SafeArea` nesting means this doesn't double the inset: the outer one
/// zeroes `MediaQuery.padding.top` for everything below it, so [topBar]'s
/// own inner `SafeArea` sees nothing left to add.
Widget topBarSliver(PreferredSizeWidget topBar) =>
    SliverFloatingHeader(child: topBar);

/// Lets shell refresh actions use exactly the same callback as pull-to-refresh.
class TabRefreshScope extends InheritedWidget {
  final GlobalKey<RefreshIndicatorState> refreshKey;
  const TabRefreshScope({
    super.key,
    required this.refreshKey,
    required super.child,
  });
  static GlobalKey<RefreshIndicatorState>? keyOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabRefreshScope>()?.refreshKey;
  @override
  bool updateShouldNotify(TabRefreshScope oldWidget) =>
      refreshKey != oldWidget.refreshKey;
}
