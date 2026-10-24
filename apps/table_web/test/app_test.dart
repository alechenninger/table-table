import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:table_table_web/app.dart';

void main() {
  testComponents('starts empty, with copy disabled and no errors', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    expect(find.text('table-table'), findsOneComponent);
    expect(_copyButton().disabled, isTrue);
    expect(find.tag('table'), findsNothing);
    expect(find.textContaining('Couldn’t'), findsNothing);
  });

  testComponents('pasted input previews as a table and copies plain TSV', (tester) async {
    String? copied;
    tester.pumpComponent(TableApp(copyText: (text) async => copied = text));
    await _enter(tester, 'Name,Count\nAda,12');
    expect(find.tag('table'), findsOneComponent);
    expect(find.text('Ada'), findsOneComponent);
    expect(find.text('2 rows · 2 columns'), findsOneComponent);
    expect(find.text('CSV detected'), findsOneComponent);
    await tester.click(_button('copy-output'));
    expect(copied, 'Name\tCount\nAda\t12');
    expect(find.text('Table preserved.'), findsOneComponent);
  });

  testComponents('switching output updates the preview and copied text', (tester) async {
    String? copied;
    tester.pumpComponent(TableApp(copyText: (text) async => copied = text));
    await _enter(tester, 'A,B\n1,2');
    await tester.click(_button('copy-output'));
    await tester.click(_button('output-markdown'));
    expect(find.text('Table preserved.'), findsNothing);
    expect(find.tag('table'), findsNothing);
    const markdown = '| A   | B   |\n| --- | --- |\n| 1   | 2   |';
    expect(find.text(markdown), findsOneComponent);
    await tester.click(_button('copy-output'));
    expect(copied, markdown);
  });

  testComponents('column ambiguity requires a choice and allows another choice', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await _enter(tester, List.generate(12, (index) => '$index').join('\n\n'));
    expect(find.text('Columns'), findsOneComponent);
    expect(_copyButton().disabled, isTrue);
    await tester.click(find.componentWithText(button, '3'));
    expect(find.text('4 rows · 3 columns'), findsOneComponent);
    expect(_copyButton().disabled, isFalse);
    await tester.click(find.componentWithText(button, '4'));
    expect(find.text('3 rows · 4 columns'), findsOneComponent);
    await _enter(tester, List.generate(12, (index) => 'new $index').join('\n\n'));
    expect(_copyButton().disabled, isTrue);
  });

  testComponents('invalid input clears stale output and disables copy', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await _enter(tester, 'A,B\n1,2');
    await _enter(tester, 'not a table');
    expect(find.text('CSV detected'), findsNothing);
    expect(find.tag('table'), findsNothing);
    expect(_copyButton().disabled, isTrue);
    expect(
      find.text('Couldn’t read a table. Check the text or choose its format.'),
      findsOneComponent,
    );
    await _enter(tester, '');
    expect(find.textContaining('Couldn’t'), findsNothing);
  });

  testComponents('input format override is respected', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await _enter(tester, 'A,B\n1,2');
    final picker = find.byType(select).evaluate().single.component as select;
    expect(find.text('CSV detected'), findsOneComponent);
    picker.onChange!(['markdown']);
    await tester.pump();
    expect(_copyButton().disabled, isTrue);
    (find.byType(select).evaluate().single.component as select).onChange!(['csv']);
    await tester.pump();
    expect(_copyButton().disabled, isFalse);
    expect(find.text('CSV detected'), findsNothing);
  });

  testComponents('example and clear update both panes', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await tester.click(find.componentWithText(button, 'Try an example'));
    expect(find.text('Engineering'), findsOneComponent);
    expect(find.text('Markdown detected'), findsOneComponent);
    expect(_copyButton().disabled, isFalse);
    await tester.click(find.componentWithText(button, 'Clear'));
    expect(find.tag('table'), findsNothing);
    expect(_copyButton().disabled, isTrue);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Markdown detected'), findsNothing);
  });

  testComponents('clipboard failure offers the exact output for manual copy', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async => throw StateError('denied')));
    await _enter(tester, 'A,B\n1,2');
    await tester.click(_button('copy-output'));
    expect(find.text('Table preserved.'), findsNothing);
    expect(find.text('Copy unavailable. Select the text above and copy.'), findsOneComponent);
    final fallback = find.byComponentPredicate((c) => c is textarea && c.id == 'copy-fallback');
    expect(fallback, findsOneComponent);
    expect((fallback.evaluate().single.component as textarea).readonly, isTrue);
    expect(find.text('A\tB\n1\t2'), findsOneComponent);
  });

  testComponents('finishing an old copy does not mark new output as copied', (tester) async {
    final copy = Completer<void>();
    tester.pumpComponent(TableApp(copyText: (_) => copy.future));
    await _enter(tester, 'A,B\n1,2');
    await tester.click(_button('copy-output'));
    expect(_copyButton().disabled, isTrue);
    await _enter(tester, 'C,D\n3,4');
    copy.complete();
    await tester.pump();
    expect(find.text('Table preserved.'), findsNothing);
    expect(_copyButton().disabled, isFalse);
    expect(find.text('3'), findsOneComponent);
  });

  testComponents('cell markup stays text', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await _enter(tester, 'A,B\n<script>alert(1)</script>,x');
    expect(find.text('<script>alert(1)</script>'), findsOneComponent);
    expect(find.tag('script'), findsNothing);
  });
}

Finder _button(String id) => find.byComponentPredicate((c) => c is button && c.id == id);

button _copyButton() => _button('copy-output').evaluate().single.component as button;

Future<void> _enter(ComponentTester tester, String text) async {
  final input = find.byComponentPredicate((c) => c is textarea && c.id == 'table-input');
  (input.evaluate().single.component as textarea).onInput!(text);
  await tester.pump();
}
