import 'package:flutter/material.dart';
import '../../models/nextcloud_item.dart';
import 'details_sheet.dart';

/// A persistent (non-modal) draggable panel that rests as a small "peek"
/// of a file's details - just the header - so it's always partly visible
/// without blocking the content above it, and expands into the full
/// [DetailsSheet] (with its Info/Versions/Activity tabs) once dragged past
/// [_expandThreshold]. Meant to be placed directly in a `Stack`, not shown
/// via `showModalBottomSheet`/`showBottomSheet` - there's no scrim and
/// nothing behind it is blocked from receiving gestures.
class PeekDetailsSheet extends StatefulWidget {
  final NextcloudItem item;

  const PeekDetailsSheet({super.key, required this.item});

  @override
  State<PeekDetailsSheet> createState() => _PeekDetailsSheetState();
}

class _PeekDetailsSheetState extends State<PeekDetailsSheet> {
  static const _peekSize = 0.16;
  static const _maxSize = 0.9;
  static const _expandThreshold = 0.3;

  double _size = _peekSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expanded = _size > _expandThreshold;

    return DraggableScrollableSheet(
      initialChildSize: _peekSize,
      minChildSize: _peekSize,
      maxChildSize: _maxSize,
      snap: true,
      snapSizes: const [_peekSize, _maxSize],
      builder: (context, scrollController) {
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            if ((notification.extent - _size).abs() > 0.002) {
              setState(() => _size = notification.extent);
            }
            return false;
          },
          child: Container(
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
                Expanded(
                  child: expanded
                      ? DetailsSheet(item: widget.item)
                      // Peek state: just the header, but still wrapped in
                      // a scrollable using the sheet's own controller - a
                      // DraggableScrollableSheet only picks up drag-to-
                      // resize gestures from a Scrollable using that
                      // controller, even over otherwise-static content.
                      : SingleChildScrollView(
                          controller: scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: DetailsHeader(item: widget.item),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
