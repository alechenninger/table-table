import 'delimited_rows.dart';
import 'errors.dart';

/// Source text and a tab-delimited scan shared during one parse.
///
/// Wrapped text is tried before TSV. If it fails, TSV reuses the same scan.
/// The context is released after parsing. Quoted line endings can be cell
/// content, so the source stays untouched and each reader decides which
/// whitespace is part of its syntax.
final class InputContext {
  final String text;
  final int? columns;
  List<List<String>>? _tabRows;

  InputContext(this.text, {this.columns});

  List<List<String>> get tabRows {
    if (!text.contains('\t')) {
      throw const ParseError('no tab-delimited rows found');
    }
    return _tabRows ??= readDelimitedRows(text, 'tsv', '\t');
  }
}
