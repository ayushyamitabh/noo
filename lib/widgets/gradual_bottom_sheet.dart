import 'package:flutter/material.dart';
import 'noo/noo_layout.dart';

typedef GradualSheetBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

/// Shows a bottom sheet that can be dragged open/closed gradually (and
/// snaps to a few comfortable stops on release) instead of the default
/// modal bottom sheet's binary fully-open/fully-dismissed behavior.
/// [builder] gets a [ScrollController] it can hand to its own scrollable
/// content so dragging that content also resizes the sheet; content that
/// manages its own scrolling (e.g. a TabBarView of independent lists) can
/// just ignore it.
Future<T?> showGradualBottomSheet<T>(
  BuildContext context, {
  required GradualSheetBuilder builder,
  double initialSize = 0.6,
  double minSize = 0.3,
  double maxSize = 0.95,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    anchorPoint: NooLayout.popupAnchor(context),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: minSize,
        maxChildSize: maxSize,
        snap: true,
        snapSizes: [minSize, initialSize, maxSize],
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(child: builder(context, scrollController)),
              ],
            ),
          );
        },
      );
    },
  );
}
