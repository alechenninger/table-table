import 'dart:convert';

import 'package:table_table/table_table.dart' as tables;
import 'package:table_table_web/conversion.dart';
import 'package:table_table_web/preview_data.dart';

int _sink = 0;

/// Measures the same frontend lifecycle against the old and new implementations.
/// Compile this source with each revision's package configuration. --once plus
/// --mode=NAME allows an external process monitor to measure peak memory for a
/// single workload, without mixing it with warmed benchmark batches.
/// Compare native and JavaScript builds against the same baseline. The migration
/// budget is roughly 5–10% more total conversion time; preview speed alone misses
/// the work deferred to first copy. Measure that work and peak memory too.
void main(List<String> arguments) {
  final filters = arguments.where((argument) => !argument.startsWith('--'));
  final modes = arguments.where((argument) => argument.startsWith('--mode='));
  final selectedMode = modes.isEmpty ? null : modes.single.substring(7);
  for (final fixture in _fixtures(filters)) {
    print(
      jsonEncode({'fixture': fixture.name, 'input_utf8_bytes': utf8.encode(fixture.text).length}),
    );
    for (final output in ['slack', 'markdown']) {
      ReadyConversion convert([String? inputFormat]) =>
          Conversion.fromInput(
                fixture.text,
                inputFormat: inputFormat ?? 'auto',
                outputFormat: output,
              )
              as ReadyConversion;
      int preview(ReadyConversion conversion) {
        final visible = PreviewData.fromConversion(conversion, output);
        return visible.rows.length + (visible.markdown?.length ?? 0);
      }

      final actions = <String, int Function()>{
        'explicit-full-$output': () => tables
            .render(fixture.text, inputFormat: fixture.inputFormat, outputFormat: output)
            .length,
        'auto-full-$output': () => tables.render(fixture.text, outputFormat: output).length,
        'preview-$output': () => preview(convert()),
        'preview-full-$output': () {
          final conversion = convert();
          return preview(conversion) + conversion.output.length;
        },
        'repeated-$output': () {
          final conversion = convert();
          var result = preview(conversion) + conversion.output.length;
          for (var repeat = 0; repeat < 5; repeat++) {
            result += preview(conversion) + conversion.output.length;
          }
          return result;
        },
        'switch-$output': () {
          final original = convert();
          final first = preview(original) + original.output.length;
          final destination = output == 'slack' ? 'markdown' : 'slack';
          final switched = original.withOutputFormat(destination) as ReadyConversion;
          final visible = PreviewData.fromConversion(switched, destination);
          return first + visible.shownDataRows + switched.output.length;
        },
      };
      for (final entry in actions.entries) {
        if (selectedMode != null && selectedMode != entry.key) continue;
        _measure('${fixture.name}/${entry.key}', entry.value, once: arguments.contains('--once'));
      }
      if (selectedMode == null) {
        final timer = Stopwatch()..start();
        final conversion = convert();
        _sink ^= preview(conversion);
        final previewMicros = timer.elapsedMicroseconds;
        _sink ^= conversion.output.length;
        print(
          jsonEncode({
            'name': '${fixture.name}/latency-$output',
            'preview_ms': previewMicros / 1000,
            'first_copy_ms': (timer.elapsedMicroseconds - previewMicros) / 1000,
            'total_ms': timer.elapsedMicroseconds / 1000,
          }),
        );
      }
    }
  }
  print(jsonEncode({'checksum': _sink}));
}

Iterable<({String name, String text, String inputFormat})> _fixtures(
  Iterable<String> filters,
) sync* {
  for (final spec in [
    ('tall-ascii', 30000, 5),
    ('wide-unicode', 2000, 100),
    ('whitespace', 10000, 5),
    ('long-cells', 100, 5),
  ]) {
    final (name, count, columns) = spec;
    if (filters.isNotEmpty && !filters.any(name.contains)) continue;
    final text = StringBuffer();
    for (var row = 0; row <= count; row++) {
      if (row > 0) text.write('\r\n');
      for (var column = 0; column < columns; column++) {
        if (column > 0) text.write(',');
        final value = row == 0
            ? 'Column $column'
            : switch (name) {
                'wide-unicode' => '李明 👩🏽‍💻 cafe\u0301 $row-$column',
                'whitespace' => '  one\t  two\r\n"three" $row-$column  ',
                'long-cells' => '${'x' * 16000} $row-$column',
                _ => 'value $row-$column',
              };
        text.write('"${value.replaceAll('"', '""')}"');
      }
    }
    yield (name: name, text: text.toString(), inputFormat: 'csv');
  }
}

void _measure(String name, int Function() action, {required bool once}) {
  final first = Stopwatch()..start();
  _sink ^= action();
  first.stop();
  if (once) {
    print(jsonEncode({'name': name, 'first_ms': first.elapsedMicroseconds / 1000}));
    return;
  }
  final samples = <double>[];
  for (var sample = 0; sample < 5; sample++) {
    final timer = Stopwatch()..start();
    var iterations = 0;
    do {
      _sink ^= action();
      iterations++;
    } while (timer.elapsedMicroseconds < 100000);
    samples.add(timer.elapsedMicroseconds / iterations / 1000);
  }
  samples.sort();
  print(
    jsonEncode({
      'name': name,
      'first_ms': first.elapsedMicroseconds / 1000,
      'median_ms': samples[2],
      'min_ms': samples.first,
      'max_ms': samples.last,
    }),
  );
}
