import 'dart:convert';

import 'package:table_table/table_table.dart';
import 'package:table_table/src/delimited_format_session.dart';
import 'package:test/test.dart';

void main() {
  test('readers preserve decoded content and writers prepare the original', () {
    const source = 'ID,Note\r\n001,"  hello\tworld\r\n""again""  "\r\n,\r\n';
    final parsed = tableFormats.parse(source);
    expect(parsed.format.id, 'csv');
    expect(parsed.table.rows, [
      ['ID', 'Note'],
      ['001', '  hello\tworld\r\n"again"  '],
      ['', ''],
    ]);
    final session = tableFormats.prepare(parsed.table, outputFormat: 'slack');
    expect(session.preview(maxRows: 2, maxColumns: 2).table!.rows[1],
        ['001', 'hello world "again"']);
    expect(session.fullText, 'ID\tNote\n001\thello world "again"\n\t');
    expect(formatMarkdown(parsed.table), contains('hello world "again"'));
    expect(parsed.table.rows[1][1], '  hello\tworld\r\n"again"  ');
  });

  test('the immutable model pads once without cleaning or dropping empty rows',
      () {
    final rows = [
      [' A ', 'B'],
      <String>[],
      ['001']
    ];
    final table = Table(rows);
    rows.first[0] = 'changed';
    rows.add(['added']);
    expect(table.rows, [
      [' A ', 'B'],
      ['', ''],
      ['001', '']
    ]);
    expect(() => table.rows.add(['new']), throwsUnsupportedError);
    expect(() => table.rows.first[0] = 'changed', throwsUnsupportedError);
  });

  test(
      'delimited readers interpret record endings without changing quoted text',
      () {
    for (final format in ['csv', 'tsv']) {
      final delimiter = format == 'csv' ? ',' : '\t';
      for (final ending in ['\n', '\r', '\r\n']) {
        const cell = '  001\r\n\t A  B\rC\n"D"  ';
        final encoded = cell.replaceAll('"', '""');
        final table = parseTable(
            '$ending"ID"${delimiter}Note$ending'
            '"$encoded"${delimiter}end$ending$delimiter$ending',
            inputFormat: format);
        expect(table.rows, [
          ['ID', 'Note'],
          [cell, 'end'],
          ['', '']
        ]);
      }
    }
  });

  test(
      'text readers remove delimiter padding without collapsing interior spaces',
      () {
    for (final format in ['markdown', 'pipe', 'spaced']) {
      final source = switch (format) {
        'markdown' => '| A  B | C |\n| --- | --- |\n| 001 | x\ty |',
        'pipe' => ' A  B | C \n 001 | x\ty ',
        _ => ' A  B \n\n C \n\n 001 \n\n x\ty ',
      };
      final parsed = tableFormats.parse(source, inputFormat: format);
      expect(parsed.table.rows, [
        ['A  B', 'C'],
        ['001', 'x\ty']
      ]);
      expect(formatTsv(parsed.table), 'A B\tC\n001\tx y');
    }
  });

  test('delimited sessions are lazy and retain only the latest rectangle', () {
    final visits = <String>[];
    final session = _counted(visits);
    expect(visits, isEmpty);
    final first = session.preview(maxRows: 1, maxColumns: 2);
    expect(first.text, 'A\tB');
    expect(visits, ['a', 'b']);
    expect(session.preview(maxRows: 1, maxColumns: 2), same(first));
    session.preview(maxRows: 2, maxColumns: 1);
    expect(visits, ['a', 'b', 'd']);
    session.preview(maxRows: 2, maxColumns: 2);
    expect(visits, ['a', 'b', 'd', 'b', 'e']);
    expect(first.table!.rows, [
      ['A', 'B']
    ]);
    visits.clear();
    expect(session.fullText, 'A\tB\tC\nD\tE\tF\nG\tH\tI');
    expect(visits, ['c', 'f', 'g', 'h', 'i']);
    session.fullText;
    expect(visits.length, 5);
    visits.clear();
    session.preview(maxRows: 3, maxColumns: 3);
    expect(visits, ['c', 'f', 'g', 'h', 'i']);
  });

  test('full-first rendering does no preview work and caches its string', () {
    final visits = <String>[];
    final session = _counted(visits);
    final full = session.fullText;
    expect(visits, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']);
    expect(session.fullText, same(full));
    visits.clear();
    session.preview(maxRows: 1, maxColumns: 1);
    expect(visits, ['a']);
  });

  test('text budgets change only visible cells and keep the unshortened cache',
      () {
    final visits = <String>[];
    final session = DelimitedFormatSession(
      Table([
        ['abcdef', '👩🏽‍💻👩🏽‍💻'],
        ['last', 'value']
      ]),
      prepareCell: (cell) {
        visits.add(cell);
        return cell;
      },
      columnSeparator: '\t',
      rowSeparator: '\n',
      showGrid: true,
    );
    const limits = PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 16);
    final preview =
        session.preview(maxRows: 2, maxColumns: 2, textLimits: limits);
    expect(preview.table!.rows, [
      ['abc…', '…'],
      ['last', 'val…']
    ]);
    expect(preview.textShortened, isTrue);
    expect(preview.isLimited, isTrue);
    expect(session.preview(maxRows: 2, maxColumns: 2, textLimits: limits),
        same(preview));
    expect(session.fullText, 'abcdef\t👩🏽‍💻👩🏽‍💻\nlast\tvalue');
    expect(visits.length, 4);
    final complete = session.preview(maxRows: 2, maxColumns: 2);
    expect(complete.textShortened, isFalse);
    expect(complete.text, session.fullText);
    expect(visits.length, 4);
    expect(preview.table!.rows.first.first, 'abc…');
  });

  test('Markdown shortens before escaping and never copies shortened layout',
      () {
    final table = Table([
      ['x|x|x|x', 'B'],
      ['李明👩🏽‍💻' * 10, 'last']
    ]);
    final session = tableFormats.prepare(table, outputFormat: 'markdown');
    const limits = PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 80);
    final preview =
        session.preview(maxRows: 2, maxColumns: 2, textLimits: limits);
    expect(preview.text, contains(r'x\|x…'));
    expect(preview.text, contains('李明…'));
    expect(preview.text.length, lessThanOrEqualTo(80));
    expect(session.fullText, formatMarkdown(table));
    expect(session.fullText, isNot(contains('…')));
    expect(session.preview(maxRows: 2, maxColumns: 2, textLimits: limits),
        same(preview));
    expect(session.preview(maxRows: 2, maxColumns: 2).text, session.fullText);
  });

  test('encoded fields are reused for full output after shortening a preview',
      () {
    final encoded = <String>[];
    final session = DelimitedFormatSession(
      Table([
        ['abcdef', 'xy'],
        ['other', 'last'],
      ]),
      prepareCell: (cell) => cell.toUpperCase(),
      encodeCell: (cell) {
        encoded.add(cell);
        return jsonEncode(cell);
      },
      columnSeparator: '\t',
      rowSeparator: '\n',
      showGrid: false,
    );
    final preview = session.preview(
        maxRows: 1,
        maxColumns: 2,
        textLimits:
            const PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 8));
    expect(preview.text, '"ABC…"\t"XY"');
    expect(encoded, ['ABCDEF', 'XY', 'ABC…']);
    expect(session.fullText, '"ABCDEF"\t"XY"\n"OTHER"\t"LAST"');
    expect(encoded, ['ABCDEF', 'XY', 'ABC…', 'OTHER', 'LAST']);
    session.fullText;
    session.preview(maxRows: 1, maxColumns: 2);
    expect(encoded, ['ABCDEF', 'XY', 'ABC…', 'OTHER', 'LAST']);
  });

  test('wrapped detection and TSV share a scan only within one conversion', () {
    final observed = <List<List<String>>>[];
    final wrapped =
        tableFormats.inputs.singleWhere((format) => format.id == 'cursor');
    final tsv = tableFormats.inputs.singleWhere((format) => format.id == 'tsv');
    InputFormat counted(InputFormat input) => InputFormat(
          id: input.id,
          label: input.label,
          read: input.read,
          readInContext: (source) {
            observed.add(source.tabRows);
            return input.readInContext!(source);
          },
        );
    final registry = FormatRegistry(
        inputs: [counted(wrapped), counted(tsv)],
        outputs: [],
        detectionOrder: ['cursor', 'tsv']);
    expect(registry.parse('A\tB\nx\ty').format.id, 'tsv');
    expect(observed, hasLength(2));
    expect(observed[0], same(observed[1]));
    registry.parse('A\tB\nx\ty');
    expect(observed[2], isNot(same(observed[0])));
    expect(observed[2], same(observed[3]));
  });

  test('previews clamp dimensions and validate limits without preparing cells',
      () {
    final visits = <String>[];
    final session = _counted(visits);
    for (final limits in [(0, 1), (1, 0), (-1, 1), (1, -1)]) {
      expect(() => session.preview(maxRows: limits.$1, maxColumns: limits.$2),
          throwsRangeError);
    }
    expect(visits, isEmpty);
    final preview = session.preview(maxRows: 100, maxColumns: 100);
    expect(preview.isLimited, isFalse);
    expect(session.preview(maxRows: 3, maxColumns: 3), same(preview));
    expect(session.fullText, same(preview.text));
    expect(visits.length, 9);
  });

  test('Markdown prepares escaped cells and measures each requested subset',
      () {
    final table = Table([
      [' A|李 ', 'B'],
      ['x', '  one\n two  '],
      ['longest value', 'end'],
    ]);
    final session = tableFormats.prepare(table, outputFormat: 'markdown');
    final preview = session.preview(maxRows: 2, maxColumns: 1);
    expect(preview.table, isNull);
    expect(preview.text, '| A\\|李 |\n| ----- |\n| x     |');
    expect(session.preview(maxRows: 2, maxColumns: 1), same(preview));
    expect(session.fullText, formatMarkdown(table));
    expect(session.fullText, contains('one two'));
    expect(table.rows.first.first, ' A|李 ');
  });

  test('catalog validates registration and explicit reads never fall through',
      () {
    final registry = FormatRegistry(
      inputs: tableFormats.inputs,
      outputs: tableFormats.outputs,
      detectionOrder: ['csv', 'spaced'],
    );
    const cells = 'A\n\nB\n\nC\n\n1\n\n2\n\n3';
    expect(() => registry.parse(cells), throwsA(isA<AmbiguousColumnsError>()));
    expect(registry.parse(cells, columns: 3).format.id, 'spaced');
    expect(() => registry.parse(cells, inputFormat: 'csv'),
        throwsA(isA<ParseError>()));
    expect(() => registry.parse(cells, inputFormat: 'unknown'),
        throwsA(isA<ParseError>()));
    expect(
        () => registry.prepare(
            Table([
              ['x']
            ]),
            outputFormat: 'unknown'),
        throwsA(isA<ParseError>()));
    for (final order in [
      ['missing'],
      ['csv', 'csv']
    ]) {
      expect(
          () => FormatRegistry(
              inputs: tableFormats.inputs,
              outputs: tableFormats.outputs,
              detectionOrder: order),
          throwsArgumentError);
    }
    expect(
        () => FormatRegistry(
            inputs: [tableFormats.inputs.first, tableFormats.inputs.first],
            outputs: tableFormats.outputs,
            detectionOrder: []),
        throwsArgumentError);
    expect(() => registry.inputs.clear(), throwsUnsupportedError);
  });

  test('unexpected reader failures propagate', () {
    final registry = FormatRegistry(inputs: [
      InputFormat(
          id: 'broken',
          label: 'Broken',
          read: (text, {columns}) => throw StateError('bug'))
    ], outputs: [], detectionOrder: [
      'broken'
    ]);
    expect(() => registry.parse('x'), throwsStateError);
  });
}

DelimitedFormatSession _counted(List<String> visits) => DelimitedFormatSession(
      Table([
        ['a', 'b', 'c'],
        ['d', 'e', 'f'],
        ['g', 'h', 'i']
      ]),
      prepareCell: (cell) {
        visits.add(cell);
        return cell.toUpperCase();
      },
      columnSeparator: '\t',
      rowSeparator: '\n',
      showGrid: true,
    );
