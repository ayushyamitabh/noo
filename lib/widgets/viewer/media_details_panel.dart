import 'package:flutter/material.dart';
import '../../models/nextcloud_item.dart';
import '../../theme/design_tokens.dart';
import '../details/details_sheet.dart';
import '../noo/overlays/noo_overlay_header.dart';

/// Builds the viewer's bottom bar with a drag [handle] on top and the
/// expandable [below] details region underneath its action row.
typedef MediaPanelBarBuilder =
    Widget Function(BuildContext context, Widget handle, Widget below);

/// The media viewer's bottom bar as a draggable panel: dragging it (or
/// swiping up on the media, via [MediaDetailsPanelState.expand]) grows the
/// panel upward so the action row rides on top of the file's details instead
/// of the details covering it in a separate modal sheet.
class MediaDetailsPanel extends StatefulWidget {
  final NextcloudItem item;
  final MediaPanelBarBuilder builder;

  const MediaDetailsPanel({
    super.key,
    required this.item,
    required this.builder,
  });

  @override
  State<MediaDetailsPanel> createState() => MediaDetailsPanelState();
}

class MediaDetailsPanelState extends State<MediaDetailsPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  double _maxHeight = 1;

  bool get isExpanded => _c.value > 0.5;

  void expand() => _c.animateTo(1, curve: Curves.easeOutCubic);
  void collapse() => _c.animateTo(0, curve: Curves.easeOutCubic);
  void toggle() => isExpanded ? collapse() : expand();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _c.value -= (d.primaryDelta ?? 0) / _maxHeight;
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -400) {
      expand();
    } else if (v > 400) {
      collapse();
    } else {
      toggleToNearest();
    }
  }

  void toggleToNearest() => _c.value > 0.5 ? expand() : collapse();

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    _maxHeight = MediaQuery.sizeOf(context).height * 0.55;

    final handle = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: colors.fg3.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );

    final below = AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.value == 0) return const SizedBox.shrink();
        return SizedBox(
          height: _c.value * _maxHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: _maxHeight,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NooSpace.lg,
                  NooSpace.md,
                  NooSpace.lg,
                  NooSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NooOverlayHeader(
                      leading: detailsFileTile(widget.item),
                      title: widget.item.name,
                      subtitle: detailsMetaLine(widget.item),
                      onClose: collapse,
                    ),
                    const SizedBox(height: NooSpace.lg),
                    DetailsBody(
                      key: ValueKey(widget.item.id),
                      item: widget.item,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: widget.builder(context, handle, below),
    );
  }
}
