import 'package:jaspr_test/jaspr_test.dart';
import 'package:table_table/slack_table.dart' as tables;
import 'package:table_table_web/clipboard_paste.dart';

void main() {
  const html =
      '<table><tr><th>Pattern</th><th>Cell</th></tr>'
      '<tr><td>Paragraph</td><td><p>Policy engine URI</p></td></tr>'
      '<tr><td>List</td><td><ul><li>Deployment</li><li>Route</li></ul></td></tr>'
      '<tr><td>Button</td><td><button style="user-select:none">Reconcile</button></td></tr>'
      '<tr><td>Quotes</td><td>&quot;literal&quot;</td></tr></table>';

  test('rich paste preserves source markup and is detected as HTML', () {
    final pasted = htmlTablePaste(html)!;
    expect(pasted.source, html);
    expect(pasted.table.sourceFormat, tables.InputFormats.html);
    expect(
      tables.formatTsv(pasted.table),
      'Pattern\tCell\n'
      'Paragraph\tPolicy engine URI\n'
      'List\tDeployment Route\n'
      'Button\tReconcile\n'
      'Quotes\t"literal"',
    );
  });

  test('a partial replacement is parsed in the context of the final source', () {
    const source =
        '😀 before<table><tr><th>A</th><th>B</th></tr>'
        '<tr><td>old value</td><td>end</td></tr></table>after';
    const replacement = '<p>new value</p>';
    expect(htmlTablePaste(replacement), isNull);
    final start = source.indexOf('old value');
    final candidate = source.replaceRange(start, start + 'old value'.length, replacement);
    final pasted = htmlTablePaste(candidate)!;
    expect(pasted.source, candidate);
    expect(pasted.table.rows, [
      ['A', 'B'],
      ['new value', 'end'],
    ]);
  });

  test('a standalone table can be invalid in the final editor context', () {
    expect(htmlTablePaste(html), isNotNull);
    const source = '<!-- replace me -->';
    final start = source.indexOf('replace me');
    expect(htmlTablePaste(source.replaceRange(start, start + 'replace me'.length, html)), isNull);
  });

  test('ordinary or unavailable HTML leaves plain-text paste untouched', () {
    for (final html in ['', '<p>hello</p>', '<table></table>']) {
      expect(htmlTablePaste(html), isNull);
    }
  });
}
