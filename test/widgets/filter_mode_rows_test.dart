import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:noo/providers/files_controller.dart';
import 'package:noo/widgets/filter_mode_rows.dart';

import 'noo/noo_test_utils.dart';

void main() {
  setUpNooTests();

  group('HiddenFilesFilterRow', () {
    testNooWidgets(
      'only the selected option shows its label, tapping another reports it',
      (tester, theme, c) async {
        var value = HiddenFilesFilter.hide;
        await pumpNoo(
          tester,
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 360,
              child: HiddenFilesFilterRow(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
          theme: theme,
        );
        expect(find.text('Hidden files'), findsOneWidget);
        expect(find.text('Hide'), findsOneWidget);
        expect(find.text('Only hidden'), findsNothing);

        await tester.tap(find.byIcon(LucideIcons.layers));
        await tester.pumpAndSettle();
        expect(value, HiddenFilesFilter.include);
        expect(find.text('All'), findsOneWidget);
      },
    );
  });

  group('StorageScopeRow', () {
    testNooWidgets('offers cloud only / only external / all', (
      tester,
      theme,
      c,
    ) async {
      var value = StorageScope.cloud;
      await pumpNoo(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 360,
            child: StorageScopeRow(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
        theme: theme,
      );
      expect(find.text('External storage'), findsOneWidget);
      expect(find.text('Cloud only'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.hardDrive).last);
      await tester.pumpAndSettle();
      expect(value, StorageScope.external);
      expect(find.text('Only external'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.layers));
      await tester.pumpAndSettle();
      expect(value, StorageScope.all);
      expect(find.text('All'), findsOneWidget);
    });
  });
}
