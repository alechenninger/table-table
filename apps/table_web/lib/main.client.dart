import 'dart:js_interop';

import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import 'app.dart';
import 'clipboard_paste.dart';

void main() {
  runApp(
    TableApp(
      copyText: (text) => web.window.navigator.clipboard.writeText(text).toDart,
      bindInputPaste: (onPaste) =>
          (event) => _handleInputPaste(event, onPaste),
      onInputKeyDown: _handleInputKeyDown,
      onLoveMouseMove: _handleLoveMouseMove,
    ),
    attachTo: '#app',
  );
}

void _handleInputPaste(web.Event event, void Function(ParsedInput) onPaste) {
  final input = event.currentTarget as web.HTMLTextAreaElement;
  final clipboard = (event as web.ClipboardEvent).clipboardData;
  final html = clipboard?.getData('text/html') ?? '';
  if (html.isEmpty) return;
  final start = input.selectionStart;
  final end = input.selectionEnd;
  final pasted = htmlTablePaste(input.value.replaceRange(start, end, html));
  if (pasted == null) return;

  event.preventDefault();
  input.setRangeText(html, start, end, 'end');
  onPaste(pasted);
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

  final input = event.currentTarget as web.HTMLTextAreaElement;

  key.preventDefault();
  input.setRangeText('\t', input.selectionStart, input.selectionEnd, 'end');
  input.dispatchEvent(
    web.InputEvent('input', web.InputEventInit(bubbles: true, inputType: 'insertText', data: '\t')),
  );
}

void _handleLoveMouseMove(web.Event event) {
  if (!web.window
      .matchMedia('(hover: hover) and (prefers-reduced-motion: no-preference)')
      .matches) {
    return;
  }

  final love = event.currentTarget as web.HTMLElement;
  final pointer = event as web.MouseEvent;
  final bounds = love.getBoundingClientRect();
  love.style.setProperty('--love-light-x', '${pointer.clientX - bounds.left}px');
  love.style.setProperty('--love-light-y', '${pointer.clientY - bounds.top}px');
}
