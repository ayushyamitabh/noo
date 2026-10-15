import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/sync_status_controller.dart';
import '../services/sync_service.dart';
import '../theme/design_tokens.dart';
import 'noo/lists/noo_grouped_list.dart';
import 'noo/lists/noo_settings_row.dart';
import 'noo/overlays/noo_sheet.dart';
import 'noo/overlays/noo_messenger.dart';

/// The synced targets (folders/files) with a "stop syncing" action per
/// target - what used to be Settings' Device Sync card's own inline list,
/// moved into a sheet here so the main Offline view can look like a plain
/// Files-style browser instead of always showing this management UI up top.
///
/// Also lists what's *on the device* without being synced - files left
/// behind when "Sync everything" is turned off (or a sync is cancelled part
/// way) - each with a "remove from device" action. Without that they'd sit in
/// the Offline tab with nothing in this list to remove them by.
class ManageSyncedFoldersSheet extends StatefulWidget {
  final SyncStatusController sync;

  const ManageSyncedFoldersSheet({super.key, required this.sync});

  static void show(BuildContext context) {
    final sync = context.read<SyncStatusController>();
    showNooSheet(context, children: [ManageSyncedFoldersSheet(sync: sync)]);
  }

  @override
  State<ManageSyncedFoldersSheet> createState() =>
      _ManageSyncedFoldersSheetState();
}

class _ManageSyncedFoldersSheetState extends State<ManageSyncedFoldersSheet> {
  List<DeviceOnlyItem> _deviceOnly = const [];
  // What the on-device list was last read for - it's re-read whenever one of
  // these changes (a sync pass starting/ending, a path added/removed).
  String _readFor = '';

  SyncStatusController get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    sync.addListener(_onSyncChanged);
    _refresh();
  }

  @override
  void dispose() {
    sync.removeListener(_onSyncChanged);
    super.dispose();
  }

  String get _key =>
      '${sync.syncEverything}|${sync.isSyncingNow}|${sync.syncedFileCount}|'
      '${sync.syncedPaths.join('\n')}';

  void _onSyncChanged() {
    if (_key != _readFor) _refresh();
  }

  Future<void> _refresh() async {
    final key = _readFor = _key;
    List<DeviceOnlyItem> items;
    try {
      items = await sync.deviceOnlyItems();
    } catch (e) {
      // Unreadable mirror: still show the configured paths.
      debugPrint('[ManageSyncedFoldersSheet] Could not list device files: $e');
      return;
    }
    if (!mounted || key != _readFor) return;
    setState(() => _deviceOnly = items);
  }

  void _remove(BuildContext context, String path) {
    sync.removeSyncedPath(path);
    NooMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from device sync'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _removeFromDevice(
    BuildContext context,
    DeviceOnlyItem item,
  ) async {
    final messenger = NooMessenger.of(context);
    setState(
      () => _deviceOnly = [
        for (final other in _deviceOnly)
          if (other.path != item.path) other,
      ],
    );
    await sync.removeDeviceCopy(item.path);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Removed from this device'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    unawaited(_refresh());
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
        final deviceOnly = _deviceOnly;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synced to this device',
              style: NooText.cardTitle.copyWith(color: colors.fg1),
            ),
            const SizedBox(height: NooSpace.sm),
            if (everything) ...[
              Text(
                sync.syncExternal
                    ? 'Every folder in this account, including external storage, is being synced to this device.'
                    : 'Every cloud folder in this account is being synced to this device.',
                style: NooText.body.copyWith(color: colors.fg3),
              ),
              if (deviceOnly.isNotEmpty) ...[
                const SizedBox(height: NooSpace.lg),
                Text(
                  'On this device',
                  style: NooText.cardTitle.copyWith(color: colors.fg1),
                ),
                const SizedBox(height: NooSpace.sm),
                NooGroupedList(
                  children: [
                    for (final item in deviceOnly)
                      NooSettingsRow(
                        icon: item.isFolder
                            ? LucideIcons.folder
                            : LucideIcons.file,
                        label: Text(item.path),
                      ),
                  ],
                ),
              ],
            ] else if (targets.isEmpty && deviceOnly.isEmpty)
              Text(
                'Nothing synced yet. Select a folder or file in Files and '
                'use "Sync to device" to mirror it here for offline access.',
                style: NooText.body.copyWith(color: colors.fg3),
              )
            else ...[
              if (targets.isNotEmpty)
                NooGroupedList(
                  children: [
                    for (final target in targets)
                      NooSettingsRow(
                        icon: LucideIcons.folderSync,
                        label: Text(target),
                        trailing: IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            size: 18,
                            color: colors.fg3,
                          ),
                          tooltip: 'Stop syncing',
                          onPressed: () => _remove(context, target),
                        ),
                      ),
                  ],
                ),
              if (deviceOnly.isNotEmpty) ...[
                if (targets.isNotEmpty) const SizedBox(height: NooSpace.lg),
                Text(
                  'On this device, not syncing',
                  style: NooText.cardTitle.copyWith(color: colors.fg1),
                ),
                const SizedBox(height: 4),
                Text(
                  'Left over from a sync that was turned off or cancelled. '
                  'They stay until you remove them.',
                  style: NooText.meta.copyWith(color: colors.fg3),
                ),
                const SizedBox(height: NooSpace.sm),
                NooGroupedList(
                  children: [
                    for (final item in deviceOnly)
                      NooSettingsRow(
                        icon: item.isFolder
                            ? LucideIcons.folder
                            : LucideIcons.file,
                        label: Text(item.path),
                        trailing: IconButton(
                          icon: Icon(
                            LucideIcons.trash2,
                            size: 18,
                            color: colors.fg3,
                          ),
                          tooltip: 'Remove from device',
                          onPressed: () => _removeFromDevice(context, item),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}
