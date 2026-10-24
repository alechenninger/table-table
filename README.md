# table-table

Convert Markdown, CSV, TSV, Cursor canvas, Jira Rovo copies, or simple
pipe-delimited tables into tab-separated rows for pasting into Slack, or padded
Markdown tables.

Paste a table into the Jaspr web app and copy it for Slack or Markdown. Conversion
runs in your browser; table contents are not uploaded or saved.

The same Dart core powers the web app and the `table-table` CLI. The existing
`slack-table` and `md-table` commands remain available: `table-table` and
`slack-table` default to Slack TSV, while `md-table` defaults to Markdown.

## Web app

Requires Dart 3.10 or newer for Jaspr, and Node.js 20 or newer for the daisyUI
and Tailwind CSS build. From this checkout:

```sh
cd apps/table_web
dart pub get
npm ci
npm run dev
```

Open the local URL printed by Jaspr. Paste into the input, choose an output
format, and copy. Column choices appear only when needed. If clipboard access
is unavailable, the app exposes selectable output for manual copying.

To create a static deployment:

```sh
npm run build
```

Serve `apps/table_web/build/jaspr/` with any static host. Use HTTPS outside
localhost for browser clipboard access. No backend, accounts, external fonts,
analytics, ads, or storage are configured.

## Run or install

Requires Dart 3.4 or newer. From this checkout:

```sh
dart pub get
dart run bin/table_table.dart table.md
dart run bin/md_table.dart table.csv
```

Install all three commands into Dart's global executable directory:

```sh
dart pub global activate --source path .
```

Add Dart's global executable directory to your `PATH` if needed (normally
`$HOME/.pub-cache/bin` on macOS/Linux). If the Python version is already
installed, ensure the Dart commands appear first on your `PATH`.

Alternatively, build standalone executables that do not require Python or a
Dart SDK at runtime:

```sh
mkdir -p build
dart compile exe bin/slack_table.dart -o build/slack-table
dart compile exe bin/md_table.dart -o build/md-table
dart compile exe bin/table_table.dart -o build/table-table
./build/table-table table.md
```

## Usage

```sh
# Pipe input and print Slack table paste data.
cat table.md | slack-table

# Pipe input and copy the result too.
cat table.md | slack-table --copy

# With an interactive terminal, read the clipboard and replace it with output.
slack-table

# Explicitly use the clipboard, even when stdin is redirected.
slack-table --clipboard

# Wait for clipboard text to change, convert it, copy it, and exit.
slack-table --wait -q

# Read files; - reads stdin among the files.
slack-table table.md
slack-table header.csv - < body.csv

# Render Markdown instead of Slack TSV.
slack-table table.csv --output markdown
md-table table.csv
md-table --wait -q
```

Example input:

```md
| Header A | Header B |
| --- | --- |
| Data 1A | Data 1B |
| Data 2A | Data 2B |
```

Default output (columns are separated by tabs):

```text
Header A	Header B
Data 1A	Data 1B
Data 2A	Data 2B
```

With `--output markdown`:

```md
| Header A | Header B |
| -------- | -------- |
| Data 1A  | Data 1B  |
| Data 2A  | Data 2B  |
```

Use `--input markdown`, `--input cursor`, `--input csv`, `--input tsv`,
`--input pipe`, or `--input spaced` to force a parser. The default is `auto`.
For blank-line-separated cells with multiple possible column counts, interactive
input prompts for a choice. Use `--columns N` in scripts or pipelines.

File and piped input print to stdout; add `--copy` to also copy the result.
Interactive clipboard input, `--clipboard` (alias `--clip`), and `--wait` copy
the result by default. `--quiet` (`-q`) suppresses stdout, but leaves errors on
stderr. An empty clipboard in interactive mode falls back to terminal paste,
finished with Ctrl-D. Successful commands exit with 0, input/usage/clipboard
errors with 2, and Ctrl-C with 130. Run `--help` for options.

Text clipboard integration uses `pbpaste`/`pbcopy` on macOS, PowerShell on
Windows, and `wl-paste`/`wl-copy`, `xclip`, or `xsel` on Linux. `--wait` compares
clipboard text, including changes that keep the same text length.

## Reuse the core

```dart
import 'package:slack_table/slack_table.dart';

final output = render('Name,Count\nAlpha,12');
final markdown = render('Name,Count\nAlpha,12', outputFormat: 'markdown');

final table = parseTable('Name,Count\nAlpha,12', inputFormat: 'csv');
final rows = table.rows;
final detectedFormat = table.sourceFormat;
final formatted = formatMarkdown(table);
```

The API also exports `Table`, `formatTable`, `formatTsv`, `ParseError`, and
`AmbiguousColumnsError`. `InputFormats` and `OutputFormats` provide shared string
constants and `values` lists for frontend format choices; existing string
arguments remain supported. Ambiguous input carries a `candidates` list so each
frontend can obtain a column count and retry. Output strings do not include a
terminal newline; the CLI adds one when printing. The core performs no I/O and
does not import the CLI or clipboard implementation.

Parsing order, whitespace normalization, CSV quoting, and Markdown padding
preserve the Python behavior. Markdown widths count Unicode code points, not
terminal display columns or grapheme clusters.

## Test

After `dart pub get`, run the core contracts directly in Dart:

```sh
dart test
```

The 28 tests in `test/core_test.dart` and `test/core_regressions_test.dart`
preserve the Python tests' inputs, expected outputs, and error assertions. They
call the Dart library directly, without Python or subprocesses. Both suites
passed against Dart before the temporary Python-to-Dart bridge was removed.

For the full check, including CLI subprocess contracts and the retained Python
reference suite, use Python 3.9+ (no third-party Python packages are needed):

```sh
python3 tool/check.py
```

This checks formatting and static analysis, runs the Dart core tests, builds both
legacy CLIs and `table-table`, then runs:

1. The original Python suite plus additional migration regression cases against
   the retained Python implementation.
2. Python CLI subprocess contracts using temporary clipboard commands and POSIX
   terminals, without reading or changing your actual clipboard. This harness
   runs on macOS/Linux; Windows clipboard integration has not been verified.
3. Browser compilation of the public core API. If Node is installed, the
   resulting JavaScript also runs a smoke test.

The original Python tests remain in `tests/` as reference coverage for the
retained implementation. Dart CLI behavior is checked independently through
`tests/cli_contract/`, which invokes the real compiled executables. The original
CLI/clipboard/OCR mock-based tests only exercise the Python implementation.

For Jaspr's component tests, run `dart test` in `apps/table_web`. After installing
Dart dependencies in both packages and running `npm ci` in `apps/table_web`,
`python3 tool/check.py --web` runs the complete
check, including Jaspr analysis, component tests, and a production web build.

## Python reference and OCR

The original implementation remains in `src/slack_table`, with its original
tests and packaging, as the migration reference. Its image/OCR functionality is
**not ported to Dart**. The Dart CLI currently accepts text input only and does
not require Tesseract. See [the Python reference instructions](docs/python-reference.md)
to use the previous implementation, including its optional runtime OCR paths.

When OCR is added to Dart, it can supply a `Table` to the same formatters. Engine
integration and image access can remain outside the portable text core.
