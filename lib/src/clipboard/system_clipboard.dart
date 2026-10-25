import 'dart:io';

import '../clipboard.dart';
import 'command_clipboard.dart';
import 'macos_clipboard.dart';

Clipboard createSystemClipboard() =>
    Platform.isMacOS ? MacOsClipboard() : CommandClipboard.detect();
