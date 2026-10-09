import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/nextcloud_item.dart';
import '../providers/recent_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/lists/noo_settings_row.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/noo/overlays/noo_sheet.dart';
import '../widgets/share_sheet.dart';
import '../widgets/tabs/tab_day_groups.dart';
import '../widgets/tabs/tab_location.dart';
import '../widgets/tabs/tab_state_slivers.dart';
import 'file_viewer_screen.dart';

/// Recently modified files across the whole account (not folders), newest
/// first - see [RecentController.fetchAll]. Grouped into Today/Yesterday/
/// This week/Earlier per `DESIGN_SYSTEM.md` §4; meta is "Modified {time} ·
/// {location}" since the server only ever reports a modification, not a
/// distinct action per entry.
class RecentView extends StatefulWidget {
  final ScrollController scrollController;

  /// This tab's own shell top bar, planted as its first sliver - see
  /// `buildAppTabView`'s doc comment. Null on desktop and while picking.
  final PreferredSizeWidget? topBar;

  const RecentView({super.key, required this.scrollController, this.topBar});

  @override
  State<RecentView> createState() => _RecentViewState();
}

class _RecentViewState extends State<RecentView> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final recent = context.watch<RecentController>();

    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => recent.fetchAll());
    }

    final items = recent.items;
    final isDesktop = NooLayout.isDesktop(context);
    final groups = groupByRecentBucket<NextcloudItem>(
      items,
      (item) => item.lastModified,
    );

    final List<Widget> contentSlivers = [
      if (widget.topBar != null) topBarSliver(widget.topBar!),
      const SliverToBoxAdapter(child: SizedBox(height: NooSpace.md)),
      if (recent.isLoading && items.isEmpty)
        tabLoadingSliver
      else if (recent.errorMessage != null)
        tabErrorSliver(
          context,
          title: 'Could not load recent files',
          message: recent.errorMessage!,
          onRetry: recent.fetchAll,
        )
      else if (items.isEmpty)
        tabEmptySliver(
          context,
          icon: LucideIcons.clock,
          message: 'No recent files',
        )
      else if (isDesktop)
        _buildDesktopTable(context, groups)
      else
        _buildMobileGroups(context, groups),
      ...tabBottomInsetSlivers(context),
    ];

    return ColoredBox(
      color: NooLayout.contentBackground(context),
      child: RefreshIndicator(
        key: TabRefreshScope.keyOf(context),
        color: colors.accent,
        backgroundColor: colors.surface,
        onRefresh: recent.fetchAll,
        // See files_view.dart's identical fix - without this, the sticky
        // controls row rides up under the status bar once the floating top
        // bar above it fully collapses.
        child: SafeArea(
          top: true,
          bottom: false,
          child: CustomScrollView(
            controller: widget.scrollController,
            // See files_view.dart's identical fix - without this, pull-to-
            // refresh can't be triggered on an empty or single-item list.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: contentSlivers,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileGroups(
    BuildContext context,
    List<TabDayGroup<NextcloudItem>> groups,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: NooSpace.sm),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final group = groups[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == groups.length - 1 ? 0 : 18,
            ),
            child: NooGroupedList(
              label: group.label,
              children: [
                for (final item in group.items) _buildRow(context, item),
              ],
            ),
          );
        }, childCount: groups.length),
      ),
    );
  }

  Widget _buildDesktopTable(
    BuildContext context,
    List<TabDayGroup<NextcloudItem>> groups,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: NooSpace.xl,
        vertical: NooSpace.xs,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final group = groups[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TabGroupLabel(group.label),
                const NooFileTableHeader(
                  col2Label: 'Modified',
                  col3Label: 'Location',
                ),
                for (final item in group.items) _buildDesktopRow(context, item),
              ],
            ),
          );
        }, childCount: groups.length),
      ),
    );
  }

  Widget _buildRow(BuildContext context, NextcloudItem item) {
    return NooFileRow(
      kind: NooFileKind.from(
        name: item.name,
        mimeType: item.mimeType,
        isDirectory: item.isFolder,
      ),
      name: item.name,
      meta: 'Modified ${_metaTime(item.lastModified)} · ${_location(item)}',
      favorite: item.isFavorite,
      iosStyle: NooLayout.iosStyle(context),
      onTap: () => _openFile(context, item),
      onMore: () => _showItemSheet(context, item),
    );
  }

  Widget _buildDesktopRow(BuildContext context, NextcloudItem item) {
    return NooFileTableRow(
      kind: NooFileKind.from(
        name: item.name,
        mimeType: item.mimeType,
        isDirectory: item.isFolder,
      ),
      name: item.name,
      col2: _metaTime(item.lastModified),
      col3: _location(item),
      favorite: item.isFavorite,
      onTap: () => _openFile(context, item),
      onMore: () => _showItemSheet(context, item),
    );
  }

  void _showItemSheet(BuildContext context, NextcloudItem item) {
    showNooSheet(
      context,
      children: [
        NooGroupedList(
          children: [
            NooSettingsRow(
              icon: LucideIcons.info,
              label: const Text('Details'),
              onTap: () {
                Navigator.pop(context);
                DetailsSheet.show(context, item);
              },
            ),
            NooSettingsRow(
              icon: LucideIcons.share2,
              label: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                ShareSheet.show(context, item);
              },
            ),
          ],
        ),
      ],
    );
  }

  /// Preserves the original screen's exact tap behavior: always opens the
  /// media viewer (the server's recent-files search only ever returns
  /// files, never folders, so there's no folder-navigation case to handle).
  void _openFile(BuildContext context, NextcloudItem item) {
    final recent = context.read<RecentController>();
    final siblings = recent.items.where((i) => i.isMedia).toList();
    Navigator.push(
      context,
      FileViewerScreen.route(item: item, siblings: siblings),
    );
  }
}

String _metaTime(DateTime dt) {
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return DateFormat.jm().format(dt);
  }
  if (dt.year == now.year) return DateFormat.MMMd().format(dt);
  return DateFormat.yMMMd().format(dt);
}

String _location(NextcloudItem item) => tabLocationLabel(item.path, item.name);
