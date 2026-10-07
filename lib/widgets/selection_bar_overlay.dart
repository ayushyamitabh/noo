import 'package:flutter/material.dart';

/// Pins selection actions above the shell navigation. Scaffold supplies its
/// navigation footprint through MediaQuery padding when the body extends
/// behind navigation; otherwise the body already ends above it.
class SelectionBarOverlay extends StatelessWidget {
  static const clearance = 64.0;

  final Widget child;
  final Widget? bar;

  const SelectionBarOverlay({super.key, required this.child, this.bar});

  @override
  Widget build(BuildContext context) {
    if (bar == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          child: SizedBox(height: 56, child: bar),
        ),
      ],
    );
  }
}
