import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Tracks pointer input without assuming that a large screen has a mouse.
class NooPointerSelection extends StatefulWidget {
  final Widget child;
  const NooPointerSelection({super.key, required this.child});

  static bool available(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PointerScope>()?.available ??
      false;

  @override
  State<NooPointerSelection> createState() => _NooPointerSelectionState();
}

class _NooPointerSelectionState extends State<NooPointerSelection> {
  bool trackpad = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.mouseTracker.addListener(_refresh);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
  }

  void _pointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.trackpad && !trackpad) {
      trackpad = true;
      _refresh();
    } else if (event.kind == PointerDeviceKind.touch && trackpad) {
      trackpad = false;
      _refresh();
    }
  }

  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.mouseTracker.removeListener(_refresh);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PointerScope(
    available:
        trackpad || WidgetsBinding.instance.mouseTracker.mouseIsConnected,
    child: widget.child,
  );
}

class _PointerScope extends InheritedWidget {
  final bool available;
  const _PointerScope({required this.available, required super.child});
  @override
  bool updateShouldNotify(_PointerScope oldWidget) =>
      available != oldWidget.available;
}

class NooPointerCheckbox extends StatelessWidget {
  final bool selected;
  final VoidCallback? onToggle;
  const NooPointerCheckbox({super.key, required this.selected, this.onToggle});
  @override
  Widget build(BuildContext context) =>
      onToggle == null || !NooPointerSelection.available(context)
      ? const SizedBox.shrink()
      : SizedBox(
          width: 40,
          height: 40,
          child: Checkbox(
            value: selected,
            onChanged: (_) => onToggle!(),
            semanticLabel: selected ? 'Deselect item' : 'Select item',
          ),
        );
}
