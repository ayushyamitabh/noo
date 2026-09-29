import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import '../core/noo_progress_bar.dart';

enum NooSummaryCardTone { normal, danger, accent }

/// Stat card with optional progress, meta and action (Offline summary,
/// desktop stats) - Noo Design System project,
/// `components/lists/SummaryCard.jsx`, mobile variant.
class NooSummaryCard extends StatelessWidget {
  final String stat;
  final String? caption;

  /// 0-1; renders a [NooProgressBar].
  final double? progress;
  final String? meta;
  final Widget? action;
  final NooSummaryCardTone tone;

  const NooSummaryCard({
    super.key,
    required this.stat,
    this.caption,
    this.progress,
    this.meta,
    this.action,
    this.tone = NooSummaryCardTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final bg = tone == NooSummaryCardTone.danger
        ? colors.dangerSoft
        : colors.surface;
    final statColor = switch (tone) {
      NooSummaryCardTone.danger => colors.danger,
      NooSummaryCardTone.accent => colors.accentText,
      NooSummaryCardTone.normal => colors.fg1,
    };
    final capColor = tone == NooSummaryCardTone.danger
        ? colors.danger
        : colors.fg2;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NooRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat, style: NooText.stat.copyWith(color: statColor)),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              style: NooText.body.copyWith(
                fontSize: 14,
                height: 1.2,
                color: capColor,
              ),
            ),
          ],
          // Its own row below the description, not squeezed beside the
          // stat/caption - there wasn't room to grow the action (e.g. a
          // labelled "Sync now" button) without it colliding with a long
          // caption.
          if (action != null) ...[const SizedBox(height: 14), action!],
          if (progress != null) ...[
            const SizedBox(height: 14),
            NooProgressBar(value: progress!),
          ],
          if (meta != null) ...[
            const SizedBox(height: 14),
            Text(meta!, style: NooText.meta.copyWith(color: colors.fg3)),
          ],
        ],
      ),
    );
  }
}
