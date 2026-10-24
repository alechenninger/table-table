import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../slack_table.dart';
import 'clipboard.dart';

/// Run the native text CLI. The portable core never imports this library.
Future<int> runCli(
  List<String> arguments, {
  String prog = 'slack-table',
  String defaultOutput = OutputFormats.slack,
}) async {
  final parser = _buildParser(defaultOutput);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('$prog: ${error.message}');
    return 2;
  }
  if (args.flag('help')) {
    stdout.writeln('Usage: $prog [options] [files...]\n\n'
        'Convert pasted or piped tables to Slack-native data or Markdown.\n\n'
        '${parser.usage}\n\n'
        'Omit files for stdin or the clipboard. Use - to read stdin among files.\n'
        'Image/OCR input is not yet available in the Dart CLI.');
    return 0;
  }
  if (args.flag('version')) {
    stdout.writeln('$prog 0.1.0');
    return 0;
  }

  final cli = _Cli(args);
  final interrupt = ProcessSignal.sigint.watch().listen((_) {
    stderr.writeln('$prog: interrupted');
    exit(130);
  });
  try {
    await cli.run();
    return 0;
  } on _CliError catch (error) {
    stderr.writeln('$prog: ${error.message}');
    return 2;
  } on ClipboardError catch (error) {
    stderr.writeln('$prog: ${error.message}');
    return 2;
  } on ParseError catch (error) {
    stderr.writeln('$prog: ${error.message}');
    return 2;
  } on FileSystemException catch (error) {
    stderr.writeln('$prog: ${error.message}: ${error.path}');
    return 2;
  } on FormatException catch (error) {
    stderr.writeln('$prog: ${error.message}');
    return 2;
  } finally {
    await cli.close();
    await interrupt.cancel();
  }
}

class _CliError implements Exception {
  final String message;

  const _CliError(this.message);
}

class _Cli {
  final ArgResults args;
  final Clipboard _clipboard = Clipboard();
  final StreamIterator<String> _input = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  late final int? _columns;

  _Cli(this.args);

  Future<void> run() async {
    _columns = _columnCount(args.option('columns'));
    final (table, copyByDefault) = await _readTable();
    final outputFormat = args.option('output')!;
    final output = formatTable(table, outputFormat: outputFormat);
    if (args.flag('copy') || copyByDefault) {
      await _clipboard.write(output);
      if (!args.flag('quiet') && stderr.hasTerminal) {
        final label = outputFormat == OutputFormats.markdown
            ? 'Markdown table'
            : 'Slack-native table data';
        stderr.writeln('Copied $label to the clipboard.');
      }
    }
    if (!args.flag('quiet')) stdout.writeln(output);
  }

  Future<void> close() => _input.cancel();

  Future<(Table, bool)> _readTable() async {
    if (args.flag('wait')) {
      if (args.rest.isNotEmpty || args.flag('clipboard')) {
        throw const _CliError(
            '--wait cannot be combined with files or --clipboard');
      }
      return (await _waitForClipboardTable(), true);
    }
    if (args.flag('clipboard')) {
      if (args.rest.isNotEmpty) {
        throw const _CliError('--clipboard cannot be combined with files');
      }
      return (await _readClipboardTable(), true);
    }
    if (args.rest.isNotEmpty) {
      final chunks = <String>[];
      for (final name in args.rest) {
        chunks.add(
            name == '-' ? await _readStdin() : await File(name).readAsString());
      }
      return (await _parseText(chunks.join('\n')), false);
    }
    if (!stdin.hasTerminal) {
      return (await _parseText(await _readStdin()), false);
    }
    try {
      return (await _readClipboardTable(), true);
    } on _CliError {
      if (stderr.hasTerminal) {
        stderr.writeln('Paste a table, then press Ctrl-D:');
      }
      return (await _parseText(await _readStdin()), true);
    }
  }

  Future<Table> _readClipboardTable() async {
    final String text;
    try {
      text = await _clipboard.read();
    } on ClipboardError catch (error) {
      throw _CliError('could not read clipboard text: $error');
    }
    return _parseClipboardText(text);
  }

  Future<Table> _parseClipboardText(String text) {
    if (text.trim().isEmpty) {
      throw const _CliError('no table text found on the clipboard');
    }
    return _parseText(text);
  }

  Future<Table> _waitForClipboardTable() async {
    final String original;
    try {
      original = await _clipboard.read();
    } on ClipboardError catch (error) {
      throw _CliError('could not read clipboard: $error');
    }
    if (stderr.hasTerminal) {
      stderr
          .writeln('Copy a table now. Waiting for the clipboard to change...');
    }
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final String current;
      try {
        current = await _clipboard.read();
      } on ClipboardError catch (error) {
        throw _CliError('could not read clipboard: $error');
      }
      // Compare text itself, including same-length changes, and parse the
      // observed value without reading a potentially newer clipboard value.
      if (current != original) return _parseClipboardText(current);
    }
  }

  Future<Table> _parseText(String text) async {
    final format = args.option('input')!;
    try {
      return parseTable(text, inputFormat: format, columns: _columns);
    } on AmbiguousColumnsError catch (error) {
      if (!stdin.hasTerminal) {
        throw _CliError('$error; specify one with --columns N');
      }
      final columns = await _promptForColumnCount(error.candidates);
      return parseTable(text, inputFormat: format, columns: columns);
    }
  }

  Future<int> _promptForColumnCount(List<int> candidates) async {
    final label = candidates.join(', ');
    while (true) {
      stderr.write('Number of columns ($label): ');
      await stderr.flush();
      if (!await _input.moveNext()) {
        throw const _CliError('no column count selected');
      }
      final selected = int.tryParse(_input.current.trim(), radix: 10);
      if (candidates.contains(selected)) return selected!;
      stderr.writeln('Choose one of: $label.');
    }
  }

  Future<String> _readStdin() async {
    final text = StringBuffer();
    while (await _input.moveNext()) {
      text.writeln(_input.current);
    }
    return text.toString();
  }
}

ArgParser _buildParser(String defaultOutput) => ArgParser()
  ..addOption('input',
      allowed: InputFormats.values,
      defaultsTo: InputFormats.auto,
      help: 'Input format to parse.')
  ..addOption('columns',
      valueHelp: 'N',
      help:
          'Column count for blank-line-separated cells; prompts if ambiguous.')
  ..addOption('output',
      allowed: OutputFormats.values,
      defaultsTo: defaultOutput,
      help: 'Output format.')
  ..addFlag('copy',
      abbr: 'c',
      negatable: false,
      help: 'Copy the formatted table to the clipboard.')
  ..addFlag('clipboard',
      aliases: ['clip'],
      negatable: false,
      help: 'Read from the clipboard and copy the result back.')
  ..addFlag('wait',
      negatable: false,
      help: 'Wait for clipboard text to change, convert it, copy it, and exit.')
  ..addFlag('quiet',
      abbr: 'q',
      negatable: false,
      help: 'Do not print the formatted table to stdout.')
  ..addFlag('version', negatable: false, help: 'Show the version.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

int? _columnCount(String? value) {
  if (value == null) return null;
  final columns = int.tryParse(value.trim(), radix: 10);
  if (columns == null) {
    throw const _CliError('argument --columns: must be an integer');
  }
  if (columns < 2) {
    throw const _CliError('argument --columns: must be at least 2');
  }
  return columns;
}
