import 'dart:io';

import 'package:table_table/table_table.dart';
import 'package:table_table/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments,
      prog: 'md-table', defaultOutput: OutputFormats.markdown);
}
