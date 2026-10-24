// Adapted from string_width 0.1.5, Copyright 2022 Huiyuan Zhu Limited.
// Licensed under Apache-2.0; see ../../third_party/string_width/LICENSE.
// Modified to cache matchers and add a printable-ASCII fast path.

import 'package:ansi_regex/ansi_regex.dart';
import 'package:characters/characters.dart';
import 'package:east_asian_width/east_asian_width.dart';
import 'package:emoji_regex/emoji_regex.dart';

final _ansi = ansiRegex();
final _emoji = emojiRegex();

/// Display width with the same rules as string_width's default narrow mode.
int displayWidth(String value) {
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code < 0x20 || code > 0x7e) return _unicodeWidth(value);
  }
  return value.length;
}

int _unicodeWidth(String value) {
  // Replace whole emoji sequences before segmenting graphemes, preserving
  // the existing behavior for flags, variation selectors, and ZWJ sequences.
  value = value.replaceAll(_ansi, '').replaceAll(_emoji, '  ');
  var width = 0;
  for (final character in value.characters) {
    final code = character.codeUnitAt(0);
    if (code <= 0x1f ||
        (code >= 0x7f && code <= 0x9f) ||
        (code >= 0x300 && code <= 0x36f)) {
      continue;
    }
    final category = eastAsianWidth(character);
    width +=
        category == EastAsianWidth.fullwidth || category == EastAsianWidth.wide
            ? 2
            : 1;
  }
  return width;
}
