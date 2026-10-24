import 'dart:math' as math;

import 'package:string_width/string_width.dart';

import 'formats.dart';

class ParseError implements Exception {
  final String message;

  const ParseError(this.message);

  @override
  String toString() => message;
}

class AmbiguousColumnsError extends ParseError {
  final List<int> candidates;

  AmbiguousColumnsError(List<int> candidates)
      : candidates = List.unmodifiable(candidates),
        super(
            'ambiguous column count; valid choices are ${candidates.join(', ')}');
}

class Table {
  final List<List<String>> rows;
  final String sourceFormat;
  final bool _isNormalized;

  Table(List<List<String>> rows, {this.sourceFormat = InputFormats.auto})
      : rows = _freezeRows(rows),
        _isNormalized = false;

  // Parser cells are already clean; pad and freeze them once for both outputs.
  Table._parsed(List<List<String>> rows,
      {required this.sourceFormat, int minColumns = 0})
      : rows = _freezeRows(_padded(rows, minColumns)),
        _isNormalized = true;

  List<List<String>> get _normalizedRows =>
      _isNormalized ? rows : _normalized(rows);
}

/// Parse text and format it for Slack (default) or Markdown.
String render(
  String text, {
  String inputFormat = InputFormats.auto,
  String outputFormat = OutputFormats.slack,
  int? columns,
}) =>
    formatTable(
      parseTable(text, inputFormat: inputFormat, columns: columns),
      outputFormat: outputFormat,
    );

/// Parse a table without performing I/O or prompting for ambiguous columns.
Table parseTable(String text,
    {String inputFormat = InputFormats.auto, int? columns}) {
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(RegExp(r'^\n+|\n+$'), '');
  if (_strip(text).isEmpty) throw const ParseError('no table input found');

  // Detection precedence: specialized tables before general delimiters,
  // and TSV before CSV when the input contains both tabs and commas.
  final hasTabs = text.contains('\t');
  List<List<String>>? tabRows;
  List<List<String>> readTabs(String format) =>
      tabRows ??= _readDelimitedRows(text, format, '\t');

  final parsers = <String, Table Function(String)>{
    InputFormats.markdown: _parseMarkdown,
    InputFormats.cursor: (_) {
      if (!hasTabs) {
        throw const ParseError('no cursor canvas tab fragments found');
      }
      return _parseCursorCanvas(readTabs(InputFormats.cursor));
    },
    InputFormats.tsv: (_) {
      if (!hasTabs) {
        throw const ParseError('no tab-delimited rows found');
      }
      return _parseDelimitedRows(readTabs(InputFormats.tsv), InputFormats.tsv);
    },
    InputFormats.csv: _parseCsv,
    InputFormats.pipe: _parsePipe,
    InputFormats.spaced: (value) => _parseSpacedCells(value, columns),
  };
  if (inputFormat != InputFormats.auto) {
    final parser = parsers[inputFormat];
    if (parser == null) {
      final names =
          [InputFormats.auto, ...(parsers.keys.toList()..sort())].join(', ');
      throw ParseError(
          'unknown input format ${_repr(inputFormat)}; expected $names');
    }
    return parser(text);
  }
  for (final entry in parsers.entries) {
    if (entry.key == InputFormats.markdown && !text.contains('|')) continue;
    try {
      return entry.value(text);
    } on AmbiguousColumnsError {
      rethrow;
    } on ParseError {
      // Auto-detection tries the next parser only after a parse failure.
    }
  }
  throw const ParseError('could not detect a supported table format');
}

String formatTable(Table table, {String outputFormat = OutputFormats.slack}) {
  switch (outputFormat) {
    case OutputFormats.slack:
      return formatTsv(table);
    case OutputFormats.markdown:
      return formatMarkdown(table);
    default:
      throw ParseError(
        'unknown output format ${_repr(outputFormat)}; expected ${OutputFormats.values.join(', ')}',
      );
  }
}

/// Render cells as tab-separated values suitable for pasting into Slack.
String formatTsv(Table table) {
  final rows = table._normalizedRows;
  if (rows.isEmpty) throw const ParseError('no table rows found');
  return rows.map((row) => row.join('\t')).join('\n');
}

/// Render Markdown padded to display columns, using the first row as the header.
String formatMarkdown(Table table) {
  final rows = table._normalizedRows;
  if (rows.isEmpty || rows.first.isEmpty) {
    throw const ParseError('no table rows found');
  }
  final escapedRows = [
    for (final row in rows) [for (final cell in row) _escapeMarkdownCell(cell)],
  ];
  final columnWidths = List.filled(escapedRows.first.length, 3);
  final measuredWidths = <List<int>>[];
  // Measure escaped source: wide glyphs occupy two columns, while combining
  // marks share a column with their base character.
  for (final row in escapedRows) {
    final widths = [for (final cell in row) _displayWidth(cell)];
    measuredWidths.add(widths);
    for (var column = 0; column < row.length; column++) {
      columnWidths[column] = math.max(columnWidths[column], widths[column]);
    }
  }
  final separator = [for (final width in columnWidths) '-' * width];
  return [
    _formatMarkdownRow(escapedRows.first, columnWidths, measuredWidths.first),
    _formatMarkdownRow(separator, columnWidths, columnWidths),
    for (var i = 1; i < escapedRows.length; i++)
      _formatMarkdownRow(escapedRows[i], columnWidths, measuredWidths[i]),
  ].join('\n');
}

// Match the Python CSV reader's default limit, measured in code points.
const _csvFieldLimit = 131072;
final _separator = RegExp(r'^:?-{3,}:?$');
// Match Python str.split()/strip(), including its extra control characters,
// but excluding the BOM which Dart's trim() treats as whitespace.
const _whitespaceCharacters =
    r'\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000';
final _whitespace = RegExp('[$_whitespaceCharacters]+');
final _edgeWhitespace =
    RegExp('^[$_whitespaceCharacters]+|[$_whitespaceCharacters]+\$');

String _escapeMarkdownCell(String cell) =>
    cell.replaceAll('\\', '\\\\').replaceAll('|', r'\|');

int _displayWidth(String value) {
  // Printable ASCII occupies one display column per code unit. Keep controls,
  // ANSI escapes, and all Unicode on the existing display-width path.
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code < 32 || code > 126) return stringWidth(value);
  }
  return value.length;
}

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

Table _parseMarkdown(String text) {
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
    return Table._parsed(
      [header, ...body],
      sourceFormat: InputFormats.markdown,
      minColumns: math.max(header.length, separator.length),
    );
  }
  throw const ParseError('no markdown table separator found');
}

Table _parsePipe(String text) {
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
  return Table._parsed(rows, sourceFormat: InputFormats.pipe);
}

Table _parseCsv(String text) {
  if (!text.contains(',')) {
    throw const ParseError('no comma-delimited rows found');
  }
  return _parseDelimitedRows(
      _readDelimitedRows(text, InputFormats.csv, ','), InputFormats.csv);
}

Table _parseCursorCanvas(List<List<String>> rows) {
  if (rows.length < 3) {
    throw const ParseError(
        'cursor canvas input needs a header and fragmented rows');
  }
  final columnCount = rows.first.length;
  if (columnCount < 3) {
    throw const ParseError(
        'cursor canvas header must have at least three columns');
  }
  final body = rows.skip(1);
  if (!body.any((row) => row.length != columnCount)) {
    throw const ParseError('no wrapped cursor canvas rows found');
  }
  final logicalRows = [rows.first];
  var pending = <String>[];
  for (final row in body) {
    if (row.length > columnCount) {
      throw const ParseError('cursor canvas row has too many columns');
    }
    if (pending.isEmpty && row.length == columnCount) {
      logicalRows.add(row);
      continue;
    }
    if (pending.length + row.length > columnCount) {
      throw const ParseError(
          'cursor canvas fragments do not align to the header');
    }
    pending.addAll(row);
    if (pending.length == columnCount) {
      logicalRows.add(pending);
      pending = [];
    }
  }
  if (pending.isNotEmpty) {
    throw const ParseError(
        'cursor canvas fragments ended before a row was complete');
  }
  return Table._parsed(logicalRows, sourceFormat: InputFormats.cursor);
}

Table _parseSpacedCells(String text, int? columns) {
  final blocks = _strip(text).split(RegExp(r'\n[ \t]*\n+'));
  if (blocks.length < 4 ||
      blocks.any((block) => _strip(block).contains('\n'))) {
    throw const ParseError('no blank-line-separated cell stream found');
  }
  final cells = blocks.map(_cleanCell).toList();
  final candidates = [
    for (var n = 2; n <= cells.length ~/ 2; n++)
      if (cells.length % n == 0) n,
  ];
  if (columns == null) {
    if (candidates.isEmpty) {
      throw const ParseError(
          'could not infer rows from blank-line-separated cells');
    }
    if (candidates.length > 1) throw AmbiguousColumnsError(candidates);
    columns = candidates.first;
  } else if (!candidates.contains(columns)) {
    throw ParseError('${cells.length} blank-line-separated cells cannot form '
        'multiple complete rows of $columns columns');
  }
  return Table._parsed([
    for (var i = 0; i < cells.length; i += columns)
      cells.sublist(i, i + columns),
  ], sourceFormat: InputFormats.spaced);
}

Table _parseDelimitedRows(List<List<String>> rows, String format) {
  if (rows.first.length < 2) {
    throw ParseError('$format input must have at least two columns');
  }
  return Table._parsed(rows, sourceFormat: format);
}

// Python csv.reader's default dialect: quotes only open at field start,
// doubled quotes escape quotes, embedded newlines are allowed, and an
// unterminated quoted field is accepted. No numeric conversion is performed.
List<List<String>> _readDelimitedRows(
    String text, String format, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  StringBuffer? fragments;
  var start = 0;
  var atStart = true;
  var quoted = false;
  var fieldLength = 0;
  final delimiterCode = delimiter.codeUnitAt(0);

  void finishCell(int end) {
    final tail = text.substring(start, end);
    final cell =
        fragments == null ? tail : (fragments!..write(tail)).toString();
    row.add(_cleanCell(cell));
    fragments = null;
    start = end + 1;
    atStart = true;
    fieldLength = 0;
  }

  void finishRow(int end) {
    finishCell(end);
    if (row.any((value) => value.isNotEmpty)) rows.add(row);
    row = [];
  }

  // Scan UTF-16 indices and copy whole spans. Only quote removal needs a
  // buffer; ordinary fields need no code-point list or per-character writes.
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (quoted) {
      if (code == 34) {
        fragments ??= StringBuffer();
        fragments!.write(text.substring(start, i));
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 34) {
          fragments!.write('"');
          i++;
          start = i + 1;
        } else {
          quoted = false;
          start = i + 1;
          continue;
        }
      }
    } else if (atStart && code == 34) {
      quoted = true;
      atStart = false;
      start = i + 1;
      continue;
    } else if (code == delimiterCode) {
      finishCell(i);
      continue;
    } else if (code == 10) {
      finishRow(i);
      continue;
    } else {
      atStart = false;
    }
    if (++fieldLength > _csvFieldLimit) {
      throw const ParseError('field larger than field limit ($_csvFieldLimit)');
    }
    // The field limit counts code points, including one per surrogate pair.
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) i++;
    }
  }
  finishRow(text.length);
  if (rows.isEmpty) throw ParseError('no $format rows found');
  return rows;
}

List<String> _nonEmptyLines(String text) =>
    text.split('\n').where((line) => _strip(line).isNotEmpty).toList();

List<String> _splitMarkdownRow(String line) {
  line = _strip(line);
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
    cells.add(_cleanCell(cell));
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

String _strip(String value) => value.replaceAll(_edgeWhitespace, '');

String _cleanCell(String cell) => _strip(cell).replaceAll(_whitespace, ' ');

bool _isSeparatorRow(List<String> cells) =>
    cells.isNotEmpty &&
    cells.every((cell) => _separator.hasMatch(_strip(cell)));

List<List<String>> _freezeRows(List<List<String>> rows) =>
    List.unmodifiable(rows.map((row) => List<String>.unmodifiable(row)));

List<List<String>> _normalized(List<List<String>> rows) => _padded([
      for (final row in rows) [for (final cell in row) _cleanCell(cell)]
    ]);

List<List<String>> _padded(List<List<String>> rows, [int minColumns = 0]) {
  final columns = rows.map((row) => row.length).fold(minColumns, math.max);
  return rows
      .map((row) => row.length == columns
          ? row
          : [...row, ...List.filled(columns - row.length, '')])
      .toList();
}

String _repr(String value) {
  final quote = value.contains("'") && !value.contains('"') ? '"' : "'";
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll(quote, '\\$quote')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '$quote$escaped$quote';
}
