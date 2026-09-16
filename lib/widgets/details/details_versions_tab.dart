import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../models/nextcloud_file_version.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/server_provider.dart';
import '../synced_header_scaffold.dart' show formatBytes;

/// File version history — a synthetic "Current version" row (from the
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
    final provider = context.read<ServerProvider>();
    final result = await provider.fetchFileVersions(widget.item);
    if (!mounted) return;
    setState(() {
      _versions = result;
      _isLoading = false;
    });
  }

  Future<void> _restore(NextcloudFileVersion version) async {
    final provider = context.read<ServerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.restoreFileVersion(
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
    final provider = context.read<ServerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(
        tempDir.path,
        '${version.versionLabel}_${widget.item.name}',
      );
      final success = await provider.downloadVersion(
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
        ext: ext,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final version = items[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.history_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          title: Text(
            version.isCurrent
                ? 'Current version'
                : DateFormat.yMMMd().add_jm().format(version.timestamp),
          ),
          subtitle: Text(
            '${DateFormat.yMMMd().format(version.timestamp)} • ${formatBytes(version.size)}',
          ),
          trailing: version.isCurrent
              ? null
              : PopupMenuButton<String>(
                  onSelected: (value) => value == 'restore'
                      ? _restore(version)
                      : _download(version),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'restore', child: Text('Restore')),
                    PopupMenuItem(value: 'download', child: Text('Download')),
                  ],
                ),
        );
      },
    );
  }
}
