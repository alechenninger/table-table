import 'dart:io';

import 'package:table_table/table_table.dart';
import 'package:table_table/src/clipboard.dart';
import 'package:table_table/src/clipboard/macos_clipboard.dart';
import 'package:table_table/src/clipboard_table.dart';

/// Exercise the real AppKit ABI in a private pasteboard, including under AOT.
Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    print('AppKit clipboard smoke check requires macOS.');
    return;
  }
  final clipboard = MacOsClipboard(
      name: 'table-table.smoke.$pid.${DateTime.now().microsecondsSinceEpoch}');
  // Confirm access before entering cleanup, so a sandbox denial isn't masked
  // by a second failed attempt to release a pasteboard that was never opened.
  await clipboard.read();
  try {
    const html = '<table><tr><th>Name</th><th>Role</th></tr>'
        '<tr><td>李明 👩🏽‍💻</td><td><p>Engineering</p></td></tr></table>';
    final contents = ClipboardSnapshot({
      ClipboardFormat.plainText: 'Name\tRole\nmissing\ttext',
      ClipboardFormat.html: html,
    });
    await clipboard.write(contents);
    final observed = await clipboard.read();
    if (observed != contents) {
      throw StateError('native formats did not round trip');
    }
    if (formatTsv(parseClipboardTable(observed)) !=
        'Name\tRole\n李明 👩🏽‍💻\tEngineering') {
      throw StateError('HTML representation was not selected');
    }
    if (arguments.isNotEmpty) {
      final result = await Process.run(
          arguments.single, ['slack-table', '--clipboard'],
          environment: {'TEST_NATIVE_PASTEBOARD': clipboard.name!});
      if (result.exitCode != 0 ||
          result.stdout != 'Name\tRole\n李明 👩🏽‍💻\tEngineering\n') {
        throw StateError('compiled native CLI failed: ${result.stderr}');
      }
      if (await clipboard.read() !=
          ClipboardSnapshot.text('Name\tRole\n李明 👩🏽‍💻\tEngineering')) {
        throw StateError(
            'compiled native CLI did not replace the private pasteboard');
      }
    }
    for (final text in ['', 'before\u0000after 李明 😀 e\u0301', 'x' * 1048576]) {
      final expected = ClipboardSnapshot.text(text);
      await clipboard.write(expected);
      if (await clipboard.read() != expected) {
        throw StateError('native string did not round trip');
      }
    }
    await clipboard.write(ClipboardSnapshot({}));
    if ((await clipboard.read()).representations.isNotEmpty) {
      throw StateError('private pasteboard was not cleared');
    }
    print('AppKit FFI clipboard smoke check passed (private pasteboard).');
  } finally {
    await clipboard.release();
  }
}
