import 'dart:convert';

import '../core/game_mode.dart';

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
    this.setCode,
    this.setName,
    this.loyalty,
    this.isCreature = false,
    this.isArtifact = false,
    this.isEnchantment = false,
    this.isPlaneswalker = false,
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
  final String? setCode;
  final String? setName;
  final String? loyalty;
  final bool isCreature;
  final bool isArtifact;
  final bool isEnchantment;
  final bool isPlaneswalker;

  String get colorsKey => colors.join(',');

  bool matches(GameMode mode) => switch (mode) {
    GameMode.creature => isCreature,
    GameMode.artifact => isArtifact,
    GameMode.enchantment => isEnchantment,
    GameMode.planeswalker => isPlaneswalker,
  };

  bool matchesAny(Set<GameMode> modes) => modes.any(matches);

  String? get artUrl => (imageUriArtCrop != null && imageUriArtCrop!.isNotEmpty)
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
    'set_code': setCode,
    'set_name': setName,
    'loyalty': loyalty,
    'is_creature': isCreature ? 1 : 0,
    'is_artifact': isArtifact ? 1 : 0,
    'is_enchantment': isEnchantment ? 1 : 0,
    'is_planeswalker': isPlaneswalker ? 1 : 0,
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
      setCode: row['set_code'] as String?,
      setName: row['set_name'] as String?,
      loyalty: row['loyalty'] as String?,
      isCreature: _flag(row['is_creature'], ifNull: true),
      isArtifact: _flag(row['is_artifact']),
      isEnchantment: _flag(row['is_enchantment']),
      isPlaneswalker: _flag(row['is_planeswalker']),
    );
  }

  Map<String, Object?> toIsolateMap() => toRow();

  factory Creature.fromIsolateMap(Map<dynamic, dynamic> map) {
    return Creature.fromRow(Map<String, Object?>.from(map));
  }
}

bool _flag(Object? value, {bool ifNull = false}) {
  if (value == null) return ifNull;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return ifNull;
}
