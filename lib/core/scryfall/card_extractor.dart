import '../../models/creature.dart';

const _tokenLayouts = {'token', 'double_faced_token', 'emblem', 'art_series'};

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _imageUri(Map<String, dynamic> source, String key) {
  final uris = _asMap(source['image_uris']);
  final value = uris?[key];
  return value is String && value.isNotEmpty ? value : null;
}

String? _text(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num) return value.toString();
  return null;
}

/// Aura whose first `Enchant …` line targets a creature, or an aura with no
/// such line. Land, artifact, player, and planeswalker auras return false.
bool _isCreatureAura(String typeLine, String? oracleText) {
  if (!typeLine.contains('Aura')) return false;
  final text = (oracleText ?? '').trim();
  if (text.isEmpty) return true;
  final first = text.split(RegExp(r'\r?\n')).first.trim();
  if (!first.toLowerCase().startsWith('enchant ')) return true;
  return RegExp(r'\bcreature\b', caseSensitive: false).hasMatch(first);
}

int _faceRank(String? typeLine, String? oracleText) {
  if (typeLine == null || typeLine.contains('Token')) return 0;
  if (typeLine.contains('Creature')) return 4;
  if (typeLine.contains('Planeswalker')) return 3;
  if (typeLine.contains('Artifact')) return 2;
  if (typeLine.contains('Enchantment') &&
      !_isCreatureAura(typeLine, oracleText)) {
    return 1;
  }
  return 0;
}

Map<String, dynamic>? _bestFace(Map<String, dynamic> card) {
  final faces = card['card_faces'];
  if (faces is List && faces.isNotEmpty) {
    Map<String, dynamic>? best;
    var bestRank = 0;
    for (final raw in faces) {
      final map = _asMap(raw);
      if (map == null) continue;
      final rank = _faceRank(
        map['type_line'] as String?,
        map['oracle_text'] as String?,
      );
      if (rank > bestRank) {
        best = map;
        bestRank = rank;
      }
    }
    return best;
  }
  final rank = _faceRank(
    card['type_line'] as String?,
    card['oracle_text'] as String?,
  );
  return rank == 0 ? null : card;
}

/// Picks one supported permanent from a Scryfall oracle card.
///
/// Face priority is creature, planeswalker, artifact, then enchantment.
/// Creature auras are dropped. Flags describe only the stored face.
Creature? extractCreature(Map<String, dynamic> card) {
  final layout = card['layout'] as String?;
  if (layout != null && _tokenLayouts.contains(layout)) return null;

  final face = _bestFace(card);
  if (face == null) return null;

  final typeLine = (face['type_line'] as String?) ?? '';
  final oracleText =
      (face['oracle_text'] as String?) ?? card['oracle_text'] as String?;
  if (typeLine.isEmpty || typeLine.contains('Token')) return null;

  final isCreature = typeLine.contains('Creature');
  final isArtifact = typeLine.contains('Artifact');
  final isPlaneswalker = typeLine.contains('Planeswalker');
  final isEnchantment =
      typeLine.contains('Enchantment') &&
      !_isCreatureAura(typeLine, oracleText);
  if (!isCreature && !isArtifact && !isEnchantment && !isPlaneswalker) {
    return null;
  }

  final id = card['id'] as String?;
  if (id == null || id.isEmpty) return null;

  final name = (face['name'] as String?) ?? (card['name'] as String?) ?? '';
  if (name.isEmpty) return null;

  final colorsRaw = face['colors'] ?? card['colors'] ?? const [];
  final colors = <String>[];
  if (colorsRaw is List) {
    for (final c in colorsRaw) {
      if (c is String) colors.add(c);
    }
  }

  final cmc = (card['cmc'] as num?)?.round() ?? 0;

  return Creature(
    id: id,
    name: name,
    manaCost: (face['mana_cost'] as String?) ?? card['mana_cost'] as String?,
    cmc: cmc,
    power: face['power'] as String? ?? card['power'] as String?,
    toughness: face['toughness'] as String? ?? card['toughness'] as String?,
    oracleText: oracleText,
    colors: colors,
    typeLine: typeLine,
    imageUriArtCrop: _imageUri(face, 'art_crop') ?? _imageUri(card, 'art_crop'),
    imageUriNormal: _imageUri(face, 'normal') ?? _imageUri(card, 'normal'),
    setCode: card['set'] as String?,
    setName: card['set_name'] as String?,
    loyalty: _text(face['loyalty'] ?? card['loyalty']),
    isCreature: isCreature,
    isArtifact: isArtifact,
    isEnchantment: isEnchantment,
    isPlaneswalker: isPlaneswalker,
  );
}
