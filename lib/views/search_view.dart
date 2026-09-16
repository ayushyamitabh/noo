import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import 'file_viewer_screen.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<NextcloudItem> _results = [];
  bool _isSearching = false;
  String? _error;
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final provider = context.read<ServerProvider>();
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await provider.searchFiles(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _hasSearched = true;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  IconData _iconFor(NextcloudItemType type) {
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

  /// Navigates the Files tab to [item] (its own folder if it's a folder,
  /// its parent folder otherwise - rebuilding the whole breadcrumb trail
  /// from root rather than assuming it's under wherever the user was
  /// browsing before), switches the shell to the Files tab, and closes
  /// search. For a file, also opens it once back on Files.
  Future<void> _openResult(NextcloudItem item) async {
    final provider = context.read<ServerProvider>();
    final navigator = Navigator.of(context);

    final folderPath = item.isFolder ? item.path : p.dirname(item.path);
    await provider.navigateToAbsoluteFolder(folderPath);
    provider.requestTab(AppTab.files);
    navigator.popUntil((route) => route.isFirst);

    if (!item.isFolder) {
      navigator.push(FileViewerScreen.route(item: item));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SearchBar(
                controller: _controller,
                focusNode: _focusNode,
                autoFocus: true,
                hintText: 'Search your files...',
                elevation: const WidgetStatePropertyAll(0),
                onChanged: _onChanged,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, colorScheme, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      );
    }
    if (!_hasSearched) {
      return const SizedBox.shrink();
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return ListTile(
          leading: Icon(_iconFor(item.type), color: colorScheme.primary),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.isFolder
                ? item.path
                : DateFormat.yMMMd().format(item.lastModified),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openResult(item),
        );
      },
    );
  }
}
