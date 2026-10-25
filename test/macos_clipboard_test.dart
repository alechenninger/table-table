import 'dart:io';
import 'dart:isolate';

import 'package:table_table/src/clipboard.dart';
import 'package:table_table/src/clipboard/macos_clipboard.dart';
import 'package:table_table/src/clipboard/system_clipboard.dart';
import 'package:test/test.dart';

void main() {
  group('AppKit FFI', () {
    late MacOsClipboard clipboard;

    setUp(() {
      clipboard = MacOsClipboard(
          name:
              'table-table.test.$pid.${DateTime.now().microsecondsSinceEpoch}');
    });
    tearDown(() => clipboard.release());

    test('macOS selects the native adapter without initializing a command', () {
      expect(createSystemClipboard(), isA<MacOsClipboard>());
    });

    test('all text representations round trip together on a private pasteboard',
        () async {
      final contents = ClipboardSnapshot({
        ClipboardFormat.plainText: 'Name\tStatus\n李明\t👩🏽‍💻',
        ClipboardFormat.html:
            '<table><tr><td>李明</td><td>👩🏽‍💻 e\u0301</td></tr></table>',
      });
      await clipboard.write(contents);
      expect(await clipboard.read(), contents);
      await clipboard.write(ClipboardSnapshot.text('replacement'));
      expect(await clipboard.read(), ClipboardSnapshot.text('replacement'));
    });

    test(
        'HTML-only, empty, NUL-containing, and long strings retain exact contents',
        () async {
      for (final contents in [
        ClipboardSnapshot({ClipboardFormat.html: '<p>HTML only</p>'}),
        ClipboardSnapshot.text(''),
        ClipboardSnapshot.text('before\u0000after 😀 李明'),
        ClipboardSnapshot.text('x' * 1048576),
        ClipboardSnapshot({}),
      ]) {
        await clipboard.write(contents);
        expect(await clipboard.read(), contents);
      }
    });

    test('repeated reads remain valid across autorelease pool drains',
        () async {
      final contents = ClipboardSnapshot({
        ClipboardFormat.plainText: 'same text',
        ClipboardFormat.html: '<p>same HTML</p>',
      });
      await clipboard.write(contents);
      for (var i = 0; i < 100; i++) {
        expect(await clipboard.read(), contents);
      }
    });

    test('HTML-only changes are visible across independent adapter instances',
        () async {
      final other = MacOsClipboard(name: clipboard.name);
      final before = ClipboardSnapshot({
        ClipboardFormat.plainText: 'same',
        ClipboardFormat.html: '<p>A</p>'
      });
      final after = ClipboardSnapshot({
        ClipboardFormat.plainText: 'same',
        ClipboardFormat.html: '<p>B</p>'
      });
      await clipboard.write(before);
      expect(await other.read(), before);
      await other.write(after);
      expect(await clipboard.read(), after);
      expect(await clipboard.read(), isNot(before));
    });

    test(
        'CLI reads HTML and replaces both formats with output across a process boundary',
        () async {
      const html = '<table><tr><th>A</th><th>B</th></tr>'
          '<tr><td>rich</td><td><p>value</p></td></tr></table>';
      await clipboard.write(ClipboardSnapshot({
        ClipboardFormat.plainText: 'wrong,table',
        ClipboardFormat.html: html
      }));
      final result = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'run',
        'test/fixtures/cli_driver.dart',
        'slack-table',
        '--clipboard'
      ], environment: {
        'TEST_NATIVE_PASTEBOARD': clipboard.name!
      });
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'A\tB\nrich\tvalue\n');
      expect(
          await clipboard.read(), ClipboardSnapshot.text('A\tB\nrich\tvalue'));
    });
    test('concurrent isolates serialize their native reads and writes',
        () async {
      await clipboard.write(ClipboardSnapshot({
        ClipboardFormat.plainText: 'initial',
        ClipboardFormat.html: '<p>initial</p>',
      }));
      final name = clipboard.name!;
      await Future.wait([
        for (var worker = 0; worker < 4; worker++)
          Isolate.run(() => _exercisePasteboard(name, worker)),
      ]);
    });

    test('CLI wait observes a real AppKit HTML-only change', () async {
      final directory =
          await Directory.systemTemp.createTemp('table-clipboard-wait-');
      final marker = File('${directory.path}/reads');
      String html(String value) => '<table><tr><th>A</th><th>B</th></tr>'
          '<tr><td>$value</td><td>value</td></tr></table>';
      await clipboard.write(ClipboardSnapshot({
        ClipboardFormat.plainText: 'unchanged',
        ClipboardFormat.html: html('before'),
      }));
      final process = await Process.start(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'run',
        'test/fixtures/cli_driver.dart',
        'slack-table',
        '--wait',
        '--quiet',
      ], environment: {
        'TEST_NATIVE_PASTEBOARD': clipboard.name!,
        'TEST_NATIVE_READS': marker.path,
      });
      final output = process.stdout.drain<void>();
      final errors = process.stderr.drain<void>();
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!await marker.exists() ||
            (int.tryParse(await marker.readAsString()) ?? 0) < 1) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('CLI did not observe its initial snapshot');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await clipboard.write(ClipboardSnapshot({
          ClipboardFormat.plainText: 'unchanged',
          ClipboardFormat.html: html('after'),
        }));
        expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
        expect(await marker.readAsString(), '2');
        expect(await clipboard.read(),
            ClipboardSnapshot.text('A\tB\nafter\tvalue'));
      } finally {
        process.kill();
        await process.exitCode;
        await Future.wait([output, errors]);
        await directory.delete(recursive: true);
      }
    });
  }, skip: !Platform.isMacOS);

  test('the general clipboard cannot be released', () async {
    expect(MacOsClipboard().release(), throwsA(isA<ClipboardError>()));
  }, skip: !Platform.isMacOS);
}

Future<void> _exercisePasteboard(String name, int worker) async {
  final clipboard = MacOsClipboard(name: name);
  for (var i = 0; i < 25; i++) {
    final value = '$worker:$i';
    await clipboard.write(ClipboardSnapshot({
      ClipboardFormat.plainText: value,
      ClipboardFormat.html: '<p>$value</p>',
    }));
    final observed = await clipboard.read();
    final text = observed[ClipboardFormat.plainText];
    if (text == null || observed[ClipboardFormat.html] != '<p>$text</p>') {
      throw StateError('native operations returned mixed clipboard contents');
    }
  }
}
