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
      version: 1,
      onCreate: (db, version) async {
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
  image_uri_normal TEXT
)
''');
        await db.execute(
          'CREATE INDEX idx_creatures_cmc ON creatures(cmc)',
        );
        await db.execute('''
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
)
''');
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
