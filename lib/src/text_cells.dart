// Match Python str.split()/strip(), including its extra control characters,
// but excluding the BOM which Dart's trim() treats as whitespace.
const _whitespaceCharacters =
    r'\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000';
final _whitespace = RegExp('[$_whitespaceCharacters]+');
final _edgeWhitespace =
    RegExp('^[$_whitespaceCharacters]+|[$_whitespaceCharacters]+\$');

String strip(String value) => value.replaceAll(_edgeWhitespace, '');

bool hasNonWhitespace(String text) {
  for (var i = 0; i < text.length; i++) {
    if (!_isWhitespace(text.codeUnitAt(i))) return true;
  }
  return false;
}

String cleanCell(String cell) {
  // Already-normalized cells need neither regex matching nor a new string.
  var previousSpace = false;
  for (var i = 0; i < cell.length; i++) {
    final code = cell.codeUnitAt(i);
    if (code > 0x20 && code < 0x7f) {
      previousSpace = false;
      continue;
    }
    if (_isWhitespace(code)) {
      if (code != 0x20 || i == 0 || i == cell.length - 1 || previousSpace) {
        return strip(cell).replaceAll(_whitespace, ' ');
      }
      previousSpace = true;
    } else {
      previousSpace = false;
    }
  }
  return cell;
}

// Keep this predicate in sync with _whitespaceCharacters. Whitespace contains
// no supplementary code points, so scanning UTF-16 code units is sufficient.
bool _isWhitespace(int code) =>
    code == 0x20 ||
    (code >= 0x09 && code <= 0x0d) ||
    (code >= 0x1c && code <= 0x1f) ||
    code == 0x85 ||
    code == 0xa0 ||
    code == 0x1680 ||
    (code >= 0x2000 && code <= 0x200a) ||
    (code >= 0x2028 && code <= 0x2029) ||
    code == 0x202f ||
    code == 0x205f ||
    code == 0x3000;
