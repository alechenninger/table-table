import 'input_context.dart';
import 'table.dart';
import 'preview_text.dart';

export 'format_ids.dart';
export 'input_context.dart' show InputContext;
export 'preview_text.dart' show PreviewTextLimits;

/// A supported input format and the function that reads it.
///
/// Start [read] with a cheap syntax check before doing expensive parsing. Remove
/// the input's syntax and keep cell content intact for the destination to format.
/// Throw ParseError on failure, or AmbiguousColumnsError when the user needs to
/// choose a column count.
final class InputFormat {
  final String id;
  final String label;
  final Table Function(String text, {int? columns}) read;

  /// Optional conversion-scoped reader for formats that share a delimited scan.
  /// Direct [read] calls remain independent, while detection supplies one context.
  final Table Function(InputContext source)? readInContext;

  const InputFormat(
      {required this.id,
      required this.label,
      required this.read,
      this.readInContext});
}

/// A destination, such as Slack, or a text format, such as Markdown.
///
/// The writer chooses cleanup and escaping. A format can provide a reader, a
/// writer, or both. Clipboard access stays with the caller.
final class OutputFormat {
  final String id;
  final String label;
  final FormattedTable Function(Table table) prepare;

  const OutputFormat(
      {required this.id, required this.label, required this.prepare});
}

/// Output prepared on demand for one table and one destination.
///
/// Creating a session does no cell work. It keeps the most recent preview's
/// prepared cells and builds complete text only when requested. Rendering the
/// complete text must leave the cell cache bounded by that preview.
///
/// Keep the session through UI-only changes and replace it when the source or
/// destination changes. Each destination prepares cells from the original table
/// because its cleanup and escaping rules can differ.
abstract interface class FormattedTable {
  /// Compute complete output on first access; subsequent reads reuse it.
  String get fullText;

  /// Prepare the first rows and columns, including any header.
  ///
  /// Limits must be positive. Layout can depend on which cells are shown, so a
  /// Markdown preview's spacing can differ from complete output. Text limits
  /// shorten displayed content before escaping and leave full output intact.
  OutputPreview preview(
      {required int maxRows,
      required int maxColumns,
      PreviewTextLimits? textLimits});
}

/// An immutable preview, separate from the unabridged copyable output.
///
/// Without [table], a frontend shows [text]. Grid previews contain prepared
/// cell values so they represent what will be copied. The original table
/// remains available for changing destinations without losing content.
final class OutputPreview {
  final String text;
  final Table? table;
  final int shownRows;
  final int shownColumns;
  final int totalRows;
  final int totalColumns;
  final bool textShortened;

  const OutputPreview({
    required this.text,
    this.table,
    required this.shownRows,
    required this.shownColumns,
    required this.totalRows,
    required this.totalColumns,
    this.textShortened = false,
  });

  bool get isLimited =>
      shownRows < totalRows || shownColumns < totalColumns || textShortened;
}
