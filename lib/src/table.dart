import 'errors.dart';
import 'format_ids.dart';

/// An immutable rectangular grid of text and column alignment.
///
/// Readers decode syntax; writers decide how to present the preserved content.
/// Missing cells are padded once, and strings are reused without copying.
/// Preservation keeps decoded cell text and supported column semantics, rather
/// than exact source bytes or arbitrary rich formatting. Readers still interpret
/// HTML visibility, Markdown padding, and other rules that determine which text
/// belongs in a cell. Writers choose cleanup and presentation.
final class Table {
  final List<List<String>> rows;

  /// Alignment for each column, including its header, in [rows].
  ///
  /// There is exactly one immutable entry per normalized column. Unspecified
  /// alignment leaves presentation to the destination, unlike explicit left
  /// alignment. Destinations without alignment support can ignore these values.
  final List<ColumnAlignment> columnAlignments;

  /// The reader ID for callers of the original [parseTable] convenience API.
  final String sourceFormat;

  /// Snapshot cells and alignments without destination cleanup.
  ///
  /// Missing alignments are padded with [ColumnAlignment.unspecified]. Supplying
  /// more alignments than the normalized column count throws [ArgumentError];
  /// metadata cannot create columns.
  factory Table(List<List<String>> rows,
      {List<ColumnAlignment> columnAlignments = const [],
      String sourceFormat = InputFormats.auto}) {
    final cells = _snapshot(rows);
    final width = cells.first.length;
    if (columnAlignments.length > width) {
      throw ArgumentError.value(columnAlignments, 'columnAlignments',
          'cannot exceed the table column count ($width)');
    }
    return Table._(
      cells,
      List<ColumnAlignment>.unmodifiable([
        ...columnAlignments,
        ...List<ColumnAlignment>.filled(
            width - columnAlignments.length, ColumnAlignment.unspecified),
      ]),
      sourceFormat,
    );
  }

  Table._(this.rows, this.columnAlignments, this.sourceFormat);

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

/// Horizontal alignment shared by a column's header and body cells.
enum ColumnAlignment {
  /// No explicit source alignment; the destination chooses its default.
  unspecified,
  left,
  center,
  right,
}
