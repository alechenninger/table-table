import 'errors.dart';

// Match the Python CSV reader's default limit, measured in code points.
const _csvFieldLimit = 131072;
// Python csv.reader's default dialect: quotes only open at field start,
// doubled quotes escape quotes, embedded newlines are allowed, and an
// unterminated quoted field is accepted. No numeric conversion is performed.
List<List<String>> readDelimitedRows(
    String text, String format, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  StringBuffer? fragments;
  var start = 0;
  var recordStart = 0;
  var atStart = true;
  var quoted = false;
  var fieldLength = 0;
  final delimiterCode = delimiter.codeUnitAt(0);

  void finishCell(int end) {
    final tail = text.substring(start, end);
    final cell =
        fragments == null ? tail : (fragments!..write(tail)).toString();
    row.add(cell);
    fragments = null;
    start = end + 1;
    atStart = true;
    fieldLength = 0;
  }

  void finishRow(int end) {
    finishCell(end);
    // Ignore physical blank lines, but retain explicit empty fields/records.
    if (row.length > 1 || end > recordStart) rows.add(row);
    recordStart = end + 1;
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
    } else if (code == 10 || code == 13) {
      finishRow(i);
      if (code == 13 && i + 1 < text.length && text.codeUnitAt(i + 1) == 10) {
        i++;
        start = i + 1;
        recordStart = i + 1;
      }
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
  if (recordStart < text.length) finishRow(text.length);
  if (rows.isEmpty) throw ParseError('no $format rows found');
  return rows;
}
