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
      version: 2,
      onCreate: (db, version) async {
        await _createV2(db);
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

Future<void> _createV2(Database db) async {
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
  set_name TEXT
)
''');
  await db.execute('CREATE INDEX idx_creatures_cmc ON creatures(cmc)');
  await db.execute('CREATE INDEX idx_creatures_set ON creatures(set_code)');
  await db.execute('''
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
)
''');
  await _createMatchTables(db);
  await _createPrinterTable(db);
}

Future<void> _createMatchTables(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  turn_index INTEGER NOT NULL
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
