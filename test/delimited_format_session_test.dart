import 'package:table_table/table_table.dart';
import 'package:table_table/src/delimited_format_session.dart';
import 'package:test/test.dart';

void main() {
  test('CSV preview shortens cell content before quoting and escaping', () {
    for (final (source, shortened, encoded) in [
      ('abcdef', 'abc…', '"abc…","x"'),
      ('ab"cdef', 'ab"…', '"ab""…","x"'),
      ('a,bcdef', 'a,b…', '"a,b…","x"'),
      ('a\nbcdef', 'a\nb…', '"a\nb…","x"'),
    ]) {
      final table = Table([
        [source, 'x'],
      ]);
      final csv = _session(table);
      const limits =
          PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 8);
      final preview =
          csv.preview(maxRows: 1, maxColumns: 2, textLimits: limits);
      expect(preview.text, encoded, reason: source);
      expect(preview.textShortened, isTrue);
      expect(parseTable(preview.text, inputFormat: 'csv').rows, [
        [shortened, 'x'],
      ]);
      expect(csv.preview(maxRows: 1, maxColumns: 2, textLimits: limits),
          same(preview));
      final full = '"${source.replaceAll('"', '""')}","x"';
      expect(csv.fullText, full);
      expect(csv.preview(maxRows: 1, maxColumns: 2).text, full);
      expect(preview.text, encoded);
      expect(table.rows.first, [source, 'x']);
    }
  });

  test('CSV content budgets exclude quotes and leave full output unshortened',
      () {
    final table = Table([
      ['abcdef', 'ghijkl'],
    ]);
    final csv = _session(table);
    const limits = PreviewTextLimits(maxCellCodeUnits: 4, maxTextCodeUnits: 6);
    final full = csv.fullText;
    final preview = csv.preview(maxRows: 1, maxColumns: 2, textLimits: limits);
    expect(preview.text, '"abc…","g…"');
    expect(parseTable(preview.text, inputFormat: 'csv').rows, [
      ['abc…', 'g…'],
    ]);
    expect(csv.fullText, same(full));
    expect(full, '"abcdef","ghijkl"');

    final short = _session(Table([
      ['ab"', 'x'],
    ]));
    final unshortened = short.preview(
        maxRows: 1,
        maxColumns: 2,
        textLimits:
            const PreviewTextLimits(maxCellCodeUnits: 3, maxTextCodeUnits: 4));
    expect(unshortened.text, '"ab""","x"');
    expect(unshortened.textShortened, isFalse);
    expect(short.fullText, same(unshortened.text));
  });
}

// Quoted fields let the independent CSV reader verify delimiter boundaries.
DelimitedFormatSession _session(Table table) => DelimitedFormatSession(
      table,
      prepareCell: (cell) => cell,
      encodeCell: _quoteField,
      columnSeparator: ',',
      rowSeparator: '\r\n',
      showGrid: false,
    );

String _quoteField(String cell) => '"${cell.replaceAll('"', '""')}"';
