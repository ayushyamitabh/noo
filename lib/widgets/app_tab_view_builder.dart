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
Widget buildAppTabView(AppTab tab, ScrollController controller) {
  switch (tab) {
    case AppTab.files:
      // Keyed so the Files and Offline tabs (same widget type) never share
      // State when the visible-tab list shifts positions in the IndexedStack.
      return FilesView(
        key: const ValueKey('files'),
        scrollController: controller,
      );
    case AppTab.photos:
      return PhotosView(scrollController: controller);
    case AppTab.favorites:
      return FavoritesView(scrollController: controller);
    case AppTab.activity:
      return ActivityView(scrollController: controller);
    case AppTab.trash:
      return TrashView(scrollController: controller);
    case AppTab.shares:
      return SharesView(scrollController: controller);
    case AppTab.recent:
      return RecentView(scrollController: controller);
    case AppTab.offline:
      return FilesView(
        key: const ValueKey('offline'),
        scrollController: controller,
        offline: true,
      );
  }
}
