import 'dart:convert';

import 'package:table_table/slack_table.dart' as tables;
import 'package:table_table_web/clipboard_paste.dart';
import 'package:table_table_web/conversion.dart';
import 'package:table_table_web/preview_data.dart';

int _sink = 0;

void main(List<String> arguments) {
  for (final fixture in _fixtures()) {
    if (arguments.isNotEmpty && !arguments.any(fixture.name.contains)) continue;
    print(
      jsonEncode({
        'fixture': fixture.name,
        'input_utf8_bytes': utf8.encode(fixture.input).length,
        'rows': fixture.rows,
        'columns': fixture.columns,
      }),
    );
    final parsed = _measure('${fixture.name}/parse-html', () {
      final table = tables.parseTable(fixture.input, inputFormat: tables.InputFormats.html);
      return fixture.check(table);
    });
    if (parsed != _Measurement.measured) continue;
    for (final output in tables.OutputFormats.values) {
      final rendered = _measure('${fixture.name}/render-$output', () {
        return tables.render(fixture.input, outputFormat: output).length;
      });
      if (rendered != _Measurement.measured) break;
      final converted = _measure('${fixture.name}/convert-preview-$output', () {
        return _convertPreview(fixture, fixture.input, output);
      });
      if (converted != _Measurement.measured) break;
      final pasted = _measure('${fixture.name}/paste-preview-$output', () {
        final pasted = htmlTablePaste(fixture.input);
        if (pasted == null) throw StateError('supported table rejected by paste handler');
        return _preparePreview(
          fixture,
          Conversion.fromTable(pasted.table, outputFormat: output),
          output,
        );
      });
      if (pasted != _Measurement.measured) break;
    }
  }
  print(jsonEncode({'checksum': _sink}));
}

int _convertPreview(_Fixture fixture, String input, String outputFormat) {
  final conversion = Conversion.fromInput(
    input,
    inputFormat: tables.InputFormats.auto,
    outputFormat: outputFormat,
  );
  return _preparePreview(fixture, conversion, outputFormat);
}

int _preparePreview(_Fixture fixture, Conversion conversion, String outputFormat) {
  if (conversion is! ReadyConversion) throw StateError('conversion is not ready');
  final preview = PreviewData.fromConversion(conversion, outputFormat);
  return fixture.check(conversion.table) + conversion.output.length + preview.rows.length;
}

class _Fixture {
  final String name;
  final String input;
  final int rows;
  final int columns;

  const _Fixture(this.name, this.input, this.rows, this.columns);

  int check(tables.Table table) {
    if (table.sourceFormat != tables.InputFormats.html ||
        table.rows.length != rows ||
        table.rows.first.length != columns ||
        table.rows.last.length != columns) {
      throw StateError('unexpected table dimensions or source format');
    }
    return table.rows.length + table.rows.last.last.length;
  }
}

Iterable<_Fixture> _fixtures() sync* {
  yield _grid('small-100x5', 100, 5);
  yield _grid('tall-10000x5', 10000, 5);
  yield _grid('tall-50000x5', 50000, 5);
  yield _grid('wide-10x2000', 10, 2000);
  yield _grid(
    'rich-1000x10',
    1000,
    10,
    cell: (row, column) =>
        '<div style="display:flex;gap:8px"><code style="font-family:monospace;'
        'background:rgba(0,0,0,0.2)">r$row-c$column</code>'
        '<span style="display:inline-flex;user-select:none;border-radius:9999px">'
        '<span>optional</span></span></div><p>Needs <strong>a Route</strong> '
        'and <em>edge TLS</em>.</p><ul><li>Deployment</li><li>Route</li></ul>',
  );
  yield _grid(
    'entities-1000x10',
    1000,
    10,
    cell: (_, _) =>
        '<span>&lt;tag&gt;&amp;&quot;quoted&quot;&nbsp;李明 👩🏽‍💻 '
        '&#x1f600;&#769;</span>',
  );
  yield _grid('unclosed-cells-10000x5', 10000, 5, closeTags: false);
  for (final depth in [1000, 10000]) {
    yield _Fixture(
      'deep-cell-$depth',
      '<table><tr><th>A</th><th>B</th></tr><tr><td>'
          '${'<span>' * depth}value${'</span>' * depth}</td><td>end</td></tr></table>',
      2,
      2,
    );
  }
  for (final depth in [1000, 10000]) {
    yield _Fixture(
      'deep-wrapper-$depth',
      '${'<div>' * depth}<table><tr><th>A</th><th>B</th></tr>'
          '<tr><td>value</td><td>end</td></tr></table>${'</div>' * depth}',
      2,
      2,
    );
  }
  yield _Fixture(
    'nested-tables-1000',
    '<table><tr><th>A</th><th>B</th></tr><tr><td>'
        '${_grid('nested', 1000, 2).input}</td><td>end</td></tr></table>',
    2,
    2,
  );
  yield _Fixture(
    'surrounding-html-50000',
    '${'<div><span>unrelated text</span></div>' * 25000}'
        '<table><tr><th>A</th><th>B</th></tr><tr><td>value</td><td>end</td></tr></table>'
        '${'<div><span>unrelated text</span></div>' * 25000}',
    2,
    2,
  );
  yield _Fixture(
    'long-cell-1mb',
    '<table><tr><th>A</th><th>B</th></tr><tr><td>${'x' * 1048576}'
        '</td><td>end</td></tr></table>',
    2,
    2,
  );
  yield _Fixture(
    'ragged-1000x1000',
    '<table><tr>${'<th>column</th>' * 1000}</tr>'
        '${'<tr><td>value</td></tr>' * 1000}</table>',
    1001,
    1000,
  );
  yield _grid('empty-10000x5', 10000, 5, cell: (_, _) => '');
}

_Fixture _grid(
  String name,
  int dataRows,
  int columns, {
  String Function(int, int)? cell,
  bool closeTags = true,
}) {
  final source = StringBuffer('<table><thead><tr>');
  for (var column = 0; column < columns; column++) {
    source.write('<th>Column $column${closeTags ? '</th>' : ''}');
  }
  source.write('${closeTags ? '</tr>' : ''}</thead><tbody>');
  for (var row = 0; row < dataRows; row++) {
    source.write('<tr>');
    for (var column = 0; column < columns; column++) {
      final content = cell == null ? 'r$row-c$column' : cell(row, column);
      source.write('<td>$content${closeTags ? '</td>' : ''}');
    }
    if (closeTags) source.write('</tr>');
  }
  source.write('</tbody></table>');
  return _Fixture(name, source.toString(), dataRows + 1, columns);
}

// Fixture generation, JSON encoding, and console output are outside timings.
// Report first-call latency separately, then three warmed batches of >=50 ms.
// Catch failures per operation so deep-tree crashes are visible in the report.
// Report a first call over one second once, then skip that fixture's other work.
_Measurement _measure(String name, int Function() action) {
  final first = Stopwatch()..start();
  try {
    _sink ^= action();
    first.stop();
    if (first.elapsedMilliseconds > 1000) {
      print(
        jsonEncode({
          'name': name,
          'first_ms': first.elapsedMicroseconds / 1000,
          'samples': 1,
          'note': 'over 1 s; warmed batches and remaining fixture operations skipped',
        }),
      );
      return _Measurement.slow;
    }
    final samples = <double>[];
    for (var sample = 0; sample < 3; sample++) {
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
    print(
      jsonEncode({
        'name': name,
        'first_ms': first.elapsedMicroseconds / 1000,
        'median_ms': samples[1],
        'min_ms': samples.first,
        'max_ms': samples.last,
        'samples': samples.length,
      }),
    );
    return _Measurement.measured;
  } catch (error, stack) {
    print(
      jsonEncode({
        'name': name,
        'error': '$error',
        'stack': stack.toString().split('\n').take(3).join('\n'),
        'elapsed_ms': first.elapsedMicroseconds / 1000,
      }),
    );
    return _Measurement.failed;
  }
}

enum _Measurement { measured, slow, failed }
