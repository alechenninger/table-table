import 'package:characters/characters.dart';

/// Frontend-selected character limits, applied only to visible preview text.
/// Prepared cell caches and complete output always retain unshortened content.
/// These constrain content rather than cache bytes; a large cell can still
/// dominate retained text. Encoding and layout may need separate output limits.
final class PreviewTextLimits {
  final int maxCellCodeUnits;
  final int maxTextCodeUnits;

  const PreviewTextLimits(
      {required this.maxCellCodeUnits, required this.maxTextCodeUnits})
      : assert(maxCellCodeUnits > 0),
        assert(maxTextCodeUnits > 0);

  @override
  bool operator ==(Object other) =>
      other is PreviewTextLimits &&
      maxCellCodeUnits == other.maxCellCodeUnits &&
      maxTextCodeUnits == other.maxTextCodeUnits;

  @override
  int get hashCode => Object.hash(maxCellCodeUnits, maxTextCodeUnits);
}

/// A single preview's text allowance; never retained by a formatting session.
final class PreviewTextBudget {
  final PreviewTextLimits limits;
  bool shortened = false;
  int _remainingCells;
  int _remainingText;

  PreviewTextBudget(this.limits, int cells)
      : _remainingCells = cells,
        _remainingText = limits.maxTextCodeUnits {
    if (limits.maxCellCodeUnits < 1 || limits.maxTextCodeUnits < cells) {
      throw ArgumentError(
          'preview text limits must allow at least one character per cell');
    }
  }

  String cell(String value) {
    _remainingCells--;
    final available = _remainingText - _remainingCells;
    final allowance = available < limits.maxCellCodeUnits
        ? available
        : limits.maxCellCodeUnits;
    final result = shortenPreviewText(value, allowance);
    shortened |= result.length != value.length;
    _remainingText -= result.length;
    return result;
  }
}

/// Shorten a bounded prefix without splitting a grapheme or retaining ellipses
/// in the values used for full output.
String shortenPreviewText(String value, int limit) {
  if (value.length <= limit) return value;
  var end = limit;
  final last = value.codeUnitAt(end - 1);
  final next = value.codeUnitAt(end);
  if (last >= 0xd800 && last <= 0xdbff && next >= 0xdc00 && next <= 0xdfff) {
    end--;
  }
  // Discard the final, possibly incomplete grapheme of a bounded prefix. First
  // finish on a code-point boundary so partial ZWJ sequences remain visible.
  if (end == 0) return '…';
  return '${value.substring(0, end).characters.skipLast(1)}…';
}
