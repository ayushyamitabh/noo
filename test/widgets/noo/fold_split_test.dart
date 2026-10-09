import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/widgets/noo/nav/noo_sidebar.dart';
import 'package:noo/widgets/noo/noo_layout.dart';
import 'package:noo/widgets/noo/overlays/noo_dialog.dart';
import 'package:noo/widgets/noo/overlays/noo_sheet.dart';
import 'noo_test_utils.dart';
import 'package:noo/services/ios_hinge.dart';

/// Foldables: the tablet layout's sidebar ends on the crease (50/50 on a
/// book-style fold), and dialogs/sheets open on the right-hand screen.
void main() {
  setUpNooTests();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  const fold = DisplayFeature(
    bounds: Rect.fromLTWH(420, 0, 0, 800),
    type: DisplayFeatureType.fold,
    state: DisplayFeatureState.postureHalfOpened,
  );

  /// Runs [read] in a context with the given window.
  Future<T?> readWith<T>(
    WidgetTester tester,
    T Function(BuildContext) read, {
    Size size = const Size(840, 800),
    List<DisplayFeature> features = const [],
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    T? value;
    final probe = Builder(
      builder: (context) {
        value = read(context);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          displayFeatures: features,
          padding: padding,
        ),
        child: probe,
      ),
    );
    return value;
  }

  double? split(BuildContext context) => NooLayout.foldSplitWidth(context);

  testWidgets('Duo switches from tablet to split and back on posture updates', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    double? width;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(669, 951)),
        child: IosHingeLayout(
          child: Builder(
            builder: (context) {
              width = NooLayout.foldSplitWidth(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(width, isNull);
    IosHinge.partiallyOpen.value = true;
    await tester.pump();
    expect(width, 334.5);
    IosHinge.partiallyOpen.value = false;
    await tester.pump();
    expect(width, isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  const flatFold = DisplayFeature(
    bounds: Rect.fromLTWH(420, 0, 0, 800),
    type: DisplayFeatureType.fold,
    state: DisplayFeatureState.postureFlat,
  );

  testWidgets('Android flat and unknown folds use standard tablet layout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await readWith(tester, split, features: [flatFold]), isNull);
    expect(
      await readWith(tester, NooLayout.popupAnchor, features: [flatFold]),
      isNull,
    );
    const unknownFold = DisplayFeature(
      bounds: Rect.fromLTWH(420, 0, 0, 800),
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.unknown,
    );
    expect(await readWith(tester, split, features: [unknownFold]), isNull);
    expect(await readWith(tester, split, features: [fold]), 420);
    debugDefaultTargetPlatformOverride = null;
  });

  group('sidebar split', () {
    testWidgets('a vertical fold splits at the crease', (tester) async {
      expect(await readWith(tester, split, features: [fold]), 420);
    });

    testWidgets('the leading inset is taken off the split', (tester) async {
      expect(
        await readWith(
          tester,
          split,
          features: [fold],
          padding: const EdgeInsets.only(left: 20),
        ),
        400,
      );
    });

    testWidgets('a horizontal fold leaves the sidebar alone', (tester) async {
      const horizontal = DisplayFeature(
        bounds: Rect.fromLTWH(0, 400, 840, 0),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      );
      expect(await readWith(tester, split, features: [horizontal]), isNull);
    });

    testWidgets('no fold, or a phone-sized window: no split', (tester) async {
      expect(await readWith(tester, split), isNull);
      expect(
        await readWith(
          tester,
          split,
          size: const Size(400, 800),
          features: [fold],
        ),
        isNull,
      );
    });

    testWidgets('NooSidebar takes the split width', (tester) async {
      await pumpNoo(
        tester,
        const SizedBox(height: 600, child: NooSidebar(width: 420)),
        surfaceSize: const Size(1000, 700),
      );
      expect(tester.getSize(find.byType(NooSidebar)).width, 420);
    });
  });

  testWidgets(
    'iOS foldables use the tablet layout without a half-width sidebar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await readWith(tester, NooLayout.isDesktop, size: const Size(669, 951)),
        isTrue,
      );
      expect(await readWith(tester, split, features: [flatFold]), isNull);
      expect(
        await readWith(tester, NooLayout.popupAnchor, features: [flatFold]),
        isNull,
      );
      expect(
        await readWith(tester, NooLayout.isDesktop, size: const Size(466, 678)),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  group('popups', () {
    testWidgets('anchor top-right on a foldable, default elsewhere', (
      tester,
    ) async {
      expect(
        await readWith(tester, NooLayout.popupAnchor, features: [fold]),
        const Offset(840, 0),
      );
      expect(await readWith(tester, NooLayout.popupAnchor), isNull);
    });

    Future<void> pumpFoldable(WidgetTester tester, Widget home) async {
      await tester.binding.setSurfaceSize(const Size(840, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: nooTheme(Brightness.light),
          // Half-opened: the posture Flutter splits popups at for a
          // zero-width fold (as the fold emulator reports).
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              displayFeatures: const [
                DisplayFeature(
                  bounds: Rect.fromLTWH(420, 0, 0, 800),
                  type: DisplayFeatureType.fold,
                  state: DisplayFeatureState.postureHalfOpened,
                ),
              ],
            ),
            child: child!,
          ),
          home: home,
        ),
      );
    }

    testWidgets('a Noo sheet opens on the right-hand screen', (tester) async {
      await pumpFoldable(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showNooSheet<void>(context, children: const [Text('Sheet')]),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Sheet')).dx, greaterThan(420));
    });

    testWidgets('a Noo dialog opens on the right-hand screen', (tester) async {
      await pumpFoldable(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNooDialog<void>(
              context,
              title: 'Dialog',
              children: const [Text('Body')],
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Dialog')).dx, greaterThan(420));
    });
  });
}
