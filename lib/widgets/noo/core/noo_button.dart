import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

enum NooButtonVariant {
  primary,
  tonal,
  secondary,
  danger,
  outline,
  text,
  textDanger,
}

enum NooButtonSize { cta, card, field, toolbar, compact, xs }

class _SizeSpec {
  final double height;
  final double px;
  final double font;
  final double icon;
  final double gap;
  const _SizeSpec(this.height, this.px, this.font, this.icon, this.gap);
}

const _sizes = {
  NooButtonSize.cta: _SizeSpec(52, 20, 16, 20, 10),
  NooButtonSize.card: _SizeSpec(44, 18, 15, 16, 8),
  NooButtonSize.field: _SizeSpec(40, 16, 14, 16, 6),
  NooButtonSize.toolbar: _SizeSpec(36, 16, 14, 16, 8),
  NooButtonSize.compact: _SizeSpec(32, 14, 13, 14, 6),
  NooButtonSize.xs: _SizeSpec(28, 12, 12, 14, 6),
};

/// The pill button for every action in the design system
/// (Noo Design System project, `components/core/Button.jsx`). Pick
/// [NooButtonVariant] by emphasis and [NooButtonSize] by context - never
/// build a bespoke `ElevatedButton`/`FilledButton` for app chrome; extend
/// this instead.
class NooButton extends StatefulWidget {
  final NooButtonVariant variant;
  final NooButtonSize size;
  final IconData? icon;
  final Widget? child;
  final bool fullWidth;
  final bool disabled;
  final VoidCallback? onTap;

  /// A round, icon-only button (no label) - [icon] centred in a circle as
  /// wide as the size's height, instead of the pill's side padding. Callers
  /// are responsible for a tooltip/semantic label, since there's no text.
  final bool iconOnly;

  /// Continuous icon-only to labelled expansion for animated shell actions.
  final double? expansion;

  const NooButton({
    super.key,
    this.variant = NooButtonVariant.primary,
    this.size = NooButtonSize.toolbar,
    this.icon,
    this.child,
    this.fullWidth = false,
    this.disabled = false,
    this.onTap,
    this.iconOnly = false,
    this.expansion,
  });

  @override
  State<NooButton> createState() => _NooButtonState();
}

class _NooButtonState extends State<NooButton> {
  bool _down = false;

  (Color, Color, BoxBorder?) _colors(NooColors colors) {
    switch (widget.variant) {
      case NooButtonVariant.primary:
        return (colors.accent, Colors.white, null);
      case NooButtonVariant.tonal:
        return (colors.accentSoft, colors.accentText, null);
      case NooButtonVariant.secondary:
        return (colors.surface2, colors.fg1, null);
      case NooButtonVariant.danger:
        return (colors.dangerSoft, colors.danger, null);
      case NooButtonVariant.outline:
        return (
          Colors.transparent,
          colors.fg1,
          Border.all(color: colors.surface3, width: 1.5),
        );
      case NooButtonVariant.text:
        return (Colors.transparent, colors.accentText, null);
      case NooButtonVariant.textDanger:
        return (Colors.transparent, colors.danger, null);
    }
  }

  bool get _isTextVariant =>
      widget.variant == NooButtonVariant.text ||
      widget.variant == NooButtonVariant.textDanger;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final s = _sizes[widget.size]!;
    final (bg, fg, border) = _colors(colors);
    final hasLeadingIcon =
        widget.icon != null && widget.child != null && !_isTextVariant;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) Icon(widget.icon, size: s.icon, color: fg),
        if (widget.icon != null && widget.child != null)
          SizedBox(width: s.gap * (widget.expansion ?? 1)),
        if (widget.child != null && widget.expansion != 0)
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: widget.expansion ?? 1,
              heightFactor: 1,
              child: Opacity(
                opacity: widget.expansion ?? 1,
                child: DefaultTextStyle(
                  style: NooText.buttonSm.copyWith(fontSize: s.font, color: fg),
                  child: widget.child!,
                ),
              ),
            ),
          ),
      ],
    );

    return Opacity(
      opacity: widget.disabled ? 0.45 : 1,
      child: GestureDetector(
        onTapDown: widget.disabled ? null : (_) => setState(() => _down = true),
        onTapUp: widget.disabled ? null : (_) => setState(() => _down = false),
        onTapCancel: widget.disabled
            ? null
            : () => setState(() => _down = false),
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedScale(
          scale: _down && !widget.disabled ? NooMotion.pressScale : 1,
          duration: NooMotion.fast,
          curve: NooMotion.ease,
          child: Container(
            height: s.height,
            width: widget.iconOnly
                ? s.height
                : (widget.fullWidth ? double.infinity : null),
            padding: widget.expansion != null
                ? EdgeInsets.only(
                    left:
                        (s.height - s.icon) / 2 +
                        (s.px - 4 - (s.height - s.icon) / 2) *
                            widget.expansion!,
                    right:
                        (s.height - s.icon) / 2 +
                        (s.px - (s.height - s.icon) / 2) * widget.expansion!,
                  )
                : _isTextVariant || widget.iconOnly
                ? EdgeInsets.zero
                : EdgeInsets.only(
                    left: hasLeadingIcon ? s.px - 4 : s.px,
                    right: s.px,
                  ),
            // Only align when fullWidth actually expands this Container -
            // otherwise (no width, alignment set) Container wraps the child
            // in an Align that fills all available *bounded* space instead
            // of shrink-wrapping to it, which is what stretched this button
            // edge-to-edge instead of sizing to its content (see NooFab's
            // doc comment for the same bug).
            alignment: widget.fullWidth || widget.iconOnly
                ? Alignment.center
                : null,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(NooRadii.pill),
              border: border,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
