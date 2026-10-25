import 'dart:io';

import 'package:table_table/slack_table.dart';
import 'package:test/test.dart';

void main() {
  test('preserves all cells in the copied HTML stress test', () {
    final source = File('test/fixtures/copied_table.html').readAsStringSync();
    for (final format in [InputFormats.auto, InputFormats.html]) {
      final table = parseTable(source, inputFormat: format);
      expect(table.sourceFormat, InputFormats.html);
      expect(table.rows, [
        ['Pattern', 'Cell', 'Element'],
        ['Plain text', 'graph-builder', 'text node in td'],
        ['Code', 'make bundle', 'code'],
        ['Link', 'cincinnati-operator', 'a'],
        ['Pill', 'OwnNamespace', 'span, inline-flex'],
        ['Button', 'Reconcile', 'button, inline-flex'],
        ['Paragraph', 'Policy engine URI', 'p'],
        [
          'Nested emphasis',
          'Needs a Route and edge TLS.',
          'p with nested spans'
        ],
        ['Line break', 'first line second line', 'br inside a span'],
        ['List', 'Deployment Route', 'ul and li'],
        ['Flex row', 'HTTP_PROXY optional', 'div, display flex'],
        ['Flex column', 'openshift-config pull-secret', 'column flex of p'],
        [
          'Mixed inline',
          'Copy status.policyEngineURI from the operand.',
          'p containing code and a',
        ],
      ]);
      expect(formatTsv(table).split('\n'), hasLength(13));
      expect(formatMarkdown(table), contains('HTTP_PROXY optional'));
    }
  });

  test('keeps empty cells, empty rows, entities, and inline punctuation', () {
    final table = parseTable('<TABLE><TR><TH>A<TH>B<TH>C'
        '<TR><TD><TD>&lt;tag&gt;&amp;&nbsp;😀<TD>pre'
        '<span style="display:inline-flex"><code>fix</code></span>.'
        '<TR><TD><TD><TD></TABLE>');
    expect(table.rows, [
      ['A', 'B', 'C'],
      ['', '<tag>& 😀', 'prefix.'],
      ['', '', ''],
    ]);
  });

  test('separates block and layout children, skipping non-content nodes', () {
    final table = parseTable('<table><tr><td>A</td><td>B</td></tr><tr><td>'
        '<p>one</p><p>two<br>three</p>'
        '<span style="display:flex"><code>four</code><span>five</span></span>'
        '<script>bad()</script><style>bad{}</style><template>bad</template>'
        '<span hidden>bad</span><span style="display: none">bad</span>'
        '</td><td>end</td></tr></table>');
    expect(table.rows[1], ['one two three four five', 'end']);
  });

  test('nested tables contribute cell text, not extra outer rows', () {
    final table = parseTable('<table><tr><th>A</th><th>B</th></tr><tr><td>'
        '<table><tr><td>nested</td><td>values</td></tr></table>'
        '</td><td>outer</td></tr></table>');
    expect(table.rows, [
      ['A', 'B'],
      ['nested values', 'outer'],
    ]);
  });

  test('deep wrappers and cell contents do not exhaust the traversal stack',
      () {
    for (final (before, after) in [
      ('<span>' * 10000, '</span>' * 10000),
      ('', ''),
    ]) {
      final table = parseTable(
          '$before<table><tr><th>A</th><th>B</th></tr>'
          '<tr><td>${'<span>' * 10000}value${'</span>' * 10000}'
          '</td><td>end</td></tr></table>$after',
          inputFormat: InputFormats.html);
      expect(table.rows, [
        ['A', 'B'],
        ['value', 'end'],
      ]);
    }
  });

  test('iterative traversal preserves document order and block boundaries', () {
    final table =
        parseTable('<div>intro</div><table><tr><th>A</th><th>B</th></tr>'
            '<tr><td>before<div><p>one</p><p>two</p></div>after'
            '<span style="display:flex"><code>x</code><span>y</span></span>.'
            '</td><td>end</td></tr></table>'
            '<table><tr><td>other</td><td>table</td></tr></table>');
    expect(table.rows, [
      ['A', 'B'],
      ['before one two after x y .', 'end'],
    ]);
  });

  test('rejects absent tables, single columns, and merged cells explicitly',
      () {
    for (final source in [
      '<p>Not a table</p>',
      '<table><tr><td>one</td></tr></table>',
      '<table><tr><td colspan="2">merged</td><td>value</td></tr></table>',
      '<table><tr><td rowspan="2">merged</td><td>value</td></tr></table>',
    ]) {
      expect(() => parseTable(source, inputFormat: InputFormats.html),
          throwsA(isA<ParseError>()));
    }
  });
}
