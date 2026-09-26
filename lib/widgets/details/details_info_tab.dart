import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/nextcloud_item.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../synced_header_scaffold.dart' show formatBytes;

/// Plain metadata list of the Details sheet/dialog - name, type, size,
/// location, and dates. No network calls, so no loading state needed.
class DetailsInfoTab extends StatelessWidget {
  final NextcloudItem item;

  const DetailsInfoTab({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Name', item.name),
      ('Type', item.isFolder ? 'Folder' : (item.mimeType ?? 'File')),
      if (!item.isFolder) ('Size', formatBytes(item.size)),
      ('Location', item.path),
      ('Modified', DateFormat.yMMMd().add_jm().format(item.lastModified)),
      ('Created', DateFormat.yMMMd().add_jm().format(item.dateCreated)),
      ('Favorite', item.isFavorite ? 'Yes' : 'No'),
    ];

    return NooGroupedList(
      children: [for (final row in rows) _InfoRow(label: row.$1, value: row.$2)],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NooSpace.md,
          vertical: NooSpace.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: NooText.body.copyWith(fontSize: 14, color: colors.fg3),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: NooText.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.fg1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
