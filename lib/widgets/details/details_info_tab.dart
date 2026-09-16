import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/nextcloud_item.dart';
import '../synced_header_scaffold.dart' show formatBytes;

/// Plain metadata tab of the Details sheet — name, type, size, location,
/// and dates. No network calls, so no loading state needed.
class DetailsInfoTab extends StatelessWidget {
  final NextcloudItem item;
  final ScrollController? scrollController;

  const DetailsInfoTab({super.key, required this.item, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final rows = <(String, String)>[
      ('Name', item.name),
      ('Type', item.isFolder ? 'Folder' : (item.mimeType ?? 'File')),
      if (!item.isFolder) ('Size', formatBytes(item.size)),
      ('Location', item.path),
      ('Modified', DateFormat.yMMMd().add_jm().format(item.lastModified)),
      ('Created', DateFormat.yMMMd().add_jm().format(item.dateCreated)),
      ('Favorite', item.isFavorite ? 'Yes' : 'No'),
    ];

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final (label, value) = rows[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
