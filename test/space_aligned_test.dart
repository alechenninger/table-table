import 'dart:io';

import 'package:table_table/table_table.dart';
import 'package:test/test.dart';

void main() {
  for (final inputFormat in ['auto', 'space-aligned']) {
    group(inputFormat, () {
      test('reads the wide pod sample with multiword headers', () {
        final table = parseTable(
            File('samples/kubectl-pods-wide.txt').readAsStringSync(),
            inputFormat: inputFormat);
        expect(table.sourceFormat, 'space-aligned');
        expect(table.rows.length, 13);
        expect(table.rows.first, [
          'NAMESPACE',
          'NAME',
          'READY',
          'STATUS',
          'RESTARTS',
          'AGE',
          'IP',
          'NODE',
          'NOMINATED NODE',
          'READINESS GATES',
        ]);
        expect(table.rows[1], [
          'kube-system',
          'coredns-559f6c778d-7s4tn',
          '1/1',
          'Running',
          '0',
          '70s',
          '10.244.0.3',
          'table-samples-control-plane',
          '<none>',
          '<none>',
        ]);
        expect(table.rows.last, [
          'table-demo',
          'frontend-74d4b967c5-hnw6p',
          '0/1',
          'ContainerCreating',
          '0',
          '51s',
          '<none>',
          'table-samples-control-plane',
          '<none>',
          '<none>',
        ]);
      });

      test('reads the service sample without interpreting placeholder values',
          () {
        final table = parseTable(
            File('samples/kubectl-services.txt').readAsStringSync(),
            inputFormat: inputFormat);
        expect(table.sourceFormat, 'space-aligned');
        expect(table.rows, [
          ['NAME', 'TYPE', 'CLUSTER-IP', 'EXTERNAL-IP', 'PORT(S)', 'AGE'],
          ['cache', 'ClusterIP', '10.96.201.146', '<none>', '6379/TCP', '51s'],
          ['cache-headless', 'ClusterIP', 'None', '<none>', '6379/TCP', '51s'],
          [
            'frontend',
            'NodePort',
            '10.96.106.90',
            '<none>',
            '80:31860/TCP',
            '51s'
          ],
          [
            'frontend-public',
            'LoadBalancer',
            '10.96.68.137',
            '<pending>',
            '443:31672/TCP',
            '51s'
          ],
        ]);
      });

      test('keeps comma-separated ports in a single cell', () {
        const source = 'NAME   PORT(S)          AGE\n'
            'web    80/TCP,443/TCP   1d';
        final table = parseTable(source, inputFormat: inputFormat);
        expect(table.sourceFormat, 'space-aligned');
        expect(table.rows, [
          ['NAME', 'PORT(S)', 'AGE'],
          ['web', '80/TCP,443/TCP', '1d'],
        ]);
        expect(formatTsv(table), 'NAME\tPORT(S)\tAGE\nweb\t80/TCP,443/TCP\t1d');
        expect(
            formatMarkdown(table), contains('| web  | 80/TCP,443/TCP | 1d  |'));
      });

      test('keeps multiword restarts and empty cells at their header positions',
          () {
        const source = 'NAME   RESTARTS        AGE   NOTE\n'
            'web    2 (3m ago)      1d    one  two\n'
            'api                    2d\n'
            'job';
        expect(parseTable(source, inputFormat: inputFormat).rows, [
          ['NAME', 'RESTARTS', 'AGE', 'NOTE'],
          ['web', '2 (3m ago)', '1d', 'one  two'],
          ['api', '', '2d', ''],
          ['job', '', '', ''],
        ]);
      });

      test('accepts blank lines, line endings, and a header without data', () {
        for (final newline in ['\n', '\r\n', '\r']) {
          expect(
            parseTable(
                    '${newline}NAME   AGE$newline   $newline'
                    'web    1d$newline',
                    inputFormat: inputFormat)
                .rows,
            [
              ['NAME', 'AGE'],
              ['web', '1d']
            ],
          );
          expect(
              parseTable('NAME   AGE$newline', inputFormat: inputFormat).rows, [
            ['NAME', 'AGE']
          ]);
        }
      });
    });
  }

  test('rejects missing headers, unaligned rows, and other table delimiters',
      () {
    for (final source in [
      '',
      'No resources found in default namespace.',
      'NAME AGE\nweb 1d',
      'NAME   AGE\na-long-name   1d',
      'NAME   AGE\nweb 1d',
      'NAME\tAGE\nweb\t1d',
      'NAME,  AGE\nweb,   1d',
      'NAME | AGE\nweb  | 1d',
    ]) {
      expect(() => parseTable(source, inputFormat: 'space-aligned'),
          throwsA(isA<ParseError>()),
          reason: source);
    }
  });

  test('preserves detection of CSV, TSV, and pipe tables with padding', () {
    for (final (source, expected) in [
      ('NAME,  AGE\nweb,   1d', 'csv'),
      ('NAME\tAGE\nweb\t1d', 'tsv'),
      ('NAME  |  AGE\nweb   |  1d', 'pipe'),
    ]) {
      expect(parseTable(source).sourceFormat, expected);
    }
  });
}
