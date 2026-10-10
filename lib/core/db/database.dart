import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _db;

  Future<Database> get db async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    return open();
  }

  Future<Database> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'momir.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createV3(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE creatures ADD COLUMN set_code TEXT');
          await db.execute('ALTER TABLE creatures ADD COLUMN set_name TEXT');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_creatures_set ON creatures(set_code)',
          );
          await _createMatchTables(db);
          await _createPrinterTable(db);
        }
        if (oldVersion < 3) {
          await _upgradeToV3(db);
        }
      },
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<String?> meta(String key) async {
    final rows = await (await db).query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    await (await db).insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> _createV3(Database db) async {
  await db.execute('''
CREATE TABLE creatures (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mana_cost TEXT,
  cmc INTEGER NOT NULL,
  power TEXT,
  toughness TEXT,
  oracle_text TEXT,
  colors TEXT NOT NULL,
  type_line TEXT,
  image_uri_art_crop TEXT,
  image_uri_normal TEXT,
  set_code TEXT,
  set_name TEXT,
  loyalty TEXT,
  is_creature INTEGER NOT NULL DEFAULT 0,
  is_artifact INTEGER NOT NULL DEFAULT 0,
  is_enchantment INTEGER NOT NULL DEFAULT 0,
  is_planeswalker INTEGER NOT NULL DEFAULT 0
)
''');
  await db.execute('CREATE INDEX idx_creatures_cmc ON creatures(cmc)');
  await db.execute('CREATE INDEX idx_creatures_set ON creatures(set_code)');
  await _createKindIndexes(db);
  await db.execute('''
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
)
''');
  await _createMatchTables(db);
  await _createPrinterTable(db);
}

Future<void> _upgradeToV3(Database db) async {
  await _addColumnIfMissing(db, 'creatures', 'loyalty', 'TEXT');
  await _addColumnIfMissing(
    db,
    'creatures',
    'is_creature',
    'INTEGER NOT NULL DEFAULT 1',
  );
  await _addColumnIfMissing(
    db,
    'creatures',
    'is_artifact',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(
    db,
    'creatures',
    'is_enchantment',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(
    db,
    'creatures',
    'is_planeswalker',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await db.execute('UPDATE creatures SET is_creature = 1');
  await db.execute(
    "UPDATE creatures SET is_artifact = 1 WHERE type_line LIKE '%Artifact%'",
  );
  await db.execute(
    "UPDATE creatures SET is_enchantment = 1 WHERE type_line LIKE '%Enchantment%'",
  );
  await db.execute(
    "UPDATE creatures SET is_planeswalker = 1 WHERE type_line LIKE '%Planeswalker%'",
  );
  await _addColumnIfMissing(
    db,
    'matches',
    'mode',
    "TEXT NOT NULL DEFAULT 'creature'",
  );
  await _createKindIndexes(db);
}

Future<void> _addColumnIfMissing(
  Database db,
  String table,
  String column,
  String definition,
) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  final exists = rows.any((row) => row['name'] == column);
  if (exists) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}

Future<void> _createKindIndexes(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_creatures_creature_cmc ON creatures(is_creature, cmc)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_creatures_artifact_cmc ON creatures(is_artifact, cmc)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_creatures_enchantment_cmc ON creatures(is_enchantment, cmc)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_creatures_planeswalker_cmc ON creatures(is_planeswalker, cmc)',
  );
}

Future<void> _createMatchTables(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  turn_index INTEGER NOT NULL,
  mode TEXT NOT NULL DEFAULT 'creature'
)
''');
  await db.execute('''
CREATE TABLE IF NOT EXISTS match_players (
  match_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  PRIMARY KEY (match_id, position)
)
''');
  await db.execute('''
CREATE TABLE IF NOT EXISTS summons (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  match_id INTEGER NOT NULL,
  player_position INTEGER NOT NULL,
  creature_id TEXT NOT NULL,
  cmc INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  print_error TEXT
)
''');
}

Future<void> _createPrinterTable(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS saved_printers (
  address TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  custom_name TEXT NOT NULL,
  device_name TEXT,
  last_used TEXT
)
''');
}
