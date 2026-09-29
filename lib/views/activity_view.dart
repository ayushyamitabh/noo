import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/nextcloud_item.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/media/noo_activity_item.dart';
import '../widgets/noo/media/noo_photo_tile.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/tabs/tab_day_groups.dart';
import '../widgets/tabs/tab_state_slivers.dart';

/// The whole-account activity feed - lives on [FilesController] (fetched
/// alongside the current Files folder) rather than its own controller, see
/// `FilesController.refreshData`. Grouped by calendar day per
/// `DESIGN_SYSTEM.md` §4; desktop centers the feed at 760px.
///
/// [NextcloudActivity] only carries a rendered `title`/`subject` string
/// pair plus an `author` username - the server response has no structured
/// actor/verb/object breakdown or file reference, so the bold "actor"
/// segment is the author and the rest of the sentence (already fully
/// formed server-side) rides as one plain run rather than being split
/// further, and there's no reliable file to show in the trailing file
/// tile slot - see this screen's rebuild report for what a richer feed
/// would need from the service layer.
class ActivityView extends StatelessWidget {
  final ScrollController scrollController;

  const ActivityView({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final files = context.watch<FilesController>();
    final session = context.watch<SessionController>();
    final activities = files.activities;
    final isDesktop = NooLayout.isDesktop(context);
    final groups = groupByCalendarDay<NextcloudActivity>(
      activities,
      (a) => a.timestamp,
    );

    Widget feed;
    if (files.isLoading && activities.isEmpty) {
      feed = tabLoadingSliver;
    } else if (activities.isEmpty) {
      feed = tabEmptySliver(
        context,
        icon: LucideIcons.activity,
        message: 'No recent activity',
      );
    } else {
      feed = SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: NooLayout.gutter(context)),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final group = groups[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: NooGroupedList(
                label: group.label,
                children: [
                  for (final act in group.items)
                    Material(
                      color: colors.surface,
                      child: NooActivityItem(
                        actor: act.author,
                        verb: act.title,
                        tail: act.subject.isNotEmpty && act.subject != act.title
                            ? act.subject
                            : null,
                        time: DateFormat.jm().format(act.timestamp),
                        avatarColor: NooPhotoTile.paletteColor(
                          act.author.hashCode,
                        ),
                        currentUser:
                            act.author.toLowerCase() ==
                            session.username.toLowerCase(),
                      ),
                    ),
                ],
              ),
            );
          }, childCount: groups.length),
        ),
      );
    }

    final List<Widget> contentSlivers = [
      const SliverToBoxAdapter(child: SizedBox(height: NooSpace.md)),
      feed,
      ...tabBottomInsetSlivers,
    ];

    final scrollView = CustomScrollView(
      controller: scrollController,
      // See files_view.dart's identical fix - without this, pull-to-
      // refresh can't be triggered on an empty or single-item feed.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: contentSlivers,
    );

    return ColoredBox(
      color: colors.bg,
      child: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.surface,
        onRefresh: () => context.read<FilesController>().refreshData(),
        // "Desktop limits it to 760px wide" (DESIGN_SYSTEM.md §4) - centered
        // rather than left-aligned, so a wide window doesn't stretch the
        // feed's short sentences edge to edge.
        child: isDesktop
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: scrollView,
                ),
              )
            : scrollView,
      ),
    );
  }
}
