# table-table

For the love of tables. Copying a table between apps should leave you with a table.

**table-table converts table text into tab-separated rows for pasting into Slack,
or neatly aligned Markdown for a document or README.** Give it Markdown, CSV,
spreadsheet cells, or a messy table copied from Cursor or Jira Rovo. It detects
the format and puts the rows and columns back together.

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

Clipboard support uses macOS's `pbpaste`/`pbcopy`, PowerShell on Windows, or
`wl-paste`/`wl-copy`, `xclip`, or `xsel` on Linux. Linux users need one of those
clipboard tool pairs installed. Windows clipboard support is implemented but
has not been verified by the CLI test suite.

## What can it read?

Input is detected automatically. If it guesses wrong, choose a format in the
web app or pass `--input FORMAT` to the CLI.

| Input                                                    | CLI format |
| -------------------------------------------------------- | ---------- |
| Markdown tables, including the header separator          | `markdown` |
| Comma-separated values, including quoted cells           | `csv`      |
| Tab-separated values, such as copied spreadsheet cells   | `tsv`      |
| Rows separated by pipes (`Name \| Role`)                 | `pipe`     |
| Cursor canvas copies with fragmented rows                | `cursor`   |
| Cells separated by blank lines, such as Jira Rovo copies | `spaced`   |

Blank-line-separated cells may need a column count. The web app and interactive
CLI ask when necessary; in a script, supply it explicitly:

```sh
slack-table --input spaced --columns 3 copied-table.txt
```

A few things to know about the output:

- Markdown uses the first row as the header. Padding accounts for wide CJK
  characters, combining marks, and emoji, though alignment still depends on
  the font used to display it.
- Cell whitespace is trimmed and collapsed, including embedded tabs and line
  breaks. Short rows are padded with empty cells.
- Values stay as text, so IDs such as `001` keep their leading zeros.
- Input must be text. Screenshots and image/OCR conversion are not supported.

## Contribute

A useful place to start is a table that doesn't survive conversion. For a bug
report, include a small input example, the output you expected, and whether you
used the web app or CLI. Replace any private data before sharing it.

The project has three main parts:

| Where                                                                                 | What lives there                                        |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| [`lib/src/core.dart`](lib/src/core.dart)                                              | Table parsing and formatting, with no I/O               |
| [`lib/src/formats.dart`](lib/src/formats.dart)                                        | Format names shared by the library, CLI, and web app    |
| [`lib/src/cli.dart`](lib/src/cli.dart) and [`clipboard.dart`](lib/src/clipboard.dart) | Command-line behavior and system clipboard access       |
| [`apps/table_web/`](apps/table_web/)                                                  | The Jaspr web app, styled with Tailwind CSS and daisyUI |
| [`test/`](test/)                                                                      | Dart tests for parsing and formatting                   |
| [`tests/cli_contract/`](tests/cli_contract/)                                          | Python tests that exercise the compiled commands        |

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
CLI tests use temporary clipboard commands and leave your actual clipboard
alone.

For web changes, install the dependencies from the web quick start above, then
run this from the repository root:

```sh
python3 tool/check.py --web
```

This adds web formatting and analysis, component tests, and a production build.
For a faster web-only test run, use `dart test` inside `apps/table_web`.

## Use the Dart library

The public API is in [`lib/slack_table.dart`](lib/slack_table.dart). The package
is not published to pub.dev; another local Dart project can use a path dependency
on this checkout:

```yaml
dependencies:
  slack_table:
    path: /path/to/this/checkout
```

```dart
import 'package:slack_table/slack_table.dart';

final slackText = render('Name,Role\nAda,Engineering');
final markdown = render(
  'Name,Role\nAda,Engineering',
  outputFormat: OutputFormats.markdown,
);

// Parse once if you need to inspect the cells or produce both formats.
final table = parseTable('Name,Role\nAda,Engineering');
final rows = table.rows;
final formatted = formatMarkdown(table);
```

The library performs no I/O. Invalid input throws `ParseError`; ambiguous
blank-line-separated input throws `AmbiguousColumnsError`, whose `candidates`
list lets you offer a choice and retry with `columns: N`. Returned output has
no trailing newline; the CLI adds one when printing.
