import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

enum NooBadgeTone { success, danger, accent, warning, info }

/// Small status pill, e.g. "Connected" in settings (Noo Design System
/// project, `components/core/Badge.jsx`).
class NooBadge extends StatelessWidget {
  final NooBadgeTone tone;
  final Widget child;

  const NooBadge({super.key, this.tone = NooBadgeTone.success, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final (bg, fg) = switch (tone) {
      NooBadgeTone.success => (colors.successSoft, colors.success),
      NooBadgeTone.danger => (colors.dangerSoft, colors.danger),
      NooBadgeTone.accent => (colors.accentSoft, colors.accentText),
      NooBadgeTone.warning => (colors.warningSoft, colors.warning),
      NooBadgeTone.info => (colors.infoSoft, colors.info),
    };
    return Container(
      height: 24,
      // Centering the text vertically within the fixed 24px height needs
      // *some* alignment mechanism, but Container's own `alignment:` (with
      // a height but no width) would expand to fill all available
      // *bounded* width instead of shrink-wrapping (see NooFab's doc
      // comment) - a Row with mainAxisSize.min sidesteps that entirely:
      // it shrink-wraps horizontally regardless of incoming constraints,
      // while its default crossAxisAlignment.center still centers the
      // text within the Container's tight 24px height.
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(NooRadii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultTextStyle(
            style: NooText.label.copyWith(fontSize: 12, height: 1, color: fg),
            child: child,
          ),
        ],
      ),
    );
  }
}
