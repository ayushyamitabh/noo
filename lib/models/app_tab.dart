import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every destination the bottom nav bar can show. Order here is only the
/// fallback default — actual order/visibility/default-tab are user
/// configurable and persisted in `SettingsController`.
enum AppTab {
  files,
  photos,
  favorites,
  activity,
  trash,
  shares,
  recent,
  offline,
}

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
      case AppTab.favorites:
        return 'Favorites';
      case AppTab.activity:
        return 'Activity';
      case AppTab.trash:
        return 'Trash';
      case AppTab.shares:
        return 'Shares';
      case AppTab.recent:
        return 'Recent';
      case AppTab.offline:
        return 'Offline';
    }
  }

  // Lucide icon mapping per DESIGN_SYSTEM.md 1.5 - the Lucide icon slug is
  // named in a comment where it doesn't match the Dart identifier.
  IconData get icon {
    switch (this) {
      case AppTab.files:
        return LucideIcons.folder;
      case AppTab.photos:
        return LucideIcons.images;
      case AppTab.favorites:
        return LucideIcons.star;
      case AppTab.activity:
        return LucideIcons.activity;
      case AppTab.trash:
        return LucideIcons.trash2; // trash-2
      case AppTab.shares:
        return LucideIcons.share2; // share-2
      case AppTab.recent:
        return LucideIcons.clock;
      case AppTab.offline:
        return LucideIcons.hardDriveDownload; // hard-drive-download
    }
  }
}
