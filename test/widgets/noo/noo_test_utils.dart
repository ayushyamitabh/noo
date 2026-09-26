import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:noo/theme/app_theme.dart';
import 'package:noo/theme/design_tokens.dart';

/// Shared setup for the design-system component tests. Google Fonts can't
/// fetch in the sandbox, so runtime fetching is off (see standards.md
/// "Testing"); the resulting missing-font load errors are async and don't
/// affect layout assertions.
void setUpNooTests() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
}

/// Themes built through the real [AppTheme] (non-dynamic), so the
/// [NooColors] extension is registered exactly as in the app. Built lazily
/// inside test bodies - AppTheme touches Google Fonts, which needs the test
/// binding to exist first.
ThemeData nooTheme(Brightness brightness) => brightness == Brightness.light
    ? AppTheme.light(AppTheme.defaultNextcloudBlue, useDynamicColor: false)
    : AppTheme.dark(AppTheme.defaultNextcloudBlue, useDynamicColor: false);

Future<void> pumpNoo(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  Size surfaceSize = const Size(800, 900),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? nooTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

/// Runs [body] once per theme, each as its own named test.
void testNooWidgets(
  String description,
  Future<void> Function(WidgetTester tester, ThemeData theme, NooColors colors) body,
) {
  for (final brightness in Brightness.values) {
    testWidgets('$description (${brightness.name})', (tester) async {
      final theme = nooTheme(brightness);
      await body(tester, theme, theme.extension<NooColors>()!);
    });
  }
}

/// The nearest colored [BoxDecoration] painted around [finder] (Container
/// and AnimatedContainer both build a [DecoratedBox]).
BoxDecoration decorationOf(WidgetTester tester, Finder finder) {
  final boxes = find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null,
    ),
    matchRoot: true,
  );
  return tester.widget<DecoratedBox>(boxes.first).decoration as BoxDecoration;
}
