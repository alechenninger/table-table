import 'package:table_table/src/clipboard.dart';
import 'package:test/test.dart';

void main() {
  test('snapshot keeps absent and empty representations distinct', () {
    final absent = ClipboardSnapshot({});
    final empty = ClipboardSnapshot.text('');
    expect(absent[ClipboardFormat.plainText], isNull);
    expect(empty[ClipboardFormat.plainText], '');
    expect(absent, isNot(empty));
  });

  test('snapshot copies and freezes its representations', () {
    final values = {ClipboardFormat.plainText: 'original'};
    final snapshot = ClipboardSnapshot(values);
    values[ClipboardFormat.plainText] = 'changed';
    expect(snapshot[ClipboardFormat.plainText], 'original');
    expect(() => snapshot.representations.clear(), throwsUnsupportedError);
  });

  test('snapshot equality includes HTML and is independent of format order',
      () {
    final a = ClipboardSnapshot(
        {ClipboardFormat.plainText: 'same', ClipboardFormat.html: '<p>A</p>'});
    final b = ClipboardSnapshot(
        {ClipboardFormat.html: '<p>A</p>', ClipboardFormat.plainText: 'same'});
    final changed = ClipboardSnapshot(
        {ClipboardFormat.plainText: 'same', ClipboardFormat.html: '<p>B</p>'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(changed));
    expect(a, isNot(ClipboardSnapshot.text('same')));
  });
}
