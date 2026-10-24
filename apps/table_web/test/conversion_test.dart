import 'package:jaspr_test/jaspr_test.dart';
import 'package:table_table_web/conversion.dart';

void main() {
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
