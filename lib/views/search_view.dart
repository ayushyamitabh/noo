import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/app_tab.dart';
import '../models/nextcloud_item.dart';
import '../providers/files_controller.dart';
import '../providers/settings_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/core/noo_search_field.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/nav/noo_toolbar.dart';
import '../widgets/noo/noo_layout.dart';
import 'file_viewer_screen.dart';

/// Full-text file search, pushed from the shell's search entry point
/// (`openSearch` in `widgets/shell/shell_common.dart`). Debounces input,
/// then lists matches as file rows - tapping one jumps to the result on the
/// Files tab (see [_openResult]). Per DESIGN_SYSTEM.md §4 "Search".
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
    final files = context.read<FilesController>();
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await files.searchFiles(query);
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

  /// Navigates the Files tab to [item] (its own folder if it's a folder,
  /// its parent folder otherwise - rebuilding the whole breadcrumb trail
  /// from root rather than assuming it's under wherever the user was
  /// browsing before), switches the shell to the Files tab, and closes
  /// search. For a file, also opens it once back on Files.
  Future<void> _openResult(NextcloudItem item) async {
    final files = context.read<FilesController>();
    final settings = context.read<SettingsController>();
    final navigator = Navigator.of(context);

    final folderPath = item.isFolder ? item.path : p.dirname(item.path);
    await files.navigateToAbsoluteFolder(folderPath);
    settings.requestTab(AppTab.files);
    navigator.popUntil((route) => route.isFirst);

    if (!item.isFolder) {
      navigator.push(FileViewerScreen.route(item: item));
    }
  }

  void _clear() {
    _controller.clear();
    _focusNode.requestFocus();
    _onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: desktop
          ? NooToolbar(
              titleWidget: _buildField(onSurface: true),
              actions: [
                IconTheme.merge(
                  data: IconThemeData(color: colors.fg1, size: 24),
                  child: NooTopBarButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ],
            )
          : null,
      body: SafeArea(
        top: !desktop,
        child: desktop
            ? _buildBody(context, desktop)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NooSpace.xs,
                      NooSpace.xs,
                      NooSpace.md,
                      NooSpace.xs,
                    ),
                    child: Row(
                      children: [
                        IconTheme.merge(
                          data: IconThemeData(color: colors.fg1, size: 24),
                          child: NooTopBarButton(
                            icon: LucideIcons.arrowLeft,
                            tooltip: 'Back',
                            onTap: () => Navigator.pop(context),
                          ),
                        ),
                        Expanded(child: _buildField(onSurface: false)),
                      ],
                    ),
                  ),
                  Expanded(child: _buildBody(context, desktop)),
                ],
              ),
      ),
    );
  }

  Widget _buildField({required bool onSurface}) {
    // The pill `NooSearchField`, not the inset-panel `NooTextField` - this
    // is a search field (DESIGN_SYSTEM.md's "Search field" component,
    // radius 999 outside the one iOS-inline exception), not a form input.
    // `ios: false` matches the Android shape we're building against now;
    // revisit once the iOS large-title/inline-field entry point is built.
    return NooSearchField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      placeholder: 'Search files',
      onChanged: _onChanged,
      onSurface: onSurface,
      ios: false,
      trailing: _controller.text.isEmpty
          ? null
          : _ClearFieldButton(onTap: _clear),
    );
  }

  Widget _buildBody(BuildContext context, bool desktop) {
    final colors = context.nooColors;

    if (_isSearching) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null) {
      return _buildMessage(
        context,
        icon: LucideIcons.circleAlert,
        iconColor: colors.danger,
        title: 'Couldn\'t search',
        message: _error,
      );
    }
    if (!_hasSearched) {
      return _buildMessage(
        context,
        icon: LucideIcons.search,
        iconColor: colors.fg3,
        title: 'Search your files',
        message: 'Find files and folders by name.',
      );
    }
    if (_results.isEmpty) {
      return _buildMessage(
        context,
        icon: LucideIcons.searchX,
        iconColor: colors.fg3,
        title: 'No results found',
      );
    }
    return desktop ? _buildDesktopResults(context) : _buildMobileResults(context);
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? message,
  }) {
    final colors = context.nooColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NooSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: NooSpace.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: NooText.cardTitle.copyWith(color: colors.fg2),
            ),
            if (message != null) ...[
              const SizedBox(height: NooSpace.xxs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: NooText.body.copyWith(color: colors.fg3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileResults(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        NooSpace.sm,
        NooSpace.xs,
        NooSpace.sm,
        NooSpace.xl,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NooRadii.card),
            child: NooFileRow(
              kind: NooFileKind.from(
                name: item.name,
                mimeType: item.mimeType,
                isDirectory: item.isFolder,
              ),
              name: item.name,
              meta: _mobileMeta(item),
              favorite: item.isFavorite,
              iosStyle: NooLayout.iosStyle(context),
              onTap: () => _openResult(item),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopResults(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: NooSpace.xl,
        vertical: NooSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NooFileTableHeader(col2Label: 'Modified', col3Label: 'Location'),
          for (final item in _results)
            NooFileTableRow(
              kind: NooFileKind.from(
                name: item.name,
                mimeType: item.mimeType,
                isDirectory: item.isFolder,
              ),
              name: item.name,
              col2: DateFormat.yMMMd().format(item.lastModified),
              col3: item.isFolder ? item.path : p.dirname(item.path),
              favorite: item.isFavorite,
              onTap: () => _openResult(item),
            ),
        ],
      ),
    );
  }

  /// Mirrors the pre-rework screen's exact copy: a folder result shows its
  /// own full path (there's no separate "location" field to fall back to),
  /// a file result shows when it was last modified.
  String _mobileMeta(NextcloudItem item) =>
      item.isFolder ? item.path : DateFormat.yMMMd().format(item.lastModified);
}

/// Small round "clear" button for [NooTextField.trailing] - clears the
/// query and puts focus back in the field, same as the old `SearchBar`'s
/// trailing close icon.
class _ClearFieldButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ClearFieldButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return SizedBox.square(
      dimension: 32,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(LucideIcons.x, size: 16, color: colors.fg3),
        ),
      ),
    );
  }
}
