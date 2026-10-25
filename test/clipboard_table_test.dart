import 'dart:io';

import 'package:table_table/slack_table.dart';
import 'package:table_table/src/clipboard.dart';
import 'package:table_table/src/clipboard_table.dart';
import 'package:test/test.dart';

void main() {
  const html = '<table><tr><th>A</th><th>B</th></tr>'
      '<tr><td>rich</td><td><p>value</p></td></tr></table>';

  test('auto prefers HTML and returns the parsed table directly', () {
    final source = File('test/fixtures/copied_table.html').readAsStringSync();
    final table = parseClipboardTable(ClipboardSnapshot({
      ClipboardFormat.plainText: 'Wrong,Count\nplain,999',
      ClipboardFormat.html: source,
    }));
    expect(table.sourceFormat, InputFormats.html);
    expect(table.rows, hasLength(13));
    expect(table.rows[4][1], 'OwnNamespace');
    expect(table.rows[5][1], 'Reconcile');
    expect(table.rows[10][1], 'HTTP_PROXY optional');
  });

  test('HTML-only and plain-text-only clipboards work', () {
    expect(
        parseClipboardTable(ClipboardSnapshot({ClipboardFormat.html: html}))
            .rows[1],
        ['rich', 'value']);
    expect(
        parseClipboardTable(ClipboardSnapshot.text('A\tB\nx\ty')).sourceFormat,
        InputFormats.tsv);
  });

  test('explicit text formats ignore the rich representation', () {
    final contents = ClipboardSnapshot({
      ClipboardFormat.html: html,
      ClipboardFormat.plainText: 'A,B\nplain,text'
    });
    final table = parseClipboardTable(contents, inputFormat: InputFormats.csv);
    expect(table.sourceFormat, InputFormats.csv);
    expect(table.rows[1], ['plain', 'text']);
  });

  test('unusable HTML falls back to plain text', () {
    for (final source in [
      '',
      '<p>not a table</p>',
      '<table><tr><td colspan="2">merged</td><td>x</td></tr></table>'
    ]) {
      final table = parseClipboardTable(ClipboardSnapshot({
        ClipboardFormat.html: source,
        ClipboardFormat.plainText: 'A,B\nplain,text',
      }));
      expect(table.sourceFormat, InputFormats.csv);
      expect(table.rows[1], ['plain', 'text']);
    }
  });

  test('explicit HTML also accepts literal markup copied as plain text', () {
    final table = parseClipboardTable(
        ClipboardSnapshot({
          ClipboardFormat.html: '<pre>escaped markup</pre>',
          ClipboardFormat.plainText: html,
        }),
        inputFormat: InputFormats.html);
    expect(table.sourceFormat, InputFormats.html);
    expect(table.rows[1], ['rich', 'value']);
  });

  test('fallback retains column ambiguity and accepts a selected count', () {
    final contents = ClipboardSnapshot({
      ClipboardFormat.html: '<p>no table</p>',
      ClipboardFormat.plainText: 'A\n\nB\n\nC\n\n1\n\n2\n\n3',
    });
    expect(() => parseClipboardTable(contents),
        throwsA(isA<AmbiguousColumnsError>()));
    expect(parseClipboardTable(contents, columns: 3).rows[1], ['1', '2', '3']);
  });

  test('HTML failure remains meaningful when no fallback can be read', () {
    final contents = ClipboardSnapshot({
      ClipboardFormat.html:
          '<table><tr><td rowspan="2">merged</td><td>x</td></tr></table>'
    });
    expect(
        () => parseClipboardTable(contents),
        throwsA(isA<ParseError>().having(
            (error) => error.message, 'message', contains('merged cells'))));
    expect(() => parseClipboardTable(ClipboardSnapshot({})),
        throwsA(isA<ParseError>()));
  });
}
