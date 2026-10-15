import 'package:flutter_test/flutter_test.dart';
import 'package:noo/models/nextcloud_item.dart';

void main() {
  NextcloudItem item({String? mountType}) => NextcloudItem(
    id: '1',
    name: 'a.txt',
    path: '/a.txt',
    type: NextcloudItemType.file,
    size: 1,
    lastModified: DateTime(2026),
    mountType: mountType,
  );

  test('isSharedWithMe only for received-share mounts', () {
    expect(item().isSharedWithMe, isFalse);
    expect(item(mountType: 'shared').isSharedWithMe, isTrue);
    expect(item(mountType: 'external').isSharedWithMe, isFalse);
    expect(item(mountType: 'external').isExternalStorage, isTrue);
  });

  test('isOwnedByOther also covers items nested in a shared folder', () {
    final nested = item().copyWith(ownerId: 'Jamie');
    expect(nested.isSharedWithMe, isFalse);
    expect(nested.isOwnedByOther('alex'), isTrue);
    expect(nested.isOwnedByOther('jamie'), isFalse);
    expect(item().isOwnedByOther('alex'), isFalse);
    expect(item(mountType: 'shared').isOwnedByOther('alex'), isTrue);
  });

  test('copyWith keeps and replaces owner info', () {
    final owned = item(
      mountType: 'shared',
    ).copyWith(ownerId: 'jamie', ownerDisplayName: 'Jamie Rivera');
    expect(owned.ownerId, 'jamie');
    expect(owned.copyWith(name: 'b.txt').ownerDisplayName, 'Jamie Rivera');
  });
}
