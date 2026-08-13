import '../../models/creature.dart';

const _tokenLayouts = {
  'token',
  'double_faced_token',
  'emblem',
  'art_series',
};

bool _isCreatureType(String? typeLine) {
  if (typeLine == null) return false;
  if (typeLine.contains('Token')) return false;
  return typeLine.contains('Creature');
}

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

/// Picks a unique creature identity from a Scryfall oracle card object.
Creature? extractCreature(Map<String, dynamic> card) {
  final layout = card['layout'] as String?;
  if (layout != null && _tokenLayouts.contains(layout)) return null;

  final cardType = card['type_line'] as String? ?? '';
  Map<String, dynamic> face = card;

  final faces = card['card_faces'];
  if (faces is List) {
    for (final raw in faces) {
      final map = _asMap(raw);
      if (map != null && _isCreatureType(map['type_line'] as String?)) {
        face = map;
        break;
      }
    }
  }

  final typeLine = (face['type_line'] as String?) ?? cardType;
  if (!_isCreatureType(typeLine)) return null;

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
    oracleText: face['oracle_text'] as String? ?? card['oracle_text'] as String?,
    colors: colors,
    typeLine: typeLine,
    imageUriArtCrop: _imageUri(face, 'art_crop') ?? _imageUri(card, 'art_crop'),
    imageUriNormal: _imageUri(face, 'normal') ?? _imageUri(card, 'normal'),
  );
}
