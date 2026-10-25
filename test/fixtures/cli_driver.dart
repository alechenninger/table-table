import 'dart:convert';
import 'dart:io';

import 'package:table_table/slack_table.dart';
import 'package:table_table/src/cli.dart';
import 'package:table_table/src/clipboard.dart';
import 'package:table_table/src/clipboard/command_clipboard.dart';
import 'package:table_table/src/clipboard/macos_clipboard.dart';

/// Compose the real CLI with an isolated clipboard for process-boundary tests.
/// Production entry points never read these test environment variables.
Future<void> main(List<String> arguments) async {
  final prog = arguments.first;
  exitCode = await runCli(arguments.sublist(1),
      prog: prog,
      defaultOutput:
          prog == 'md-table' ? OutputFormats.markdown : OutputFormats.slack,
      clipboard: _TestClipboard());
}

class _TestClipboard implements Clipboard {
  late final Clipboard _backend = _createBackend();
  int _nativeReads = 0;

  @override
  Future<ClipboardSnapshot> read() async {
    final snapshot = await _backend.read();
    final marker = Platform.environment['TEST_NATIVE_READS'];
    if (marker != null) {
      await File(marker).writeAsString('${++_nativeReads}');
    }
    return snapshot;
  }

  @override
  Future<void> write(ClipboardSnapshot contents) => _backend.write(contents);

  Clipboard _createBackend() {
    final nativeName = Platform.environment['TEST_NATIVE_PASTEBOARD'];
    if (nativeName != null) return MacOsClipboard(name: nativeName);
    final sequence = Platform.environment['TEST_CLIPBOARD_SNAPSHOTS'];
    if (sequence != null) return _SequenceClipboard(File(sequence));
    return CommandClipboard.detect();
  }
}

class _SequenceClipboard implements Clipboard {
  final List<ClipboardSnapshot> _snapshots;
  int _reads = 0;

  _SequenceClipboard(File source)
      : _snapshots = [
          for (final values in jsonDecode(source.readAsStringSync()) as List)
            ClipboardSnapshot({
              for (final entry in (values as Map).entries)
                ClipboardFormat.values
                        .firstWhere((format) => format.mediaType == entry.key):
                    entry.value as String,
            }),
        ];

  @override
  Future<ClipboardSnapshot> read() async {
    final index = _reads < _snapshots.length ? _reads : _snapshots.length - 1;
    _reads++;
    await File(Platform.environment['TEST_READS']!).writeAsString('$_reads');
    return _snapshots[index];
  }

  @override
  Future<void> write(ClipboardSnapshot contents) =>
      File(Platform.environment['TEST_CLIPBOARD_RESULT']!)
          .writeAsString(jsonEncode({
        for (final entry in contents.representations.entries)
          entry.key.mediaType: entry.value,
      }));
}
