import 'package:table_table/slack_table.dart';
import 'package:table_table/src/clipboard.dart';
import 'package:table_table/src/clipboard_table.dart';

// Compile this entry point with dart compile js to check that the public API
// and clipboard model have no native-only dependencies. It also runs in Node.
void main() {
  final output = render('Name,Count\nAlpha,12');
  if (output != 'Name\tCount\nAlpha\t12') throw StateError(output);
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
  try {
    parseTable(List.generate(12, (i) => '$i').join('\n\n'));
    throw StateError('Expected ambiguous columns');
  } on AmbiguousColumnsError catch (error) {
    if (error.candidates.join(',') != '2,3,4,6') throw StateError('$error');
  }
  print('Web core smoke test passed.');
}
