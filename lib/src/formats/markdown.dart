import 'dart:math' as math;

import '../display_width.dart';
import '../errors.dart';
import '../formats.dart';
import '../table.dart';
import '../preview_text.dart';
import '../text_cells.dart';

const markdownInput = InputFormat(
    id: InputFormats.markdown, label: 'Markdown', read: _readMarkdown);
const pipeInput = InputFormat(
    id: InputFormats.pipe, label: 'Pipe-separated', read: _readPipe);
const markdownOutput = OutputFormat(
    id: OutputFormats.markdown, label: 'Markdown', prepare: _prepareMarkdown);
final _separator = RegExp(r'^:?-{3,}:?$');

String _escapeMarkdownCell(String cell) =>
    cell.replaceAll('\\', '\\\\').replaceAll('|', r'\|');

String _formatMarkdownRow(
    List<String> row, List<int> columnWidths, List<int> measuredWidths) {
  final paddedCells = <String>[];
  for (var column = 0; column < row.length; column++) {
    final cell = row[column];
    final padding = columnWidths[column] - measuredWidths[column];
    paddedCells.add(cell + ' ' * padding);
  }
  return '| ${paddedCells.join(' | ')} |';
}

Table _readMarkdown(String text, {int? columns}) {
  // Reject before normalization, which can copy a large non-Markdown source.
  if (!text.contains('|') || !text.contains('---')) {
    throw const ParseError('no markdown table separator found');
  }
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = _nonEmptyLines(text);
  if (lines.length < 2) {
    throw const ParseError('markdown tables need a header and separator');
  }
  for (var i = 1; i < lines.length; i++) {
    if (!lines[i].contains('---')) continue;
    final separator = _splitMarkdownRow(lines[i]);
    if (!_isSeparatorRow(separator)) continue;
    final header = _splitMarkdownRow(lines[i - 1]);
    if (header.length < 2) {
      throw const ParseError('markdown header must have at least two columns');
    }
    final body = <List<String>>[];
    for (final line in lines.skip(i + 1)) {
      final row = _splitMarkdownRow(line);
      if (row.length < 2) break;
      body.add(row);
    }
    return Table(
      [
        [
          ...header,
          ...List<String>.filled(
              math.max(0, separator.length - header.length), '')
        ],
        ...body,
      ],
      sourceFormat: InputFormats.markdown,
    );
  }
  throw const ParseError('no markdown table separator found');
}

Table _readPipe(String text, {int? columns}) {
  if (!text.contains('|')) {
    throw const ParseError('no pipe-delimited rows found');
  }
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = _nonEmptyLines(text);
  if (lines.isEmpty || !lines.any((line) => line.contains('|'))) {
    throw const ParseError('no pipe-delimited rows found');
  }
  final rows = lines.map(_splitMarkdownRow).toList();
  if (rows.first.length < 2) {
    throw const ParseError(
        'pipe-delimited input must have at least two columns');
  }
  if (rows.length > 1 && _isSeparatorRow(rows[1])) rows.removeAt(1);
  return Table(rows, sourceFormat: InputFormats.pipe);
}

List<String> _nonEmptyLines(String text) =>
    text.split('\n').where(hasNonWhitespace).toList();

List<String> _splitMarkdownRow(String line) {
  line = strip(line);
  if (line.startsWith('|')) line = line.substring(1);
  if (line.endsWith('|') && !line.endsWith(r'\|')) {
    line = line.substring(0, line.length - 1);
  }
  final cells = <String>[];
  StringBuffer? fragments;
  var start = 0;

  void finishCell(int end) {
    final tail = line.substring(start, end);
    final cell =
        fragments == null ? tail : (fragments!..write(tail)).toString();
    cells.add(strip(cell));
    fragments = null;
    start = end + 1;
  }

  for (var i = 0; i < line.length; i++) {
    final code = line.codeUnitAt(i);
    if (code == 92 && i + 1 < line.length) {
      if (line.codeUnitAt(i + 1) == 124) {
        fragments ??= StringBuffer();
        fragments!.write(line.substring(start, i));
        start = i + 1;
      }
      i++;
    } else if (code == 124) {
      finishCell(i);
    }
  }
  finishCell(line.length);
  return cells;
}

bool _isSeparatorRow(List<String> cells) =>
    cells.isNotEmpty && cells.every((cell) => _separator.hasMatch(strip(cell)));

FormattedTable _prepareMarkdown(Table table) => _MarkdownSession(table);

/// Markdown measures escaped source and aligns each requested rectangle.
/// Full rendering may need temporary layout data for the complete table; only
/// the last preview's cells and the final string survive the call.
/// A preview measures its own subset to avoid scanning the whole table before
/// copy, so its padding may differ from complete output.
final class _MarkdownSession implements FormattedTable {
  final Table _table;
  _MarkdownCells? _lastCells;
  OutputPreview? _lastPreview;
  String? _fullText;
  PreviewTextLimits? _lastTextLimits;

  _MarkdownSession(this._table);

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
    final rows = math.min(maxRows, _table.rows.length);
    final columns = math.min(maxColumns, _table.rows.first.length);
    final previous = _lastPreview;
    if (previous != null &&
        _lastCells!.values.length == rows &&
        _lastCells!.values.first.length == columns &&
        _lastTextLimits == textLimits) {
      return previous;
    }
    final cells = _prepare(rows, columns);
    final budget = textLimits == null
        ? null
        : PreviewTextBudget(textLimits, rows * columns);
    var visible = cells;
    if (budget != null) {
      final values = <List<String>>[];
      final widths = <List<int>>[];
      for (var row = 0; row < rows; row++) {
        final rowValues = <String>[];
        final rowWidths = <int>[];
        for (var column = 0; column < columns; column++) {
          final original = cleanCell(_table.rows[row][column]);
          final shortened = budget.cell(original);
          if (identical(original, shortened)) {
            rowValues.add(cells.values[row][column]);
            rowWidths.add(cells.widths[row][column]);
          } else {
            final escaped = _escapeMarkdownCell(shortened);
            rowValues.add(escaped);
            rowWidths.add(displayWidth(escaped));
          }
        }
        values.add(rowValues);
        widths.add(rowWidths);
      }
      visible = _MarkdownCells(values, widths);
    }
    var text = _render(visible);
    var shownRows = rows;
    var shortened = budget?.shortened ?? false;
    if (textLimits != null && text.length > textLimits.maxTextCodeUnits) {
      final prefix = text.substring(0, textLimits.maxTextCodeUnits);
      final end = prefix.lastIndexOf('\n');
      text = end < 0
          ? shortenPreviewText(text, textLimits.maxTextCodeUnits)
          : prefix.substring(0, end);
      shownRows = math.max(1, text.split('\n').length - 1);
      shortened = true;
    }
    final result = OutputPreview(
        text: text,
        shownRows: shownRows,
        textShortened: shortened,
        shownColumns: columns,
        totalRows: _table.rows.length,
        totalColumns: _table.rows.first.length);
    // Cache unshortened escaped cells and widths, never preview-specific padding:
    // a larger rectangle or full output can need different alignment.
    _lastCells = cells;
    _lastTextLimits = textLimits;
    _lastPreview = result;
    return result;
  }

  String _renderFull() {
    final preview = _lastPreview;
    if (preview != null && !preview.isLimited) return preview.text;
    return _render(_prepare(_table.rows.length, _table.rows.first.length));
  }

  _MarkdownCells _prepare(int rows, int columns) {
    final cached = _lastCells;
    final escaped = <List<String>>[];
    final measured = <List<int>>[];
    for (var row = 0; row < rows; row++) {
      final values = <String>[];
      final widths = <int>[];
      final previousValues = cached != null && row < cached.values.length
          ? cached.values[row]
          : const <String>[];
      final previousWidths = cached != null && row < cached.widths.length
          ? cached.widths[row]
          : const <int>[];
      for (var column = 0; column < columns; column++) {
        if (column < previousValues.length) {
          values.add(previousValues[column]);
          widths.add(previousWidths[column]);
        } else {
          final value =
              _escapeMarkdownCell(cleanCell(_table.rows[row][column]));
          values.add(value);
          // Measure escaped source: backslashes contribute to alignment. Wide
          // glyphs occupy two columns; combining marks share their base's.
          widths.add(displayWidth(value));
        }
      }
      escaped.add(values);
      measured.add(widths);
    }
    return _MarkdownCells(escaped, measured);
  }

  String _render(_MarkdownCells cells) {
    final columnWidths = List<int>.filled(cells.values.first.length, 3);
    for (final widths in cells.widths) {
      for (var column = 0; column < widths.length; column++) {
        columnWidths[column] = math.max(columnWidths[column], widths[column]);
      }
    }
    final separator = [for (final width in columnWidths) '-' * width];
    return [
      _formatMarkdownRow(cells.values.first, columnWidths, cells.widths.first),
      _formatMarkdownRow(separator, columnWidths, columnWidths),
      for (var row = 1; row < cells.values.length; row++)
        _formatMarkdownRow(cells.values[row], columnWidths, cells.widths[row]),
    ].join('\n');
  }
}

final class _MarkdownCells {
  final List<List<String>> values;
  final List<List<int>> widths;

  const _MarkdownCells(this.values, this.widths);
}
