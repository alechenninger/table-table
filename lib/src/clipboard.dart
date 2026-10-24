import 'dart:convert';
import 'dart:io';

class ClipboardError implements Exception {
  final String message;

  const ClipboardError(this.message);

  @override
  String toString() => message;
}

/// Native text clipboard access. Kept out of the portable library's exports.
class Clipboard {
  Future<String> read() async => _run(_detectCommands().$1);

  Future<void> write(String text) async {
    await _run(_detectCommands().$2, input: text);
  }

  // Compare text itself: macOS `clipboard info` can be unchanged when different
  // text of the same length is copied. Image changes are outside this adapter.
  Future<String> signature() => read();

  (List<String>, List<String>) _detectCommands() {
    if (Platform.isMacOS && _hasCommand('pbpaste') && _hasCommand('pbcopy')) {
      return (['pbpaste'], ['pbcopy']);
    }
    if (Platform.isWindows) {
      final powershell = _hasCommand('powershell')
          ? 'powershell'
          : _hasCommand('pwsh')
              ? 'pwsh'
              : null;
      if (powershell != null) {
        return (
          [powershell, '-NoProfile', '-Command', 'Get-Clipboard -Raw'],
          [
            powershell,
            '-NoProfile',
            '-Command',
            'Set-Clipboard -Value ([Console]::In.ReadToEnd())'
          ],
        );
      }
    }
    if (_hasCommand('wl-paste') && _hasCommand('wl-copy')) {
      return (['wl-paste', '--no-newline'], ['wl-copy']);
    }
    if (_hasCommand('xclip')) {
      return (
        ['xclip', '-selection', 'clipboard', '-out'],
        ['xclip', '-selection', 'clipboard', '-in'],
      );
    }
    if (_hasCommand('xsel')) {
      return (
        ['xsel', '--clipboard', '--output'],
        ['xsel', '--clipboard', '--input']
      );
    }
    throw const ClipboardError('no supported clipboard command found');
  }

  bool _hasCommand(String command) {
    final separator = Platform.isWindows ? ';' : ':';
    final extensions = Platform.isWindows
        ? [
            '',
            ...(Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
                .split(';')
          ]
        : [''];
    for (final directory
        in (Platform.environment['PATH'] ?? '').split(separator)) {
      for (final extension in extensions) {
        final file = File('${directory.isEmpty ? '.' : directory}'
            '${Platform.pathSeparator}$command$extension');
        final stat = file.statSync();
        if (stat.type == FileSystemEntityType.file &&
            (Platform.isWindows || stat.mode & 0x49 != 0)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<String> _run(List<String> command, {String? input}) async {
    try {
      final process = await Process.start(command.first, command.sublist(1));
      // Listen to every I/O future immediately so decoder or broken-pipe
      // errors cannot escape while another stream is still completing.
      final results = await Future.wait<Object?>([
        process.exitCode,
        process.stdout.transform(utf8.decoder).join(),
        process.stderr.transform(utf8.decoder).join(),
        () async {
          if (input != null) process.stdin.write(input);
          await process.stdin.close();
          return null;
        }(),
      ]);
      final result = results[0] as int;
      final text = results[1] as String;
      final error = results[2] as String;
      if (result != 0) {
        final detail = error.trim().isNotEmpty ? error.trim() : text.trim();
        throw ClipboardError(detail.isEmpty
            ? '${command.first} exited with status $result'
            : detail);
      }
      return text;
    } on ProcessException catch (error) {
      throw ClipboardError(error.message);
    } on IOException catch (error) {
      throw ClipboardError(error.toString());
    } on FormatException catch (error) {
      throw ClipboardError(error.message);
    }
  }
}
