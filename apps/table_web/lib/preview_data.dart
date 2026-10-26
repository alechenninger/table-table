import 'dart:math' as math;

import 'package:table_table/table_table.dart' as tables;

import 'conversion.dart';

/// A bounded presentation of a conversion. Copying uses the conversion itself.
final class PreviewData {
  static const maxDataRows = 50;
  static const maxColumns = 20;
  static const maxCellCodeUnits = 256;
  static const maxTextCodeUnits = 20000;

  final List<List<String>> rows;
  final String? text;
  final bool isMarkdown;

  final int totalDataRows;
  final int totalColumns;
  final int shownDataRows;
  final int shownColumns;
  final bool textShortened;

  factory PreviewData.fromConversion(ReadyConversion conversion, String outputFormat) {
    final preview = conversion.formatted.preview(
      maxRows: maxDataRows + 1,
      maxColumns: maxColumns,
      textLimits: const tables.PreviewTextLimits(
        maxCellCodeUnits: maxCellCodeUnits,
        maxTextCodeUnits: maxTextCodeUnits,
      ),
    );
    final rows = preview.table?.rows ?? const <List<String>>[];
    final totalDataRows = preview.totalRows - 1;
    final totalColumns = preview.totalColumns;
    final shownDataRows = math.max(0, preview.shownRows - 1);
    final shownColumns = preview.shownColumns;
    final textShortened = preview.textShortened;
    final text = preview.table == null ? preview.text : null;
    return PreviewData._(
      rows: rows,
      text: text,
      isMarkdown: outputFormat == tables.OutputFormats.markdown,
      totalDataRows: totalDataRows,
      totalColumns: totalColumns,
      shownDataRows: shownDataRows,
      shownColumns: shownColumns,
      textShortened: textShortened,
    );
  }

  const PreviewData._({
    required this.rows,
    required this.text,
    required this.isMarkdown,
    required this.totalDataRows,
    required this.totalColumns,
    required this.shownDataRows,
    required this.shownColumns,
    required this.textShortened,
  });

  String? get markdown => isMarkdown ? text : null;

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
