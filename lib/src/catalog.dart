import 'formats/csv.dart';
import 'formats/cursor.dart';
import 'formats/html.dart';
import 'formats/markdown.dart';
import 'formats/slack.dart';
import 'formats/space_aligned.dart';
import 'formats/spaced.dart';
import 'formats/tsv.dart';
import 'pipeline.dart';

/// Supported formats, with UI order independent of detection precedence.
///
/// To add a format, put its reader or writer in formats/, register it here, and
/// include tests and user documentation. A reader also needs a detection position
/// and tests for inputs that other readers can accept. A text writer can use the
/// frontend's plain-text preview without adding a UI component.
final tableFormats = FormatRegistry(
  inputs: [
    htmlInput,
    markdownInput,
    cursorInput,
    csvInput,
    tsvInput,
    spaceAlignedInput,
    pipeInput,
    spacedInput
  ],
  outputs: [slackOutput, markdownOutput],
  // Specialized tables precede general delimiters. A tab scan is shared by
  // wrapped text and TSV, and TSV wins over CSV when both delimiters occur.
  // Space-aligned cells can contain commas (for example, kubectl service ports).
  detectionOrder: [
    'html',
    'markdown',
    'cursor',
    'tsv',
    'space-aligned',
    'csv',
    'pipe',
    'spaced'
  ],
);
