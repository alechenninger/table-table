part of 'core.dart';

final _htmlTableTag = RegExp(r'<table[\s>]', caseSensitive: false);
final _htmlDisplay =
    RegExp(r'(?:^|;)\s*display\s*:\s*([\w-]+)', caseSensitive: false);
const _htmlBlocks = {
  'address',
  'article',
  'aside',
  'blockquote',
  'br',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tr',
  'td',
  'th',
  'ul',
};
const _htmlIgnored = {'script', 'style', 'template'};

Table _parseHtml(String text) {
  // Parse inert data, never attach copied markup to a browser document.
  final table = _firstHtmlTable(html_parser.parse(text));
  if (table == null) throw const ParseError('no HTML table found');
  final rows = <List<String>>[];
  final pending = <html.Node>[table];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node is! html.Element) continue;
    if (node.localName == 'tr') {
      final cells = <String>[];
      for (final cell in node.nodes) {
        if (cell is! html.Element ||
            (cell.localName != 'td' && cell.localName != 'th')) {
          continue;
        }
        // Merged cells need a grid expansion; reject rather than shift columns.
        if (_htmlHasSpan(cell, 'rowspan') || _htmlHasSpan(cell, 'colspan')) {
          throw const ParseError(
              'HTML tables with merged cells are not supported');
        }
        cells.add(_htmlCellText(cell));
      }
      if (cells.isNotEmpty) rows.add(cells);
      // Cell contents cannot contribute rows to the containing table. Skipping
      // them also avoids revisiting every inline node during row discovery.
      continue;
    }
    if (node.localName == 'table' && node != table) continue;
    for (var i = node.nodes.length - 1; i >= 0; i--) {
      pending.add(node.nodes[i]);
    }
  }
  if (rows.isEmpty || rows.every((row) => row.length < 2)) {
    throw const ParseError('HTML table must have at least two columns');
  }
  return Table._parsed(rows, sourceFormat: InputFormats.html);
}

html.Element? _firstHtmlTable(html.Node root) {
  // The package's CSS selectors recurse through the DOM. Keep our traversal
  // iterative so deeply wrapped clipboard fragments cannot exhaust the stack.
  final pending = <html.Node>[root];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node is html.Element && node.localName == 'table') return node;
    for (var i = node.nodes.length - 1; i >= 0; i--) {
      pending.add(node.nodes[i]);
    }
  }
  return null;
}

bool _htmlHasSpan(html.Element cell, String attribute) {
  final source = cell.attributes[attribute];
  if (source == null) return false;
  final value = int.tryParse(source);
  return value != null && value != 1;
}

String _htmlCellText(html.Element cell) {
  final text = StringBuffer();
  // Null marks a pending space, including the end of a block element. This
  // preserves separators without recursive calls or per-node frame objects.
  final pending = <html.Node?>[];
  for (var i = cell.nodes.length - 1; i >= 0; i--) {
    pending.add(cell.nodes[i]);
  }
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node == null) {
      text.write(' ');
      continue;
    }
    if (node is html.Text) {
      text.write(node.data);
      continue;
    }
    if (node is! html.Element) continue;
    final style = node.attributes['style'];
    final display = style == null
        ? null
        : _htmlDisplay.firstMatch(style)?.group(1)?.toLowerCase();
    if (_htmlIgnored.contains(node.localName) ||
        node.attributes.containsKey('hidden') ||
        display == 'none') {
      continue;
    }
    final block = node.localName == 'br' ||
        (display == null
            ? _htmlBlocks.contains(node.localName)
            : const {'block', 'flex', 'grid', 'list-item', 'table', 'table-row'}
                .contains(display));
    // Flex/grid children have visual separation even without text whitespace.
    final layout =
        const {'flex', 'inline-flex', 'grid', 'inline-grid'}.contains(display);
    if (block) {
      text.write(' ');
      pending.add(null);
    }
    for (var i = node.nodes.length - 1; i >= 0; i--) {
      pending.add(node.nodes[i]);
      if (layout && i != 0) pending.add(null);
    }
  }
  return _cleanCell(text.toString());
}
