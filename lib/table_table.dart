/// Read tables and prepare text for destinations such as Slack and Markdown.
///
/// This library handles parsing and output rules. Callers handle files, the
/// clipboard, UI controls, and preview limits.
///
/// For a single conversion, call [render]. For an interactive UI, parse once with
/// [tableFormats], keep the returned [ParsedTable], and prepare a [FormattedTable]
/// for the selected destination. Keep that session while the source and
/// destination stay the same, so previews and copy actions can reuse their work.
///
/// Each destination starts with the original cells. This lets writers make
/// different choices about spaces, quoting, and line breaks without losing
/// content when the user changes destinations. Column alignment stays on the
/// original [Table], so destinations can retain it when their format supports it.
///
/// Formatting happens when a preview or complete text is requested. A session
/// keeps its most recent preview and, once requested, the complete output string.
/// Keeping only one preview saves memory, even if resizing means preparing some
/// cells again. First copy includes the work deferred by the preview; faster
/// previews alone do not mean a faster complete conversion.
library;

export 'src/core.dart';
export 'src/display_width.dart' show displayWidth;
export 'src/formats.dart';
export 'src/catalog.dart';
export 'src/pipeline.dart';
