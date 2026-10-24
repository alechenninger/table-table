The Unicode width rules in `lib/src/display_width.dart` are adapted from
`string_width` 0.1.5 by Huiyuan Zhu, licensed under Apache-2.0 (see `LICENSE`).
The adaptation caches ANSI and emoji matchers and adds a printable-ASCII fast
path. The original package remains a development dependency for parity tests.
