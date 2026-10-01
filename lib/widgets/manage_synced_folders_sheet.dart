import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/sync_status_controller.dart';
import '../theme/design_tokens.dart';
import 'noo/lists/noo_grouped_list.dart';
import 'noo/lists/noo_settings_row.dart';
import 'noo/overlays/noo_sheet.dart';

/// The configured sync targets (folders/files) with a "stop syncing"
/// action per target - what used to be Settings' Device Sync card's own
/// inline list, moved into a sheet here so the main Offline view can look
/// like a plain Files-style browser instead of always showing this
/// management UI up top.
class ManageSyncedFoldersSheet extends StatelessWidget {
  final SyncStatusController sync;

  const ManageSyncedFoldersSheet({super.key, required this.sync});

  static void show(BuildContext context) {
    final sync = context.read<SyncStatusController>();
    showNooSheet(context, children: [ManageSyncedFoldersSheet(sync: sync)]);
  }

  void _remove(BuildContext context, String path) {
    sync.removeSyncedPath(path);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from device sync'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    // AnimatedBuilder, not a one-shot read: removing a target should update
    // this list in place without closing the sheet, and showNooSheet's
    // `children` is built once by the caller - this widget owns its own
    // rebuild instead.
    return AnimatedBuilder(
      animation: sync,
      builder: (context, _) {
        final everything = sync.syncEverything;
        final targets = sync.syncedPaths;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synced to this device',
              style: NooText.cardTitle.copyWith(color: colors.fg1),
            ),
            const SizedBox(height: NooSpace.sm),
            if (everything)
              Text(
                'Every folder in this account is being synced to this device.',
                style: NooText.body.copyWith(color: colors.fg3),
              )
            else if (targets.isEmpty)
              Text(
                'Nothing synced yet. Select a folder or file in Files and '
                'use "Sync to device" to mirror it here for offline access.',
                style: NooText.body.copyWith(color: colors.fg3),
              )
            else
              NooGroupedList(
                children: [
                  for (final target in targets)
                    NooSettingsRow(
                      icon: LucideIcons.folderSync,
                      label: Text(target),
                      trailing: IconButton(
                        icon: Icon(LucideIcons.x, size: 18, color: colors.fg3),
                        tooltip: 'Stop syncing',
                        onPressed: () => _remove(context, target),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
