/// Input identifiers shared by the parsers and their frontends.
abstract final class InputFormats {
  static const auto = 'auto';
  static const html = 'html';
  static const markdown = 'markdown';
  static const cursor = 'cursor';
  static const csv = 'csv';
  static const tsv = 'tsv';
  static const spaceAligned = 'space-aligned';
  static const pipe = 'pipe';
  static const spaced = 'spaced';

  /// Compatibility list of built-in choices. Frontends enumerate the catalog.
  static const values = [
    auto,
    html,
    markdown,
    cursor,
    csv,
    tsv,
    spaceAligned,
    pipe,
    spaced
  ];
}

/// Output identifiers shared by the formatters and their frontends.
abstract final class OutputFormats {
  static const slack = 'slack';
  static const markdown = 'markdown';

  static const values = [slack, markdown];
}
