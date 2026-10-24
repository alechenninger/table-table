import 'package:slack_table/slack_table.dart';
import 'package:test/test.dart';

// Direct ports of tests/test_core_regressions.py, including all subtest cases.
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

  test('unicode markdown width counts code points', () {
    expect(
      formatMarkdown(Table([
        ['😀', 'e\u0301'],
        ['😀😀😀😀', 'x'],
      ])),
      '| 😀    | e\u0301  |\n| ---- | --- |\n| 😀😀😀😀 | x   |',
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
      ('A,B\nx,y', 'csv'),
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
}
