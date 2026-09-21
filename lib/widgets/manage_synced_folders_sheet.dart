import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_status_controller.dart';

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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => ManageSyncedFoldersSheet(sync: sync),
    );
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
    return AnimatedBuilder(
      animation: sync,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final everything = sync.syncEverything;
        final targets = sync.syncedPaths;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Synced to this device',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (everything)
                  Text(
                    'Every folder in this account is being synced to this '
                    'device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else if (targets.isEmpty)
                  Text(
                    'Nothing synced yet - select a folder or file in Files '
                    'and use "Sync to device" to mirror it here for offline '
                    'access.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: targets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final target = targets[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.sync_rounded),
                          title: Text(target),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Stop syncing',
                            onPressed: () => _remove(context, target),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
