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

/// Renders [children] once, unconstrained, to measure their natural height
/// against the sheet's available height. Content that fits within
/// [_kNooSheetPeekFraction] just stays as that first (plain, content-sized)
/// render - the common case for a short menu/option list. Content taller
/// than that switches to a [DraggableScrollableSheet] opened at the peek
/// fraction instead, so it never jumps straight to (near) full height with
/// no room left to adjust. The one extra layout pass for tall content
/// happens within the sheet's own entrance animation, so it isn't visible
/// as a jump.
class _NooSheetBody extends StatefulWidget {
  final List<Widget> children;

  const _NooSheetBody({required this.children});

  @override
  State<_NooSheetBody> createState() => _NooSheetBodyState();
}

class _NooSheetBodyState extends State<_NooSheetBody> {
  final _contentKey = GlobalKey();
  bool _measured = false;
  bool _needsPeek = false;

  void _measureAfterFrame(double availableHeight) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _measured) return;
      final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      final contentHeight = box?.size.height ?? 0;
      setState(() {
        _measured = true;
        _needsPeek = contentHeight > availableHeight * _kNooSheetPeekFraction;
      });
    });
  }

  Widget _buildContent(ScrollController? scrollController) {
    final colors = context.nooColors;
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        key: _measured ? null : _contentKey,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!_measured) {
            _measureAfterFrame(constraints.maxHeight);
            return _buildContent(null);
          }
          if (!_needsPeek) {
            return _buildContent(null);
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
                child: _buildContent(scrollController),
              );
            },
          );
        },
      ),
    );
  }
}
