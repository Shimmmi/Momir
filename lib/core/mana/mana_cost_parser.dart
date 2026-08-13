class ManaSpan {
  const ManaSpan.text(this.text) : symbol = null;
  const ManaSpan.symbol(this.symbol) : text = null;

  final String? text;
  final String? symbol;

  bool get isSymbol => symbol != null;
}

final _token = RegExp(r'\{([^}]+)\}');

/// Splits a Scryfall mana/oracle string into text and `{...}` symbol spans.
List<ManaSpan> parseManaText(String? input) {
  if (input == null || input.isEmpty) return const [];
  final spans = <ManaSpan>[];
  var cursor = 0;
  for (final match in _token.allMatches(input)) {
    if (match.start > cursor) {
      spans.add(ManaSpan.text(input.substring(cursor, match.start)));
    }
    spans.add(ManaSpan.symbol(match.group(1)!));
    cursor = match.end;
  }
  if (cursor < input.length) {
    spans.add(ManaSpan.text(input.substring(cursor)));
  }
  return spans;
}

String manaAssetPath(String code) {
  final file = code.replaceAll('/', '_');
  return 'assets/mana/$file.png';
}
