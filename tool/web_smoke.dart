import 'package:slack_table/slack_table.dart';

// Compile this entry point with dart compile js to check that the public API
// has no native-only dependencies. It also runs under Node for a JS smoke test.
void main() {
  final output = render('Name,Count\nAlpha,12');
  if (output != 'Name\tCount\nAlpha\t12') throw StateError(output);
  final markdown = formatMarkdown(Table([
    ['😀', 'B'],
    ['x', 'y']
  ]));
  if (markdown != '| 😀   | B   |\n| --- | --- |\n| x   | y   |') {
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
