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

  test('table discovery skips templates and hidden ancestor subtrees', () {
    const ignored = '<table><tr><td>ignored</td><td>table</td></tr></table>';
    for (final wrapper in [
      '<template>$ignored</template>',
      '<div hidden>$ignored</div>',
      '<div style="display:none">$ignored</div>',
      '<div hidden style="display:block">$ignored</div>',
      '<table hidden><tr><td>ignored</td><td>table</td></tr></table>',
      '<table style="display:none"><tr><td>ignored</td><td>table</td></tr></table>',
    ]) {
      final table = parseTable(
          '$wrapper<table><tr><td>real</td><td>value</td>'
          '</tr></table>',
          inputFormat: InputFormats.html);
      expect(
          table.rows,
          [
            ['real', 'value']
          ],
          reason: wrapper);
    }
  });

  test('row discovery and cell extraction use the same visibility rules', () {
    final table = parseTable(
        '<table><tr><th hidden>hidden</th><th>A</th><th>B</th>'
        '</tr><tbody hidden><tr><td>hidden</td><td>group</td></tr></tbody>'
        '<tbody style="display:none"><tr><td>hidden</td><td>group</td></tr></tbody>'
        '<tr hidden><td>hidden</td><td>row</td></tr>'
        '<tr style="display:none"><td>hidden</td><td>row</td></tr>'
        '<tr><td style="display:none" colspan="2">hidden</td><td>real</td>'
        '<td>before<span hidden>hidden</span><span style="display:none">hidden'
        '</span><template>hidden</template>after</td></tr></table>',
        inputFormat: InputFormats.html);
    expect(table.rows, [
      ['A', 'B'],
      ['real', 'beforeafter'],
    ]);
  });

  test('inline display declarations respect syntax, order, and importance', () {
    const cases = {
      'display:none;display:inline': 'visible',
      'display:inline;display:none': '',
      'display:inline!important;display:none': 'visible',
      'display:none!important;display:inline': '',
      'display:none!important;display:inline!important': 'visible',
      'display:inline!important;display:none!important': '',
      'DISPLAY:NoNe;display:INLINE': 'visible',
      '/* ;display:none; */ display /* comment */:inline': 'visible',
      'content:";display:none;";display:inline': 'visible',
      'display:none;display:not-a-display': '',
      'display:none;display:"inline"': '',
      'display:inline !IMPORTANT;display:none': 'visible',
      'display:inline ! important;display:none': 'visible',
      'display:inline !/**/important;display:none': 'visible',
      '--x:f(display:none;display:block);display:inline': 'visible',
      '--x:{display:none;};display:inline': 'visible',
      'display:none;--x:f(display:inline;)': '',
      'display:none;/* display:inline */': '',
      'display:\fnone': '',
      'display:none;display:block flow list-item': 'visible',
      'display:none;display:list-item flow-root inline': 'visible',
      'display:none;display:table block': 'visible',
      'display:none;display:inherit': 'visible',
      'display:none;display:inline block': '',
      'display:none;display:flex grid': '',
      'display:none;display:list-item flex': '',
      r'display:\6e one': '',
      r'd\69 splay:none': '',
    };
    for (final entry in cases.entries) {
      final table = parseTable(
          '<table><tr><td>A</td><td>B</td></tr><tr><td>'
          "<span style='${entry.key}'>visible</span>"
          '</td><td>end</td></tr></table>',
          inputFormat: InputFormats.html);
      expect(table.rows[1], [entry.value, 'end'], reason: entry.key);
    }
  });

  test('unrelated CSS values cannot overflow or exhaust the parsing stack', () {
    for (final value in [
      '${'9' * 1000}px',
      '${'f(' * 10000}0${')' * 10000}',
    ]) {
      for (final style in [
        'display:none; margin-left:$value',
        'margin-left:$value; display:none',
      ]) {
        final table = parseTable(
            '<table><tr><td>A</td><td>B</td></tr><tr><td>'
            '<span style="$style">hidden</span>'
            '</td><td>end</td></tr></table>',
            inputFormat: InputFormats.html);
        expect(table.rows[1], ['', 'end']);
      }
    }
  });

  test('inline CSS changes apply during table, row, and cell discovery', () {
    final table = parseTable(
        '<table style="display:none;display:table">'
        '<tr><th>A</th><th>B</th></tr>'
        '<tr style="display:none;display:table-row"><td>real</td>'
        '<td style="display:none;display:table-cell">value</td></tr></table>',
        inputFormat: InputFormats.html);
    expect(table.rows, [
      ['A', 'B'],
      ['real', 'value'],
    ]);
  });

  test('styles with a shared prefix still honor later display declarations',
      () {
    const cases = {
      'margin-left:1px': 'one two',
      'margin-left:2px': 'one two',
      'display:none': '',
      r'd\69 splay:none': '',
      'content:"display:none"': 'one two',
      '--x:f(display:none;)': 'one two',
    };
    final table = parseTable(
        '<table><tr><th>A</th><th>B</th></tr>'
        '${cases.keys.map((suffix) => '<tr><td><span style=\'display:flex;$suffix\'>'
            '<b>one</b><b>two</b></span></td><td>end</td></tr>').join()}'
        '</table>',
        inputFormat: InputFormats.html);
    expect(table.rows.skip(1), [
      for (final text in cases.values) [text, 'end']
    ]);
  });

  test('CSS display values preserve block and layout boundaries', () {
    for (final display in [
      'flex',
      'grid',
      'inline-flex',
      'inline-grid',
      'block flex',
      'inline flex',
      'block grid',
      'inline grid'
    ]) {
      final table = parseTable(
          '<table><tr><td>A</td><td>B</td></tr><tr><td>'
          '<span style="display:none;display:$display"><b>one</b><b>two</b>'
          '</span></td><td>end</td></tr></table>',
          inputFormat: InputFormats.html);
      expect(table.rows[1], ['one two', 'end'], reason: display);
    }
    final table = parseTable(
        '<table><tr><td>A</td><td>B</td></tr><tr><td>'
        'before<div style="display:inline">middle</div>after'
        '</td><td>end</td></tr></table>',
        inputFormat: InputFormats.html);
    expect(table.rows[1], ['beforemiddleafter', 'end']);
  });

  test('span attributes follow HTML integer parsing and default values', () {
    const single = [
      '',
      'invalid',
      '1',
      '01',
      '+1',
      '1tail',
      '1.5',
      '1e2',
      '  \t\n\f+01tail',
      '-1',
      '-2tail',
      '\u00a02',
      '\u000b2'
    ];
    for (final attribute in ['rowspan', 'colspan']) {
      for (final value in [
        ...single,
        if (attribute == 'colspan') ...['0', '-0', '0x2']
      ]) {
        final table = parseTable(
            '<table><tr><td $attribute="$value">A</td>'
            '<td>B</td></tr></table>',
            inputFormat: InputFormats.html);
        expect(
            table.rows,
            [
              ['A', 'B']
            ],
            reason: '$attribute="$value"');
      }
    }
  });

  test('rejects every HTML span that represents merged cells without overflow',
      () {
    for (final attribute in ['rowspan', 'colspan']) {
      for (final value in [
        '2',
        '2tail',
        '2.5',
        '+2tail',
        ' \t\n\f002tail',
        '9' * 1000,
        '${'0' * 1000}2',
        if (attribute == 'rowspan') ...['0', '-0', '0x2']
      ]) {
        expect(
            () => parseTable(
                '<table><tr><td $attribute="$value">A</td>'
                '<td>B</td></tr></table>',
                inputFormat: InputFormats.html),
            throwsA(isA<ParseError>()
                .having((e) => e.message, 'message', contains('merged cells'))),
            reason: '$attribute="$value"');
      }
    }
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
