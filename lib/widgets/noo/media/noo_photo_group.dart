import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// Month group heading for the Photos grid (`DESIGN_SYSTEM.md` section 2,
/// "Photo grid"): group heading (Schibsted 18/500, fg-1) on the left and
/// the item count in meta style (fg-3) on the right.
class NooPhotoGroupHeader extends StatelessWidget {
  final String title;

  /// e.g. `"128 photos"`; hidden when null.
  final String? count;

  /// Horizontal inset - 16 on mobile (the grid itself is edge to edge),
  /// 24 on desktop.
  final EdgeInsetsGeometry padding;

  const NooPhotoGroupHeader({
    super.key,
    required this.title,
    this.count,
    this.padding = const EdgeInsets.fromLTRB(
      NooSpace.md,
      NooSpace.lg,
      NooSpace.md,
      NooSpace.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NooText.groupHeading.copyWith(height: 1, color: colors.fg1),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: NooSpace.sm),
            Text(count!, style: NooText.meta.copyWith(color: colors.fg3)),
          ],
        ],
      ),
    );
  }
}

/// Square-tile photo grid (`DESIGN_SYSTEM.md` section 2, "Photo grid"):
/// mobile is 3 columns with a 2px gap edge to edge ([NooPhotoGrid.mobile]
/// defaults), desktop 8 columns with 4px ([NooPhotoGrid.desktop]).
///
/// Builds lazily from [itemBuilder] (typically returning a `NooPhotoTile`).
/// Use the default constructor inside a `CustomScrollView` as a sliver
/// (one per month group, after a `SliverToBoxAdapter(NooPhotoGroupHeader)`),
/// or [NooPhotoGrid.box] for a non-scrolling box that sizes to its content
/// (e.g. inside a `Column`/`ListView` item).
class NooPhotoGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int columns;
  final double gap;
  final EdgeInsetsGeometry padding;
  final bool _sliver;

  /// Sliver form. Defaults are the mobile layout.
  const NooPhotoGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.columns = 3,
    this.gap = 2,
    this.padding = EdgeInsets.zero,
  }) : _sliver = true;

  /// Box form: a shrink-wrapped, non-scrolling grid.
  const NooPhotoGrid.box({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.columns = 3,
    this.gap = 2,
    this.padding = EdgeInsets.zero,
  }) : _sliver = false;

  /// Mobile/desktop column + gap presets from the spec.
  static const mobileColumns = 3;
  static const mobileGap = 2.0;
  static const desktopColumns = 8;
  static const desktopGap = 4.0;

  SliverGridDelegate get _delegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
      );

  @override
  Widget build(BuildContext context) {
    if (_sliver) {
      return SliverPadding(
        padding: padding,
        sliver: SliverGrid(
          gridDelegate: _delegate,
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: _delegate,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
