import 'package:string_width/string_width.dart';
import 'package:table_table/src/display_width.dart';
import 'package:test/test.dart';

void main() {
  test('cached width matches the original Unicode rules across calls', () {
    final samples = [
      '',
      'Plain ASCII 123 | \\',
      String.fromCharCodes(List.generate(256, (i) => i)),
      '李明 São Paulo 東京',
      'ＡＢ ｶﾅ 𠮷野',
      'e\u0301 \u0301x',
      '👩🏽‍💻 🇯🇵 ❤️',
      '👨‍👩‍👧‍👦 🤦🏼‍♂️',
      '1\ufe0f\u20e3',
      '🇦🇦🇨',
      '\x1b[31m李明\x1b[0m',
      '\x1b]8;;https://example.com\x07label\x1b]8;;\x07',
      '\x9b31mred\x9b0m',
      '\x00\x7f\x85',
      '\ud800x\udc00',
    ];
    // Combining strings also checks boundaries where matching an emoji can
    // affect segmentation. Reusing the matchers must not retain match state.
    for (var repeat = 0; repeat < 2; repeat++) {
      for (final left in samples) {
        for (final right in samples) {
          final value = left + right;
          expect(displayWidth(value), stringWidth(value), reason: value);
        }
      }
    }
  });
}
