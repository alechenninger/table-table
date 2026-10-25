import '../slack_table.dart';
import 'clipboard.dart';

/// Select a representation and parse it once. HTML is preferred only when the
/// selected input format permits it; failed HTML can fall back to plain text.
Table parseClipboardTable(ClipboardSnapshot contents,
    {String inputFormat = InputFormats.auto, int? columns}) {
  ParseError? htmlError;
  if (inputFormat == InputFormats.auto || inputFormat == InputFormats.html) {
    final html = contents[ClipboardFormat.html];
    if (html != null) {
      try {
        return parseTable(html, inputFormat: InputFormats.html);
      } on ParseError catch (error) {
        htmlError = error;
      }
    }
  }
  final text = contents[ClipboardFormat.plainText];
  if (text != null && text.trim().isNotEmpty) {
    try {
      return parseTable(text, inputFormat: inputFormat, columns: columns);
    } on AmbiguousColumnsError {
      rethrow;
    } on ParseError {
      if (inputFormat == InputFormats.html && htmlError != null) {
        throw htmlError;
      }
      rethrow;
    }
  }
  if (htmlError != null) throw htmlError;
  throw const ParseError('no table text found on the clipboard');
}
