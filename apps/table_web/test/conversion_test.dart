import 'package:jaspr_test/jaspr_test.dart';
import 'package:table_table/table_table.dart' as tables;
import 'package:table_table/src/delimited_format_session.dart';
import 'package:table_table_web/conversion.dart';
import 'package:table_table_web/preview_data.dart';

void main() {
  test('conversion retains its lazy session through previews and repeated copy reads', () {
    final table = tables.Table([
      for (var row = 0; row < 100; row++) ['r$row', 'value'],
    ]);
    var visits = 0;
    final session = DelimitedFormatSession(
      table,
      prepareCell: (cell) {
        visits++;
        return cell;
      },
      columnSeparator: '\t',
      rowSeparator: '\n',
      showGrid: true,
    );
    final conversion = ReadyConversion(table: table, formatted: session, outputFormat: 'slack');
    expect(visits, 0);
    PreviewData.fromConversion(conversion, 'slack');
    expect(visits, 102);
    expect(conversion.withOutputFormat('slack'), same(conversion));
    expect(conversion.output, endsWith('r99\tvalue'));
    expect(visits, 200);
    conversion.output;
    expect(visits, 200);
  });

  test('destination previews clean preserved cells without changing the source', () {
    final conversion =
        Conversion.fromInput(
              'A,B\n001,"  one\t two\nthree  "',
              inputFormat: 'csv',
              outputFormat: 'slack',
            )
            as ReadyConversion;
    final preview = PreviewData.fromConversion(conversion, 'slack');
    expect(preview.rows[1], ['001', 'one two three']);
    expect(conversion.table.rows[1][1], '  one\t two\nthree  ');
    final markdown = conversion.withOutputFormat('markdown') as ReadyConversion;
    expect(PreviewData.fromConversion(markdown, 'markdown').markdown, contains('one two three'));
    expect(markdown.table, same(conversion.table));
  });

  test('input distinguishes empty, invalid, ambiguous, and ready results', () {
    expect(_convert(' \n '), isA<EmptyConversion>());
    expect(_convert('not a table'), isA<InvalidConversion>());
    expect(_convert('A,B\n1,2'), isA<ReadyConversion>());
    final ambiguous = _convert('A\n\nB\n\nC\n\n1\n\n2\n\n3') as AmbiguousConversion;
    expect(ambiguous.candidates, [2, 3]);
  });

  test('output changes reuse the parsed table and preserve column choices', () {
    final original = _convert('A\n\nB\n\nC\n\n1\n\n2\n\n3', columns: 3) as ReadyConversion;
    final markdown = original.withOutputFormat('markdown') as ReadyConversion;
    expect(markdown.table, same(original.table));
    expect(markdown.candidates, [2, 3]);
    expect(markdown.output, '| A   | B   | C   |\n| --- | --- | --- |\n| 1   | 2   | 3   |');
    final slack = markdown.withOutputFormat('slack') as ReadyConversion;
    expect(slack.table, same(original.table));
    expect(slack.output, 'A\tB\tC\n1\t2\t3');
    expect(original.output, slack.output);
  });

  test('conversion from a table retains its identity across output changes', () {
    final table = tables.parseTable(
      '<table><tr><th>A</th><th>B</th></tr>'
      '<tr><td><p>one</p><p>two</p></td><td>end</td></tr></table>',
    );
    final conversion = Conversion.fromTable(table, outputFormat: 'slack') as ReadyConversion;
    expect(conversion.table, same(table));
    expect(conversion.output, 'A\tB\none two\tend');
    final markdown = conversion.withOutputFormat('markdown') as ReadyConversion;
    expect(markdown.table, same(table));
    expect(markdown.output, tables.formatMarkdown(table));
  });

  test('invalid output formats produce an invalid conversion from a table', () {
    expect(
      Conversion.fromTable(tables.parseTable('A,B\nx,y'), outputFormat: 'invalid'),
      isA<InvalidConversion>(),
    );
  });

  test('output changes preserve unresolved input states', () {
    for (final input in ['', 'not a table', 'A\n\nB\n\nC\n\n1\n\n2\n\n3']) {
      final conversion = _convert(input);
      expect(conversion.withOutputFormat('markdown'), same(conversion));
    }
  });

  test('an unavailable column count keeps the choice unresolved', () {
    final conversion = _convert('A\n\nB\n\nC\n\n1\n\n2\n\n3', columns: 4);
    expect(conversion, isA<AmbiguousConversion>());
    expect((conversion as AmbiguousConversion).candidates, [2, 3]);
  });
}

Conversion _convert(String input, {int? columns}) => Conversion.fromInput(
  input,
  inputFormat: 'auto',
  outputFormat: 'slack',
  columns: columns,
);
