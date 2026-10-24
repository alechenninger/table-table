import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:slack_table/slack_table.dart' as tables;

class TableApp extends StatefulComponent {
  final Future<void> Function(String) copyText;

  const TableApp({required this.copyText, super.key});

  @override
  State<TableApp> createState() => _TableAppState();
}

class _TableAppState extends State<TableApp> {
  static const _example = '| Name | Role |\n| --- | --- |\n| Ada | Engineering |\n| Sam | Design |';
  static const _formats = {
    'auto': 'Auto-detect',
    'markdown': 'Markdown',
    'csv': 'CSV',
    'tsv': 'TSV',
    'pipe': 'Pipe-separated',
    'cursor': 'Cursor',
    'spaced': 'Spaced cells',
  };

  String _input = '';
  String _inputFormat = 'auto';
  String _outputFormat = 'slack';
  int? _columns;
  List<int> _candidates = [];
  tables.Table? _table;
  String _output = '';
  String? _error;
  bool _copying = false;
  bool _copied = false;
  bool _copyFailed = false;
  int _revision = 0;
  int _inputKey = 0;

  @override
  Component build(BuildContext context) {
    return main_(classes: 'app', [
      header([
        p(classes: 'wordmark', [
          img(src: 'favicon.svg', alt: '', width: 20, height: 20),
          .text('table-table'),
        ]),
        h1([.text('For the love of tables.')]),
        p(classes: 'intro', [
          .text('Tables are everywhere. Keep them tables, wherever you paste.'),
        ]),
      ]),
      hr(classes: 'hero-divider'),
      div(classes: 'workspace', [
        section(
          classes: 'pane input-pane',
          attributes: {'aria-labelledby': 'input-label'},
          [
            div(classes: 'pane-heading', [
              div(classes: 'input-heading', [
                label(id: 'input-label', htmlFor: 'table-input', [.text('Input')]),
                span(
                  classes: 'detected-format',
                  attributes: {'role': 'status', 'aria-atomic': 'true'},
                  [
                    if (_table != null && _inputFormat == 'auto') ...[
                      span(
                        classes: 'detection-check',
                        attributes: {'aria-hidden': 'true'},
                        [
                          .text('✓'),
                        ],
                      ),
                      span([.text('${_formats[_table!.sourceFormat]} detected')]),
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
                  for (final entry in _formats.entries)
                    option(value: entry.key, [.text(entry.value)]),
                ],
              ),
            ]),
            textarea(
              key: ValueKey(_inputKey),
              id: 'table-input',
              classes: _error == null
                  ? 'textarea table-input'
                  : 'textarea textarea-error table-input',
              placeholder: 'Paste something table-ish…',
              spellCheck: SpellCheck.isFalse,
              attributes: {
                'wrap': 'off',
                'aria-describedby': 'input-feedback',
                if (_error != null) 'aria-invalid': 'true',
                'autocapitalize': 'off',
                'autocorrect': 'off',
              },
              onInput: _changeInput,
              [.text(_input)],
            ),
            div(
              id: 'input-feedback',
              classes: 'input-feedback',
              attributes: {'aria-live': 'polite'},
              [
                if (_candidates.isNotEmpty)
                  div(classes: 'column-choice', [
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
                  ])
                else if (_error != null)
                  p(classes: 'error', [.text(_error!)]),
              ],
            ),
            div(classes: 'pane-footer', [
              button(classes: 'btn btn-sm btn-outline', onClick: _loadExample, [
                .text('Try an example'),
              ]),
              if (_input.isNotEmpty)
                button(classes: 'btn btn-sm btn-outline', onClick: _clear, [.text('Clear')]),
            ]),
          ],
        ),
        section(
          classes: 'pane output-pane',
          attributes: {'aria-label': 'Output'},
          [
            div(classes: 'pane-heading', [
              div(
                classes: 'join output-format',
                attributes: {'role': 'group', 'aria-label': 'Output format'},
                [
                  for (final (value, title) in [('slack', 'Slack'), ('markdown', 'Markdown')])
                    button(
                      id: 'output-$value',
                      classes: 'join-item btn btn-sm btn-ghost',
                      attributes: {'aria-pressed': '${_outputFormat == value}'},
                      onClick: () => _changeOutputFormat(value),
                      [.text(title)],
                    ),
                ],
              ),
            ]),
            div(classes: 'preview-toolbar', [
              span(classes: 'table-size', [
                if (_table != null)
                  .text(
                    '${_table!.rows.length} ${_table!.rows.length == 1 ? 'row' : 'rows'}'
                    ' · ${_table!.rows.first.length} columns',
                  ),
              ]),
              button(
                id: 'copy-output',
                classes: 'btn btn-sm btn-primary copy-button',
                disabled: _output.isEmpty || _copying,
                onClick: _copy,
                [.text(_copied ? 'Table preserved.' : 'Copy')],
              ),
            ]),
            div(classes: 'preview', [
              if (_table == null)
                p(classes: 'empty-preview', [
                  .text('Your table will appear here, columns and all.'),
                ])
              else if (_copyFailed)
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
              else if (_outputFormat == 'markdown')
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
                          for (final cell in _table!.rows.first) th(scope: 'col', [.text(cell)]),
                        ]),
                      ]),
                      tbody([
                        for (final row in _table!.rows.skip(1))
                          tr([
                            for (final cell in row) td([.text(cell)]),
                          ]),
                      ]),
                    ]),
                  ],
                ),
            ]),
            div(
              id: 'copy-feedback',
              classes: 'copy-feedback',
              attributes: {'role': 'status'},
              [
                if (_copyFailed)
                  p(classes: 'error', [.text('Copy unavailable. Select the text above and copy.')]),
                if (_copied)
                  span(classes: 'sr-only', [.text('Table preserved. Copied to clipboard.')]),
              ],
            ),
          ],
        ),
      ]),
      details(classes: 'about', [
        summary([.text('Why tables?')]),
        p([
          .text(
            'Rows belong together. Columns mean something. '
            'Copying and pasting shouldn’t undo all that.',
          ),
        ]),
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
      _convert();
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
      _inputFormat = 'auto';
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
    _revision++;
    _table = null;
    _output = '';
    _error = null;
    _candidates = [];
    _copied = false;
    _copying = false;
    _copyFailed = false;
    if (_input.trim().isEmpty) return;
    try {
      try {
        _table = tables.parseTable(_input, inputFormat: _inputFormat);
      } on tables.AmbiguousColumnsError catch (error) {
        _candidates = error.candidates;
        if (_columns == null || !_candidates.contains(_columns)) return;
        _table = tables.parseTable(_input, inputFormat: _inputFormat, columns: _columns);
      }
      _output = tables.formatTable(_table!, outputFormat: _outputFormat);
    } on tables.ParseError {
      _error = 'Couldn’t read a table. Check the text or choose its format.';
    }
  }

  Future<void> _copy() async {
    if (_output.isEmpty || _copying) return;
    final revision = _revision;
    setState(() => _copying = true);
    try {
      await component.copyText(_output);
      if (!mounted || revision != _revision) return;
      setState(() {
        _copying = false;
        _copied = true;
        _copyFailed = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _copying = false;
        _copied = false;
        _copyFailed = true;
      });
    }
  }
}
