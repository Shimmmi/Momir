enum GameMode {
  creature,
  artifact,
  enchantment,
  planeswalker;

  String get column => switch (this) {
    GameMode.creature => 'is_creature',
    GameMode.artifact => 'is_artifact',
    GameMode.enchantment => 'is_enchantment',
    GameMode.planeswalker => 'is_planeswalker',
  };

  String get label => switch (this) {
    GameMode.creature => 'Momir',
    GameMode.artifact => 'Artifact Momir',
    GameMode.enchantment => 'Enchantment Momir',
    GameMode.planeswalker => 'Planeswalker Momir',
  };

  String get typeLabel => switch (this) {
    GameMode.creature => 'Существа',
    GameMode.artifact => 'Артефакты',
    GameMode.enchantment => 'Чары',
    GameMode.planeswalker => 'Мироходцы',
  };

  String get emptyPool => switch (this) {
    GameMode.creature => 'Существ с такой стоимостью нет',
    GameMode.artifact => 'Артефактов с такой стоимостью нет',
    GameMode.enchantment => 'Чар с такой стоимостью нет',
    GameMode.planeswalker => 'Мироходцев с такой стоимостью нет',
  };

  static GameMode? parse(String? raw) {
    if (raw == null) return null;
    for (final mode in values) {
      if (mode.name == raw) return mode;
    }
    return null;
  }

  static Set<GameMode>? tryParseSet(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final modes = <GameMode>{};
    for (final part in raw.split(',')) {
      final mode = parse(part.trim());
      if (mode != null) modes.add(mode);
    }
    return modes.isEmpty ? null : modes;
  }

  static String encode(Set<GameMode> modes) =>
      modes.map((mode) => mode.name).join(',');
}
