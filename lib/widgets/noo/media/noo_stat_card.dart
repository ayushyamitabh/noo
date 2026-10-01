import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import '../core/noo_progress_bar.dart';

/// Desktop stat card (`DESIGN_SYSTEM.md` sections 1.3/1.4): radius 18,
/// Stat text (Schibsted 600, 28 on desktop), a label below and an optional
/// 6px [NooProgressBar]. The mobile/Offline equivalent with an action
/// button is `NooSummaryCard`.
class NooStatCard extends StatelessWidget {
  final String stat;
  final String label;

  /// 0-1; renders a [NooProgressBar] under the label.
  final double? progress;

  /// Optional line under the progress bar, e.g. `"of 50 GB"`.
  final String? meta;

  final IconData? icon;

  /// Defaults to `surface`; pass `surface2` when the card sits on a
  /// `surface` pane.
  final Color? color;

  final VoidCallback? onTap;

  const NooStatCard({
    super.key,
    required this.stat,
    required this.label,
    this.progress,
    this.meta,
    this.icon,
    this.color,
    this.onTap,
  });

  /// Desktop Stat size (spec 1.3: 32 mobile / 28 desktop); [NooText.stat]
  /// only carries the mobile size.
  static const _desktopStatSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return Material(
      color: color ?? colors.surface,
      borderRadius: BorderRadius.circular(NooRadii.gridCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: colors.fg2),
                const SizedBox(height: NooSpace.sm),
              ],
              Text(
                stat,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.stat.copyWith(
                  fontSize: _desktopStatSize,
                  letterSpacing: -_desktopStatSize * 0.03,
                  color: colors.fg1,
                ),
              ),
              const SizedBox(height: NooSpace.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.meta.copyWith(color: colors.fg2),
              ),
              if (progress != null) ...[
                const SizedBox(height: NooSpace.smd),
                NooProgressBar(value: progress!),
              ],
              if (meta != null) ...[
                const SizedBox(height: NooSpace.xs),
                Text(
                  meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.meta.copyWith(fontSize: 12, color: colors.fg3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
