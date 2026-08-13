class ManaSpan {
  const ManaSpan.text(this.text) : symbol = null;
  const ManaSpan.symbol(this.symbol) : text = null;

  final String? text;
  final String? symbol;

  bool get isSymbol => symbol != null;
}

class OraclePiece {
  const OraclePiece._({this.text, this.symbol, required this.kind});
  const OraclePiece.word(String text)
    : this._(text: text, kind: OraclePieceKind.word);
  const OraclePiece.symbol(String symbol)
    : this._(symbol: symbol, kind: OraclePieceKind.symbol);
  const OraclePiece.space() : this._(text: ' ', kind: OraclePieceKind.space);
  const OraclePiece.lineBreak() : this._(kind: OraclePieceKind.lineBreak);

  final String? text;
  final String? symbol;
  final OraclePieceKind kind;
}

enum OraclePieceKind { word, symbol, space, lineBreak }

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

/// Turns oracle text into words, spaces, line breaks and mana symbols.
List<OraclePiece> oraclePieces(String? input) {
  if (input == null || input.isEmpty) return const [];
  final pieces = <OraclePiece>[];
  for (final span in parseManaText(input)) {
    if (span.isSymbol) {
      pieces.add(OraclePiece.symbol(span.symbol!));
      continue;
    }
    final raw = (span.text ?? '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    var i = 0;
    while (i < raw.length) {
      final ch = raw[i];
      if (ch == '\n') {
        pieces.add(const OraclePiece.lineBreak());
        i++;
        continue;
      }
      if (ch == ' ' || ch == '\t') {
        pieces.add(const OraclePiece.space());
        i++;
        continue;
      }
      final start = i;
      while (i < raw.length &&
          raw[i] != ' ' &&
          raw[i] != '\t' &&
          raw[i] != '\n') {
        i++;
      }
      pieces.add(OraclePiece.word(raw.substring(start, i)));
    }
  }
  return pieces;
}

String manaAssetPath(String code) {
  final file = code.replaceAll('/', '_');
  return 'assets/mana/$file.png';
}
