import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Every destination the bottom nav bar can show. Order here is only the
/// fallback default — actual order/visibility/default-tab are user
/// configurable and persisted in [ServerProvider].
enum AppTab { files, photos, activity, trash, shares, recent }

/// At most this many tabs may be visible in the bottom nav bar at once —
/// the rest are reachable through the "more" dropdown instead.
const int maxVisibleTabs = 5;

extension AppTabInfo on AppTab {
  String get label {
    switch (this) {
      case AppTab.files:
        return 'Files';
      case AppTab.photos:
        return 'Photos';
      case AppTab.activity:
        return 'Activity';
      case AppTab.trash:
        return 'Trash';
      case AppTab.shares:
        return 'Shares';
      case AppTab.recent:
        return 'Recent';
    }
  }

  IconData get icon {
    switch (this) {
      case AppTab.files:
        return Icons.folder_rounded;
      case AppTab.photos:
        return Icons.photo_library_rounded;
      case AppTab.activity:
        return Icons.electric_bolt_rounded;
      case AppTab.trash:
        return Icons.delete_outline_rounded;
      case AppTab.shares:
        return Icons.groups_rounded;
      case AppTab.recent:
        return Symbols.search_activity_rounded;
    }
  }
}
