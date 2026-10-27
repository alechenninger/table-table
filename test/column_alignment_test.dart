import 'package:table_table/table_table.dart';
import 'package:test/test.dart';

void main() {
  const alignments = ColumnAlignment.values;
  const source = '| A | B | C | D |\n'
      '| --- | :--- | :---: | ---: |\n'
      '| a | b | c | d |';

  test('column alignments default to unspecified for every normalized column',
      () {
    final table = Table([
      ['A'],
      ['a', 'b'],
    ]);

    expect(table.columnAlignments,
        [ColumnAlignment.unspecified, ColumnAlignment.unspecified]);
  });

  test('column alignments are snapshotted, padded, and immutable', () {
    final supplied = [ColumnAlignment.right];
    final table = Table([
      ['A'],
      ['a', 'b'],
    ], columnAlignments: supplied);
    supplied[0] = ColumnAlignment.left;
    supplied.add(ColumnAlignment.center);

    expect(table.columnAlignments,
        [ColumnAlignment.right, ColumnAlignment.unspecified]);
    expect(() => table.columnAlignments[0] = ColumnAlignment.left,
        throwsUnsupportedError);
    expect(() => table.columnAlignments.add(ColumnAlignment.left),
        throwsUnsupportedError);
  });

  test('excess column alignments cannot create columns', () {
    expect(
      () => Table([
        ['A'],
      ], columnAlignments: [
        ColumnAlignment.left,
        ColumnAlignment.right
      ]),
      throwsArgumentError,
    );
  });

  for (final inputFormat in ['auto', 'markdown', 'pipe']) {
    test('$inputFormat retains separator alignment for each column', () {
      final table = parseTable(source, inputFormat: inputFormat);

      expect(table.columnAlignments, alignments);
      expect(table.rows, [
        ['A', 'B', 'C', 'D'],
        ['a', 'b', 'c', 'd'],
      ]);
      final reparsed = parseTable(formatMarkdown(table));
      expect(reparsed.columnAlignments, table.columnAlignments);
      expect(reparsed.rows, table.rows);
    });

    test('$inputFormat pads alignment for columns beyond the separator', () {
      final table = parseTable('| A | B |\n| :--- | ---: |\n| a | b | c |',
          inputFormat: inputFormat);

      expect(table.columnAlignments, [
        ColumnAlignment.left,
        ColumnAlignment.right,
        ColumnAlignment.unspecified,
      ]);
      expect(table.rows.first, ['A', 'B', '']);
    });

    test('$inputFormat retains alignment when the separator extends the header',
        () {
      final table = parseTable('| A | B |\n| :--- | ---: | :---: |\n| a | b |',
          inputFormat: inputFormat);

      expect(table.rows, [
        ['A', 'B', ''],
        ['a', 'b', ''],
      ]);
      expect(table.columnAlignments, [
        ColumnAlignment.left,
        ColumnAlignment.right,
        ColumnAlignment.center,
      ]);
    });
  }

  test('readers without alignment syntax leave alignment unspecified', () {
    for (final source in ['A,B\na,b', 'A\tB\na\tb', 'A|B\na|b']) {
      expect(parseTable(source).columnAlignments,
          [ColumnAlignment.unspecified, ColumnAlignment.unspecified]);
    }
  });

  test('Markdown source visually aligns headers and body cells', () {
    expect(
      render(source, outputFormat: 'markdown'),
      '| A   | B    |   C   |    D |\n'
      '| --- | :--- | :---: | ---: |\n'
      '| a   | b    |   c   |    d |',
    );
  });

  test('Markdown measures alignment markers, escaped cells, and Unicode', () {
    final table = Table([
      ['李明', 'x|y', 'Count'],
      ['e\u0301', 'abcdefgh', '1'],
    ], columnAlignments: [
      ColumnAlignment.left,
      ColumnAlignment.center,
      ColumnAlignment.right,
    ]);

    expect(
      formatMarkdown(table),
      '| 李明 |   x\\|y   | Count |\n'
      '| :--- | :------: | ----: |\n'
      '| e\u0301    | abcdefgh |     1 |',
    );
  });

  test('center padding puts an odd extra space on the right, including blanks',
      () {
    final table = Table([
      ['Odd', 'Even'],
      ['x', 'xy'],
      ['', ''],
      ['12345'],
    ], columnAlignments: [
      ColumnAlignment.center,
      ColumnAlignment.center
    ]);

    expect(
      formatMarkdown(table),
      '|  Odd  | Even  |\n'
      '| :---: | :---: |\n'
      '|   x   |  xy   |\n'
      '|       |       |\n'
      '| 12345 |       |',
    );
  });

  test('right alignment pads Unicode by display width, not string length', () {
    final table = Table([
      ['CJK', 'Emoji', 'Mark'],
      ['李明', '👩🏽‍💻', 'e\u0301'],
      ['', '', ''],
    ], columnAlignments: [
      ColumnAlignment.right,
      ColumnAlignment.right,
      ColumnAlignment.right,
    ]);

    expect(
      formatMarkdown(table),
      '|  CJK | Emoji | Mark |\n'
      '| ---: | ----: | ---: |\n'
      '| 李明 |    👩🏽‍💻 |    e\u0301 |\n'
      '|      |       |      |',
    );
  });

  test('header-only Markdown retains column alignment', () {
    final table = Table([
      ['A', 'B', 'C', 'D'],
    ], columnAlignments: alignments);

    final reparsed = parseTable(formatMarkdown(table));
    expect(reparsed.rows, table.rows);
    expect(reparsed.columnAlignments, alignments);
  });

  test('Markdown previews retain alignment through resizing and shortening',
      () {
    final table = Table([
      ['A', 'B', 'C', 'D'],
      ['longest value', 'b', 'c', 'd'],
      ['a', 'b', 'c', 'd'],
    ], columnAlignments: alignments);
    final session = tableFormats.prepare(table, outputFormat: 'markdown');
    const limits =
        PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 200);
    final preview =
        session.preview(maxRows: 2, maxColumns: 3, textLimits: limits);

    expect(preview.text.split('\n')[1], '| ---- | :--- | :---: |');
    expect(preview.text, contains('lon…'));
    expect(session.preview(maxRows: 2, maxColumns: 3, textLimits: limits),
        same(preview));
    expect(session.preview(maxRows: 1, maxColumns: 2).text.split('\n')[1],
        '| --- | :--- |');
    expect(session.fullText, formatMarkdown(table));
    expect(session.fullText, contains('longest value'));
    expect(parseTable(session.fullText).columnAlignments, alignments);
    expect(session.preview(maxRows: 3, maxColumns: 4).text, session.fullText);
    expect(table.rows[1][0], 'longest value');
  });

  test('switching destinations retains the original column semantics', () {
    final table = parseTable(source);
    final markdown = tableFormats.prepare(table, outputFormat: 'markdown');
    final original = markdown.fullText;
    final slack = tableFormats.prepare(table, outputFormat: 'slack');

    expect(slack.preview(maxRows: 1, maxColumns: 2).text, 'A\tB');
    expect(slack.fullText, 'A\tB\tC\tD\na\tb\tc\td');
    expect(table.columnAlignments, alignments);
    expect(tableFormats.prepare(table, outputFormat: 'markdown').fullText,
        original);
  });

  test('preview shortening and full output each align their own rectangle', () {
    final table = Table([
      ['C', 'R'],
      ['abcdef', '123456'],
      ['x', '7'],
    ], columnAlignments: [
      ColumnAlignment.center,
      ColumnAlignment.right
    ]);
    final session = tableFormats.prepare(table, outputFormat: 'markdown');
    const limits =
        PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 200);
    final preview =
        session.preview(maxRows: 3, maxColumns: 2, textLimits: limits);

    expect(
      preview.text,
      '|   C   |    R |\n'
      '| :---: | ---: |\n'
      '| abc…  | 123… |\n'
      '|   x   |    7 |',
    );
    expect(session.preview(maxRows: 2, maxColumns: 1, textLimits: limits).text,
        '|   C   |\n| :---: |\n| abc…  |');
    expect(
      session.fullText,
      '|   C    |      R |\n'
      '| :----: | -----: |\n'
      '| abcdef | 123456 |\n'
      '|   x    |      7 |',
    );
    expect(session.preview(maxRows: 3, maxColumns: 2).text, session.fullText);
    expect(preview.text, contains('abc…'));
    expect(parseTable(session.fullText).rows, table.rows);
  });
}
