import 'dart:convert';

import 'package:table_table/slack_table.dart';

int _sink = 0;

void main() {
  for (final spec in [
    ('ascii-tsv-100', 100, false, '\t', 5),
    ('ascii-tsv-10000', 10000, false, '\t', 5),
    ('ascii-csv-1000', 1000, false, ',', 5),
    ('unicode-tsv-1000', 1000, true, '\t', 5),
    ('ascii-tsv-100000', 100000, false, '\t', 5),
    ('wide-unicode-tsv-2000', 2000, true, '\t', 100),
    ('unicode-tsv-30000', 30000, true, '\t', 5),
  ]) {
    final (name, count, unicode, delimiter, columns) = spec;
    final input = [
      [
        'Name',
        'Role',
        'Count',
        'Status',
        'Notes',
        for (var column = 5; column < columns; column++) 'Metric $column',
      ].join(delimiter),
      for (var i = 0; i < count; i++)
        [
          unicode ? '李明$i' : 'Person $i',
          'Engineering',
          '$i',
          unicode ? '👩🏽‍💻' : 'Active',
          unicode ? 'cafe\u0301 東京' : 'Some notes here',
          for (var column = 5; column < columns; column++) 'value-$i-$column',
        ].join(delimiter),
    ].join('\n');
    final format = delimiter == '\t' ? 'tsv' : 'csv';
    final table = parseTable(input, inputFormat: format);
    print(jsonEncode({
      'fixture': name,
      'input_utf8_bytes': utf8.encode(input).length,
      'rows': table.rows.length,
      'columns': columns,
    }));
    _measure('$name/parse-explicit', input.length,
        () => parseTable(input, inputFormat: format).rows.length);
    _measure(
        '$name/parse-auto', input.length, () => parseTable(input).rows.length);
    _measure('$name/format-tsv', input.length, () => formatTsv(table).length);
    if (count < 100000) {
      _measure('$name/format-markdown', input.length,
          () => formatMarkdown(table).length);
    }
    _measure('$name/render-tsv', input.length, () => render(input).length);
    if (count < 100000) {
      _measure('$name/render-markdown', input.length,
          () => render(input, outputFormat: 'markdown').length);
    }
  }
  print(jsonEncode({'checksum': _sink}));
}

// Setup is excluded. Report the first call separately from warmed samples;
// keep each timed batch long enough for JavaScript's millisecond clock.
void _measure(String name, int units, int Function() action) {
  final first = Stopwatch()..start();
  _sink ^= action();
  first.stop();
  _sink ^= action();
  final samples = <double>[];
  final sampleCount = first.elapsedMilliseconds > 100 ? 3 : 7;
  for (var sample = 0; sample < sampleCount; sample++) {
    final timer = Stopwatch()..start();
    var iterations = 0;
    do {
      _sink ^= action();
      iterations++;
    } while (timer.elapsedMicroseconds < 50000);
    timer.stop();
    samples.add(timer.elapsedMicroseconds / iterations / 1000);
  }
  samples.sort();
  print(jsonEncode({
    'name': name,
    'input_code_units': units,
    'first_ms': first.elapsedMicroseconds / 1000,
    'median_ms': samples[samples.length ~/ 2],
    'min_ms': samples.first,
    'max_ms': samples.last,
  }));
}
