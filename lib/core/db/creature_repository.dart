import 'package:sqflite/sqflite.dart';

import '../../models/creature.dart';
import '../constants.dart';
import '../game_mode.dart';
import 'database.dart';

class CreatureRepository {
  CreatureRepository(this._database);

  final AppDatabase _database;

  Future<int> count() async {
    final db = await _database.db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM creatures');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> countFor(GameMode mode) async {
    final db = await _database.db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM creatures WHERE ${mode.column} = 1',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<Map<GameMode, int>> countsByMode() async {
    final db = await _database.db;
    final rows = await db.rawQuery('''
SELECT
  COALESCE(SUM(is_creature), 0) AS creature,
  COALESCE(SUM(is_artifact), 0) AS artifact,
  COALESCE(SUM(is_enchantment), 0) AS enchantment,
  COALESCE(SUM(is_planeswalker), 0) AS planeswalker
FROM creatures
''');
    final row = rows.first;
    int read(String key) => (row[key] as num?)?.toInt() ?? 0;
    return {
      GameMode.creature: read('creature'),
      GameMode.artifact: read('artifact'),
      GameMode.enchantment: read('enchantment'),
      GameMode.planeswalker: read('planeswalker'),
    };
  }

  Future<void> deleteByModes(Set<GameMode> modes) async {
    if (modes.isEmpty) return;
    if (modes.length >= GameMode.values.length) {
      await clearCreatures();
      return;
    }
    final db = await _database.db;
    final clause = modes.map((mode) => '${mode.column} = 1').join(' OR ');
    await db.rawDelete('DELETE FROM creatures WHERE $clause');
  }

  Future<void> replaceAll(List<Creature> batch) async {
    final db = await _database.db;
    final batchOp = db.batch();
    for (final c in batch) {
      batchOp.insert(
        'creatures',
        c.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batchOp.commit(noResult: true);
  }

  Future<void> clearCreatures() async {
    final db = await _database.db;
    await db.delete('creatures');
  }

  Future<List<({String id, String? printUrl, String? displayUrl})>> imageJobs({
    Set<GameMode>? modes,
  }) async {
    final db = await _database.db;
    final rows = await db.query(
      'creatures',
      columns: ['id', 'image_uri_art_crop', 'image_uri_normal'],
      where: _modeClause(modes),
    );
    return rows
        .map(
          (row) => (
            id: row['id'] as String,
            printUrl: row['image_uri_art_crop'] as String?,
            displayUrl: row['image_uri_normal'] as String?,
          ),
        )
        .toList(growable: false);
  }

  Future<List<({String id, String? url})>> artJobs() async {
    final db = await _database.db;
    final rows = await db.query(
      'creatures',
      columns: ['id', 'image_uri_art_crop', 'image_uri_normal'],
    );
    return rows
        .map((row) {
          final crop = row['image_uri_art_crop'] as String?;
          final normal = row['image_uri_normal'] as String?;
          final url = (crop != null && crop.isNotEmpty) ? crop : normal;
          return (id: row['id'] as String, url: url);
        })
        .toList(growable: false);
  }

  Future<Set<String>> allIds() async {
    final db = await _database.db;
    final rows = await db.query('creatures', columns: ['id']);
    return rows.map((r) => r['id'] as String).toSet();
  }

  /// [cmc] 0–[kMaxExactCmc] exact; [kMaxExactCmc]+1 means that value and above.
  Future<Creature?> pickRandom(
    int cmc, {
    Set<String> colors = const {},
    GameMode mode = GameMode.creature,
  }) async {
    final db = await _database.db;
    final where = StringBuffer('${mode.column} = 1');
    final args = <Object>[];
    if (cmc > kMaxExactCmc) {
      where.write(' AND cmc >= ?');
      args.add(kMaxExactCmc + 1);
    } else {
      where.write(' AND cmc = ?');
      args.add(cmc);
    }
    for (final color in const ['W', 'U', 'B', 'R', 'G']) {
      if (colors.isNotEmpty && !colors.contains(color)) {
        where.write(' AND colors NOT LIKE ?');
        args.add('%"$color"%');
      }
    }
    final rows = await db.rawQuery(
      'SELECT * FROM creatures WHERE $where ORDER BY RANDOM() LIMIT 1',
      args,
    );
    if (rows.isEmpty) return null;
    return Creature.fromRow(rows.first);
  }

  Future<Creature?> byId(String id) async {
    final db = await _database.db;
    final rows = await db.query(
      'creatures',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Creature.fromRow(rows.first);
  }

  Future<List<({String code, String name})>> sets() async {
    final db = await _database.db;
    final rows = await db.rawQuery('''
SELECT set_code, set_name, COUNT(*) AS c
FROM creatures
WHERE set_code IS NOT NULL AND set_code != ''
GROUP BY set_code
ORDER BY set_name COLLATE NOCASE
''');
    return rows
        .map(
          (row) => (
            code: row['set_code'] as String,
            name: (row['set_name'] as String?) ?? (row['set_code'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<List<Creature>> search({
    String query = '',
    int? cmc,
    Set<String> colors = const {},
    String? setCode,
    GameMode? mode,
    bool sortByCmc = false,
    int limit = 60,
    int offset = 0,
  }) async {
    final db = await _database.db;
    final where = StringBuffer('1 = 1');
    final args = <Object>[];
    final text = query.trim();
    if (text.isNotEmpty) {
      where.write(' AND name LIKE ?');
      args.add('%$text%');
    }
    if (cmc != null) {
      if (cmc > kMaxExactCmc) {
        where.write(' AND cmc >= ?');
        args.add(kMaxExactCmc + 1);
      } else {
        where.write(' AND cmc = ?');
        args.add(cmc);
      }
    }
    if (setCode != null && setCode.isNotEmpty) {
      where.write(' AND set_code = ?');
      args.add(setCode);
    }
    if (mode != null) {
      where.write(' AND ${mode.column} = 1');
    }
    for (final color in const ['W', 'U', 'B', 'R', 'G']) {
      if (colors.isNotEmpty && !colors.contains(color)) {
        where.write(' AND colors NOT LIKE ?');
        args.add('%"$color"%');
      }
    }
    final order = sortByCmc
        ? 'cmc, name COLLATE NOCASE'
        : 'name COLLATE NOCASE';
    final rows = await db.rawQuery(
      'SELECT * FROM creatures WHERE $where ORDER BY $order LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(Creature.fromRow).toList(growable: false);
  }
}

String? _modeClause(Set<GameMode>? modes) {
  if (modes == null ||
      modes.isEmpty ||
      modes.length >= GameMode.values.length) {
    return null;
  }
  return modes.map((mode) => '${mode.column} = 1').join(' OR ');
}
