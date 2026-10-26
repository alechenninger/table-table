import 'errors.dart';
import 'format_ids.dart';

/// An immutable rectangular grid of text, without destination cleanup.
///
/// Readers decode syntax; writers decide how to present the preserved content.
/// Missing cells are padded once, and strings are reused without copying.
/// Preservation means keeping cell text, rather than exact source bytes or rich
/// formatting. Readers still interpret HTML visibility, Markdown padding, and
/// other rules that determine which text belongs in a cell.
final class Table {
  final List<List<String>> rows;

  /// The reader ID for callers of the original [parseTable] convenience API.
  final String sourceFormat;

  Table(List<List<String>> rows, {this.sourceFormat = InputFormats.auto})
      : rows = _snapshot(rows);

  static List<List<String>> _snapshot(List<List<String>> rows) {
    var width = 0;
    for (final row in rows) {
      if (row.length > width) width = row.length;
    }
    if (width == 0) throw const ParseError('no table cells found');
    return List<List<String>>.unmodifiable([
      for (final row in rows)
        List<String>.unmodifiable(row.length == width
            ? row
            : [...row, ...List<String>.filled(width - row.length, '')]),
    ]);
  }
}
