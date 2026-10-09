import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/app_tab.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_toggle.dart';
import '../noo/lists/noo_settings_row.dart';
import '../noo/lists/noo_tab_order_row.dart';
import '../noo/noo_layout.dart';
import 'settings_section.dart';

/// Settings section 7: bottom-nav tab order, visibility (pinned = shown, up
/// to [SettingsController.maxVisibleTabs] - one fewer while Appearance's
/// "Search in bottom bar" is on) and default tab.
class SettingsTabsSection extends StatelessWidget {
  const SettingsTabsSection({super.key});

  void _openDefaultTabPicker(
    BuildContext context,
    SettingsController settings,
  ) {
    final visible = settings.tabOrder
        .where((t) => !settings.hiddenTabs.contains(t))
        .toList();
    showSettingsPicker(
      context,
      title: 'Default tab',
      options: [
        for (final tab in visible)
          NooSettingsRow(
            icon: tab.icon,
            label: Text(tab.label),
            trailing: tab == settings.defaultTab
                ? Icon(
                    LucideIcons.check,
                    size: 18,
                    color: context.nooColors.accentText,
                  )
                : null,
            onTap: () {
              settings.setDefaultTab(tab);
              Navigator.pop(context);
            },
          ),
      ],
    );
  }

  void _handleTogglePin(
    BuildContext context,
    SettingsController settings,
    AppTab tab,
    bool pinned,
  ) {
    // setTabHidden's `hidden` argument is the *new* hidden state, which is
    // just the tab's current pinned (= visible) state flipped.
    final error = settings.setTabHidden(tab, pinned);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _handleReorder(SettingsController settings, int oldIndex, int newIndex) {
    final order = List<AppTab>.from(settings.tabOrder);
    final tab = order.removeAt(oldIndex);
    order.insert(newIndex, tab);
    settings.setTabOrder(order);
  }

  static const _subtitle = 'Drag to reorder, pin up to 5 to the bottom bar';

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final desktop = NooLayout.isDesktop(context);

    final optionRows = [
      if (!desktop)
        NooSettingsRow(
          icon: LucideIcons.arrowUpDown,
          label: const Text('Tap tab to scroll to top'),
          subtitle: const Text(
            'Tapping the current bottom bar tab scrolls its list back to the top',
          ),
          trailing: NooToggle(
            checked: settings.tapTabToScrollTop,
            onChanged: settings.setTapTabToScrollTop,
          ),
        ),
      NooSettingsRow(
        icon: LucideIcons.star,
        label: const Text('Default tab'),
        value: settings.defaultTab.label,
        onTap: () => _openDefaultTabPicker(context, settings),
      ),
    ];
    final orderList = _TabOrderList(
      tabs: settings.tabOrder,
      hiddenTabs: settings.hiddenTabs,
      flat: desktop,
      onReorder: (oldIndex, newIndex) =>
          _handleReorder(settings, oldIndex, newIndex),
      onTogglePin: (tab, pinned) =>
          _handleTogglePin(context, settings, tab, pinned),
    );

    if (!desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSection(
            title: 'Tabs',
            subtitle: _subtitle,
            children: optionRows,
          ),
          const SizedBox(height: NooSpace.md),
          orderList,
        ],
      );
    }

    // Desktop: one bordered card holding both the plain option rows and
    // the reorderable list, so Tabs still reads as a single grid cell
    // ("a 2-column grid of cards with a 1px line and radius 20") instead of
    // splitting into two stacked cards the way the mobile layout does.
    final colors = context.nooColors;
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
          if (SettingsCategoryHeading.shows(context, 'Tabs'))
            Text('Tabs', style: NooText.cardTitle.copyWith(color: colors.fg1)),
          const SizedBox(height: 4),
          Text(_subtitle, style: NooText.meta.copyWith(color: colors.fg3)),
          const SizedBox(height: NooSpace.md),
          FlatRowGroup(children: optionRows),
          const SizedBox(height: NooSpace.sm),
          orderList,
        ],
      ),
    );
  }
}

/// The reorderable [NooTabOrderRow] stack - a radius-20, line-divided card
/// like [NooGroupedList] draws, but [NooGroupedList] itself has no
/// reordering support, so this rebuilds that same look around a
/// [ReorderableListView.builder] instead of wrapping it.
class _TabOrderList extends StatelessWidget {
  final List<AppTab> tabs;
  final Set<AppTab> hiddenTabs;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(AppTab tab, bool pinned) onTogglePin;

  /// True when an ancestor (the desktop card) already supplies the
  /// surrounding radius-20 border, so this should render just the divided
  /// rows without its own outer clip/line background.
  final bool flat;

  const _TabOrderList({
    required this.tabs,
    required this.hiddenTabs,
    required this.onReorder,
    required this.onTogglePin,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final list = ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: tabs.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final tab = tabs[index];
        final pinned = !hiddenTabs.contains(tab);
        return Padding(
          key: ValueKey(tab),
          padding: EdgeInsets.only(top: index > 0 ? 1 : 0),
          child: NooTabOrderRow(
            icon: tab.icon,
            label: tab.label,
            pinned: pinned,
            onTogglePin: () => onTogglePin(tab, pinned),
            dragIndex: index,
          ),
        );
      },
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        flat ? NooRadii.input : NooRadii.card,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.line),
        child: list,
      ),
    );
  }
}
