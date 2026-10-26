import 'package:characters/characters.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:table_table/table_table.dart' as tables;

import 'preview_data.dart';

class TablePreview extends StatelessComponent {
  final PreviewData data;

  static const _cellClasses =
      'min-w-24 max-w-90 px-3 py-2 align-top whitespace-normal wrap-anywhere';

  const TablePreview({required this.data, super.key});

  @override
  Component build(BuildContext context) {
    return div([
      if (data.isLimited)
        p(
          id: 'preview-notice',
          classes: 'px-3 py-2 text-sm leading-6 text-base-content/65 sm:px-4',
          attributes: {'role': 'status'},
          [.text(data.notice)],
        ),
      if (data.text case final text?)
        pre(
          classes:
              'm-0 max-h-96 max-w-full overflow-auto p-3 font-mono text-base leading-6 [tab-size:4] focus-visible:outline-2 focus-visible:outline-primary focus-visible:outline-offset-2 sm:p-4',
          attributes: {
            'tabindex': '0',
            'aria-label': data.isMarkdown ? 'Markdown output' : 'Output preview',
          },
          [if (data.isMarkdown) ..._markdownText(text) else .text(text)],
        )
      else
        div(
          classes:
              'table-scroll max-h-96 max-w-full overflow-auto p-0.5 focus-visible:outline-2 focus-visible:outline-primary focus-visible:-outline-offset-2',
          attributes: {'tabindex': '0', 'aria-label': 'Slack table preview'},
          [
            table(classes: 'table w-max text-base leading-6', [
              thead(classes: 'text-base', [
                tr([
                  for (final cell in data.rows.first)
                    th(scope: 'col', classes: _cellClasses, [.text(cell)]),
                ]),
              ]),
              tbody([
                for (final row in data.rows.skip(1))
                  tr([
                    for (final cell in row) td(classes: _cellClasses, [.text(cell)]),
                  ]),
              ]),
            ]),
          ],
        ),
    ]);
  }

  // Copy feedback leaves the data unchanged; reuse its prepared Unicode spans
  // and table children instead of regenerating the preview.
  @override
  bool shouldRebuild(covariant TablePreview newComponent) => !identical(data, newComponent.data);
}

Iterable<Component> _markdownText(String source) sync* {
  final text = StringBuffer();
  final widths = <String, int>{};
  for (final character in source.characters) {
    // Keep fallback CJK and emoji fonts on the same grid as Markdown padding.
    if (character.codeUnitAt(0) > 127 &&
        widths.putIfAbsent(character, () => tables.displayWidth(character)) == 2) {
      if (text.isNotEmpty) {
        yield Component.text(text.toString());
        text.clear();
      }
      yield span(classes: 'inline-block w-[2ch] text-center', [.text(character)]);
    } else {
      text.write(character);
    }
  }
  if (text.isNotEmpty) yield Component.text(text.toString());
}
