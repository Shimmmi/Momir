import 'dart:convert';

class Creature {
  const Creature({
    required this.id,
    required this.name,
    required this.cmc,
    required this.colors,
    this.manaCost,
    this.power,
    this.toughness,
    this.oracleText,
    this.typeLine,
    this.imageUriArtCrop,
    this.imageUriNormal,
  });

  final String id;
  final String name;
  final String? manaCost;
  final int cmc;
  final String? power;
  final String? toughness;
  final String? oracleText;
  final List<String> colors;
  final String? typeLine;
  final String? imageUriArtCrop;
  final String? imageUriNormal;

  String get colorsKey => colors.join(',');

  String? get artUrl =>
      (imageUriArtCrop != null && imageUriArtCrop!.isNotEmpty)
      ? imageUriArtCrop
      : imageUriNormal;

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'mana_cost': manaCost,
    'cmc': cmc,
    'power': power,
    'toughness': toughness,
    'oracle_text': oracleText,
    'colors': jsonEncode(colors),
    'type_line': typeLine,
    'image_uri_art_crop': imageUriArtCrop,
    'image_uri_normal': imageUriNormal,
  };

  factory Creature.fromRow(Map<String, Object?> row) {
    final rawColors = row['colors'] as String? ?? '[]';
    List<String> colors;
    try {
      colors = (jsonDecode(rawColors) as List<dynamic>).cast<String>();
    } catch (_) {
      colors = rawColors
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
    }
    return Creature(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      manaCost: row['mana_cost'] as String?,
      cmc: (row['cmc'] as num?)?.round() ?? 0,
      power: row['power'] as String?,
      toughness: row['toughness'] as String?,
      oracleText: row['oracle_text'] as String?,
      colors: colors,
      typeLine: row['type_line'] as String?,
      imageUriArtCrop: row['image_uri_art_crop'] as String?,
      imageUriNormal: row['image_uri_normal'] as String?,
    );
  }

  Map<String, Object?> toIsolateMap() => toRow();

  factory Creature.fromIsolateMap(Map<dynamic, dynamic> map) {
    return Creature.fromRow(Map<String, Object?>.from(map));
  }
}
