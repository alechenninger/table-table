import 'package:table_table/slack_table.dart' as tables;

/// The result of interpreting the current input, including any column choices.
sealed class Conversion {
  const Conversion();

  factory Conversion.fromInput(
    String input, {
    required String inputFormat,
    required String outputFormat,
    int? columns,
  }) {
    if (input.trim().isEmpty) return const EmptyConversion();

    try {
      tables.Table table;
      var candidates = const <int>[];
      try {
        table = tables.parseTable(input, inputFormat: inputFormat);
      } on tables.AmbiguousColumnsError catch (error) {
        candidates = error.candidates;
        if (columns == null || !candidates.contains(columns)) {
          return AmbiguousConversion(candidates);
        }
        table = tables.parseTable(input, inputFormat: inputFormat, columns: columns);
      }
      return ReadyConversion(
        table: table,
        output: tables.formatTable(table, outputFormat: outputFormat),
        candidates: candidates,
      );
    } on tables.ParseError {
      return const InvalidConversion();
    }
  }

  /// Reuse the parsed table and preserve column choices when changing output.
  Conversion withOutputFormat(String outputFormat) => switch (this) {
    ReadyConversion(:final table, :final candidates) => ReadyConversion(
      table: table,
      output: tables.formatTable(table, outputFormat: outputFormat),
      candidates: candidates,
    ),
    EmptyConversion() || AmbiguousConversion() || InvalidConversion() => this,
  };
}

final class EmptyConversion extends Conversion {
  const EmptyConversion();
}

final class AmbiguousConversion extends Conversion {
  final List<int> candidates;

  AmbiguousConversion(List<int> candidates) : candidates = List.unmodifiable(candidates);
}

final class InvalidConversion extends Conversion {
  const InvalidConversion();
}

final class ReadyConversion extends Conversion {
  final tables.Table table;
  final String output;
  final List<int> candidates;

  ReadyConversion({required this.table, required this.output, List<int> candidates = const []})
    : candidates = List.unmodifiable(candidates);
}
