import 'package:flutter/material.dart';
import '../models/app_tab.dart';
import '../views/activity_view.dart';
import '../views/favorites_view.dart';
import '../views/files_view.dart';
import '../views/photos_view.dart';
import '../views/recent_view.dart';
import '../views/shares_view.dart';
import '../views/trash_view.dart';

/// Builds the view widget for a given [AppTab]. Shared by the main shell
/// (for visible tabs) and the "more tabs" dropdown (for launching a tab
/// that's currently hidden from the bottom nav bar).
///
/// [topBar], when given, is that tab's own [AppTopBar] instance (built by
/// the caller, which owns `NooLayout.navStyle`/pick-mode/search-in-bottom-
/// bar state) - each view plants it as its own first sliver (see
/// `topBarSliver` in `tabs/tab_state_slivers.dart`) so it scrolls away and
/// reappears independently, tied to that tab's own `ScrollController`
/// rather than living in the shared `Scaffold.appBar`. Null on desktop
/// (which shows `NooToolbar` instead) and while picking (no top bar at
/// all), matching `Scaffold.appBar`'s old `pickRequest == null` guard.
Widget buildAppTabView(
  AppTab tab,
  ScrollController controller, {
  PreferredSizeWidget? topBar,
}) {
  switch (tab) {
    case AppTab.files:
      // Keyed so the Files and Offline tabs (same widget type) never share
      // State when the visible-tab list shifts positions in the IndexedStack.
      return FilesView(
        key: const ValueKey('files'),
        scrollController: controller,
        topBar: topBar,
      );
    case AppTab.photos:
      return PhotosView(scrollController: controller, topBar: topBar);
    case AppTab.favorites:
      return FavoritesView(scrollController: controller, topBar: topBar);
    case AppTab.activity:
      return ActivityView(scrollController: controller, topBar: topBar);
    case AppTab.trash:
      return TrashView(scrollController: controller, topBar: topBar);
    case AppTab.shares:
      return SharesView(scrollController: controller, topBar: topBar);
    case AppTab.recent:
      return RecentView(scrollController: controller, topBar: topBar);
    case AppTab.offline:
      return FilesView(
        key: const ValueKey('offline'),
        scrollController: controller,
        offline: true,
        topBar: topBar,
      );
  }
}
