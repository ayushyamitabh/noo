import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/theme/design_tokens.dart';
import 'package:noo/widgets/noo/core/noo_avatar.dart';
import 'package:noo/widgets/noo/core/noo_button.dart';
import 'package:noo/widgets/noo/overlays/noo_dialog.dart';
import 'package:noo/widgets/noo/overlays/noo_overlay_header.dart';
import 'package:noo/widgets/noo/overlays/noo_share_parts.dart';
import 'package:noo/widgets/noo/overlays/noo_sheet.dart';
import 'package:noo/widgets/noo/overlays/noo_text_field.dart';

import 'noo_test_utils.dart';

/// A button that opens an overlay from a context below MaterialApp.
Widget _launcher(void Function(BuildContext) open) => Builder(
  builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open')),
);

Finder _dialogCard() => find.byWidgetPredicate(
  (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null,
);

void main() {
  setUpNooTests();

  group('NooOverlayHeader', () {
    testNooWidgets('title, subtitle, leading and close', (tester, theme, c) async {
      var closed = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 360,
          child: NooOverlayHeader(
            leading: const Icon(LucideIcons.fileText),
            title: 'Report.pdf',
            subtitle: '2 MB · Documents',
            onClose: () => closed++,
          ),
        ),
        theme: theme,
      );
      expect(find.text('Report.pdf'), findsOneWidget);
      expect(tester.widget<Text>(find.text('2 MB · Documents')).style!.color, c.fg3);
      expect(decorationOf(tester, find.byIcon(LucideIcons.x)).color, c.surface2);
      await tester.tap(find.byIcon(LucideIcons.x));
      expect(closed, 1);
    });

    testWidgets('no close button without onClose', (tester) async {
      await pumpNoo(tester, const SizedBox(width: 360, child: NooOverlayHeader(title: 'T')));
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });
  });

  group('showNooSheet', () {
    testNooWidgets('shows children on a surface sheet and dismisses', (tester, theme, c) async {
      await pumpNoo(
        tester,
        _launcher((ctx) => showNooSheet<void>(ctx, children: const [Text('Section A'), Text('Section B')])),
        theme: theme,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Section A'), findsOneWidget);
      expect(find.text('Section B'), findsOneWidget);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, c.surface);
      final gap = tester.getTopLeft(find.text('Section B')).dy -
          tester.getBottomLeft(find.text('Section A')).dy;
      expect(gap, 22);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Section A'), findsNothing);
    });
  });

  group('NooDialog', () {
    testNooWidgets('card is 540 wide, r24, single dialog shadow', (tester, theme, c) async {
      await pumpNoo(
        tester,
        NooDialog(title: 'Share "Report.pdf"', onClose: () {}, children: const [Text('body')]),
        theme: theme,
        surfaceSize: const Size(1200, 900),
      );
      final deco = decorationOf(tester, find.text('body'));
      expect(deco.color, c.surface);
      expect(deco.borderRadius, BorderRadius.circular(NooRadii.dialog));
      expect(deco.boxShadow, const [nooDialogShadow]);
      final card = _dialogCard();
      expect(tester.getSize(card).width, 540);
    });

    testWidgets('narrow screens shrink the card to fit with a 24px margin', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: nooTheme(Brightness.light),
          home: const NooDialog(title: 'T', children: [Text('body')]),
        ),
      );
      final card = _dialogCard();
      expect(tester.getSize(card).width, 400 - 48);
    });

    testNooWidgets('header close is a 32px surface-2 circle', (tester, theme, c) async {
      var closed = 0;
      await pumpNoo(
        tester,
        NooDialogHeader(
          leading: const Icon(LucideIcons.fileText),
          title: 'Share "Report.pdf"',
          subtitle: '2 MB · Documents',
          onClose: () => closed++,
        ),
        theme: theme,
      );
      expect(tester.getSize(find.byType(NooCloseButton)), const Size(32, 32));
      expect(decorationOf(tester, find.byIcon(LucideIcons.x)).color, c.surface2);
      await tester.tap(find.byType(NooCloseButton));
      expect(closed, 1);
    });

    testNooWidgets('showNooDialog uses the scrim and closes via the button', (tester, theme, c) async {
      Future<String?>? result;
      await pumpNoo(
        tester,
        _launcher(
          (ctx) => result = showNooDialog<String>(
            ctx,
            title: 'Share "Report.pdf"',
            children: const [Text('dialog body')],
          ),
        ),
        theme: theme,
        surfaceSize: const Size(1200, 900),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsOneWidget);
      final barrier = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last;
      expect(barrier.color, c.scrim);

      await tester.tap(find.byType(NooCloseButton));
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsNothing);
      expect(await result, isNull);
    });

    testWidgets('barrier tap dismisses unless disabled', (tester) async {
      await pumpNoo(
        tester,
        _launcher(
          (ctx) => showNooDialog<void>(
            ctx,
            title: 'T',
            barrierDismissible: false,
            children: const [Text('sticky')],
          ),
        ),
        surfaceSize: const Size(1200, 900),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('sticky'), findsOneWidget);
    });

    testWidgets('long content scrolls instead of overflowing', (tester) async {
      await pumpNoo(
        tester,
        _launcher(
          (ctx) => showNooDialog<void>(
            ctx,
            title: 'T',
            children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))],
          ),
        ),
        surfaceSize: const Size(1200, 600),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('NooTextField', () {
    testNooWidgets('surface-2, r14, fg-3 placeholder, typing', (tester, theme, c) async {
      String? typed;
      await pumpNoo(
        tester,
        SizedBox(
          width: 400,
          child: NooTextField(placeholder: 'Name, email or group', onChanged: (v) => typed = v),
        ),
        theme: theme,
      );
      final deco = decorationOf(tester, find.byType(TextField));
      expect(deco.color, c.surface2);
      expect(deco.borderRadius, BorderRadius.circular(NooRadii.input));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintStyle!.color, c.fg3);
      expect(field.style!.color, c.fg1);
      await tester.enterText(find.byType(TextField), 'ali');
      expect(typed, 'ali');
    });

    testNooWidgets('mono URL field with inline Copy link button', (tester, theme, c) async {
      var copied = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 480,
          child: NooTextField(
            controller: TextEditingController(text: 'https://cloud.example/s/abc'),
            mono: true,
            readOnly: true,
            onSurface: false,
            trailing: NooButton(
              size: NooButtonSize.field,
              onTap: () => copied++,
              child: const Text('Copy link'),
            ),
          ),
        ),
        theme: theme,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.fontFamily, NooText.mono.fontFamily);
      expect(field.readOnly, isTrue);
      expect(decorationOf(tester, find.byType(TextField)).color, c.surface);
      expect(tester.getSize(find.byType(NooButton)).height, NooSizes.buttonField);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(copied, 1);
    });
  });

  group('Share parts', () {
    testNooWidgets('NooShareSection title, trailing and caption', (tester, theme, c) async {
      await pumpNoo(
        tester,
        const SizedBox(
          width: 400,
          child: NooShareSection(
            title: 'Send file directly',
            trailing: Icon(LucideIcons.link),
            caption: "Link settings don't apply",
            child: Text('content'),
          ),
        ),
        theme: theme,
      );
      expect(tester.widget<Text>(find.text('Send file directly')).style!.color, c.fg1);
      expect(tester.widget<Text>(find.text("Link settings don't apply")).style!.color, c.fg3);
      expect(find.byIcon(LucideIcons.link), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
    });

    testNooWidgets('owner row is static, others get a tappable pill', (tester, theme, c) async {
      var taps = 0;
      await pumpNoo(
        tester,
        SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NooPersonAccessRow(
                avatar: NooAvatar(initials: 'AY', current: true),
                name: 'Ayushya (you)',
                subtitle: 'ayushya@example.com',
                owner: true,
              ),
              NooPersonAccessRow(
                avatar: const NooAvatar(initials: 'JD'),
                name: 'Jane Doe',
                onPermissionTap: () => taps++,
              ),
            ],
          ),
        ),
        theme: theme,
      );
      expect(find.text('Owner'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Owner')).style!.color, c.fg3);
      expect(find.byType(NooPermissionPill), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
      expect(decorationOf(tester, find.text('Can edit')).color, c.surface2);

      await tester.tap(find.text('Can edit'));
      expect(taps, 1);
    });

    testWidgets('same parts lay out inside the sheet and the dialog', (tester) async {
      List<Widget> parts() => [
        NooShareSection(
          title: 'Share with people',
          child: const NooTextField(placeholder: 'Name, email or group'),
        ),
        const NooPersonAccessRow(avatar: NooAvatar(initials: 'JD'), name: 'Jane', permission: 'Can view'),
      ];
      await pumpNoo(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _launcher((ctx) => showNooSheet<void>(ctx, children: parts())),
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showNooDialog<void>(ctx, title: 'Share', children: parts()),
                child: const Text('dialog'),
              ),
            ),
          ],
        ),
        surfaceSize: const Size(1200, 900),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Can view'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Can view'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
