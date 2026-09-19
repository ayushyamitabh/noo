import 'package:flutter/material.dart';
import '../models/sync_status.dart';

/// A small corner badge over a thumbnail showing device-sync status - a
/// `cloud_done` badge once a file's mirrored locally, `sync` while it's
/// actively being transferred. Nothing is drawn for `none`/`conflict`
/// (conflicts surface in the sync header, not as per-tile noise).
class SyncStatusBadge extends StatelessWidget {
  final SyncItemStatus status;

  const SyncStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status != SyncItemStatus.syncing && status != SyncItemStatus.synced) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final icon = status == SyncItemStatus.syncing
        ? Icons.sync_rounded
        : Icons.cloud_done_rounded;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 1.5),
      ),
      child: Icon(icon, size: 13, color: colorScheme.primary),
    );
  }
}
