import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/views/search_view.dart';

import 'files_test_harness.dart';

void main() {
  setUpFilesHarness();

  testWidgets('sort and filter controls change the results', (tester) async {
    final app = await pumpWithApp(tester, [], (_) => const SearchView());
    app.files.searchResults = [
      harnessItem('apple.txt'),
      harnessItem('zebra.txt'),
      harnessItem('docs', folder: true),
    ];
    await tester.enterText(find.byType(EditableText), 'a');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('apple.txt') < y('zebra.txt'), isTrue);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descending'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    expect(y('zebra.txt') < y('apple.txt'), isTrue);

    // Type filter via the real sheet.
    expect(find.text('docs'), findsOneWidget);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.file).hitTestable());
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('docs'), findsNothing);

    await app.finish(tester);
  });
}
