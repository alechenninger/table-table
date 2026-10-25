/// Text representations understood by the table converters.
enum ClipboardFormat {
  plainText('text/plain'),
  html('text/html');

  final String mediaType;

  const ClipboardFormat(this.mediaType);
}

/// An immutable observation of the clipboard, with absent formats omitted.
/// Equality includes every representation, so HTML-only changes are observable.
final class ClipboardSnapshot {
  final Map<ClipboardFormat, String> representations;

  ClipboardSnapshot(Map<ClipboardFormat, String> representations)
      : representations = Map.unmodifiable(representations);

  ClipboardSnapshot.text(String text) : this({ClipboardFormat.plainText: text});

  String? operator [](ClipboardFormat format) => representations[format];

  @override
  bool operator ==(Object other) =>
      other is ClipboardSnapshot &&
      representations.length == other.representations.length &&
      representations.entries.every((entry) => other[entry.key] == entry.value);

  @override
  int get hashCode => Object.hashAll([
        for (final format in ClipboardFormat.values)
          Object.hash(format, representations[format]),
      ]);
}

/// Native clipboard I/O, independent of table parsing and format preference.
abstract interface class Clipboard {
  Future<ClipboardSnapshot> read();

  /// Replace the clipboard with the supplied representations of one item.
  Future<void> write(ClipboardSnapshot contents);
}

class ClipboardError implements Exception {
  final String message;

  const ClipboardError(this.message);

  @override
  String toString() => message;
}
