import '../errors.dart';
import '../formats.dart';
import '../table.dart';
import '../text_cells.dart';

const spacedInput = InputFormat(
    id: InputFormats.spaced, label: 'Spaced cells', read: _readSpaced);

Table _readSpaced(String text, {int? columns}) {
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = strip(text).split(RegExp(r'\n[ \t]*\n+'));
  if (blocks.length < 4 || blocks.any((block) => strip(block).contains('\n'))) {
    throw const ParseError('no blank-line-separated cell stream found');
  }
  final cells = blocks.map(strip).toList();
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
  return Table([
    for (var i = 0; i < cells.length; i += columns)
      cells.sublist(i, i + columns),
  ], sourceFormat: InputFormats.spaced);
}
