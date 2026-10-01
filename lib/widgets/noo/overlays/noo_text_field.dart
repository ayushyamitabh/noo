import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// Radius-14 inset input (share "Name, email or group", link URL). Unlike
/// the pill `NooSearchField`, this is the inset-panel shape from the radius
/// scale. [trailing] hosts an inline 40px button (`NooButtonSize.field`),
/// e.g. "Copy link" - the field then tightens its right padding to 4 so the
/// button sits inset inside the rounded box. [mono] switches to the mono
/// style for URLs and local paths.
class NooTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? leadingIcon;
  final Widget? trailing;
  final bool mono;
  final bool readOnly;
  final bool autofocus;
  final TextInputType? keyboardType;
  /// True (default) on a `surface` background - uses surface-2 fill. Pass
  /// false when placed on `bg`, which uses surface instead.
  final bool onSurface;

  const NooTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.leadingIcon,
    this.trailing,
    this.mono = false,
    this.readOnly = false,
    this.autofocus = false,
    this.keyboardType,
    this.onSurface = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final base = mono
        ? NooText.mono.copyWith(fontSize: 13)
        : NooText.body.copyWith(fontSize: 15, height: 1.2);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: NooSpace.smd, right: trailing != null ? 4 : NooSpace.smd),
      decoration: BoxDecoration(
        color: onSurface ? colors.surface2 : colors.surface,
        borderRadius: BorderRadius.circular(NooRadii.input),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 18, color: colors.fg3),
            const SizedBox(width: NooSpace.xs),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              readOnly: readOnly,
              autofocus: autofocus,
              keyboardType: keyboardType,
              style: base.copyWith(color: colors.fg1),
              cursorColor: colors.accentText,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: NooSpace.smd),
                hintText: placeholder,
                hintStyle: base.copyWith(color: colors.fg3),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: NooSpace.xs), trailing!],
        ],
      ),
    );
  }
}
