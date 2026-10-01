import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Tinted info callout (info-soft fill, info icon) for a short notice that
/// must be noticed immediately, unlike a muted footer/subtitle line.
class NooInfoNote extends StatelessWidget {
  final String message;

  const NooInfoNote({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.infoSoft,
        borderRadius: BorderRadius.circular(NooRadii.input),
        border: Border.all(color: colors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 18, color: colors.info),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: NooText.body.copyWith(color: colors.fg1, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
