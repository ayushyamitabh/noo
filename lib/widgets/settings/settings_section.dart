import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../noo/lists/noo_info_note.dart';
import '../noo/noo_layout.dart';
import '../noo/overlays/noo_dialog.dart';
import '../noo/overlays/noo_sheet.dart';

/// Category heading already supplied by the tablet toolbar.
class SettingsCategoryHeading extends InheritedWidget {
  final String title;
  const SettingsCategoryHeading({
    super.key,
    required this.title,
    required super.child,
  });
  static bool shows(BuildContext context, String title) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsCategoryHeading>()
          ?.title !=
      title;
  @override
  bool updateShouldNotify(SettingsCategoryHeading oldWidget) =>
      title != oldWidget.title;
}

/// One block of Settings (DESIGN_SYSTEM.md 4's 9-part order): a
/// [NooGroupedList] on mobile (label above a radius-20 card), or a titled,
/// bordered radius-20 card holding a flat row group on desktop
/// ("Mobile uses one column of grouped lists. Desktop uses a 2-column grid
/// of cards with a 1px line and radius 20."). Shared by every
/// `lib/widgets/settings/*.dart` section so both layouts stay in sync from
/// one place.
class SettingsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Shown as a prominent [NooInfoNote] above the rows.
  final String? notice;

  const SettingsSection({
    super.key,
    required this.title,
    this.subtitle,
    this.notice,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    if (!NooLayout.isDesktop(context)) {
      return NooGroupedList(
        label: SettingsCategoryHeading.shows(context, title) ? title : null,
        notice: notice != null ? NooInfoNote(message: notice!) : null,
        footer: subtitle != null ? Text(subtitle!) : null,
        children: children,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(NooRadii.card),
      ),
      padding: const EdgeInsets.all(NooSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (SettingsCategoryHeading.shows(context, title))
            Text(title, style: NooText.cardTitle.copyWith(color: colors.fg1)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: NooText.meta.copyWith(color: colors.fg3)),
          ],
          const SizedBox(height: NooSpace.md),
          if (notice != null) ...[
            NooInfoNote(message: notice!),
            const SizedBox(height: NooSpace.md),
          ],
          FlatRowGroup(children: children),
        ],
      ),
    );
  }
}

/// The line-gapped row stack [NooGroupedList] draws internally, without its
/// own outer card/label - used for [SettingsSection]'s desktop card body,
/// which already supplies the surrounding card chrome, so nesting a second
/// radius-20 card there would double up the framing. Also reused directly
/// by `settings_tabs.dart`, whose desktop card mixes plain rows with a
/// reorderable list under one shared title/border instead of going through
/// [SettingsSection] itself.
class FlatRowGroup extends StatelessWidget {
  final List<Widget> children;
  const FlatRowGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NooRadii.input),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.line),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// The picker pattern for every "value + chevron" settings row (cache
/// policy, swipe actions, default tab...): a titled option list, a
/// [NooGroupedList] sheet on mobile or a [NooDialog] on desktop (mirrors
/// `files_controls_row.dart`'s sort/filter sheets). Each option row should
/// call `Navigator.pop(context)` itself after applying its choice.
void showSettingsPicker(
  BuildContext context, {
  required String title,
  required List<Widget> options,
}) {
  if (NooLayout.isDesktop(context)) {
    showNooDialog(
      context,
      title: title,
      children: [Column(children: options)],
    );
  } else {
    showNooSheet(
      context,
      children: [NooGroupedList(label: title, children: options)],
    );
  }
}
