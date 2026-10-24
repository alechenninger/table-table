import 'dart:io';

import 'package:slack_table/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments, prog: 'table-table');
}
