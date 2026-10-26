class ParseError implements Exception {
  final String message;

  const ParseError(this.message);

  @override
  String toString() => message;
}

class AmbiguousColumnsError extends ParseError {
  final List<int> candidates;

  AmbiguousColumnsError(List<int> candidates)
      : candidates = List.unmodifiable(candidates),
        super(
            'ambiguous column count; valid choices are ${candidates.join(', ')}');
}
