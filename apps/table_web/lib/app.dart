import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:slack_table/slack_table.dart' as tables;

import 'conversion.dart';

class TableApp extends StatefulComponent {
  final Future<void> Function(String) copyText;

  const TableApp({required this.copyText, super.key});

  @override
  State<TableApp> createState() => _TableAppState();
}

enum _CopyStatus {
  idle,
  copying,
  copied,
  failed,
  retrying;

  bool get isPending => this == copying || this == retrying;

  bool get showFallback => this == failed || this == retrying;
}

class _TableAppState extends State<TableApp> {
  static const _example = '| Name | Role |\n| --- | --- |\n| Ada | Engineering |\n| Sam | Design |';
  static const _inputFormatLabels = {
    tables.InputFormats.auto: 'Auto-detect',
    tables.InputFormats.markdown: 'Markdown',
    tables.InputFormats.csv: 'CSV',
    tables.InputFormats.tsv: 'TSV',
    tables.InputFormats.pipe: 'Pipe-separated',
    tables.InputFormats.cursor: 'Cursor',
    tables.InputFormats.spaced: 'Spaced cells',
  };

  static const _outputFormatLabels = {
    tables.OutputFormats.slack: 'Slack',
    tables.OutputFormats.markdown: 'Markdown',
  };

  String _input = '';
  String _inputFormat = tables.InputFormats.auto;
  String _outputFormat = tables.OutputFormats.slack;
  int? _columns;
  Conversion _conversion = const EmptyConversion();
  _CopyStatus _copyStatus = _CopyStatus.idle;
  int _revision = 0;
  int _inputKey = 0;

  @override
  Component build(BuildContext context) {
    return main_(classes: 'app', [
      _buildHeader(),
      hr(classes: 'hero-divider'),
      div(classes: 'workspace', [
        _buildInputPane(),
        _buildOutputPane(),
      ]),
      _buildAbout(),
    ]);
  }

  tables.Table? get _table => switch (_conversion) {
    ReadyConversion(:final table) => table,
    _ => null,
  };

  String get _output => switch (_conversion) {
    ReadyConversion(:final output) => output,
    _ => '',
  };

  List<int> get _candidates => switch (_conversion) {
    AmbiguousConversion(:final candidates) || ReadyConversion(:final candidates) => candidates,
    _ => const [],
  };

  bool get _hasError => _conversion is InvalidConversion;

  Component _buildHeader() {
    return header([
      p(classes: 'wordmark', [
        img(src: 'favicon.svg', alt: '', width: 20, height: 20),
        .text('table-table'),
      ]),
      h1([.text('For the love of tables.')]),
      p(classes: 'intro', [
        .text('Tables are everywhere. Keep them tables, wherever you paste.'),
      ]),
    ]);
  }

  Component _buildInputPane() {
    return section(
      classes: 'pane input-pane',
      attributes: {'aria-labelledby': 'input-label'},
      [
        _buildInputHeading(),
        _buildInputEditor(),
        _buildInputFeedback(),
        _buildInputActions(),
      ],
    );
  }

  Component _buildInputHeading() {
    final table = _table;
    return div(classes: 'pane-heading', [
      div(classes: 'input-heading', [
        label(id: 'input-label', htmlFor: 'table-input', [.text('Input')]),
        span(
          classes: 'detected-format',
          attributes: {'role': 'status', 'aria-atomic': 'true'},
          [
            if (table != null && _inputFormat == tables.InputFormats.auto) ...[
              span(
                classes: 'detection-check',
                attributes: {'aria-hidden': 'true'},
                [
                  .text('✓'),
                ],
              ),
              span([.text('${_inputFormatLabels[table.sourceFormat]} detected')]),
            ],
          ],
        ),
      ]),
      select(
        id: 'input-format',
        classes: 'select select-sm input-format',
        value: _inputFormat,
        attributes: {'aria-label': 'Input format'},
        onChange: (values) => _changeInputFormat(values.single),
        [
          for (final entry in _inputFormatLabels.entries)
            option(value: entry.key, [.text(entry.value)]),
        ],
      ),
    ]);
  }

  Component _buildInputEditor() {
    return textarea(
      key: ValueKey(_inputKey),
      id: 'table-input',
      classes: _hasError ? 'textarea textarea-error table-input' : 'textarea table-input',
      placeholder: 'Paste something table-ish…',
      spellCheck: SpellCheck.isFalse,
      attributes: {
        'wrap': 'off',
        'aria-describedby': 'input-feedback',
        if (_hasError) 'aria-invalid': 'true',
        'autocapitalize': 'off',
        'autocorrect': 'off',
      },
      onInput: _changeInput,
      [.text(_input)],
    );
  }

  Component _buildInputFeedback() {
    return div(
      id: 'input-feedback',
      classes: 'input-feedback',
      attributes: {'aria-live': 'polite'},
      [
        if (_candidates.isNotEmpty)
          _buildColumnChoices()
        else if (_hasError)
          p(classes: 'error', [
            .text('Couldn’t read a table. Check the text or choose its format.'),
          ]),
      ],
    );
  }

  Component _buildColumnChoices() {
    return div(classes: 'column-choice', [
      span(id: 'columns-label', [.text('Columns')]),
      div(
        classes: 'column-buttons',
        attributes: {'role': 'group', 'aria-labelledby': 'columns-label'},
        [
          for (final count in _candidates)
            button(
              classes: _columns == count
                  ? 'btn btn-sm btn-primary btn-soft'
                  : 'btn btn-sm btn-outline',
              attributes: {'aria-pressed': '${_columns == count}'},
              onClick: () => _chooseColumns(count),
              [.text('$count')],
            ),
        ],
      ),
    ]);
  }

  Component _buildInputActions() {
    return div(classes: 'pane-footer', [
      button(classes: 'btn btn-sm btn-outline', onClick: _loadExample, [
        .text('Try an example'),
      ]),
      if (_input.isNotEmpty)
        button(classes: 'btn btn-sm btn-outline', onClick: _clear, [.text('Clear')]),
    ]);
  }

  Component _buildOutputPane() {
    return section(
      classes: 'pane output-pane',
      attributes: {'aria-label': 'Output'},
      [
        _buildOutputFormats(),
        _buildOutputToolbar(),
        _buildPreview(),
        _buildCopyFeedback(),
      ],
    );
  }

  Component _buildOutputFormats() {
    return div(classes: 'pane-heading', [
      div(
        classes: 'join output-format',
        attributes: {'role': 'group', 'aria-label': 'Output format'},
        [
          for (final value in tables.OutputFormats.values)
            button(
              id: 'output-$value',
              classes: 'join-item btn btn-sm btn-ghost',
              attributes: {'aria-pressed': '${_outputFormat == value}'},
              onClick: () => _changeOutputFormat(value),
              [.text(_outputFormatLabels[value]!)],
            ),
        ],
      ),
    ]);
  }

  Component _buildOutputToolbar() {
    final table = _table;
    return div(classes: 'preview-toolbar', [
      span(classes: 'table-size', [
        if (table != null)
          .text(
            '${table.rows.length} ${table.rows.length == 1 ? 'row' : 'rows'}'
            ' · ${table.rows.first.length} columns',
          ),
      ]),
      button(
        id: 'copy-output',
        classes: 'btn btn-sm btn-primary copy-button',
        disabled: _output.isEmpty || _copyStatus.isPending,
        onClick: _copy,
        [.text(_copyStatus == _CopyStatus.copied ? 'Table preserved.' : 'Copy')],
      ),
    ]);
  }

  Component _buildPreview() {
    final parsedTable = _table;
    return div(classes: 'preview', [
      if (parsedTable == null)
        p(classes: 'empty-preview', [
          .text('Your table will appear here, columns and all.'),
        ])
      else if (_copyStatus.showFallback)
        textarea(
          key: ValueKey(_output),
          id: 'copy-fallback',
          classes: 'textarea table-input',
          readonly: true,
          spellCheck: SpellCheck.isFalse,
          attributes: {
            'wrap': 'off',
            'aria-label': 'Output text',
            'aria-describedby': 'copy-feedback',
          },
          [.text(_output)],
        )
      else if (_outputFormat == tables.OutputFormats.markdown)
        pre(
          attributes: {'tabindex': '0', 'aria-label': 'Markdown output'},
          [.text(_output)],
        )
      else
        div(
          classes: 'table-scroll',
          attributes: {'tabindex': '0', 'aria-label': 'Slack table preview'},
          [
            table(classes: 'table', [
              thead([
                tr([
                  for (final cell in parsedTable.rows.first) th(scope: 'col', [.text(cell)]),
                ]),
              ]),
              tbody([
                for (final row in parsedTable.rows.skip(1))
                  tr([
                    for (final cell in row) td([.text(cell)]),
                  ]),
              ]),
            ]),
          ],
        ),
    ]);
  }

  Component _buildCopyFeedback() {
    return div(
      id: 'copy-feedback',
      classes: 'copy-feedback',
      attributes: {'role': 'status'},
      [
        if (_copyStatus.showFallback)
          p(classes: 'error', [.text('Copy unavailable. Select the text above and copy.')]),
        if (_copyStatus == _CopyStatus.copied)
          span(classes: 'sr-only', [.text('Table preserved. Copied to clipboard.')]),
      ],
    );
  }

  Component _buildAbout() {
    return details(classes: 'about', [
      summary([.text('Why tables?')]),
      p([
        .text(
          'Rows belong together. Columns mean something. '
          'Copying and pasting shouldn’t undo all that.',
        ),
      ]),
    ]);
  }

  void _changeInput(String value) {
    setState(() {
      _input = value;
      _columns = null;
      _convert();
    });
  }

  void _changeInputFormat(String value) {
    setState(() {
      _inputFormat = value;
      _columns = null;
      _convert();
    });
  }

  void _changeOutputFormat(String value) {
    setState(() {
      _outputFormat = value;
      _conversion = _conversion.withOutputFormat(value);
      _resetCopy();
    });
  }

  void _chooseColumns(int count) {
    setState(() {
      _columns = count;
      _convert();
    });
  }

  void _loadExample() {
    setState(() {
      _inputKey++;
      _input = _example;
      _inputFormat = tables.InputFormats.auto;
      _columns = null;
      _convert();
    });
  }

  void _clear() {
    setState(() {
      _inputKey++;
      _input = '';
      _columns = null;
      _convert();
    });
  }

  void _convert() {
    _conversion = Conversion.fromInput(
      _input,
      inputFormat: _inputFormat,
      outputFormat: _outputFormat,
      columns: _columns,
    );
    _resetCopy();
  }

  void _resetCopy() {
    // A pending copy belongs to the old output, even if it finishes later.
    _revision++;
    _copyStatus = _CopyStatus.idle;
  }

  Future<void> _copy() async {
    if (_output.isEmpty || _copyStatus.isPending) return;
    final revision = _revision;
    setState(() {
      _copyStatus = _copyStatus.showFallback ? _CopyStatus.retrying : _CopyStatus.copying;
    });
    try {
      await component.copyText(_output);
      if (!mounted || revision != _revision) return;
      setState(() => _copyStatus = _CopyStatus.copied);
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() => _copyStatus = _CopyStatus.failed);
    }
  }
}
