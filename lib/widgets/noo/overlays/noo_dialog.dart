import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';
import '../noo_layout.dart';

/// Desktop counterpart of `showNooSheet`: a 540px, radius-24 card on the
/// scrim, carrying the design system's one allowed shadow
/// ([nooDialogShadow]). `showGeneralDialog` is used instead of
/// `showDialog` so the barrier takes the `scrim` token and the transition
/// follows [NooMotion] (fade + 0.98 scale, no bounce) rather than
/// Material's defaults.
Future<T?> showNooDialog<T>(
  BuildContext context, {
  Widget? leading,
  required String title,
  String? subtitle,
  required List<Widget> children,
  bool barrierDismissible = true,
}) {
  final colors = context.nooColors;
  return showGeneralDialog<T>(
    context: context,
    anchorPoint: NooLayout.popupAnchor(context),
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: colors.scrim,
    transitionDuration: NooMotion.base,
    pageBuilder: (dialogContext, _, _) => NooDialog(
      leading: leading,
      title: title,
      subtitle: subtitle,
      onClose: () => Navigator.of(dialogContext).pop(),
      children: children,
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: NooMotion.ease);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: NooMotion.pressScale,
            end: 1,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The dialog card itself, centered in whatever space it's given. Exposed
/// separately from [showNooDialog] so it can be embedded/tested without a
/// route. Sections are spaced 22px apart to match `showNooSheet`, so the
/// same share-sheet parts lay out identically in both.
class NooDialog extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final List<Widget> children;
  final double width;

  const NooDialog({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.onClose,
    required this.children,
    this.width = 540,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    // Padding (not MediaQuery maths) keeps a 24px margin on every side, so
    // the card shrinks to fit narrow windows and short content-heavy
    // dialogs scroll rather than overflow.
    return Padding(
      padding: const EdgeInsets.all(NooSpace.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(NooRadii.dialog),
              boxShadow: const [nooDialogShadow],
            ),
            // Material (not just a DecoratedBox) so TextFields/InkWells inside
            // the dialog have an ancestor to paint on.
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(NooSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NooDialogHeader(
                      leading: leading,
                      title: title,
                      subtitle: subtitle,
                      onClose: onClose,
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final child in children) ...[
                              const SizedBox(height: 22),
                              child,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop dialog header: leading slot (a 44px file tile for Share),
/// title, optional meta subtitle, and a 32px surface-2 close circle.
/// `NooOverlayHeader` is the mobile sheet variant (36px close).
class NooDialogHeader extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  const NooDialogHeader({
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
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: NooSpace.sm)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.sectionTitle.copyWith(
                  fontSize: 19,
                  color: colors.fg1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.meta.copyWith(color: colors.fg3),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: NooSpace.sm),
          NooCloseButton(onTap: onClose!),
        ],
      ],
    );
  }
}

/// 32px surface-2 circle with an `x` - the dialog close control.
class NooCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const NooCloseButton({super.key, required this.onTap, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface2,
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.x, size: 16, color: colors.fg1),
        ),
      ),
    );
  }
}
