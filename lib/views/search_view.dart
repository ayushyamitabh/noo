import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search your files...',
            border: InputBorder.none,
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
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
      body: _buildBody(context, colorScheme, theme),
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
      return Center(
        child: Text(
          'Search across your whole Nextcloud',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
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
          onTap: () {
            if (item.isFolder) {
              context.read<ServerProvider>().navigateToFolder(item.path);
              Navigator.pop(context);
            } else {
              Navigator.push(context, FileViewerScreen.route(item: item));
            }
          },
        );
      },
    );
  }
}
