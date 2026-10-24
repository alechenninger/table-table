import 'package:table_table/slack_table.dart';
import 'package:test/test.dart';

// Preserve regression coverage from the original implementation.
void main() {
  test('quoted csv cells and newlines', () {
    expect(
      render('Name,Note\r\n"Doe, Jane","said ""hi""\r\non Monday"\r\n'),
      'Name\tNote\nDoe, Jane\tsaid "hi" on Monday',
    );
  });

  test('csv keeps numbers as text and pads rows', () {
    expect(
      render('ID,Amount,Other\n001,1.00\n002,1e3,""', inputFormat: 'csv'),
      'ID\tAmount\tOther\n001\t1.00\t\n002\t1e3\t',
    );
  });

  test('permissive csv quote behavior', () {
    for (final (text, expected) in [
      ('A,B\n"unclosed,value', 'A\tB\nunclosed,value\t'),
      ('A,B\n "a",b', 'A\tB\n"a"\tb'),
      ('A,B\n"a"suffix,b', 'A\tB\nasuffix\tb'),
      ('A,B\na"b,c', 'A\tB\na"b\tc'),
    ]) {
      expect(render(text, inputFormat: 'csv'), expected, reason: text);
    }
  });

  test('quoted tsv and empty rows', () {
    expect(
      render('A\tB\n\t\n"x\ty"\tz\n', inputFormat: 'tsv'),
      'A\tB\nx y\tz',
    );
  });

  test('delimited spans preserve Unicode, escaped quotes, and suffixes', () {
    expect(
      parseTable(
        'A,B,C\n"😀""x","one,\ntwo",tail\n'
        'prefix"quote,"closed"suffix,𠮷\n,,\nlast,,',
        inputFormat: 'csv',
      ).rows,
      [
        ['A', 'B', 'C'],
        ['😀"x', 'one, two', 'tail'],
        ['prefix"quote', 'closedsuffix', '𠮷'],
        ['last', '', ''],
      ],
    );
  });

  test('formatting preserves caller-created table cells and snapshots', () {
    final rows = [
      [' A ', 'B'],
      [' x\ty ', 'z'],
      [' tail '],
    ];
    final table = Table(rows);
    rows.first[0] = 'changed';
    rows.add(['added']);

    expect(formatTsv(table), 'A\tB\nx y\tz\ntail\t');
    expect(
      formatMarkdown(table),
      '| A    | B   |\n| ---- | --- |\n| x y  | z   |\n| tail |     |',
    );
    expect(formatTsv(table), 'A\tB\nx y\tz\ntail\t');
    expect(table.rows, [
      [' A ', 'B'],
      [' x\ty ', 'z'],
      [' tail '],
    ]);
    for (final immutable in [table, parseTable('A,B\nx,y')]) {
      expect(() => immutable.rows.add(['new']), throwsUnsupportedError);
      expect(() => immutable.rows.first[0] = 'new', throwsUnsupportedError);
    }
  });

  test('markdown width still ignores ANSI escapes and control characters', () {
    expect(
      formatMarkdown(Table([
        ['\x1b[31mred\x1b[0m', 'a\x00b'],
        ['blue', 'abc'],
      ])),
      '| \x1b[31mred\x1b[0m  | a\x00b  |\n'
      '| ---- | --- |\n'
      '| blue | abc |',
    );
  });

  test('unicode markdown width counts display columns', () {
    expect(
      formatMarkdown(Table([
        ['😀', 'e\u0301'],
        ['😀😀😀😀', 'x'],
      ])),
      '| 😀       | e\u0301   |\n| -------- | --- |\n| 😀😀😀😀 | x   |',
    );
  });

  test('markdown aligns CJK names with Latin text', () {
    expect(
      formatMarkdown(Table([
        ['ID', 'Project', 'Owner', 'City', 'Status', 'Score'],
        [
          'REC-00003',
          'Kubernetes Fleet',
          '李明',
          'São Paulo',
          'Blocked',
          '0.411'
        ],
        ['REC-00004', '東京', '山田太郎', '上海', 'Done', '1'],
      ])),
      '| ID        | Project          | Owner    | City      | Status  | Score |\n'
      '| --------- | ---------------- | -------- | --------- | ------- | ----- |\n'
      '| REC-00003 | Kubernetes Fleet | 李明     | São Paulo | Blocked | 0.411 |\n'
      '| REC-00004 | 東京             | 山田太郎 | 上海      | Done    | 1     |',
    );
  });

  test('markdown aligns fullwidth, halfwidth and supplementary CJK text', () {
    expect(
      formatMarkdown(Table([
        ['ＡＢ', 'ｶﾅ', '𠮷野'],
        ['abc', 'abc', 'abc'],
      ])),
      '| ＡＢ | ｶﾅ  | 𠮷野 |\n'
      '| ---- | --- | ---- |\n'
      '| abc  | abc | abc  |',
    );
  });

  test('markdown aligns emoji sequences as single wide glyphs', () {
    expect(
      formatMarkdown(Table([
        ['👩🏽‍💻', '🇯🇵', '❤️'],
        ['abc', 'abc', 'abc'],
      ])),
      '| 👩🏽‍💻  | 🇯🇵  | ❤️  |\n'
      '| --- | --- | --- |\n'
      '| abc | abc | abc |',
    );
  });

  test('markdown measures escaped Unicode source without changing cell text',
      () {
    expect(
      formatMarkdown(Table([
        ['李|明', 'e\u0301\\x'],
        ['abc', 'é'],
      ])),
      '| 李\\|明 | e\u0301\\\\x |\n'
      '| ------ | ---- |\n'
      '| abc    | é    |',
    );
  });

  test('python whitespace and bom semantics', () {
    for (final whitespace in ['\x1c', '\x85', '\xa0', '\u2003', '\u202f']) {
      expect(
        formatTsv(Table([
          ['${whitespace}a${whitespace}b', ' c ']
        ])),
        'a b\tc',
        reason: 'whitespace U+${whitespace.runes.single.toRadixString(16)}',
      );
    }
    expect(render('\ufeffA,B\nx,y'), '\ufeffA\tB\nx\ty');
  });

  test('source format and detection precedence', () {
    for (final (text, source) in [
      ('| A | B |\n| --- | --- |\n| x | y |', 'markdown'),
      ('A\tB\nx\ty', 'tsv'),
      ('A\tB,C\nx\ty,z', 'tsv'),
      ('A\tB\tC\n1\t2\t3', 'tsv'),
      ('A\tB\tC\n1\t2\t3\t4\n5\t6\t7', 'tsv'),
      ('A\tB\tC\n1\n2', 'tsv'),
      ('A,B\nx,y', 'csv'),
      ('A,B|C\nx,y|z', 'csv'),
      ('A | B\nx | y', 'pipe'),
      ('A\n\nB\n\nx\n\ny', 'spaced'),
      ('A\tB\tC\nx\ny\nz', 'cursor'),
    ]) {
      expect(parseTable(text).sourceFormat, source, reason: source);
    }
  });

  test('markdown escapes and surrounding prose', () {
    expect(
      parseTable('Intro\n| A | B |\n| :--- | ---: |\n| x\\|y | z |\nEnd').rows,
      [
        ['A', 'B'],
        ['x|y', 'z']
      ],
    );
    expect(
      parseTable('A|B\nx|y\\', inputFormat: 'pipe').rows,
      [
        ['A', 'B'],
        ['x', 'y\\']
      ],
    );
  });

  test('pipe spans preserve backslashes around escaped pipes and Unicode', () {
    for (final (line, expected) in [
      (r'x\|😀|y', ['x|😀', 'y']),
      (r'x\\|😀', [r'x\\', '😀']),
      (r'x\\\|😀|y', [r'x\\' '|😀', 'y']),
      (r'x\😀|y', [r'x\😀', 'y']),
    ]) {
      expect(parseTable('A|B\n$line', inputFormat: 'pipe').rows[1], expected,
          reason: line);
    }
  });

  test('markdown pads to the separator and widest body row', () {
    expect(
      parseTable('| A | B |\n| --- | --- | --- |\n| x | y |').rows,
      [
        ['A', 'B', ''],
        ['x', 'y', ''],
      ],
    );
  });

  test('errors and column candidates', () {
    expect(
      () => parseTable('A,B', inputFormat: 'invalid'),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('unknown input format'),
      )),
    );
    final text = List.generate(12, (i) => '$i').join('\n\n');
    expect(
      () => parseTable(text),
      throwsA(isA<AmbiguousColumnsError>().having(
          (error) => error.candidates, 'candidates', [
        2,
        3,
        4,
        6
      ]).having((error) => error.toString(), 'message',
          'ambiguous column count; valid choices are 2, 3, 4, 6')),
    );
    expect(
      () => parseTable(text, inputFormat: 'spaced', columns: 5),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('multiple complete rows of 5 columns'),
      )),
    );
  });

  test('cursor fragment errors', () {
    expect(
      () => parseTable('A\tB\tC\nx\ny', inputFormat: 'cursor'),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('ended before a row was complete'),
      )),
    );
  });

  test('empty rows and empty cells', () {
    expect(formatTsv(Table([[], []])), '\n');
    expect(
      () => formatMarkdown(Table([[]])),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('no table rows'),
      )),
    );
    expect(
      () => parseTable(',\n,', inputFormat: 'csv'),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('no csv rows'),
      )),
    );
  });

  test('csv field limit matches reference', () {
    expect(
      () => parseTable('A,B\n${'x' * 131073},y', inputFormat: 'csv'),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('field larger than field limit'),
      )),
    );
  });

  test('csv field limit counts surrogate pairs and decoded quotes once', () {
    for (final character in ['😀', '"']) {
      final field = character * 131072;
      final encoded = field.replaceAll('"', '""');
      expect(
        parseTable('A,B\n"$encoded",x', inputFormat: 'csv').rows[1],
        [field, 'x'],
      );
      expect(
        () => parseTable('A,B\n"$encoded$encoded",x', inputFormat: 'csv'),
        throwsA(isA<ParseError>().having((error) => error.message, 'message',
            contains('field larger than field limit'))),
      );
    }
  });
}
