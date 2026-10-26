import '../errors.dart';
import '../formats.dart';
import '../table.dart';
import '../text_cells.dart';

const spaceAlignedInput = InputFormat(
    id: InputFormats.spaceAligned,
    label: 'Space-aligned',
    read: _readSpaceAligned);
final _columnGap = RegExp(r' {2,}');
final _otherDelimiters = RegExp(r'[\t,|]');

Table _readSpaceAligned(String text, {int? columns}) {
  if (!text.contains('  ') || text.contains('\t')) {
    throw const ParseError('no space-aligned table found');
  }
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where(hasNonWhitespace)
      .toList();
  if (lines.isEmpty) {
    throw const ParseError('no space-aligned table header found');
  }
  final header = lines.first.trimRight();
  final starts = [0, for (final gap in _columnGap.allMatches(header)) gap.end];
  if (starts.length < 2 ||
      header.startsWith(' ') ||
      _otherDelimiters.hasMatch(header)) {
    throw const ParseError(
        'space-aligned headers need space-separated columns');
  }

  // Header positions preserve single spaces in multiword headers, multiword
  // values such as "2 (3m ago)", and empty cells between populated columns.
  final rows = <List<String>>[];
  for (final line in lines) {
    for (final start in starts.skip(1)) {
      // Require padding at each boundary instead of silently splitting a value
      // when the source has lost its alignment. Short rows may omit empty cells.
      for (var i = start - 2; i < start && i < line.length; i++) {
        if (line.codeUnitAt(i) != 0x20) {
          throw const ParseError(
              'space-aligned row is not aligned with its header');
        }
      }
    }
    rows.add([
      for (var column = 0; column < starts.length; column++)
        starts[column] >= line.length
            ? ''
            : strip(line.substring(
                starts[column],
                column + 1 < starts.length && starts[column + 1] < line.length
                    ? starts[column + 1]
                    : line.length)),
    ]);
  }
  return Table(rows, sourceFormat: InputFormats.spaceAligned);
}
