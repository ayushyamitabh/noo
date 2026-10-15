import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noo/models/nextcloud_item.dart';
import 'package:noo/models/nextcloud_share.dart';
import 'package:noo/views/shares_view.dart';

import 'files_test_harness.dart';

NextcloudShare _share(
  String name, {
  required ShareType type,
  required String owner,
  String? with_,
  int permissions = 1,
  bool withMe = false,
}) => NextcloudShare(
  id: name,
  path: '/$name',
  name: name,
  itemType: NextcloudItemType.file,
  shareType: type,
  ownerDisplayName: owner,
  sharedWithDisplayName: with_,
  sharedAt: DateTime(2026, 10, 1),
  sharedWithMe: withMe,
  permissions: permissions,
);

/// The permission on a share is what its *recipient* can do. So `By you` and
/// `Links` rows name who they're for (you're the owner of all of them), while
/// `With you` rows name the owner and show the permission you were given.
void main() {
  setUpFilesHarness(loadFonts: true);

  final byYou = [
    _share(
      'Plan.pdf',
      type: ShareType.user,
      owner: 'Alex Morgan',
      with_: 'Ana',
    ),
    _share(
      'Photos',
      type: ShareType.group,
      owner: 'Alex Morgan',
      with_: 'Design team',
      permissions: 3,
    ),
    _share('Flyer.png', type: ShareType.publicLink, owner: 'Alex Morgan'),
  ];
  final withYou = [
    _share(
      'Budget.xlsx',
      type: ShareType.user,
      owner: 'Jamie Rivera',
      permissions: 3,
      withMe: true,
    ),
  ];

  Future<AppHarness> pump(WidgetTester tester, {Size? size}) => pumpWithApp(
    tester,
    [],
    (scroll) => SharesView(scrollController: scroll),
    size: size ?? const Size(400, 800),
    sharesBuilder: (session) =>
        HarnessShares(session, byYou: byYou, withYou: withYou),
  );

  testWidgets('By you names the recipient, not yourself', (tester) async {
    final app = await pump(tester);
    expect(find.text('Ana · Can view'), findsOneWidget);
    expect(find.text('Design team · Can edit'), findsOneWidget);
    expect(find.textContaining('Alex Morgan'), findsNothing);
    // The public link is its own tab, not mixed into By you.
    expect(find.textContaining('Public link'), findsNothing);
    await app.finish(tester);
  });

  testWidgets('Links says "Public link"', (tester) async {
    final app = await pump(tester);
    await tester.tap(find.text('Links'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Public link · Can view'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('With you keeps the owner and your own permission', (
    tester,
  ) async {
    final app = await pump(tester);
    await tester.tap(find.text('With you'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Jamie Rivera · Can edit'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('tablet table: Shared with / Owner column follows the tab', (
    tester,
  ) async {
    final app = await pump(tester, size: const Size(1100, 800));
    expect(find.text('Shared with'), findsOneWidget);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('Ana'), findsOneWidget);

    await tester.tap(find.text('With you'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Jamie Rivera'), findsOneWidget);
    await app.finish(tester);
  });
}
