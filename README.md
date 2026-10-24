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

### Install native commands globally (macOS/Linux)

Requires Make and Dart on your `PATH`. From the repository root, build all three
native commands:

```sh
make
```

`make` fetches Dart dependencies and compiles the executables into `build/`.
Install them into `$HOME/.local/bin` so they are available from any directory
for your user:

```sh
make install PREFIX="$HOME/.local"
```

Add this line to your shell configuration (`~/.zshrc` for zsh or `~/.bashrc` for
bash; use `~/.bash_profile` for a macOS bash login shell), and run it in your
current terminal too:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Verify the installation:

```sh
command -v table-table slack-table md-table
table-table --version
slack-table --version
md-table --version
```

These are real executables; shell aliases are unnecessary. `table-table` and
`slack-table` default to Slack TSV, and `md-table` defaults to Markdown.
[Native Dart executables](https://dart.dev/tools/dart-compile#exe) include their
runtime, so the installed commands need neither Python nor a Dart SDK. Build on
the OS and architecture where you will run them. Repeat the build and install
commands after updating the source; the installed copies are independent of
the checkout.

For a machine-wide installation for all users, build with `make` first, then
install into the default prefix `/usr/local` (requires administrator access):

```sh
sudo make install
```

Ensure `/usr/local/bin` is on your `PATH`. You can override `PREFIX` or set
`BINDIR` directly to choose another destination. `DESTDIR` prepends a staging
directory for packaging, for example `make install DESTDIR=/tmp/table-package`.
To use a specific Dart SDK, run `make DART=/path/to/dart`.

If an older Python installation or Dart global activation is present, keep the
native installation directory first on `PATH`. Remove any old shell aliases or
functions with these names from your shell configuration, then open a new
terminal. `type -a table-table slack-table md-table` shows conflicting commands.

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

Markdown widths count Unicode code points, not
terminal display columns or grapheme clusters.

## Test

After `dart pub get`, run the core contracts directly in Dart:

```sh
dart test
```

The tests in `test/` call the Dart library directly and cover parsing, formatting,
format choices, and regressions.

For the full check, including CLI subprocess contracts, use Python 3.9+
(no third-party Python packages are needed):

```sh
python3 tool/check.py
```

This checks formatting and static analysis, runs the Dart core tests, builds all
three native commands, then runs:

1. Python CLI subprocess contracts using temporary clipboard commands and POSIX
   terminals, without reading or changing your actual clipboard. This harness
   runs on macOS/Linux; Windows clipboard integration has not been verified.
2. Browser compilation of the public core API. If Node is installed, the
   resulting JavaScript also runs a smoke test.

Python is used only for the check runner and the CLI test harness in
`tests/cli_contract/`, which invokes the real compiled executables. The former
Python implementation, packaging, and reference tests have been removed.

For Jaspr's component tests, run `dart test` in `apps/table_web`. After installing
Dart dependencies in both packages and running `npm ci` in `apps/table_web`,
`python3 tool/check.py --web` runs the complete
check, including Jaspr analysis, component tests, and a production web build.

## Input support

The CLI accepts text input only. The former Python image/OCR functionality has
not been ported to Dart; Tesseract is not required.
