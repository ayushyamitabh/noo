import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// Pill search input with a leading icon (Noo Design System project,
/// `components/core/SearchField.jsx`).
class NooSearchField extends StatelessWidget {
  final String placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  /// true = iOS inline field (radius 12, 38px, 16px text, below the large
  /// title); false = the generic 36px pill used everywhere else (also the
  /// Android "expands from a top-bar icon" search field once expanded).
  final bool ios;
  /// True when placed directly on a `surface` background (uses surface-2
  /// fill instead of surface, so it doesn't disappear against it).
  final bool onSurface;
  final double? width;
  /// A trailing widget (e.g. a clear button), shown after the input.
  final Widget? trailing;

  const NooSearchField({
    super.key,
    this.placeholder = 'Search',
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.ios = false,
    this.onSurface = false,
    this.width,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      width: width,
      height: ios ? 38 : 36,
      padding: EdgeInsets.symmetric(horizontal: ios ? 10 : 14),
      decoration: BoxDecoration(
        color: onSurface ? colors.surface2 : colors.surface,
        borderRadius: BorderRadius.circular(ios ? 12 : NooRadii.pill),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: ios ? 18 : 16, color: colors.fg3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              autofocus: autofocus,
              style: NooText.body.copyWith(
                fontSize: ios ? 16 : 14,
                height: 1,
                color: colors.fg1,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: NooText.body.copyWith(
                  fontSize: ios ? 16 : 14,
                  height: 1,
                  color: colors.fg3,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
