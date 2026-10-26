import '../errors.dart';
import '../formats.dart';
import '../table.dart';

const tsvInput = InputFormat(
    id: InputFormats.tsv, label: 'TSV', read: readTsv, readInContext: _readTsv);

Table readTsv(String text, {int? columns}) => _readTsv(InputContext(text));

Table _readTsv(InputContext source) {
  final rows = source.tabRows;
  if (rows.first.length < 2) {
    throw const ParseError('tsv input must have at least two columns');
  }
  return Table(rows, sourceFormat: InputFormats.tsv);
}
