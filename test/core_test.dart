import 'package:table_table/table_table.dart';
import 'package:test/test.dart';

// Preserve the original implementation's inputs and expectations.
void main() {
  test('renders padded markdown', () {
    expect(
      render('Name,Count\nAlpha,12\nBeta,1000', outputFormat: 'markdown'),
      '| Name  | Count |\n| ----- | ----- |\n| Alpha | 12    |\n| Beta  | 1000  |',
    );
  });

  test('markdown sizes each column to its longest header or body cell', () {
    final table = Table([
      ['Description', 'Owner', 'ID'],
      ['Short', 'Al', '1'],
      ['Task', 'Alexandra', '42'],
    ]);

    expect(
      formatMarkdown(table),
      '| Description | Owner     | ID  |\n'
      '| ----------- | --------- | --- |\n'
      '| Short       | Al        | 1   |\n'
      '| Task        | Alexandra | 42  |',
    );
  });

  test('markdown keeps short and empty columns at least three characters wide',
      () {
    final table = Table([
      ['A', '', 'C'],
      ['', '', 'xy'],
      ['z', '', ''],
    ]);

    expect(
      formatMarkdown(table),
      '| A   |     | C   |\n'
      '| --- | --- | --- |\n'
      '|     |     | xy  |\n'
      '| z   |     |     |',
    );
  });

  test('markdown normalizes ragged rows and escapes cells', () {
    expect(
      formatMarkdown(Table([
        ['A', 'B'],
        ['x|y', 'a\nb'],
        ['z'],
      ])),
      '| A    | B   |\n| ---- | --- |\n| x\\|y | a b |\n| z    |     |',
    );
    expect(
      formatMarkdown(Table([
        ['A', 'B'],
        ['\\', 'x'],
      ])),
      '| A   | B   |\n| --- | --- |\n| \\\\  | x   |',
    );
  });

  test('markdown header only', () {
    expect(
      formatMarkdown(Table([
        ['A', 'B']
      ])),
      '| A   | B   |\n| --- | --- |',
    );
  });

  test('markdown rejects empty table', () {
    expect(() => formatMarkdown(Table([])), throwsA(isA<ParseError>()));
  });

  test('rejects unknown output format', () {
    expect(
      () => render('A,B', outputFormat: 'invalid'),
      throwsA(isA<ParseError>().having(
        (error) => error.message,
        'message',
        contains('unknown output format'),
      )),
    );
  });

  test('renders markdown as tsv for slack native tables', () {
    const text = '\n'
        '        | Header A | Header B |\n'
        '        | --- | --- |\n'
        '        | Data 1A | Data 1B |\n'
        '        | Data 2A | Data 2B |\n'
        '        ';

    expect(
      render(text),
      'Header A\tHeader B\nData 1A\tData 1B\nData 2A\tData 2B',
    );
  });

  test('format table is native tsv', () {
    final table = parseTable('Name,Count\nAlpha,12\nBeta,1000\n');
    expect(formatTable(table), 'Name\tCount\nAlpha\t12\nBeta\t1000');
  });

  test('formats tsv input without code block changes', () {
    const text = 'Name\tCount\nAlpha\t12\n';
    expect(formatTsv(parseTable(text)), 'Name\tCount\nAlpha\t12');
  });

  test('auto detects cursor canvas wrapped tsv', () {
    const text = 'Workload\tSystem A\tSystem B\tWinner\tDelta\n'
        'Scenario A\n'
        '10.0 ops/s \u00b7 100.0 ms/op\t20.0 ops/s \u00b7 50.0 ms/op\t\n'
        '2.0x faster\n'
        'Scenario B\n'
        '8.0 ops/s \u00b7 125.0 ms/op\t4.0 ops/s \u00b7 250.0 ms/op\t\n'
        '2.0x faster\n';

    expect(
      render(text),
      'Workload\tSystem A\tSystem B\tWinner\tDelta\n'
      'Scenario A\t10.0 ops/s \u00b7 100.0 ms/op\t'
      '20.0 ops/s \u00b7 50.0 ms/op\t\t2.0x faster\n'
      'Scenario B\t8.0 ops/s \u00b7 125.0 ms/op\t'
      '4.0 ops/s \u00b7 250.0 ms/op\t\t2.0x faster',
    );
  });

  test('auto detects single cell wrapped tsv rows', () {
    const text = 'Scenario\tp50\tmean\tp95\n'
        'Scenario A\n'
        '2.2 ms\n'
        '2.6 ms\n'
        '5.5 ms\n'
        'Scenario B\n'
        '2.0 ms\n'
        '2.1 ms\n'
        '2.6 ms\n'
        'Scenario C\n'
        '3.1 ms\n'
        '3.3 ms\n'
        '5.3 ms\n';

    expect(
      render(text),
      'Scenario\tp50\tmean\tp95\n'
      'Scenario A\t2.2 ms\t2.6 ms\t5.5 ms\n'
      'Scenario B\t2.0 ms\t2.1 ms\t2.6 ms\n'
      'Scenario C\t3.1 ms\t3.3 ms\t5.3 ms',
    );
  });

  test('auto detects blank line separated cells', () {
    const text = '''Component

Organization

Purpose

release-coordinator

example-labs

Coordinates staged releases, pre-deployment checks, and post-deployment checks

artifact-catalog

example-labs

Tracks deployable artifact versions

workspace-provisioner

example-labs

Creates workspaces and assigns them to groups

access-broker

example-labs

Manages credentials used during workspace provisioning''';

    expect(
      render(text, columns: 3),
      'Component\tOrganization\tPurpose\n'
      'release-coordinator\texample-labs\t'
      'Coordinates staged releases, pre-deployment checks, and post-deployment checks\n'
      'artifact-catalog\texample-labs\tTracks deployable artifact versions\n'
      'workspace-provisioner\texample-labs\tCreates workspaces and assigns them to groups\n'
      'access-broker\texample-labs\tManages credentials used during workspace provisioning',
    );
    expect(
      () => parseTable(text),
      throwsA(isA<AmbiguousColumnsError>().having(
        (error) => error.candidates,
        'candidates',
        [3, 5],
      )),
    );
  });

  test('parses escaped markdown pipes', () {
    final table = parseTable(
      '\n'
      '            | Key | Value |\n'
      '            | --- | --- |\n'
      '            | A | B\\|C |\n'
      '            ',
      inputFormat: 'markdown',
    );
    expect(table.rows[1], ['A', 'B|C']);
  });

  test('auto detects simple pipe rows', () {
    expect(render('Name | Count\nAlpha | 12\n'), 'Name\tCount\nAlpha\t12');
  });

  test('rejects empty input', () {
    expect(() => parseTable(''), throwsA(isA<ParseError>()));
  });
}
