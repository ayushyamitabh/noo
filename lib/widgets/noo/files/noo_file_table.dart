import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';
import 'noo_file_kind.dart';
import 'noo_file_row.dart';
import 'noo_file_tile.dart';
import 'noo_status_icon.dart';

/// Fixed widths of the desktop file table's grid
/// (`minmax(0,1fr) 180px 160px 120px`, `DESIGN_SYSTEM.md` 2 "File row").
/// The first column takes the remaining width.
const double _col2Width = 180;
const double _col3Width = 160;
const double _col4Width = 120;

/// Inset shared by header and rows so their columns line up; also the
/// padding inside a selected row's r12 fill.
const double _tableInset = NooSpace.sm;

/// Lays out the four table columns. Shared by [NooFileTableHeader] and
/// [NooFileTableRow] so the grid can't drift between them.
class _TableColumns extends StatelessWidget {
  final Widget name;
  final Widget col2;
  final Widget col3;
  final Widget col4;

  const _TableColumns({
    required this.name,
    required this.col2,
    required this.col3,
    required this.col4,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _tableInset),
      child: Row(
        children: [
          Expanded(child: name),
          SizedBox(width: _col2Width, child: col2),
          SizedBox(width: _col3Width, child: col3),
          SizedBox(width: _col4Width, child: col4),
        ],
      ),
    );
  }
}

/// Desktop file table header: 36px, 12/600 fg-3 labels, and a sort arrow
/// on the active column. The fourth (status/overflow) column is unlabelled.
class NooFileTableHeader extends StatelessWidget {
  /// Label for the flexible Name column.
  final String nameLabel;

  /// Labels for the 180px and 160px data columns, e.g. "Modified", "Size".
  final String col2Label;
  final String col3Label;

  /// Active sort column - 0 = name, 1 = col2, 2 = col3 - or null for none.
  final int? sortColumn;
  final bool sortAscending;

  /// Called with the tapped column's index; header cells aren't tappable
  /// when null.
  final ValueChanged<int>? onSort;

  const NooFileTableHeader({
    super.key,
    this.nameLabel = 'Name',
    required this.col2Label,
    required this.col3Label,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
  });

  Widget _cell(BuildContext context, int index) {
    final colors = context.nooColors;
    final style = NooText.label.copyWith(
      fontSize: 12,
      height: 1,
      color: colors.fg3,
    );
    final active = sortColumn == index;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            [nameLabel, col2Label, col3Label][index],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (active) ...[
          const SizedBox(width: NooSpace.xxs),
          Icon(
            sortAscending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
            size: 12,
            color: colors.fg3,
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: onSort == null
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSort!(index),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: content,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: _TableColumns(
        name: _cell(context, 0),
        col2: _cell(context, 1),
        col3: _cell(context, 2),
        col4: const SizedBox.shrink(),
      ),
    );
  }
}

/// Desktop file table row: 52px, 30px tile + name (14/500) in the flexible
/// column, two meta-style data columns, then status icons and the overflow
/// button right-aligned in the 120px column. Selected rows get an
/// accent-soft r12 fill; otherwise the row is transparent over the pane.
class NooFileTableRow extends StatelessWidget {
  final NooFileKind kind;
  final String name;

  /// Second and third column contents, e.g. modified time and size.
  final String? col2;
  final String? col3;

  /// Status icons in the last column, drawn before the favorite star.
  final List<NooSyncStatus> statuses;
  final bool favorite;
  final bool selected;
  final Widget? thumbnail;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;

  /// Overflow menu tap. The button is hidden when null.
  final VoidCallback? onMore;

  const NooFileTableRow({
    super.key,
    required this.kind,
    required this.name,
    this.col2,
    this.col3,
    this.statuses = const [],
    this.favorite = false,
    this.selected = false,
    this.thumbnail,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final metaStyle = NooText.meta.copyWith(color: colors.fg3);
    Widget dataCell(String? text) => Text(
      text ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: metaStyle,
    );

    return Material(
      color: selected ? colors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(NooRadii.sidebarItem),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTap: onSecondaryTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: NooSizes.rowDesktop,
          child: _TableColumns(
            name: Row(
              children: [
                NooFileTile(
                  kind: kind,
                  size: NooFileTileSize.desktop,
                  thumbnail: thumbnail,
                ),
                const SizedBox(width: NooSpace.sm),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.fg1,
                    ),
                  ),
                ),
                const SizedBox(width: NooSpace.md),
              ],
            ),
            col2: dataCell(col2),
            col3: dataCell(col3),
            col4: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final s in statuses) ...[
                  NooStatusIcon(s),
                  const SizedBox(width: 6),
                ],
                if (favorite) ...[
                  Icon(LucideIcons.star, size: 14, color: colors.accentText),
                  const SizedBox(width: 6),
                ],
                if (onMore != null) NooOverflowButton(size: 32, onTap: onMore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
