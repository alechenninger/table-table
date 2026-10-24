import 'dart:js_interop';

import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import 'app.dart';

void main() {
  runApp(
    TableApp(copyText: (text) => web.window.navigator.clipboard.writeText(text).toDart),
    attachTo: '#app',
  );
}
