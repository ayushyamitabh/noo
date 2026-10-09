import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// UIKit recognizes secondary clicks that Flutter's iOS-on-Mac embedder drops.
class MacSecondaryClick {
  const MacSecondaryClick._();
  static const channel = MethodChannel('dev.ayushya.noo/secondary_click');
  static int _pointer = 1000000;

  static void initialize() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'secondaryClick') return;
      final args = call.arguments as Map;
      dispatch(
        Offset((args['x'] as num).toDouble(), (args['y'] as num).toDouble()),
      );
    });
  }

  /// Positions from UIKit are already in Flutter logical pixels.
  @visibleForTesting
  static void dispatch(Offset position) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final pointer = _pointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(
      PointerAddedEvent(
        position: position,
        kind: PointerDeviceKind.mouse,
        device: -100,
        viewId: view.viewId,
      ),
    );
    binding.handlePointerEvent(
      PointerDownEvent(
        position: position,
        kind: PointerDeviceKind.mouse,
        device: -100,
        pointer: pointer,
        buttons: kSecondaryMouseButton,
        viewId: view.viewId,
      ),
    );
    binding.handlePointerEvent(
      PointerUpEvent(
        position: position,
        kind: PointerDeviceKind.mouse,
        device: -100,
        pointer: pointer,
        viewId: view.viewId,
      ),
    );
    binding.handlePointerEvent(
      PointerRemovedEvent(
        position: position,
        kind: PointerDeviceKind.mouse,
        device: -100,
        viewId: view.viewId,
      ),
    );
  }
}
