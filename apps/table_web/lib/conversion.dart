import 'package:table_table/table_table.dart' as tables;

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
      return Conversion.fromTable(
        table,
        outputFormat: outputFormat,
        candidates: candidates,
      );
    } on tables.ParseError {
      return const InvalidConversion();
    }
  }

  /// Format an already-parsed input without interpreting its source again.
  factory Conversion.fromTable(
    tables.Table table, {
    required String outputFormat,
    List<int> candidates = const [],
  }) {
    try {
      return ReadyConversion(
        table: table,
        formatted: tables.tableFormats.prepare(table, outputFormat: outputFormat),
        outputFormat: outputFormat,
        candidates: candidates,
      );
    } on tables.ParseError {
      return const InvalidConversion();
    }
  }

  /// Reuse the parsed table and preserve column choices when changing output.
  /// Replacing the session releases the old destination's cache instead of
  /// accumulating prepared output for every destination the user visits.
  Conversion withOutputFormat(String outputFormat) => switch (this) {
    ReadyConversion(outputFormat: final current) when current == outputFormat => this,
    ReadyConversion(:final table, :final candidates) => Conversion.fromTable(
      table,
      outputFormat: outputFormat,
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

/// Retain one source and session through UI feedback changes. Building a preview
/// must not read [output]: first-copy formatting is deferred and synchronous.
final class ReadyConversion extends Conversion {
  final tables.Table table;
  final tables.FormattedTable formatted;
  final String outputFormat;
  final List<int> candidates;

  ReadyConversion({
    required this.table,
    required this.formatted,
    required this.outputFormat,
    List<int> candidates = const [],
  }) : candidates = List.unmodifiable(candidates);

  /// Complete text is requested only on copy or full-source display.
  String get output => formatted.fullText;
}
