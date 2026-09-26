import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../models/nextcloud_file_version.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/item_operations.dart';
import '../../theme/design_tokens.dart';
import '../noo/files/noo_file_kind.dart';
import '../noo/files/noo_file_tile.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../synced_header_scaffold.dart' show formatBytes;

/// File version history - a synthetic "Current version" row (from the
/// item's own metadata) followed by whatever the DAV versions endpoint
/// returns, each with Restore/Download actions.
class DetailsVersionsTab extends StatefulWidget {
  final NextcloudItem item;

  const DetailsVersionsTab({super.key, required this.item});

  @override
  State<DetailsVersionsTab> createState() => _DetailsVersionsTabState();
}

class _DetailsVersionsTabState extends State<DetailsVersionsTab> {
  bool _requested = false;
  bool _isLoading = true;
  List<NextcloudFileVersion> _versions = [];

  Future<void> _load() async {
    final ops = context.read<ItemOperations>();
    final result = await ops.fetchFileVersions(widget.item);
    if (!mounted) return;
    setState(() {
      _versions = result;
      _isLoading = false;
    });
  }

  Future<void> _restore(NextcloudFileVersion version) async {
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await ops.restoreFileVersion(
      widget.item,
      version.versionLabel,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Restored version' : 'Could not restore version',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (success) _load();
  }

  Future<void> _download(NextcloudFileVersion version) async {
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(
        tempDir.path,
        '${version.versionLabel}_${widget.item.name}',
      );
      final success = await ops.downloadVersion(
        widget.item,
        version.versionLabel,
        tempPath,
      );
      if (!success) throw Exception('download failed');
      final ext = p.extension(widget.item.name).replaceFirst('.', '');
      final baseName = p.basenameWithoutExtension(widget.item.name);
      await FileSaver.instance.saveFile(
        name: baseName,
        filePath: tempPath,
        fileExtension: ext,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Version downloaded'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not download version'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final items = [
      NextcloudFileVersion(
        versionLabel: 'current',
        timestamp: widget.item.lastModified,
        size: widget.item.size,
        isCurrent: true,
      ),
      ..._versions,
    ];
    final kind = NooFileKind.from(
      name: widget.item.name,
      mimeType: widget.item.mimeType,
      isDirectory: false,
    );

    return NooGroupedList(
      children: [
        for (final version in items)
          _VersionRow(
            kind: kind,
            version: version,
            onRestore: () => _restore(version),
            onDownload: () => _download(version),
          ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  final NooFileKind kind;
  final NextcloudFileVersion version;
  final VoidCallback onRestore;
  final VoidCallback onDownload;

  const _VersionRow({
    required this.kind,
    required this.version,
    required this.onRestore,
    required this.onDownload,
  });

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
          children: [
            NooFileTile(kind: kind, size: NooFileTileSize.activity),
            const SizedBox(width: NooSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    version.isCurrent
                        ? 'Current version'
                        : DateFormat.yMMMd().add_jm().format(version.timestamp),
                    style: NooText.bodyL.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.fg1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatBytes(version.size)} · ${DateFormat.yMMMd().format(version.timestamp)}',
                    style: NooText.meta.copyWith(color: colors.fg3),
                  ),
                ],
              ),
            ),
            if (!version.isCurrent) ...[
              const SizedBox(width: NooSpace.xs),
              _RowIconButton(
                icon: LucideIcons.rotateCcw,
                tooltip: 'Restore',
                onTap: onRestore,
              ),
              const SizedBox(width: NooSpace.xxs),
              _RowIconButton(
                icon: LucideIcons.download,
                tooltip: 'Download',
                onTap: onDownload,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small round icon button matching [NooCloseButton]'s visual language
/// (surface-2 circle) but for an arbitrary action - promote this to `noo/`
/// if another row-level icon action needs the same treatment.
class _RowIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.surface2, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: colors.fg2),
        ),
      ),
    );
  }
}
