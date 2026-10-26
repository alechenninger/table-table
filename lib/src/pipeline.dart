import 'errors.dart';
import 'text_cells.dart';

import 'formats.dart';
import 'table.dart';

export 'formats.dart';
export 'table.dart';

/// The selected reader travels alongside the table, not inside its cells.
final class ParsedTable {
  final Table table;
  final InputFormat format;

  const ParsedTable(this.table, this.format);
}

/// The available formats and the order used to recognize input.
///
/// Menu order is separate from detection order. A choice can be listed first to
/// make it easy to find without changing which reader wins when several match.
final class FormatRegistry {
  final List<InputFormat> inputs;
  final List<OutputFormat> outputs;
  final List<String> detectionOrder;
  final Map<String, InputFormat> _inputs;
  final Map<String, OutputFormat> _outputs;

  FormatRegistry({
    required List<InputFormat> inputs,
    required List<OutputFormat> outputs,
    required List<String> detectionOrder,
  })  : inputs = List.unmodifiable(inputs),
        outputs = List.unmodifiable(outputs),
        detectionOrder = List.unmodifiable(detectionOrder),
        _inputs = {for (final input in inputs) input.id: input},
        _outputs = {for (final output in outputs) output.id: output} {
    if (_inputs.length != inputs.length || _outputs.length != outputs.length) {
      throw ArgumentError('format identifiers must be unique per direction');
    }
    if (_inputs.containsKey('auto') ||
        detectionOrder.toSet().length != detectionOrder.length ||
        detectionOrder.any((id) => !_inputs.containsKey(id))) {
      throw ArgumentError('detection requires unique registered reader IDs; '
          'auto is reserved for the coordinator');
    }
  }

  /// Each reader checks and parses in one call, so successful input is parsed
  /// once. A failure can mean either a different format or invalid input. An
  /// ambiguous column count goes back to the caller so the user can choose.
  ParsedTable parse(String text, {String inputFormat = 'auto', int? columns}) {
    final source = InputContext(text, columns: columns);
    if (inputFormat != 'auto') {
      final input = _inputs[inputFormat];
      if (input == null) throw ParseError('unknown input format: $inputFormat');
      return ParsedTable(
          (input.readInContext?.call(source) ??
              input.read(text, columns: columns)),
          input);
    }
    if (!hasNonWhitespace(text)) throw const ParseError('no table input found');
    for (final id in detectionOrder) {
      final input = _inputs[id]!;
      try {
        return ParsedTable(
            (input.readInContext?.call(source) ??
                input.read(text, columns: columns)),
            input);
      } on AmbiguousColumnsError {
        rethrow;
      } on ParseError {
        // Failure means try the next reader, regardless of how far it got.
      }
    }
    throw const ParseError('could not detect a supported table format');
  }

  /// Select a destination without rendering until preview or full text is read.
  FormattedTable prepare(Table table, {required String outputFormat}) {
    final output = _outputs[outputFormat];
    if (output == null) {
      throw ParseError('unknown output format: $outputFormat');
    }
    return output.prepare(table);
  }
}
