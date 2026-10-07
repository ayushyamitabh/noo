import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/models/nextcloud_item.dart';
import 'package:noo/providers/item_operations.dart';
import 'package:noo/providers/session_controller.dart';
import 'package:noo/services/nextcloud_service.dart';
import 'package:noo/views/file_viewer_screen.dart';
import 'package:noo/widgets/noo/nav/noo_top_bar.dart';
import 'package:noo/widgets/viewer/media_action_bar.dart';
import 'package:provider/provider.dart';

import '../widgets/noo/noo_test_utils.dart';

class _Service extends NextcloudService {
  _Service() : super(serverUrl: '', username: '', password: '');

  final loaded = Completer<List<int>>();
  Completer<bool>? saving;
  String? written;

  @override
  Future<List<int>> fetchBytes(String itemPath) => loaded.future;

  @override
  Future<bool> putBytes(String itemPath, List<int> bytes) {
    written = utf8.decode(bytes);
    saving = Completer<bool>();
    return saving!.future;
  }
}

// These stand-ins avoid starting session restoration and platform channels.
class _Session extends ChangeNotifier implements SessionController {
  _Session(this.service);

  @override
  final NextcloudService service;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Operations implements ItemOperations {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _button(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is NooTopBarButton && widget.tooltip == tooltip,
);

void main() {
  setUpNooTests();

  Future<_Service> mount(
    WidgetTester tester,
    Size size, {
    String name = 'notes.md',
    bool offline = false,
  }) async {
    final service = _Service();
    final session = _Session(service);
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionController>.value(value: session),
          Provider<ItemOperations>.value(value: _Operations()),
        ],
        child: MaterialApp(
          theme: nooTheme(Brightness.light),
          home: FileViewerScreen(
            item: NextcloudItem(
              id: '1',
              name: name,
              path: '/$name',
              type: NextcloudItemType.file,
              size: 12,
              lastModified: DateTime(2026),
            ),
            localPathResolver: offline ? (_) async => null : null,
          ),
        ),
      ),
    );
    return service;
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('text actions use the top bar at width $width', (tester) async {
      final service = await mount(tester, Size(width, 800));
      expect(_button('Edit'), findsNothing);
      expect(_button('Save'), findsNothing);
      service.loaded.complete(utf8.encode('# Original'));
      await tester.pumpAndSettle();

      void inHeader(String label) {
        final row = find
            .ancestor(of: _button('Back'), matching: find.byType(Row))
            .first;
        expect(
          find.descendant(of: row, matching: _button(label)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(MediaActionBar),
            matching: _button(label),
          ),
          findsNothing,
        );
      }

      inHeader('Edit');
      expect(find.byType(Markdown), findsOneWidget);
      await tester.tap(_button('Edit'));
      await tester.pumpAndSettle();
      inHeader('Preview');
      await tester.enterText(find.byType(TextField), '# Changed');
      await tester.pump();
      inHeader('Save');
      await tester.tap(_button('Preview'));
      await tester.pumpAndSettle();
      expect(tester.widget<Markdown>(find.byType(Markdown)).data, '# Changed');
      inHeader('Save');
      await tester.tap(_button('Save'));
      await tester.pump();
      expect(service.written, '# Changed');
      // While the save is in flight the Save button gives way to a spinner,
      // so it can't be tapped twice.
      expect(_button('Save'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Saving',
        ),
        findsOneWidget,
      );
      service.saving!.complete(false);
      await tester.pumpAndSettle();
      inHeader('Save');
      expect(find.text('Could not save file'), findsOneWidget);
      await tester.tap(_button('Save'));
      await tester.pump();
      service.saving!.complete(true);
      await tester.pumpAndSettle();
      expect(_button('Save'), findsNothing);
      expect(_button('Edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('plain text has Save without the markdown toggle', (
    tester,
  ) async {
    final service = await mount(
      tester,
      const Size(390, 800),
      name: 'notes.txt',
    );
    service.loaded.complete(utf8.encode('Original'));
    await tester.pumpAndSettle();
    expect(_button('Edit'), findsNothing);
    expect(_button('Preview'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.pump();
    expect(_button('Save'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final offline in [false, true]) {
    testWidgets('no text actions for offline=$offline unsupported files', (
      tester,
    ) async {
      await mount(
        tester,
        const Size(390, 800),
        name: offline ? 'notes.md' : 'data.bin',
        offline: offline,
      );
      await tester.pumpAndSettle();
      expect(_button('Edit'), findsNothing);
      expect(_button('Preview'), findsNothing);
      expect(_button('Save'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
