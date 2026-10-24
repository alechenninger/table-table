import 'dart:js_interop';

import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import 'app.dart';

void main() {
  web.document.addEventListener('keydown', _handleInputKeyDown.toJS);
  runApp(
    TableApp(copyText: (text) => web.window.navigator.clipboard.writeText(text).toDart),
    attachTo: '#app',
  );
}

void _handleInputKeyDown(web.Event event) {
  final key = event as web.KeyboardEvent;
  if (key.key != 'Tab' ||
      key.shiftKey ||
      key.ctrlKey ||
      key.altKey ||
      key.metaKey ||
      key.isComposing) {
    return;
  }

  final target = key.target;
  if (target == null || !target.isA<web.HTMLTextAreaElement>()) return;
  final input = target as web.HTMLTextAreaElement;
  if (input.id != 'table-input') return;

  key.preventDefault();
  input.setRangeText('\t', input.selectionStart, input.selectionEnd, 'end');
  input.dispatchEvent(
    web.InputEvent('input', web.InputEventInit(bubbles: true, inputType: 'insertText', data: '\t')),
  );
}
