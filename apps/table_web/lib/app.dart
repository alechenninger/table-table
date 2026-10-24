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
  // Reuse complete utility names so Tailwind can discover every class.
  static const _tableInputClasses =
      'textarea table-input w-full min-h-36 resize-y field-sizing-content p-3 '
      'font-mono text-base leading-6 [tab-size:4] sm:p-4';
  static const _tableCellClasses =
      'min-w-18 max-w-90 px-3 py-2 align-top whitespace-normal wrap-anywhere';
  static const _secondaryActionClasses =
      'btn btn-outline min-h-9 h-auto border-base-content/20 px-2 py-1 '
      'text-sm leading-6 font-medium text-base-content/70 '
      'hover:border-base-content/40 hover:bg-base-content/5 hover:text-base-content';

  static const _examples = {
    'From Google Sheets': 'Name\tRole\nAda\tEngineering\nSam\tDesign',
    'From markdown':
        '| Day | Plan |\n| --- | --- |\n| Saturday | Farmers market |\n| Sunday | Hike |',
    'From ChatGPT app': 'Task\tStatus\nDraft proposal\tDone\nReview\tIn progress',
  };
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
  ({String input, String inputFormat, int? columns})? _clearedInput;
  Conversion _conversion = const EmptyConversion();
  _CopyStatus _copyStatus = _CopyStatus.idle;
  int _revision = 0;
  int _inputKey = 0;

  @override
  Component build(BuildContext context) {
    return main_(classes: 'app mx-auto max-w-5xl px-4 pt-8 pb-12 sm:px-8 sm:pt-12 sm:pb-16', [
      _buildHeader(),
      div(
        classes:
            'workspace mt-8 grid grid-cols-1 overflow-hidden rounded-box border border-base-300 bg-base-100 sm:mt-10',
        [
          _buildInputPane(),
          _buildOutputPane(),
        ],
      ),
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
      p(
        classes:
            'wordmark flex items-center gap-2 text-base font-semibold tracking-tight text-base-content/70',
        [
          img(src: 'favicon.svg', alt: '', width: 20, height: 20),
          .text('table-table'),
        ],
      ),
      h1(
        classes:
            'mt-6 text-[clamp(2rem,1.25rem+3vw,3.25rem)] leading-tight font-semibold tracking-tight text-balance sm:mt-8',
        [.text('For the love of tables.')],
      ),
      p(classes: 'intro mt-3 max-w-xl text-lg leading-normal sm:text-xl', [
        .text('Tables are everywhere. Keep them tables, wherever you paste.'),
      ]),
    ]);
  }

  Component _buildInputPane() {
    return section(
      classes: 'pane input-pane flex min-w-0 flex-col border-b border-base-300 p-4 sm:p-6',
      attributes: {'aria-labelledby': 'paste-heading'},
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
    return div(classes: 'pane-heading mb-3 flex flex-wrap items-center justify-between gap-3', [
      h2(id: 'paste-heading', classes: 'text-base leading-6 font-semibold', [.text('Paste')]),
      select(
        id: 'input-format',
        classes: 'select input-format h-11 w-48 max-w-full text-base',
        value: _inputFormat,
        attributes: {'aria-label': 'Source format'},
        onChange: (values) => _changeInputFormat(values.single),
        [
          for (final entry in _inputFormatLabels.entries)
            option(value: entry.key, [
              .text(
                entry.key == tables.InputFormats.auto &&
                        _inputFormat == tables.InputFormats.auto &&
                        table != null
                    ? 'Auto: ${_inputFormatLabels[table.sourceFormat]}'
                    : entry.value,
              ),
            ]),
        ],
      ),
    ]);
  }

  Component _buildInputEditor() {
    return textarea(
      key: ValueKey(_inputKey),
      id: 'table-input',
      classes: _hasError ? '$_tableInputClasses textarea-error' : _tableInputClasses,
      placeholder: 'Paste something table-ish…',
      spellCheck: SpellCheck.isFalse,
      attributes: {
        'wrap': 'off',
        'aria-label': 'Table to convert',
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
      classes: 'input-feedback empty:hidden',
      attributes: {'aria-live': 'polite'},
      [
        if (_candidates.isNotEmpty)
          _buildColumnChoices()
        else if (_hasError)
          p(classes: 'mt-3 text-sm leading-6 text-error', [
            .text('Couldn’t read a table. Check the text or choose its format.'),
          ]),
      ],
    );
  }

  Component _buildColumnChoices() {
    return div(classes: 'column-choice mt-3 flex flex-wrap items-center gap-3 text-sm', [
      span(id: 'columns-label', [.text('Columns')]),
      div(
        classes: 'column-buttons flex flex-wrap gap-2',
        attributes: {'role': 'group', 'aria-labelledby': 'columns-label'},
        [
          for (final count in _candidates)
            button(
              classes: _columns == count
                  ? 'btn btn-active min-h-11 h-auto min-w-11 py-2 text-sm leading-6'
                  : 'btn btn-ghost min-h-11 h-auto min-w-11 py-2 text-sm leading-6',
              attributes: {'aria-pressed': '${_columns == count}'},
              onClick: () => _chooseColumns(count),
              [.text('$count')],
            ),
        ],
      ),
    ]);
  }

  Component _buildInputActions() {
    return div(classes: 'pane-footer flex flex-wrap items-center justify-between gap-3 pt-3', [
      button(
        id: 'example-trigger',
        classes: _secondaryActionClasses,
        attributes: {'popovertarget': 'example-sources'},
        [
          .text('Try an example'),
          span(attributes: {'aria-hidden': 'true'}, [.text('▾')]),
        ],
      ),
      div(
        id: 'example-sources',
        classes:
            'example-sources fixed m-0 mt-2 w-64 max-w-[calc(100vw-2rem)] rounded-box border border-base-300 bg-base-100 p-1 text-base-content shadow-lg open:flex open:flex-col',
        attributes: {'popover': 'auto', 'role': 'group', 'aria-label': 'Example sources'},
        [
          for (final example in _examples.entries)
            button(
              classes:
                  'btn btn-ghost min-h-11 h-auto justify-start py-2 text-sm leading-6 font-medium',
              attributes: {'popovertarget': 'example-sources', 'popovertargetaction': 'hide'},
              onClick: () => _loadExample(example.value),
              [.text(example.key)],
            ),
        ],
      ),
      if (_input.isNotEmpty || _clearedInput != null)
        button(
          id: 'input-action',
          classes: _secondaryActionClasses,
          onClick: _input.isNotEmpty ? _clear : _undoClear,
          [.text(_input.isNotEmpty ? 'Clear input' : 'Undo clear')],
        ),
      span(
        classes: 'sr-only',
        attributes: {'role': 'status'},
        [
          if (_clearedInput != null) .text('Input cleared. Use Undo clear to restore it.'),
        ],
      ),
    ]);
  }

  Component _buildOutputPane() {
    return section(
      classes: 'pane output-pane flex min-w-0 flex-col p-4 sm:p-6',
      attributes: {'aria-labelledby': 'inspect-heading'},
      [
        h2(id: 'inspect-heading', classes: 'text-base leading-6 font-semibold', [.text('Inspect')]),
        _buildOutputToolbar(),
        _buildPreview(),
        _buildTableSize(),
        _buildCopyFeedback(),
      ],
    );
  }

  Component _buildOutputFormats() {
    return div(classes: 'copy-destination flex flex-wrap items-center gap-2 text-sm', [
      span(id: 'copy-as-label', classes: 'text-base-content/70', [.text('Copy as')]),
      div(
        classes: 'output-format flex max-w-full flex-wrap rounded-field bg-base-200 p-1',
        attributes: {'role': 'group', 'aria-labelledby': 'copy-as-label'},
        [
          for (final value in tables.OutputFormats.values)
            button(
              id: 'output-$value',
              classes:
                  'btn btn-ghost min-h-11 h-auto border-0 px-3 py-2 text-sm leading-6 font-medium text-base-content/70 shadow-none aria-pressed:bg-base-100 aria-pressed:text-base-content aria-pressed:shadow-sm',
              attributes: {'aria-pressed': '${_outputFormat == value}'},
              onClick: () => _changeOutputFormat(value),
              [.text(_outputFormatLabels[value]!)],
            ),
        ],
      ),
    ]);
  }

  Component _buildOutputToolbar() {
    return div(
      classes:
          'preview-toolbar my-3 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between',
      [
        _buildOutputFormats(),
        button(
          id: 'copy-output',
          classes:
              'btn btn-primary copy-button min-h-11 h-auto w-full min-w-40 py-2 text-sm leading-6 sm:ml-auto sm:w-auto',
          disabled: _output.isEmpty || _copyStatus.isPending,
          onClick: _copy,
          [.text(_copyStatus == _CopyStatus.copied ? 'Table preserved.' : 'Copy table')],
        ),
      ],
    );
  }

  Component _buildPreview() {
    final parsedTable = _table;
    return div(
      classes: parsedTable == null
          ? 'preview min-w-0 overflow-auto grid min-h-24 place-items-center'
          : 'preview min-w-0 overflow-auto',
      [
        if (parsedTable == null)
          p(classes: 'empty-preview m-4 text-center text-sm leading-6 text-base-content/65', [
            .text('Your table will appear here.'),
          ])
        else if (_copyStatus.showFallback)
          textarea(
            key: ValueKey(_output),
            id: 'copy-fallback',
            classes: _tableInputClasses,
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
            classes:
                'm-0 overflow-auto p-3 font-mono text-base leading-6 [tab-size:4] focus-visible:outline-2 focus-visible:outline-primary focus-visible:outline-offset-2 sm:p-4',
            attributes: {'tabindex': '0', 'aria-label': 'Markdown output'},
            [.text(_output)],
          )
        else
          div(
            classes:
                'table-scroll max-w-full overflow-auto p-0.5 focus-visible:outline-2 focus-visible:outline-primary focus-visible:-outline-offset-2',
            attributes: {'tabindex': '0', 'aria-label': 'Slack table preview'},
            [
              table(classes: 'table w-auto text-base leading-6', [
                thead(classes: 'text-base', [
                  tr([
                    for (final cell in parsedTable.rows.first)
                      th(scope: 'col', classes: _tableCellClasses, [.text(cell)]),
                  ]),
                ]),
                tbody([
                  for (final row in parsedTable.rows.skip(1))
                    tr([
                      for (final cell in row) td(classes: _tableCellClasses, [.text(cell)]),
                    ]),
                ]),
              ]),
            ],
          ),
      ],
    );
  }

  Component _buildTableSize() {
    final table = _table;
    final dataRows = table == null ? 0 : table.rows.length - 1;
    return div(classes: 'table-size mt-3 text-sm leading-6 text-base-content/65 empty:hidden', [
      if (table != null)
        .text(
          '$dataRows data ${dataRows == 1 ? 'row' : 'rows'}'
          ' · ${table.rows.first.length} ${table.rows.first.length == 1 ? 'column' : 'columns'}',
        ),
    ]);
  }

  Component _buildCopyFeedback() {
    return div(
      id: 'copy-feedback',
      classes: 'copy-feedback empty:hidden',
      attributes: {'role': 'status'},
      [
        if (_copyStatus.showFallback)
          p(classes: 'mt-3 text-sm leading-6 text-error', [
            .text('Copy unavailable. Select the text above and copy.'),
          ]),
        if (_copyStatus == _CopyStatus.copied)
          span(classes: 'sr-only', [.text('Table preserved. Copied to clipboard.')]),
      ],
    );
  }

  void _changeInput(String value) {
    setState(() {
      _clearedInput = null;
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

  void _loadExample(String text) {
    setState(() {
      _clearedInput = null;
      _inputKey++;
      _input = text;
      _inputFormat = tables.InputFormats.auto;
      _columns = null;
      _convert();
    });
  }

  void _clear() {
    if (_input.isEmpty) return;
    setState(() {
      _clearedInput = (input: _input, inputFormat: _inputFormat, columns: _columns);
      _inputKey++;
      _input = '';
      _columns = null;
      _convert();
    });
  }

  void _undoClear() {
    final cleared = _clearedInput;
    if (cleared == null) return;
    setState(() {
      _clearedInput = null;
      _inputKey++;
      _input = cleared.input;
      _inputFormat = cleared.inputFormat;
      _columns = cleared.columns;
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
