import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/selection_action.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_tab_order_row.dart';
import '../noo/lists/noo_settings_row.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../noo/core/noo_segmented_control.dart';
import '../noo/noo_layout.dart';

/// Settings section: the priority order bulk actions (favorite, share,
/// download, ...) show in on the Files/Photos/Favorites multi-select
/// action bar. Every action stays available everywhere - this only decides
/// which ones land in `NooSelectionBar`'s fixed inline slots (3 mobile / 4
/// desktop, see its own doc comment) vs. behind its trailing "More" -
/// there's no pin/hide concept here the way Tabs has, so this is just a
/// position choice followed by a reorder list.
class SettingsActionBarSection extends StatelessWidget {
  const SettingsActionBarSection({super.key});

  static const _subtitle =
      'Drag to reorder - the first ones shown appear directly in the bar, the rest sit behind "More"';

  void _handleReorder(SettingsController settings, int oldIndex, int newIndex) {
    final order = List<SelectionActionKind>.from(settings.selectionActionOrder);
    final kind = order.removeAt(oldIndex);
    order.insert(newIndex, kind);
    settings.setSelectionActionOrder(order);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final desktop = NooLayout.isDesktop(context);

    final orderList = _ActionOrderList(
      rounded: desktop,
      order: settings.selectionActionOrder,
      onReorder: (oldIndex, newIndex) =>
          _handleReorder(settings, oldIndex, newIndex),
    );

    final positionRow = NooSettingsRow(
      label: const Text('Position'),
      trailing: NooSegmentedControl<SelectionBarPosition>(
        onSurface: true,
        value: settings.selectionBarPosition,
        onChanged: settings.setSelectionBarPosition,
        options: const [
          NooSegmentOption(value: SelectionBarPosition.top, label: 'Top'),
          NooSegmentOption(value: SelectionBarPosition.bottom, label: 'Bottom'),
        ],
      ),
    );
    final colors = context.nooColors;

    if (!desktop) {
      return NooGroupedList(
        footer: const Text(_subtitle),
        children: [positionRow, orderList],
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
          Text(
            'Action bar',
            style: NooText.cardTitle.copyWith(color: colors.fg1),
          ),
          const SizedBox(height: 4),
          Text(_subtitle, style: NooText.meta.copyWith(color: colors.fg3)),
          const SizedBox(height: NooSpace.md),
          positionRow,
          const SizedBox(height: NooSpace.md),
          orderList,
        ],
      ),
    );
  }
}

/// The reorderable [NooTabOrderRow] stack for [SelectionActionKind]s - same
/// radius-20, line-divided card `settings_tabs.dart`'s `_TabOrderList`
/// draws, minus the pin toggle (`showPin: false`): there's nothing to
/// show/hide here, only an order.
class _ActionOrderList extends StatelessWidget {
  final List<SelectionActionKind> order;
  final void Function(int oldIndex, int newIndex) onReorder;
  final bool rounded;

  const _ActionOrderList({
    required this.order,
    required this.onReorder,
    required this.rounded,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final list = ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: order.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final kind = order[index];
        return Padding(
          key: ValueKey(kind),
          padding: EdgeInsets.only(top: index > 0 ? 1 : 0),
          child: NooTabOrderRow(
            icon: kind.icon,
            label: kind.label,
            showPin: false,
            dragIndex: index,
          ),
        );
      },
    );
    final rows = DecoratedBox(
      decoration: BoxDecoration(color: colors.line),
      child: list,
    );
    if (!rounded) return rows;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NooRadii.card),
      child: rows,
    );
  }
}
