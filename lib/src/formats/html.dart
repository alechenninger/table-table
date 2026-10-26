import 'dart:math' as math;

import 'package:csslib/parser.dart' as css_parser;
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:source_span/source_span.dart';

import '../errors.dart';
import '../formats.dart';
import '../table.dart';
import '../text_cells.dart';

const htmlInput =
    InputFormat(id: InputFormats.html, label: 'HTML', read: _parseHtml);

final _htmlTableTag = RegExp(r'<table[\s>]', caseSensitive: false);
final _htmlDisplayCandidate = RegExp(r'display|\\', caseSensitive: false);
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

Table _parseHtml(String text, {int? columns}) {
  if (!_htmlTableTag.hasMatch(text)) {
    throw const ParseError('no HTML table found');
  }
  // Parse inert data, never attach copied markup to a browser document.
  final styles = _HtmlStyles();
  final table = _firstHtmlTable(html_parser.parse(text), styles);
  if (table == null) throw const ParseError('no HTML table found');
  final rows = <List<String>>[];
  final pending = <html.Node>[table];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node is! html.Element || styles.display(node) == _HtmlDisplay.hidden) {
      continue;
    }
    if (node.localName == 'tr') {
      final cells = <String>[];
      for (final cell in node.nodes) {
        if (cell is! html.Element ||
            (cell.localName != 'td' && cell.localName != 'th')) {
          continue;
        }
        // Attribute-free cells cannot be hidden or merged. Keep plain grids
        // out of style resolution and avoid repeated empty-map lookups.
        if (cell.attributes.isNotEmpty) {
          if (styles.display(cell) == _HtmlDisplay.hidden) continue;
          // Merged cells need a grid expansion; reject rather than shift columns.
          if (_htmlHasSpan(cell, 'rowspan') || _htmlHasSpan(cell, 'colspan')) {
            throw const ParseError(
                'HTML tables with merged cells are not supported');
          }
        }
        cells.add(_htmlCellText(cell, styles));
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
  return Table(rows, sourceFormat: InputFormats.html);
}

html.Element? _firstHtmlTable(html.Node root, _HtmlStyles styles) {
  // The package's CSS selectors recurse through the DOM. Keep our traversal
  // iterative so deeply wrapped clipboard fragments cannot exhaust the stack.
  final pending = <html.Node>[root];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node is html.Element) {
      if (styles.display(node) == _HtmlDisplay.hidden) continue;
      if (node.localName == 'table') return node;
    }
    for (var i = node.nodes.length - 1; i >= 0; i--) {
      pending.add(node.nodes[i]);
    }
  }
  return null;
}

bool _htmlHasSpan(html.Element cell, String attribute) {
  final source = cell.attributes[attribute];
  if (source == null) return false;
  final value = _htmlSpanInteger(source);
  // Invalid attributes default to one. Zero spans the remaining rows, but a
  // zero colspan defaults to one, per HTML's table processing model.
  return value != null && (value > 1 || (value == 0 && attribute == 'rowspan'));
}

/// HTML non-negative integer parsing, retaining only zero, one, or multiple.
/// https://html.spec.whatwg.org/multipage/common-microsyntaxes.html#rules-for-parsing-non-negative-integers
int? _htmlSpanInteger(String source) {
  var position = 0;
  while (position < source.length) {
    final code = source.codeUnitAt(position);
    if (code != 0x20 &&
        code != 0x09 &&
        code != 0x0a &&
        code != 0x0c &&
        code != 0x0d) {
      break;
    }
    position++;
  }
  if (position == source.length) return null;
  final negative = source.codeUnitAt(position) == 0x2d;
  if (negative || source.codeUnitAt(position) == 0x2b) position++;
  if (position == source.length) return null;
  final first = source.codeUnitAt(position);
  if (first < 0x30 || first > 0x39) return null;
  var value = 0;
  while (position < source.length) {
    final code = source.codeUnitAt(position++);
    if (code < 0x30 || code > 0x39) break;
    // Saturation preserves every decision about merging without overflowing
    // either native integers or JavaScript numbers, even for enormous values.
    value = math.min(2, value * 10 + code - 0x30);
  }
  return negative && value != 0 ? null : value;
}

// Preserve the established HTML visible-text grammar: whitespace collapses and
// block/layout boundaries introduce spaces. Rich formatting and CSS white-space
// reconstruction are outside this reader's contract.
String _htmlCellText(html.Element cell, _HtmlStyles styles) {
  // Most spreadsheet cells are empty or a single text node. Avoid allocating
  // a traversal stack and string buffer for these common cases.
  if (cell.nodes.isEmpty) return '';
  if (cell.nodes.length == 1 && cell.nodes.first is html.Text) {
    return cleanCell((cell.nodes.first as html.Text).data);
  }
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
    final display = styles.display(node);
    if (display == _HtmlDisplay.hidden) continue;
    final block = node.localName == 'br' ||
        (display == _HtmlDisplay.natural
            ? _htmlBlocks.contains(node.localName)
            : display == _HtmlDisplay.block ||
                display == _HtmlDisplay.blockLayout);
    // Flex/grid children have visual separation even without text whitespace.
    final layout = display == _HtmlDisplay.inlineLayout ||
        display == _HtmlDisplay.blockLayout;
    if (block) {
      text.write(' ');
      pending.add(null);
    }
    for (var i = node.nodes.length - 1; i >= 0; i--) {
      pending.add(node.nodes[i]);
      if (layout && i != 0) pending.add(null);
    }
  }
  return cleanCell(text.toString());
}

enum _HtmlDisplay { natural, inline, block, inlineLayout, blockLayout, hidden }

/// Interpret only inline display and explicit hidden/non-content subtrees.
/// A parse-local, bounded cache reuses the styles repeated in copied tables.
class _HtmlStyles {
  // These are text-extraction categories, rather than a rendering model.
  static const _keywords = {
    'none': _HtmlDisplay.hidden,
    'flex': _HtmlDisplay.blockLayout,
    'grid': _HtmlDisplay.blockLayout,
    'inline-flex': _HtmlDisplay.inlineLayout,
    'inline-grid': _HtmlDisplay.inlineLayout,
    'block': _HtmlDisplay.block,
    'flow': _HtmlDisplay.block,
    'flow-root': _HtmlDisplay.block,
    'list-item': _HtmlDisplay.block,
    'table': _HtmlDisplay.block,
    'table-row': _HtmlDisplay.block,
    'table-caption': _HtmlDisplay.block,
    'table-row-group': _HtmlDisplay.block,
    'table-header-group': _HtmlDisplay.block,
    'table-footer-group': _HtmlDisplay.block,
    'inline': _HtmlDisplay.inline,
    'run-in': _HtmlDisplay.inline,
    'inline-block': _HtmlDisplay.inline,
    'inline-table': _HtmlDisplay.inline,
    'contents': _HtmlDisplay.inline,
    'table-cell': _HtmlDisplay.inline,
    'table-column': _HtmlDisplay.inline,
    'table-column-group': _HtmlDisplay.inline,
    'ruby': _HtmlDisplay.inline,
    'ruby-base': _HtmlDisplay.inline,
    'ruby-text': _HtmlDisplay.inline,
    'ruby-base-container': _HtmlDisplay.inline,
    'ruby-text-container': _HtmlDisplay.inline,
    'initial': _HtmlDisplay.inline,
    'unset': _HtmlDisplay.inline,
    'inherit': _HtmlDisplay.natural,
    'revert': _HtmlDisplay.natural,
    'revert-layer': _HtmlDisplay.natural,
  };

  final _cache = <String, _HtmlDisplay>{};
  ({String source, _HtmlDisplay display})? _prefix;

  _HtmlDisplay display(html.Element element) {
    final tag = element.localName;
    if (tag == 'template' || tag == 'script' || tag == 'style') {
      return _HtmlDisplay.hidden;
    }
    final attributes = element.attributes;
    if (attributes.isEmpty) return _HtmlDisplay.natural;
    final style = attributes['style'];
    if (style == null) {
      return attributes.containsKey('hidden')
          ? _HtmlDisplay.hidden
          : _HtmlDisplay.natural;
    }
    // A sole style attribute cannot also mark the element hidden.
    if (attributes.length > 1 && attributes.containsKey('hidden')) {
      return _HtmlDisplay.hidden;
    }
    final cached = _cache[style];
    if (cached != null) return cached;
    final display = _parseDisplay(style);
    if (_cache.length < 256) _cache[style] = display;
    return display;
  }

  _HtmlDisplay _parseDisplay(String style) {
    // CSS preprocessing treats form feeds as newlines; csslib's tokenizer
    // expects this normalization to have happened before it reads whitespace.
    if (style.contains('\f')) style = style.replaceAll('\f', '\n');
    // Reuse a tokenized declaration prefix when only unrelated styles vary.
    // The boundary is a complete top-level declaration, never a regex split.
    final prefix = _prefix;
    if (prefix != null &&
        style.startsWith(prefix.source) &&
        _htmlDisplayCandidate.allMatches(style, prefix.source.length).isEmpty) {
      return prefix.display;
    }
    // Without this identifier or an escape, there can be no display property.
    // Leave unrelated CSS out of the parser, particularly large inline styles.
    var lastCandidate = -1;
    for (final match in _htmlDisplayCandidate.allMatches(style)) {
      lastCandidate = match.end;
    }
    if (lastCandidate < 0) return _HtmlDisplay.natural;
    // Use the library's lexical rules for comments, strings, and identifiers.
    // Its full expression parser recursively visits unrelated CSS values and
    // converts numbers to native integers; neither is needed for display.
    final tokenizer =
        css_parser.Tokenizer(SourceFile.fromString(style), style, true)
          ..inSelector = true;
    final tokens = <css_parser.Token>[];
    final closing = <int>[];
    var oversized = false;
    var display = _HtmlDisplay.natural;
    var important = false;
    while (true) {
      var token = tokenizer.next();
      final kind = token.kind;
      if (kind == css_parser.TokenKind.END_OF_FILE ||
          (kind == css_parser.TokenKind.SEMICOLON && closing.isEmpty)) {
        final declaration = oversized ? null : _displayDeclaration(tokens);
        if (declaration != null && (!important || declaration.important)) {
          display = declaration.display;
          important = declaration.important;
        }
        // A remaining display identifier must contain "display" or an escape.
        // Stop before unrelated values, which often make each style unique.
        if (kind == css_parser.TokenKind.END_OF_FILE ||
            token.end >= lastCandidate) {
          if (kind == css_parser.TokenKind.SEMICOLON && token.end <= 256) {
            _prefix = (source: style.substring(0, token.end), display: display);
          }
          return display;
        }
        tokens.clear();
        oversized = false;
        continue;
      }
      if (kind == css_parser.TokenKind.SINGLE_QUOTE ||
          kind == css_parser.TokenKind.DOUBLE_QUOTE) {
        token = tokenizer.finishString(
            kind == css_parser.TokenKind.SINGLE_QUOTE ? 0x27 : 0x22);
      } else if (kind == css_parser.TokenKind.LPAREN) {
        closing.add(css_parser.TokenKind.RPAREN);
      } else if (kind == css_parser.TokenKind.LBRACK) {
        closing.add(css_parser.TokenKind.RBRACK);
      } else if (kind == css_parser.TokenKind.LBRACE) {
        closing.add(css_parser.TokenKind.RBRACE);
      } else if (closing.isNotEmpty && kind == closing.last) {
        closing.removeLast();
      }
      // Supported display values contain at most three keywords plus priority.
      // Bound retained tokens even for huge unrelated declarations.
      if (tokens.length < 8) {
        tokens.add(token);
      } else {
        oversized = true;
      }
    }
  }

  ({_HtmlDisplay display, bool important})? _displayDeclaration(
      List<css_parser.Token> tokens) {
    if (tokens.length < 3 ||
        tokens.first.kind != css_parser.TokenKind.IDENTIFIER ||
        tokens.first.text.toLowerCase() != 'display' ||
        tokens[1].kind != css_parser.TokenKind.COLON) {
      return null;
    }
    var end = tokens.length;
    var important = false;
    if (tokens.last.text.toLowerCase() == '!important') {
      important = true;
      end--;
    } else if (end >= 4 &&
        tokens.last.text.toLowerCase() == 'important' &&
        tokens[end - 2].text == '!') {
      important = true;
      end -= 2;
    }
    final words = <String>[];
    for (var i = 2; i < end; i++) {
      if (tokens[i].kind != css_parser.TokenKind.IDENTIFIER) return null;
      words.add(tokens[i].text.toLowerCase());
    }
    final display = _displayValue(words);
    return display == null ? null : (display: display, important: important);
  }

  _HtmlDisplay? _displayValue(List<String> words) {
    if (words.length == 1) return _keywords[words.first];
    if (words.isEmpty || words.length > 3) return null;
    String? outside;
    String? inside;
    var listItem = false;
    for (final word in words) {
      if (const {'block', 'inline', 'run-in'}.contains(word)) {
        if (outside != null) return null;
        outside = word;
      } else if (const {'flow', 'flow-root', 'table', 'flex', 'grid', 'ruby'}
          .contains(word)) {
        if (inside != null) return null;
        inside = word;
      } else if (word == 'list-item' && !listItem) {
        listItem = true;
      } else {
        return null;
      }
    }
    if (listItem &&
        inside != null &&
        inside != 'flow' &&
        inside != 'flow-root') {
      return null;
    }
    final block =
        (outside ?? (inside == 'ruby' ? 'inline' : 'block')) == 'block';
    final layout = inside == 'flex' || inside == 'grid';
    return block
        ? (layout ? _HtmlDisplay.blockLayout : _HtmlDisplay.block)
        : (layout ? _HtmlDisplay.inlineLayout : _HtmlDisplay.inline);
  }
}
