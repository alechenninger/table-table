import 'dart:js_interop';

import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import 'app.dart';

void main() {
  web.document.addEventListener('keydown', _handleInputKeyDown.toJS);
  runApp(
    TableApp(
      copyText: (text) => web.window.navigator.clipboard.writeText(text).toDart,
      onLoveMouseMove: _handleLoveMouseMove,
    ),
    attachTo: '#app',
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
