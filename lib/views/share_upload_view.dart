import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/app_tab.dart';
import '../providers/server_provider.dart';
import '../widgets/breadcrumbs.dart';

/// Shown when another app shares one or more files to Noo (Android's
/// "Share to..." sheet). Lets the user browse to a destination folder, then
/// uploads every shared file into it via the same WebDAV upload path as the
/// Files tab's own "Upload File" action.
class ShareUploadView extends StatefulWidget {
  final List<SharedMediaFile> files;

  const ShareUploadView({super.key, required this.files});

  @override
  State<ShareUploadView> createState() => _ShareUploadViewState();
}

class _ShareUploadViewState extends State<ShareUploadView> {
  bool _uploading = false;
  int _currentFileIndex = 0;
  double? _currentFileProgress;

  @override
  void initState() {
    super.initState();
    // Shared files have no relationship to wherever the user was last
    // browsing, so start the destination picker fresh at the root.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ServerProvider>().navigateToAbsoluteFolder('/');
    });
  }

  Future<void> _uploadHere(ServerProvider provider) async {
    setState(() => _uploading = true);

    var anyFailed = false;
    for (var i = 0; i < widget.files.length; i++) {
      final file = widget.files[i];
      setState(() {
        _currentFileIndex = i;
        _currentFileProgress = 0;
      });
      final name = p.basename(file.path);
      final success = await provider.uploadFileFromPath(
        name,
        file.path,
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _currentFileProgress = sent / total);
          }
        },
      );
      if (!success) anyFailed = true;
    }

    if (!mounted) return;

    provider.requestTab(AppTab.files);
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          anyFailed
              ? 'Some files failed to upload'
              : widget.files.length == 1
              ? 'Uploaded ${p.basename(widget.files.first.path)}'
              : 'Uploaded ${widget.files.length} files',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final hasBreadcrumbs = provider.pathStack.length > 1;
    final currentPath = provider.pathStack.last;
    final currentLabel = currentPath == '/'
        ? 'Home'
        : currentPath.split('/').where((s) => s.isNotEmpty).last;
    final folders = provider.items.where((i) => i.isFolder).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.files.length == 1
              ? 'Upload ${p.basename(widget.files.first.path)}'
              : 'Upload ${widget.files.length} files',
        ),
      ),
      body: _uploading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: _currentFileProgress,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.files.length == 1
                          ? 'Uploading ${p.basename(widget.files[_currentFileIndex].path)}…'
                          : 'Uploading ${_currentFileIndex + 1} of ${widget.files.length}…',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (hasBreadcrumbs)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Breadcrumbs(
                      pathStack: provider.pathStack,
                      onTap: (index) => provider.navigateToPathIndex(index),
                    ),
                  ),
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : folders.isEmpty
                      ? Center(
                          child: Text(
                            'No subfolders here',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: folders.length,
                          itemBuilder: (context, index) {
                            final folder = folders[index];
                            return ListTile(
                              leading: Icon(
                                Icons.folder_rounded,
                                color: colorScheme.primary,
                              ),
                              title: Text(folder.name),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () =>
                                  provider.navigateToFolder(folder.path),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _uploading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _uploadHere(provider),
                  icon: const Icon(Icons.upload_rounded),
                  label: Text('Upload to $currentLabel'),
                ),
              ),
            ),
    );
  }
}
