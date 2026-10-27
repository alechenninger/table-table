import 'catalog.dart';
import 'formats.dart';
import 'table.dart';

export 'errors.dart';
export 'table.dart';

/// Parse text and format it for Slack (default) or Markdown.
String render(
  String text, {
  String inputFormat = InputFormats.auto,
  String outputFormat = OutputFormats.slack,
  int? columns,
}) =>
    formatTable(parseTable(text, inputFormat: inputFormat, columns: columns),
        outputFormat: outputFormat);

/// Parse a table without performing I/O or prompting for ambiguous columns.
Table parseTable(String text,
        {String inputFormat = InputFormats.auto, int? columns}) =>
    tableFormats.parse(text, inputFormat: inputFormat, columns: columns).table;

/// Render a registered destination immediately, for full-first callers.
String formatTable(Table table, {String outputFormat = OutputFormats.slack}) =>
    tableFormats.prepare(table, outputFormat: outputFormat).fullText;

/// Render the existing Slack paste representation, with whitespace cleanup.
///
/// This compatibility function does not define a generic TSV export contract.
String formatTsv(Table table) => formatTable(table);

/// Render Markdown padded to display columns, using the first row as the header.
/// Column alignment is retained in the header separator's colon markers.
/// Header and body padding follows column alignment; odd center padding places
/// the extra space on the right. Unspecified columns are left-aligned.
String formatMarkdown(Table table) =>
    formatTable(table, outputFormat: OutputFormats.markdown);
