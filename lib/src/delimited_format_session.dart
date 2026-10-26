import 'dart:math' as math;

import 'formats.dart';
import 'table.dart';
import 'preview_text.dart';

/// Shared lazy mechanics for outputs whose cells can be prepared independently.
///
/// The destination supplies pure cell preparation, optional encoding, and its
/// separators. Preview shortening happens between preparation and encoding.
/// Only the last requested preview rectangle retains prepared cells. Full
/// rendering uses that cache without growing it and retains just the final
/// string. Formats with global layout, such as Markdown, need their own session.
final class DelimitedFormatSession implements FormattedTable {
  final Table _table;
  final String Function(String) _prepareCell;
  final String Function(String)? _encodeCell;
  final String _columnSeparator;
  final String _rowSeparator;
  final bool _showGrid;
  _PreparedPreview? _lastPreview;
  String? _fullText;

  /// Create a lazy session. [prepareCell] performs cleanup without escaping;
  /// [encodeCell] adds field syntax after any preview shortening.
  DelimitedFormatSession(
    Table table, {
    required String Function(String) prepareCell,
    String Function(String)? encodeCell,
    required String columnSeparator,
    required String rowSeparator,
    required bool showGrid,
  })  : _table = table,
        _prepareCell = prepareCell,
        _encodeCell = encodeCell,
        _columnSeparator = columnSeparator,
        _rowSeparator = rowSeparator,
        _showGrid = showGrid;

  @override
  String get fullText => _fullText ??= _renderFull();

  @override
  OutputPreview preview(
      {required int maxRows,
      required int maxColumns,
      PreviewTextLimits? textLimits}) {
    if (maxRows < 1) throw RangeError.range(maxRows, 1, null, 'maxRows');
    if (maxColumns < 1) {
      throw RangeError.range(maxColumns, 1, null, 'maxColumns');
    }
    final rowCount = math.min(maxRows, _table.rows.length);
    final columnCount = math.min(maxColumns, _table.rows.first.length);
    final previous = _lastPreview;
    if (previous != null &&
        previous.result.shownRows == rowCount &&
        previous.result.shownColumns == columnCount &&
        previous.textLimits == textLimits) {
      return previous.result;
    }

    final cells = Table([
      for (var row = 0; row < rowCount; row++)
        _prepareRow(row, columnCount, previous),
    ]);
    final budget = textLimits == null
        ? null
        : PreviewTextBudget(textLimits, rowCount * columnCount);
    final visible = budget == null
        ? cells
        : Table([
            for (var row = 0; row < rowCount; row++)
              [
                for (var column = 0; column < columnCount; column++)
                  _previewCell(_table.rows[row][column],
                      cells.rows[row][column], budget),
              ],
          ]);
    final result = OutputPreview(
      text: visible.rows
          .map((row) => row.join(_columnSeparator))
          .join(_rowSeparator),
      table: _showGrid ? visible : null,
      textShortened: budget?.shortened ?? false,
      shownRows: rowCount,
      shownColumns: columnCount,
      totalRows: _table.rows.length,
      totalColumns: _table.rows.first.length,
    );
    // Replace rather than accumulate rectangles. Values here are unshortened;
    // ellipses introduced by a frontend must never enter the full-text cache.
    // Recomputing evicted cells on expansion keeps retention bounded.
    _lastPreview = _PreparedPreview(cells, result, textLimits);
    return result;
  }

  String _renderFull() {
    final cached = _lastPreview;
    if (cached != null && !cached.result.isLimited) {
      return cached.result.text;
    }
    // Reuse cells rather than append preview bytes: omitted columns belong
    // inside each row.
    final output = StringBuffer();
    for (var row = 0; row < _table.rows.length; row++) {
      if (row > 0) output.write(_rowSeparator);
      // Only one row of new prepared cells is temporary; full rendering never
      // populates the preview cache or creates another complete table.
      output.write(_prepareRow(row, _table.rows[row].length, cached)
          .join(_columnSeparator));
    }
    return output.toString();
  }

  List<String> _prepareRow(int row, int columns, _PreparedPreview? cached) {
    final previous = cached != null && row < cached.cells.rows.length
        ? cached.cells.rows[row]
        : const <String>[];
    final source = _table.rows[row];
    return [
      for (var column = 0; column < columns; column++)
        column < previous.length
            ? previous[column]
            : _prepareField(source[column]),
    ];
  }

  String _prepareField(String source) {
    final prepared = _prepareCell(source);
    return _encodeCell?.call(prepared) ?? prepared;
  }

  String _previewCell(String source, String encoded, PreviewTextBudget budget) {
    final encode = _encodeCell;
    if (encode == null) return budget.cell(encoded);
    // The cache retains encoded fields for full rendering. Revisit preparation
    // only inside the preview rectangle to shorten content before escaping,
    // without retaining a second grid of unencoded prepared cells.
    final prepared = _prepareCell(source);
    final shortened = budget.cell(prepared);
    return identical(prepared, shortened) ? encoded : encode(shortened);
  }
}

final class _PreparedPreview {
  final Table cells;
  final OutputPreview result;
  final PreviewTextLimits? textLimits;

  const _PreparedPreview(this.cells, this.result, this.textLimits);
}
