import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// UIKit posture updates distinguish a bent Duo from its flat tablet window.
class IosHinge {
  static const _channel = MethodChannel('dev.ayushya.noo/hinge');
  static final partiallyOpen = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'postureChanged') {
        partiallyOpen.value = call.arguments == true;
      }
    });
    try {
      partiallyOpen.value =
          await _channel.invokeMethod<bool>('isPartiallyOpen') ?? false;
    } on MissingPluginException {
      // Older iOS versions have no hinge interaction.
    }
  }
}

class IosHingeLayout extends StatelessWidget {
  const IosHingeLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: IosHinge.partiallyOpen,
    builder: (context, bent, child) {
      final media = MediaQuery.of(context);
      if (!bent || media.size.shortestSide < 600) return child!;
      return MediaQuery(
        data: media.copyWith(
          displayFeatures: [
            ...media.displayFeatures,
            DisplayFeature(
              bounds: Rect.fromLTWH(
                media.size.width / 2,
                0,
                0,
                media.size.height,
              ),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
        child: child!,
      );
    },
    child: child,
  );
}
