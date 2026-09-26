import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Sheet/dialog header: an optional leading tile, title, subtitle, close
/// circle (Noo Design System project,
/// `components/overlays/OverlayHeader.jsx`, mobile variant). [leading] is a
/// plain [Widget] rather than a file kind so this stays decoupled from the
/// file model - pass an `ItemThumbnail`/file-type tile for a file header.
class NooOverlayHeader extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  const NooOverlayHeader({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.sectionTitle.copyWith(fontSize: 19, color: colors.fg1),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: NooText.meta.copyWith(color: colors.fg3)),
              ],
            ],
          ),
        ),
        if (onClose != null)
          Semantics(
            button: true,
            label: 'Close',
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colors.surface2, shape: BoxShape.circle),
                child: Icon(LucideIcons.x, size: 18, color: colors.fg1),
              ),
            ),
          ),
      ],
    );
  }
}
