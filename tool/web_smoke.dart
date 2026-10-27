import 'package:table_table/table_table.dart';
import 'package:table_table/src/clipboard.dart';
import 'package:table_table/src/clipboard_table.dart';

// Compile this entry point with dart compile js to check that the public API
// and clipboard model have no native-only dependencies. It also runs in Node.
void main() {
  final output = render('Name,Count\nAlpha,12');
  if (output != 'Name\tCount\nAlpha\t12') throw StateError(output);
  final spaceAligned = render('NAME   PORT(S)          AGE\n'
      'web    80/TCP,443/TCP   1d');
  if (spaceAligned != 'NAME\tPORT(S)\tAGE\nweb\t80/TCP,443/TCP\t1d') {
    throw StateError(spaceAligned);
  }
  final clipboard = parseClipboardTable(ClipboardSnapshot({
    ClipboardFormat.plainText: 'wrong,table',
    ClipboardFormat.html:
        '<table><tr><th>A</th><th>B</th></tr><tr><td>x</td><td>y</td></tr></table>',
  }));
  if (formatTsv(clipboard) != 'A\tB\nx\ty') {
    throw StateError('clipboard format selection failed');
  }
  final html = render('<table><tr><th>A</th><th>B</th></tr>'
      '<tr><td><p>one</p><p>two</p></td>'
      '<td><span style="display:flex"><code>x</code><span>y</span></span>'
      '</td></tr></table>');
  if (html != 'A\tB\none two\tx y') throw StateError(html);
  final filtered = render('<template><table><tr><td>ignored</td><td>table</td>'
      '</tr></table></template><table><tr hidden><td>hidden</td><td>row</td></tr>'
      '<tr><td colspan="0">A</td><td>'
      '<span style="display:none;display:inline !IMPORTANT">visible</span>'
      '</td></tr></table>');
  if (filtered != 'A\tvisible') throw StateError(filtered);
  for (final span in ['2tail', '9' * 1000]) {
    try {
      parseTable(
          '<table><tr><td colspan="$span">merged</td><td>cell</td>'
          '</tr></table>',
          inputFormat: InputFormats.html);
      throw StateError('Expected merged-cell rejection for $span');
    } on ParseError {
      // Huge and noncanonical spans have identical semantics in native and JS.
    }
  }
  final deepHtml = render('${'<span>' * 10000}<table>'
      '<tr><th>A</th><th>B</th></tr><tr><td>'
      '${'<span>' * 10000}value${'</span>' * 10000}'
      '</td><td>end</td></tr></table>${'</span>' * 10000}');
  if (deepHtml != 'A\tB\nvalue\tend') throw StateError(deepHtml);
  final markdown = formatMarkdown(Table([
    ['李明', 'e\u0301'],
    ['x', 'y']
  ]));
  if (markdown != '| 李明 | e\u0301   |\n| ---- | --- |\n| x    | y   |') {
    throw StateError(markdown);
  }
  final aligned = parseTable('| A | B | C | D |\n'
      '| --- | :--- | :---: | ---: |\n'
      '| a | b | c | d |');
  final alignedOutput = formatMarkdown(aligned);
  final roundTrip = parseTable(alignedOutput);
  if (roundTrip.columnAlignments.join(',') !=
          ColumnAlignment.values.join(',') ||
      alignedOutput.split('\n')[1] != '| --- | :--- | :---: | ---: |') {
    throw StateError('column alignment round trip failed: $alignedOutput');
  }
  if (alignedOutput !=
      '| A   | B    |   C   |    D |\n'
          '| --- | :--- | :---: | ---: |\n'
          '| a   | b    |   c   |    d |') {
    throw StateError('visual column alignment failed: $alignedOutput');
  }
  try {
    parseTable(List.generate(12, (i) => '$i').join('\n\n'));
    throw StateError('Expected ambiguous columns');
  } on AmbiguousColumnsError catch (error) {
    if (error.candidates.join(',') != '2,3,4,6') throw StateError('$error');
  }
  print('Web core smoke test passed.');
}
