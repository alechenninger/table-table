import '../errors.dart';
import '../formats.dart';
import '../table.dart';

const cursorInput = InputFormat(
    id: InputFormats.cursor,
    label: 'Wrapped table text',
    read: readCursor,
    readInContext: _readCursor);

Table readCursor(String text, {int? columns}) =>
    _readCursor(InputContext(text, columns: columns));

Table _readCursor(InputContext source) {
  final rows = source.tabRows;
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
  return Table(logicalRows, sourceFormat: InputFormats.cursor);
}
