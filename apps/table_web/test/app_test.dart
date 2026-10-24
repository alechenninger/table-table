import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart' show Text;
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
    expect(find.text('1 data row · 2 columns'), findsOneComponent);
    expect(find.text('Auto: CSV'), findsOneComponent);
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
    expect(find.text('3 data rows · 3 columns'), findsOneComponent);
    expect(_copyButton().disabled, isFalse);
    await tester.click(find.componentWithText(button, '4'));
    expect(find.text('2 data rows · 4 columns'), findsOneComponent);
    await _enter(tester, List.generate(12, (index) => 'new $index').join('\n\n'));
    expect(_copyButton().disabled, isTrue);
  });

  testComponents('Unicode preview preserves the exact Markdown source when copied', (tester) async {
    String? copied;
    tester.pumpComponent(TableApp(copyText: (text) async => copied = text));
    await _enter(tester, 'Owner\tCity\tStatus\n李明\tSão Paulo\t👩🏽‍💻\n山田太郎\t東京\te\u0301');
    await tester.click(_button('output-markdown'));
    final previewText = find
        .descendant(of: find.tag('pre'), matching: find.byType(Text))
        .evaluate()
        .map((element) => (element.component as Text).text)
        .join();
    const markdown =
        '| Owner    | City      | Status |\n'
        '| -------- | --------- | ------ |\n'
        '| 李明     | São Paulo | 👩🏽‍💻     |\n'
        '| 山田太郎 | 東京      | e\u0301      |';
    expect(previewText, markdown);
    await tester.click(_button('copy-output'));
    expect(copied, markdown);
  });

  testComponents('output switches preserve unresolved and selected column choices', (tester) async {
    String? copied;
    tester.pumpComponent(TableApp(copyText: (text) async => copied = text));
    await _enter(tester, 'A\n\nB\n\nC\n\n1\n\n2\n\n3');
    await tester.click(_button('output-markdown'));
    expect(find.text('Columns'), findsOneComponent);
    expect(_copyButton().disabled, isTrue);

    await tester.click(find.componentWithText(button, '3'));
    expect(find.text('1 data row · 3 columns'), findsOneComponent);
    await tester.click(_button('copy-output'));
    expect(copied, '| A   | B   | C   |\n| --- | --- | --- |\n| 1   | 2   | 3   |');

    await tester.click(_button('output-slack'));
    expect(find.text('Table preserved.'), findsNothing);
    expect(find.text('Columns'), findsOneComponent);
    final selected = find.componentWithText(button, '3').evaluate().single.component as button;
    expect(selected.attributes?['aria-pressed'], 'true');
    await tester.click(_button('copy-output'));
    expect(copied, 'A\tB\tC\n1\t2\t3');

    await tester.click(find.componentWithText(button, '2'));
    expect(find.text('2 data rows · 2 columns'), findsOneComponent);
    await tester.click(_button('copy-output'));
    expect(copied, 'A\tB\nC\t1\n2\t3');
  });

  testComponents('invalid input clears stale output and disables copy', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await _enter(tester, 'A,B\n1,2');
    await _enter(tester, 'not a table');
    expect(find.text('Auto: CSV'), findsNothing);
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
    expect(find.text('Auto: CSV'), findsOneComponent);
    picker.onChange!(['markdown']);
    await tester.pump();
    expect(_copyButton().disabled, isTrue);
    (find.byType(select).evaluate().single.component as select).onChange!(['csv']);
    await tester.pump();
    expect(_copyButton().disabled, isFalse);
    expect(find.text('Auto: CSV'), findsNothing);
  });

  for (final example in [
    (
      source: 'From Google Sheets',
      format: 'TSV',
      output: 'Name\tRole\nAda\tEngineering\nSam\tDesign',
    ),
    (
      source: 'From markdown',
      format: 'Markdown',
      output: 'Day\tPlan\nSaturday\tFarmers market\nSunday\tHike',
    ),
    (
      source: 'From ChatGPT app',
      format: 'TSV',
      output: 'Task\tStatus\nDraft proposal\tDone\nReview\tIn progress',
    ),
  ]) {
    testComponents('${example.source} example and clear update both panes', (tester) async {
      String? copied;
      tester.pumpComponent(TableApp(copyText: (text) async => copied = text));
      expect(find.text('From'), findsNothing);
      expect(find.text('To'), findsNothing);
      // Loading an example restores auto-detection after a manual format choice.
      (find.byType(select).evaluate().single.component as select).onChange!(['csv']);
      await tester.pump();
      await tester.click(find.componentWithText(button, 'Try an example'));
      expect(find.tag('table'), findsNothing);
      await tester.click(find.componentWithText(button, example.source));
      expect(find.text('Auto: ${example.format}'), findsOneComponent);
      expect(find.text('2 data rows · 2 columns'), findsOneComponent);
      expect(_copyButton().disabled, isFalse);
      await tester.click(_button('copy-output'));
      expect(copied, example.output);
      await tester.click(find.componentWithText(button, 'Clear input'));
      expect(find.tag('table'), findsNothing);
      expect(_copyButton().disabled, isTrue);
      expect(find.text('Clear input'), findsNothing);
      expect(find.text('Auto: ${example.format}'), findsNothing);
    });
  }

  testComponents('undo clear restores exact input and its source format', (tester) async {
    String? copied;
    tester.pumpComponent(TableApp(copyText: (text) async => copied = text));
    const input = 'Name,Count\nAda,12\n';
    await _enter(tester, input);
    (find.byType(select).evaluate().single.component as select).onChange!(['csv']);
    await tester.pump();
    await tester.click(_button('input-action'));
    expect(find.text('Undo clear'), findsOneComponent);
    expect(find.text('Input cleared. Use Undo clear to restore it.'), findsOneComponent);
    expect(find.tag('table'), findsNothing);
    expect(_copyButton().disabled, isTrue);

    // Undo restores parsing settings but respects the current output destination.
    (find.byType(select).evaluate().single.component as select).onChange!(['tsv']);
    await tester.pump();
    await tester.click(_button('output-markdown'));
    await tester.click(_button('input-action'));
    expect(find.text('Undo clear'), findsNothing);
    expect(find.text('Clear input'), findsOneComponent);
    expect(find.text(input), findsOneComponent);
    expect((find.byType(select).evaluate().single.component as select).value, 'csv');
    await tester.click(_button('copy-output'));
    expect(copied, '| Name | Count |\n| ---- | ----- |\n| Ada  | 12    |');
  });

  testComponents('undo clear restores a chosen column count', (tester) async {
    tester.pumpComponent(TableApp(copyText: (_) async {}));
    await _enter(tester, 'A\n\nB\n\nC\n\n1\n\n2\n\n3');
    await tester.click(find.componentWithText(button, '3'));
    await tester.click(_button('input-action'));
    await tester.click(_button('input-action'));
    expect(find.text('1 data row · 3 columns'), findsOneComponent);
    final selected = find.componentWithText(button, '3').evaluate().single.component as button;
    expect(selected.attributes?['aria-pressed'], 'true');
    expect(_copyButton().disabled, isFalse);
  });

  for (final useExample in [false, true]) {
    testComponents('new input replaces undo history (example: $useExample)', (tester) async {
      tester.pumpComponent(TableApp(copyText: (_) async {}));
      await _enter(tester, 'Old,Value\nBefore,1');
      await tester.click(_button('input-action'));
      if (useExample) {
        await tester.click(find.componentWithText(button, 'From Google Sheets'));
      } else {
        await _enter(tester, 'New,Value\nAfter,2');
      }
      expect(find.text('Undo clear'), findsNothing);
      await tester.click(_button('input-action'));
      await tester.click(_button('input-action'));
      expect(find.text('Before'), findsNothing);
      expect(find.text(useExample ? 'Ada' : 'After'), findsOneComponent);
    });
  }

  testComponents('undo clear cannot restore an obsolete pending copy status', (tester) async {
    final pending = Completer<void>();
    tester.pumpComponent(TableApp(copyText: (_) => pending.future));
    await _enter(tester, 'A,B\n1,2');
    await tester.click(_button('copy-output'));
    await tester.click(_button('input-action'));
    await tester.click(_button('input-action'));
    pending.complete();
    await tester.pump();
    expect(find.text('Table preserved.'), findsNothing);
    expect(_copyButton().disabled, isFalse);
    expect(find.tag('table'), findsOneComponent);
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

  for (final oldCopyFails in [false, true]) {
    testComponents('obsolete copy (fails: $oldCopyFails) cannot change a newer copy', (
      tester,
    ) async {
      final oldCopy = Completer<void>();
      final newCopy = Completer<void>();
      final copied = <String>[];
      tester.pumpComponent(
        TableApp(
          copyText: (text) {
            copied.add(text);
            return copied.length == 1 ? oldCopy.future : newCopy.future;
          },
        ),
      );
      await _enter(tester, 'A,B\n1,2');
      await tester.click(_button('copy-output'));
      await tester.click(_button('output-markdown'));
      expect(_copyButton().disabled, isFalse);
      await tester.click(_button('copy-output'));
      expect(_copyButton().disabled, isTrue);

      if (oldCopyFails) {
        oldCopy.completeError(StateError('old copy denied'));
      } else {
        oldCopy.complete();
      }
      await tester.pump();
      expect(_copyButton().disabled, isTrue);
      expect(find.text('Table preserved.'), findsNothing);
      expect(find.textContaining('Copy unavailable'), findsNothing);

      newCopy.complete();
      await tester.pump();
      expect(_copyButton().disabled, isFalse);
      expect(find.text('Table preserved.'), findsOneComponent);
      expect(copied, ['A\tB\n1\t2', '| A   | B   |\n| --- | --- |\n| 1   | 2   |']);
    });
  }

  testComponents('manual copy remains available during a retry and clears on success', (
    tester,
  ) async {
    final retry = Completer<void>();
    var attempts = 0;
    tester.pumpComponent(
      TableApp(
        copyText: (_) {
          if (++attempts == 1) throw StateError('denied');
          return retry.future;
        },
      ),
    );
    await _enter(tester, 'A,B\n1,2');
    await tester.click(_button('copy-output'));
    await tester.click(_button('copy-output'));
    expect(_copyButton().disabled, isTrue);
    expect(find.text('A\tB\n1\t2'), findsOneComponent);
    expect(find.textContaining('Copy unavailable'), findsOneComponent);

    retry.complete();
    await tester.pump();
    expect(find.textContaining('Copy unavailable'), findsNothing);
    expect(find.tag('table'), findsOneComponent);
    expect(find.text('Table preserved.'), findsOneComponent);
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
