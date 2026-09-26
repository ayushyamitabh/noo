import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';

/// On/off switch; accent track on, surface-3 track off, white knob -
/// identical on every platform, never a native iOS/Android switch (Noo
/// Design System project, `components/core/Toggle.jsx`).
class NooToggle extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool>? onChanged;
  final bool desktop;

  const NooToggle({
    super.key,
    required this.checked,
    this.onChanged,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final w = desktop ? 44.0 : 48.0;
    final h = desktop ? 26.0 : 28.0;
    final knob = h - 6;

    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      child: AnimatedContainer(
        duration: NooMotion.fast,
        curve: NooMotion.ease,
        width: w,
        height: h,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: checked ? colors.accent : colors.surface3,
          borderRadius: BorderRadius.circular(NooRadii.pill),
        ),
        child: AnimatedAlign(
          duration: NooMotion.fast,
          curve: NooMotion.ease,
          alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: knob,
            height: knob,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
