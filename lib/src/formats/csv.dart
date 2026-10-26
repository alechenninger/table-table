import '../errors.dart';
import '../formats.dart';
import '../table.dart';
import '../delimited_rows.dart';

const csvInput =
    InputFormat(id: InputFormats.csv, label: 'CSV', read: _readCsv);

Table _readCsv(String text, {int? columns}) {
  if (!text.contains(',')) {
    throw const ParseError('no comma-delimited rows found');
  }
  final rows = readDelimitedRows(text, InputFormats.csv, ',');
  if (rows.first.length < 2) {
    throw const ParseError('csv input must have at least two columns');
  }
  return Table(rows, sourceFormat: InputFormats.csv);
}
