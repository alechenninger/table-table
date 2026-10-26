import '../delimited_format_session.dart';
import '../formats.dart';
import '../table.dart';
import '../text_cells.dart';

/// Text prepared for pasting into Slack.
///
/// Its tab-separated representation follows Slack's paste needs. A general TSV
/// export would need its own format ID and escaping rules.
const slackOutput = OutputFormat(
    id: OutputFormats.slack, label: 'Slack', prepare: _prepareSlack);

FormattedTable _prepareSlack(Table table) => DelimitedFormatSession(table,
    prepareCell: cleanCell,
    columnSeparator: '\t',
    rowSeparator: '\n',
    showGrid: true);
