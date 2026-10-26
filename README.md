# table-table

For the love of tables. Copying a table between apps should leave you with a table.

**table-table converts table text into tab-separated rows for pasting into Slack,
or neatly aligned Markdown for a document or README.** Give it Markdown, CSV,
spreadsheet cells, HTML tables, or a messy table copied from a browser or Jira
Rovo. It detects the format and puts the rows and columns back together.

Use the web app for a quick paste-and-copy workflow, or the command-line tools
for files, pipes, and your clipboard. Both use the same Dart conversion library.
The web app processes your table in your browser; it does not upload or save it.

## Try the web app locally

You'll need Dart 3.10+ and Node.js 20+. From a checkout of this repository:

```sh
cd apps/table_web
dart pub get
npm ci
npm run dev
```

Open the local URL printed in the terminal, then:

1. Paste your table, or load an example.
2. Choose **Slack** or **Markdown** as the destination.
3. Copy the result and paste it where you need it.

If the input could have more than one column count, the app lets you choose.
If the browser cannot copy to your clipboard, it provides text you can select
and copy yourself.

With Auto-detect selected, pasting a copied HTML table uses the clipboard's
HTML version when available. Rows and cells stay intact even when they contain
paragraphs, lists, buttons, or flex layouts. The editor retains the HTML source,
and the detected format is HTML. Conversion to TSV or Markdown happens only for
the output; line breaks within a cell become spaces. If the source provides only
plain text, the app uses its text parsers. Missing text and ambiguous cell
boundaries cannot always be recovered from that version.

To host it yourself, run `npm run build` from `apps/table_web` and serve the
contents of `build/jaspr/` on a static host. Use HTTPS for clipboard access
outside localhost. There is no backend or account setup.

## Use it from the terminal

`table-table` is the main command, but you'll usually use its aliases:
`slack-table` for Slack or `md-table` for Markdown. Same tool, with the output
format already selected.

Once you've [installed the commands](#install-the-commands), the everyday
workflow is:

1. **Copy a table** from your document, spreadsheet, or chat to your clipboard.
2. **Run `slack-table`** (or `md-table`) in your terminal, with no arguments.
3. **Paste into Slack.** Your clipboard now holds the converted table.

The command reads your clipboard and replaces it with Slack (or Markdown) paste data. There's no need to save a file, pipe anything, or add `--copy`.

```sh
table-table
```

If the clipboard is empty, you can paste into the terminal and finish with
Ctrl-D. If you prefer to start the command before copying your table, run
`table-table --wait --quiet`; it waits for your next copy, converts it, updates
the clipboard, and exits. Then paste as usual.

### Install the commands

On macOS or Linux, with Dart 3.4+ and Make on your `PATH`, run these commands from
the repository root:

```sh
make
make install PREFIX="$HOME/.local"
```

Plain `make` only builds the commands in `build/`. Installation requires an
explicit `make install`.

To remember your install location for this checkout, create a `Makefile.local`
file in the repository root containing:

```make
PREFIX = $(HOME)/.local
```

Then run `make install` without specifying `PREFIX`. `Makefile.local` is optional
and ignored by Git. Use Make syntax (without quotes around the path); a
command-line `PREFIX=...` still overrides this setting.

Add the install directory to your `PATH`. Run this in your current terminal and
add it to your shell startup file (usually `~/.zshrc` or `~/.bashrc`):

```sh
export PATH="$HOME/.local/bin:$PATH"
```

You now have three commands:

| Command       | Default output                        |
| ------------- | ------------------------------------- |
| `slack-table` | Slack paste data (tab-separated text) |
| `md-table`    | Markdown                              |
| `table-table` | Same as `slack-table`                 |

Check the installation with `slack-table --version`. The compiled executables
include their runtime, so Dart is only needed to build them. Build on the OS and
architecture where you'll use them, and repeat the build and install after
updating the source.

To try the clipboard workflow from source without installing the commands,
copy a table, then run this from the repository root and paste into Slack:

```sh
dart pub get
dart run bin/slack_table.dart
```

Use `bin/md_table.dart` for Markdown instead.

### Files, pipes, and explicit clipboard input

```sh
# Convert a file to Slack paste data and print it.
slack-table table.md

# Copy the result too, ready to paste into Slack.
slack-table table.md --copy

# Turn CSV into Markdown and save it to a file.
md-table table.csv > table.md

# Read from a pipeline.
cat table.csv | slack-table

# Convert the current clipboard and replace it with the result.
slack-table --clipboard
```

Files and piped input only print their result unless you add `--copy`.
Use `--clipboard` to explicitly read and replace the clipboard even when stdin
is redirected.

All three commands accept the same options. Use `--output slack` or
`--output markdown` to override the default, `--quiet` (`-q`) to suppress printed
output, and `--help` for the full option list.

On macOS, clipboard access calls AppKit directly through Dart FFI. Auto-detection
prefers the clipboard's HTML table and falls back to plain text when HTML cannot
be read as a supported table. Explicit text formats such as `--input tsv` use
the plain-text representation. `--input html` also accepts literal HTML copied
as plain text. `--wait` observes changes to both representations, including HTML
changes that leave the plain text identical. Converted output replaces the
clipboard with plain text for Slack or Markdown.

Windows uses PowerShell; Linux uses `wl-paste`/`wl-copy`, `xclip`, or `xsel`.
These command adapters currently expose plain text. Linux users need one of
those clipboard tool pairs installed. Windows clipboard support is implemented
but has not been verified by the CLI test suite. The FFI implementation is
tested on macOS arm64; its pointer-sized signatures also target macOS x86_64,
which has not been tested here.

## What can it read?

Input is detected automatically. If it guesses wrong, choose a format in the
web app or pass `--input FORMAT` to the CLI.

| Input                                                    | CLI format |
| -------------------------------------------------------- | ---------- |
| HTML tables, including nested content within cells       | `html`     |
| Markdown tables, including the header separator          | `markdown` |
| Comma-separated values, including quoted cells           | `csv`      |
| Tab-separated values, such as copied spreadsheet cells   | `tsv`      |
| Rows separated by pipes (`Name \| Role`)                 | `pipe`     |
| Wrapped table text, including Cursor canvas copies       | `cursor`   |
| Cells separated by blank lines, such as Jira Rovo copies | `spaced`   |

Blank-line-separated cells may need a column count. The web app and interactive
CLI ask when necessary; in a script, supply it explicitly:

```sh
slack-table --input spaced --columns 3 copied-table.txt
```

HTML conversion uses the first table outside templates and hidden subtrees.
Elements marked `hidden` or with inline `display:none` are omitted, including
rows and cells. Inline display keywords respect declaration order and
`!important`; stylesheets, inherited styles, CSS variables, and the original
page's layout are not reconstructed. Merged cells (`rowspan` or `colspan`)
remain unsupported. Span attributes follow HTML's integer parsing and defaults:
`colspan="0"` defaults to one, and `rowspan="0"` is rejected.

A few things to know about the output:

- Markdown uses the first row as the header. Padding accounts for wide CJK
  characters, combining marks, and emoji, though alignment still depends on
  the font used to display it.
- Slack and Markdown trim and collapse cell whitespace, including embedded tabs
  and line breaks. Readers preserve decoded cell content for destination switches;
  short rows are padded with empty cells. CSV/TSV retain explicitly empty records
  while ignoring physical blank lines. HTML retains its visible-text extraction
  rules for whitespace and block boundaries.
- Values stay as text, so IDs such as `001` keep their leading zeros.
- Input must be text. Screenshots and image/OCR conversion are not supported.

## Contribute

The comments in [the public library](lib/table_table.dart) explain the pipeline
and its API contracts. The
[measurement report](docs/format_pipeline_performance.md) records the remaining
JavaScript performance decision. To contribute a format, add its module,
register its descriptor and detection position in the catalog, and include
fixtures, tests, and user documentation.

A useful place to start is a table that doesn't survive conversion. For a bug
report, include a small input example, the output you expected, and whether you
used the web app or CLI. Replace any private data before sharing it.

The project has three main parts:

| Where                                                                                       | What lives there                                         |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| [`lib/src/core.dart`](lib/src/core.dart)                                                    | Compatibility entry points, with no I/O                  |
| [`lib/src/table.dart`](lib/src/table.dart)                                                  | Immutable rectangular text cells                         |
| [`lib/src/pipeline.dart`](lib/src/pipeline.dart) and [`catalog.dart`](lib/src/catalog.dart) | Detection, descriptors, and the supported format catalog |
| [`lib/src/formats/`](lib/src/formats/)                                                      | Readers and destination-owned output policies            |
| [`lib/src/formats.dart`](lib/src/formats.dart)                                              | Format and lazy preview contracts shared by frontends    |
| [`lib/src/cli.dart`](lib/src/cli.dart)                                                      | Command-line behavior and clipboard format preference    |
| [`lib/src/clipboard.dart`](lib/src/clipboard.dart) and [`clipboard/`](lib/src/clipboard/)   | Clipboard snapshots, interface, and platform adapters    |
| [`apps/table_web/`](apps/table_web/)                                                        | The Jaspr web app, styled with Tailwind CSS and daisyUI  |
| [`test/`](test/)                                                                            | Dart tests for parsing and formatting                    |
| [`tests/cli_contract/`](tests/cli_contract/)                                                | Python tests that exercise the compiled commands         |

Keep conversion behavior in the shared core so improvements reach both the CLI
and web app. For parser fixes, include a small regression example in the core
tests. The [web app README](apps/table_web/README.md) covers its development
workflow, styling, and component behavior.

### Run the checks

For work on parsing or formatting, start at the repository root:

```sh
dart pub get
dart test
```

The full CLI and core check also requires Python 3.9+ on macOS or Linux, with no
third-party Python packages:

```sh
python3 tool/check.py
```

It checks Dart formatting and static analysis, runs the core tests, builds all
three commands, tests their behavior, and compiles the public library to
JavaScript. If Node is available, it also runs the JavaScript smoke test. The
CLI contract tests inject an adapter backed by temporary clipboard commands or
scripted snapshots. Production entry points are also checked with piped input.
On macOS, native FFI tests use private named pasteboards, including round trips
across CLI processes and HTML-only changes under `--wait`. The full check also
compiles and runs an AOT native clipboard smoke test. These tests leave the
general clipboard untouched and need access to the macOS pasteboard service.

For web changes, install the dependencies from the web quick start above, then
run this from the repository root:

```sh
python3 tool/check.py --web
```

This adds web formatting and analysis, component tests, and a production build.
For a faster web-only test run, use `dart test` inside `apps/table_web`.

### Measure core performance

The benchmark covers parsing, formatting, and complete conversions for ASCII
and Unicode tables. It prints JSON lines with milliseconds per operation;
input generation, worker messaging, and UI rendering are excluded. To measure
optimized JavaScript in Node:

```sh
mkdir -p build
dart compile js -O2 --no-source-maps tool/benchmark.dart -o build/benchmark.js
node build/benchmark.js
```

To measure the native AOT runtime used by the CLI:

```sh
dart compile exe tool/benchmark.dart -o build/benchmark
build/benchmark
```

The fixtures include wide and Unicode-heavy tables of roughly 2 MB, and report
UTF-8 input sizes. `dart run tool/benchmark.dart` measures the Dart VM's JIT
runtime. Compare results using the same compiler settings and runtime on an
otherwise idle machine.

The HTML benchmark also exercises the browser's clipboard validation, conversion,
and bounded preview preparation. Its fixtures include tall and wide tables, heavy
repeated and distinct inline styling, entities, omitted closing tags, nested
tables, 10,000-deep trees, a 1 MiB cell, large surrounding documents, and ragged
rows that expand to a million cells. Run it from the web package:

```sh
cd apps/table_web
mkdir -p ../../build
dart compile js -O4 --no-source-maps tool/benchmark_html.dart -o ../../build/benchmark_html.js
node tool/run_dart_js.cjs ../../build/benchmark_html.js
dart compile exe tool/benchmark_html.dart -o ../../build/benchmark_html
../../build/benchmark_html
```

Append fixture-name filters such as `deep-cell` or `rich` to either runner. Results
are JSON lines with a separate first-call time and the median of three warmed
batches, each lasting at least 50 ms. A first call over one second is reported
once and the remaining operations for that fixture are skipped; this is not a
timeout. Fixture generation, clipboard I/O, browser DOM rendering, and console
output are excluded. `convert-preview-*` parses source directly, while
`paste-preview-*` uses the clipboard's structured source-and-table result. Both
paths parse once before preparing a bounded preview and then requesting full output.

For frontend lifecycle measurements (preview, first copy, repeated reads, and
switching destinations), run `tool/benchmark_pipeline.dart` from the web package
with the same native and JavaScript compiler options above. It includes tall,
wide Unicode, multiline/whitespace-heavy, and long-cell fixtures. Optional fixture
filters select workloads; `--once --mode=preview-full-slack` runs one conversion
for an external peak-memory monitor. The `latency-*` records separate preview,
first-copy, and total time. Benchmark timings are not assertions in unit tests.

## Use the Dart library

The public API is in [`lib/table_table.dart`](lib/table_table.dart). The package
is not published to pub.dev; another local Dart project can use a path dependency
on this checkout:

```yaml
dependencies:
  table_table:
    path: /path/to/this/checkout
```

```dart
import 'package:table_table/table_table.dart';

final slackText = render('Name,Role\nAda,Engineering');
final markdown = render(
  'Name,Role\nAda,Engineering',
  outputFormat: OutputFormats.markdown,
);

// Parse once and retain one lazy session for the selected destination.
final parsed = tableFormats.parse('Name,Role\nAda,Engineering');
final formatted = tableFormats.prepare(parsed.table, outputFormat: 'slack');
final preview = formatted.preview(maxRows: 51, maxColumns: 20);
// Display preview.table when provided, otherwise preview.text.
// Request the complete string on copy or complete-source display.
final copied = formatted.fullText;

// Existing convenience entry points remain available.
final table = parseTable('Name,Role\nAda,Engineering');
final markdownText = formatMarkdown(table);
```

The library performs no I/O. Invalid input throws `ParseError`; ambiguous
blank-line-separated input throws `AmbiguousColumnsError`, whose `candidates`
list lets you offer a choice and retry with `columns: N`. Returned output has
no trailing newline; the CLI adds one when printing.
