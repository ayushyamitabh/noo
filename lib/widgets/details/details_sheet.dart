import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/nextcloud_item.dart';
import '../gradual_bottom_sheet.dart';
import '../synced_header_scaffold.dart' show formatBytes;
import 'details_activity_tab.dart';
import 'details_info_tab.dart';
import 'details_versions_tab.dart';

IconData _detailsItemIcon(NextcloudItemType type) {
  switch (type) {
    case NextcloudItemType.folder:
      return Icons.folder_rounded;
    case NextcloudItemType.image:
      return Icons.image_rounded;
    case NextcloudItemType.video:
      return Icons.movie_rounded;
    case NextcloudItemType.audio:
      return Icons.audiotrack_rounded;
    case NextcloudItemType.document:
      return Icons.description_rounded;
    case NextcloudItemType.archive:
      return Icons.folder_zip_rounded;
    case NextcloudItemType.file:
      return Icons.insert_drive_file_rounded;
  }
}

/// Reusable "Details" bottom sheet for a single file/folder — Info,
/// Versions, and Activity tabs. Sharing lives in its own sheet
/// ([ShareSheet]), triggered separately from wherever a "Share" action
/// appears. Triggered from long-press selection (exactly one item), the
/// media viewer's action bar, and the "open externally" flow for
/// unsupported file types.
class DetailsSheet extends StatelessWidget {
  final NextcloudItem item;

  const DetailsSheet({super.key, required this.item});

  static Future<void> show(BuildContext context, NextcloudItem item) {
    return showGradualBottomSheet(
      context,
      builder: (context, scrollController) => DetailsSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          DetailsHeader(item: item),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.info_outline_rounded), text: 'Info'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Versions'),
              Tab(icon: Icon(Icons.electric_bolt_rounded), text: 'Activity'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                DetailsInfoTab(item: item),
                DetailsVersionsTab(item: item),
                DetailsActivityTab(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon/name/size/date row shared by [DetailsSheet] and the media viewer's
/// collapsed "peek" state (which shows just this, before the user drags the
/// sheet open far enough to reveal the tabs).
class DetailsHeader extends StatelessWidget {
  final NextcloudItem item;

  const DetailsHeader({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _detailsItemIcon(item.type),
              color: colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.isFolder
                      ? DateFormat.yMMMd().format(item.lastModified)
                      : '${formatBytes(item.size)} • ${DateFormat.yMMMd().format(item.lastModified)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
