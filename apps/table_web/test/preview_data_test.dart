import 'package:characters/characters.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:table_table/slack_table.dart' as tables;
import 'package:table_table_web/conversion.dart';
import 'package:table_table_web/preview_data.dart';

void main() {
  test('small previews preserve cells and exact Markdown source', () {
    for (final format in tables.OutputFormats.values) {
      final conversion = _conversion([
        ['Owner', 'Status'],
        ['李明', '👩🏽‍💻'],
      ], format);
      final preview = PreviewData.fromConversion(conversion, format);
      expect(preview.rows, conversion.table.rows);
      expect(preview.isLimited, isFalse);
      expect(preview.totalDataRows, 1);
      expect(preview.totalColumns, 2);
      if (format == 'markdown') expect(preview.markdown, conversion.output);
    }
  });

  test('wide and tall previews are bounded without changing the conversion', () {
    for (final format in tables.OutputFormats.values) {
      final conversion = _conversion([
        for (var row = 0; row < 76; row++) [for (var col = 0; col < 25; col++) 'r$row-c$col'],
      ], format);
      final output = conversion.output;
      final preview = PreviewData.fromConversion(conversion, format);
      expect(preview.rows.length, PreviewData.maxDataRows + 1);
      expect(preview.rows.every((r) => r.length == PreviewData.maxColumns), isTrue);
      expect(preview.shownDataRows, 50);
      expect(preview.totalDataRows, 75);
      expect(preview.shownColumns, 20);
      expect(preview.totalColumns, 25);
      expect(preview.isLimited, isTrue);
      expect(preview.notice, contains('first 50 of 75 data rows'));
      expect(preview.notice, contains('first 20 of 25 columns'));
      expect(conversion.output, output);
      expect(conversion.table.rows.last.last, 'r75-c24');
    }
  });

  test('cell and total text budgets retain markers for shortened content', () {
    final conversion = _conversion([
      for (var row = 0; row <= 50; row++) [for (var col = 0; col < 20; col++) 'x' * 1000],
    ], 'slack');
    final preview = PreviewData.fromConversion(conversion, 'slack');
    final cells = preview.rows.expand((row) => row);
    expect(
      cells.fold<int>(0, (total, cell) => total + cell.length),
      lessThanOrEqualTo(PreviewData.maxTextCodeUnits),
    );
    expect(cells.every((c) => c.isNotEmpty && c.length <= PreviewData.maxCellCodeUnits), isTrue);
    expect(cells.every((c) => c.endsWith('…')), isTrue);
    expect(preview.textShortened, isTrue);
  });

  test('shortening keeps emoji and combining sequences intact', () {
    for (final character in ['👩🏽‍💻', '🇯🇵', 'e\u0301', '👨‍👩‍👧‍👦']) {
      for (var offset = 0; offset < character.length; offset++) {
        final preview = PreviewData.fromConversion(
          _conversion([
            ['A', 'B'],
            ['${'x' * offset}${character * 500}', 'y'],
          ], 'slack'),
          'slack',
        );
        final shortened = preview.rows[1][0];
        expect(shortened.endsWith('…'), isTrue);
        expect(
          shortened
              .substring(0, shortened.length - 1)
              .characters
              .every((c) => c == character || c == 'x'),
          isTrue,
          reason: '$character at offset $offset',
        );
      }
    }
    final preview = PreviewData.fromConversion(
      _conversion([
        ['A', 'B'],
        ['a${'\u0301' * 10000}', 'x'],
      ], 'slack'),
      'slack',
    );
    expect(preview.rows[1][0], '…');
  });

  test('Markdown padding is also capped and reports the actual shown rows', () {
    final conversion = _conversion([
      [for (var col = 0; col < 20; col++) 'x' * 256],
      for (var row = 0; row < 50; row++) [for (var col = 0; col < 20; col++) 'y'],
    ], 'markdown');
    expect(conversion.output.length, greaterThan(PreviewData.maxTextCodeUnits));
    final preview = PreviewData.fromConversion(conversion, 'markdown');
    expect(preview.markdown!.length, lessThanOrEqualTo(PreviewData.maxTextCodeUnits));
    expect(preview.markdown!.split('\n').length, preview.shownDataRows + 2);
    expect(
      preview.markdown!.split('\n').every((line) => line.startsWith('|') && line.endsWith('|')),
      isTrue,
    );
    expect(preview.rows.length, preview.shownDataRows + 1);
    expect(preview.shownDataRows, lessThan(50));
    expect(preview.textShortened, isTrue);
  });
}

ReadyConversion _conversion(List<List<String>> rows, String format) {
  final table = tables.Table(rows);
  return ReadyConversion(
    table: table,
    output: tables.formatTable(table, outputFormat: format),
  );
}
