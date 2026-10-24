import 'package:table_table/slack_table.dart';
import 'package:test/test.dart';

void main() {
  test('every advertised input format has a working parser', () {
    const examples = {
      InputFormats.auto: 'A,B\n1,2',
      InputFormats.markdown: '| A | B |\n| --- | --- |\n| 1 | 2 |',
      InputFormats.cursor: 'A\tB\tC\n1\n2\n3',
      InputFormats.csv: 'A,B\n1,2',
      InputFormats.tsv: 'A\tB\n1\t2',
      InputFormats.pipe: 'A|B\n1|2',
      InputFormats.spaced: 'A\n\nB\n\n1\n\n2',
    };
    expect(InputFormats.values, unorderedEquals(examples.keys));
    for (final format in InputFormats.values) {
      final table = parseTable(examples[format]!, inputFormat: format);
      expect(table.sourceFormat,
          format == InputFormats.auto ? InputFormats.csv : format);
      expect(table.rows.length, 2, reason: format);
    }
  });

  test('every advertised output format has a working formatter', () {
    final table = Table([
      ['A', 'B'],
      ['1', '2'],
    ]);
    const expected = {
      OutputFormats.slack: 'A\tB\n1\t2',
      OutputFormats.markdown: '| A   | B   |\n| --- | --- |\n| 1   | 2   |',
    };
    expect(OutputFormats.values, unorderedEquals(expected.keys));
    for (final format in OutputFormats.values) {
      expect(formatTable(table, outputFormat: format), expected[format]);
    }
  });
}
