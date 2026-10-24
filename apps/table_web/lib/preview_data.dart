import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:table_table/slack_table.dart' as tables;

import 'conversion.dart';

/// A bounded presentation of a conversion. Copying uses the conversion itself.
final class PreviewData {
  static const maxDataRows = 50;
  static const maxColumns = 20;
  static const maxCellCodeUnits = 256;
  static const maxTextCodeUnits = 20000;

  final List<List<String>> rows;
  final String? markdown;
  final int totalDataRows;
  final int totalColumns;
  final int shownDataRows;
  final int shownColumns;
  final bool textShortened;

  factory PreviewData.fromConversion(ReadyConversion conversion, String outputFormat) {
    final table = conversion.table;
    final totalDataRows = table.rows.length - 1;
    final totalColumns = table.rows.first.length;
    var shownDataRows = math.min(totalDataRows, maxDataRows);
    final shownColumns = math.min(totalColumns, maxColumns);
    var remainingCells = (shownDataRows + 1) * shownColumns;
    var remainingText = maxTextCodeUnits;
    var textShortened = false;
    final rows = <List<String>>[];
    for (final row in table.rows.take(shownDataRows + 1)) {
      final cells = <String>[];
      for (final cell in row.take(shownColumns)) {
        remainingCells--;
        // Reserve one character for every remaining cell, so omitted content
        // can always be represented by an ellipsis within the total budget.
        final allowance = math.min(maxCellCodeUnits, remainingText - remainingCells);
        final value = _shorten(cell, allowance);
        textShortened |= value.length != cell.length;
        remainingText -= value.length;
        cells.add(value);
      }
      rows.add(List.unmodifiable(cells));
    }

    String? markdown;
    if (outputFormat == tables.OutputFormats.markdown) {
      final limited = shownDataRows < totalDataRows || shownColumns < totalColumns || textShortened;
      // Small tables already have their exact formatted source. Only a limited
      // preview needs formatting again, with widths based on its visible cells.
      markdown = limited ? tables.formatMarkdown(tables.Table(rows)) : conversion.output;
      if (markdown.length > maxTextCodeUnits) {
        final prefix = markdown.substring(0, maxTextCodeUnits);
        final lastLine = prefix.lastIndexOf('\n');
        markdown = lastLine < 0
            ? _shorten(markdown, maxTextCodeUnits)
            : prefix.substring(0, lastLine);
        shownDataRows = math.max(0, markdown.split('\n').length - 2);
        rows.removeRange(shownDataRows + 1, rows.length);
        textShortened = true;
      }
    }
    return PreviewData._(
      rows: List.unmodifiable(rows),
      markdown: markdown,
      totalDataRows: totalDataRows,
      totalColumns: totalColumns,
      shownDataRows: shownDataRows,
      shownColumns: shownColumns,
      textShortened: textShortened,
    );
  }

  const PreviewData._({
    required this.rows,
    required this.markdown,
    required this.totalDataRows,
    required this.totalColumns,
    required this.shownDataRows,
    required this.shownColumns,
    required this.textShortened,
  });

  bool get isLimited =>
      shownDataRows < totalDataRows || shownColumns < totalColumns || textShortened;

  String get notice => [
    if (shownDataRows < totalDataRows)
      'Showing the first $shownDataRows of $totalDataRows data rows.',
    if (shownColumns < totalColumns) 'Showing the first $shownColumns of $totalColumns columns.',
    if (textShortened) 'Some preview text is shortened.',
    'Copy includes the entire table.',
  ].join(' ');
}

String _shorten(String value, int limit) {
  if (value.length <= limit) return value;
  var end = limit;
  final last = value.codeUnitAt(end - 1);
  final next = value.codeUnitAt(end);
  if (last >= 0xd800 && last <= 0xdbff && next >= 0xdc00 && next <= 0xdfff) {
    end--;
  }
  // Segment only a bounded prefix, and discard its last (possibly incomplete)
  // grapheme. Finish on a code-point boundary first, so an incomplete surrogate
  // cannot hide a preceding partial ZWJ sequence in a separate grapheme.
  if (end == 0) return '…';
  return '${value.substring(0, end).characters.skipLast(1)}…';
}
