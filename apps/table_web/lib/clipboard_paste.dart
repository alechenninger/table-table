import 'package:table_table/table_table.dart' as tables;

/// Source text paired with the immutable table parsed from that exact text.
class ParsedInput {
  final String source;
  final tables.Table table;

  const ParsedInput(this.source, this.table);
}

/// Parse the prospective editor contents after inserting clipboard HTML.
/// Keep both the source markup and the table so conversion need not parse again.
/// A null result leaves the browser's normal plain-text paste untouched.
ParsedInput? htmlTablePaste(String html) {
  if (html.isEmpty) return null;
  try {
    return ParsedInput(html, tables.parseTable(html, inputFormat: tables.InputFormats.html));
  } on tables.ParseError {
    return null;
  }
}
