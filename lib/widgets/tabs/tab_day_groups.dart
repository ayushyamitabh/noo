import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import '../../theme/design_tokens.dart';

/// Day-bucketing shared by Recent (Today/Yesterday/This week/Earlier) and
/// Activity (one group per calendar day) - see `DESIGN_SYSTEM.md` §4.

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// One labelled bucket of [items], already in their original (newest-first)
/// order.
class TabDayGroup<T> {
  final String label;
  final List<T> items;
  const TabDayGroup(this.label, this.items);
}

/// Buckets newest-first [items] into Today / Yesterday / This week /
/// Earlier. Empty buckets are omitted.
List<TabDayGroup<T>> groupByRecentBucket<T>(
  List<T> items,
  DateTime Function(T item) dateOf,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  // "This week" reaches back 6 days before today (7 days inclusive) -
  // anything older falls to "Earlier".
  final weekStart = today.subtract(const Duration(days: 6));

  final todayItems = <T>[];
  final yesterdayItems = <T>[];
  final weekItems = <T>[];
  final earlierItems = <T>[];

  for (final item in items) {
    final d = dateOf(item);
    final day = DateTime(d.year, d.month, d.day);
    if (_isSameDay(day, today)) {
      todayItems.add(item);
    } else if (_isSameDay(day, yesterday)) {
      yesterdayItems.add(item);
    } else if (!day.isBefore(weekStart)) {
      weekItems.add(item);
    } else {
      earlierItems.add(item);
    }
  }

  return [
    if (todayItems.isNotEmpty) TabDayGroup('Today', todayItems),
    if (yesterdayItems.isNotEmpty) TabDayGroup('Yesterday', yesterdayItems),
    if (weekItems.isNotEmpty) TabDayGroup('This week', weekItems),
    if (earlierItems.isNotEmpty) TabDayGroup('Earlier', earlierItems),
  ];
}

/// Buckets newest-first [items] one group per calendar day (Activity's
/// "feed grouped by day" - unlike [groupByRecentBucket], days past
/// yesterday each keep their own header rather than folding into "This
/// week"/"Earlier").
List<TabDayGroup<T>> groupByCalendarDay<T>(
  List<T> items,
  DateTime Function(T item) dateOf,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final order = <DateTime>[];
  final groups = <DateTime, List<T>>{};
  for (final item in items) {
    final d = dateOf(item);
    final day = DateTime(d.year, d.month, d.day);
    final bucket = groups.putIfAbsent(day, () {
      order.add(day);
      return [];
    });
    bucket.add(item);
  }

  String labelFor(DateTime day) {
    if (_isSameDay(day, today)) return 'Today';
    if (_isSameDay(day, yesterday)) return 'Yesterday';
    return DateFormat.yMMMd().format(day);
  }

  return [for (final day in order) TabDayGroup(labelFor(day), groups[day]!)];
}

/// The "Today"/"Yesterday"/... label above a day group - `DESIGN_SYSTEM.md`
/// §2's grouped-list label style (13/600 fg-2, inset 8px). Standalone
/// (rather than `NooGroupedList.label`) for Activity, whose items aren't a
/// `NooGroupedList` card.
class TabGroupLabel extends StatelessWidget {
  final String label;

  const TabGroupLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(label, style: NooText.label.copyWith(color: colors.fg2)),
    );
  }
}
