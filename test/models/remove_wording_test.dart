import 'package:flutter_test/flutter_test.dart';
import 'package:noo/models/nextcloud_item.dart';
import 'package:noo/models/remove_wording.dart';

NextcloudItem item(String name, {String? mountType}) => NextcloudItem(
  id: name,
  name: name,
  path: '/$name',
  type: NextcloudItemType.folder,
  size: 0,
  lastModified: DateTime(2026),
  mountType: mountType,
);

void main() {
  test('a received share root reads as leaving, not deleting', () {
    final w = RemoveWording.of([item('Family', mountType: 'shared')]);
    expect(w.label, 'Leave share');
    expect(w.confirmLabel, 'Leave');
    expect(w.message, isNot(contains('cannot be undone')));
    expect(w.result(1), 'Left Family');
    expect(w.result(0), 'Failed to leave Family');
  });

  test('own items keep the delete wording', () {
    final w = RemoveWording.of([item('Docs')]);
    expect(w.label, 'Delete');
    expect(w.message, contains('cannot be undone'));
    expect(w.result(1), 'Deleted Docs');
  });

  test('a mix gets neutral wording', () {
    final w = RemoveWording.of([
      item('Docs'),
      item('Family', mountType: 'shared'),
    ]);
    expect(w.label, 'Remove');
    expect(w.result(2), 'Removed 2 of 2 item(s)');
  });

  test('several share roots', () {
    final w = RemoveWording.of([
      item('A', mountType: 'shared'),
      item('B', mountType: 'shared'),
    ]);
    expect(w.title, 'Leave shares');
    expect(w.result(2), 'Left 2 of 2 shared item(s)');
  });
}
