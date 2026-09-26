import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Per-file status markers for a file row's meta line or a table row's
/// status column (`DESIGN_SYSTEM.md` 2, "Status icons").
enum NooSyncStatus {
  synced,
  syncing,
  error,
  shared;

  IconData get icon {
    switch (this) {
      case NooSyncStatus.synced:
        return LucideIcons.circleCheck;
      case NooSyncStatus.syncing:
        return LucideIcons.refreshCw;
      case NooSyncStatus.error:
        return LucideIcons.circleAlert;
      case NooSyncStatus.shared:
        return LucideIcons.users;
    }
  }

  Color color(NooColors colors) {
    switch (this) {
      case NooSyncStatus.synced:
        return colors.success;
      case NooSyncStatus.syncing:
        return colors.accentText;
      case NooSyncStatus.error:
        return colors.danger;
      case NooSyncStatus.shared:
        return colors.fg3;
    }
  }
}

/// A single 14px status icon. For [NooSyncStatus.error] the row's meta
/// text should say what to do ("Couldn't sync · Tap to retry") - this only
/// draws the icon.
class NooStatusIcon extends StatelessWidget {
  final NooSyncStatus status;
  final double size;

  const NooStatusIcon(this.status, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Icon(
      status.icon,
      size: size,
      color: status.color(context.nooColors),
    );
  }
}
