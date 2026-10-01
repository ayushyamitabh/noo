import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// Fraction of the available height a sheet can reach before it switches
/// from sizing to its content to a draggable peek (see [_NooSheetBody]).
const double _kNooSheetPeekFraction = 0.6;
const double _kNooSheetMinFraction = 0.3;
const double _kNooSheetMaxFraction = 0.95;

/// Mobile bottom sheet on a scrim: radius-28 top, grabber, 22px gap between
/// sections (Noo Design System project, `components/overlays/Sheet.jsx`).
/// `showModalBottomSheet` already supplies the scrim/backdrop-dismiss
/// machinery, so this only standardizes the shape/padding - use it instead
/// of a bare `showModalBottomSheet` for any new sheet. Sizes to its content
/// like a plain scroll view for anything that fits comfortably on screen
/// (most sheets: a menu, a handful of settings rows); content long enough to
/// need scrolling (Details' Versions/Activity tabs with many rows, a long
/// accounts list, ...) instead opens at a native-style peek height the user
/// can drag up to reveal more of, rather than snapping straight to nearly
/// the full screen with nothing left to adjust - see [_NooSheetBody].
Future<T?> showNooSheet<T>(
  BuildContext context, {
  required List<Widget> children,
}) {
  final colors = context.nooColors;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(NooRadii.sheetTop),
      ),
    ),
    builder: (context) => _NooSheetBody(children: children),
  );
}

/// Caps content at [_kNooSheetPeekFraction] of the available height from the
/// very first frame - never a one-shot "measure, then decide" pass, since
/// some sheets (Details' Versions/Activity tabs) fetch their content
/// asynchronously and only reach their real (long) size well after that
/// first frame, which a one-shot measurement would miss entirely. Content
/// that never needs more than that cap just sizes to itself as a plain
/// scroll view, at whatever height that is - the common case for a short
/// menu/option list, and visually identical to before. [_needsPeek] flips
/// true - upgrading to a draggable [DraggableScrollableSheet], opened at the
/// exact same peek height so nothing visibly jumps - the moment a
/// [ScrollMetricsNotification] reports the content actually overflowing
/// that cap, however and whenever that happens (immediately for a long
/// static list, or later, once async content finishes loading and grows
/// past it).
class _NooSheetBody extends StatefulWidget {
  final List<Widget> children;

  const _NooSheetBody({required this.children});

  @override
  State<_NooSheetBody> createState() => _NooSheetBodyState();
}

class _NooSheetBodyState extends State<_NooSheetBody> {
  bool _needsPeek = false;

  void _handleOverflow(ScrollMetrics metrics) {
    if (_needsPeek || metrics.maxScrollExtent <= 0) return;
    // `ScrollMetricsNotification` is dispatched mid-layout; deferring avoids
    // a "setState during build" error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_needsPeek) setState(() => _needsPeek = true);
    });
  }

  Widget _buildScrollable(ScrollController? scrollController) {
    final colors = context.nooColors;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _handleOverflow(notification.metrics);
        return false;
      },
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: colors.surface3,
                borderRadius: BorderRadius.circular(NooRadii.pill),
              ),
            ),
            for (final child in widget.children) ...[
              const SizedBox(height: 22),
              child,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!_needsPeek) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * _kNooSheetPeekFraction,
              ),
              child: _buildScrollable(null),
            );
          }
          return DraggableScrollableSheet(
            initialChildSize: _kNooSheetPeekFraction,
            minChildSize: _kNooSheetMinFraction,
            maxChildSize: _kNooSheetMaxFraction,
            expand: false,
            builder: (context, scrollController) {
              // Plain `DraggableScrollableSheet` doesn't dismiss the modal
              // route on its own when dragged down to its floor - it just
              // stops resizing there - so pop explicitly once it's been
              // dragged (near) all the way down, matching a native
              // peek sheet's swipe-to-dismiss.
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  if (notification.extent <= notification.minExtent + 0.01) {
                    Navigator.of(context).maybePop();
                  }
                  return false;
                },
                child: _buildScrollable(scrollController),
              );
            },
          );
        },
      ),
    );
  }
}
