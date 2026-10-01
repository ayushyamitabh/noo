import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/nextcloud_item.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_button.dart';

/// Fallback for [FileViewerScreen]'s static preview path when the file type
/// has no inline preview at all (not an image/video/pdf/text file) - just
/// name, a generic file icon, and the "open with"/"details" escape hatches.
class MediaUnsupportedPreview extends StatelessWidget {
  final NextcloudItem item;
  final bool isBusy;
  final VoidCallback onOpenExternally;
  final VoidCallback onOpenDetails;

  const MediaUnsupportedPreview({
    super.key,
    required this.item,
    required this.isBusy,
    required this.onOpenExternally,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.file, color: colors.fg3, size: 72),
            const SizedBox(height: 16),
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: NooText.cardTitle.copyWith(
                fontSize: 16,
                color: colors.fg1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No inline preview for this file type.',
              style: NooText.meta.copyWith(color: colors.fg3),
            ),
            const SizedBox(height: 28),
            NooButton(
              size: NooButtonSize.card,
              icon: LucideIcons.externalLink,
              disabled: isBusy,
              onTap: onOpenExternally,
              child: const Text('Open with...'),
            ),
            const SizedBox(height: 12),
            NooButton(
              variant: NooButtonVariant.outline,
              size: NooButtonSize.card,
              icon: LucideIcons.info,
              onTap: onOpenDetails,
              child: const Text('Details'),
            ),
          ],
        ),
      ),
    );
  }
}
