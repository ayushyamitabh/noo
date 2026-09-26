import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// Mobile bottom sheet on a scrim: radius-28 top, grabber, 22px gap between
/// sections (Noo Design System project, `components/overlays/Sheet.jsx`).
/// `showModalBottomSheet` already supplies the scrim/backdrop-dismiss
/// machinery, so this only standardizes the shape/padding - use it instead
/// of a bare `showModalBottomSheet` for any new sheet. Scroll-controlled so a
/// tall sheet (e.g. share) can grow past half the screen; content scrolls
/// once it hits the top.
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(NooRadii.sheetTop)),
    ),
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
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
              for (final child in children) ...[
                const SizedBox(height: 22),
                child,
              ],
            ],
          ),
        ),
      );
    },
  );
}
