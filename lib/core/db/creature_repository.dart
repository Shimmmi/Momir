import 'package:sqflite/sqflite.dart';

import '../../models/creature.dart';
import '../constants.dart';
import 'database.dart';

class CreatureRepository {
  CreatureRepository(this._database);

  final AppDatabase _database;

  Future<int> count() async {
    final db = await _database.db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM creatures');
    return Sqflite.firstIntValue(rows) ?? 0;
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

  Future<List<({String id, String? printUrl, String? displayUrl})>>
  imageJobs() async {
    final db = await _database.db;
    final rows = await db.query(
      'creatures',
      columns: ['id', 'image_uri_art_crop', 'image_uri_normal'],
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
  Future<Creature?> pickRandom(int cmc, {Set<String> colors = const {}}) async {
    final db = await _database.db;
    final where = StringBuffer();
    final args = <Object>[];
    if (cmc > kMaxExactCmc) {
      where.write('cmc >= ?');
      args.add(kMaxExactCmc + 1);
    } else {
      where.write('cmc = ?');
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
    for (final color in const ['W', 'U', 'B', 'R', 'G']) {
      if (colors.isNotEmpty && !colors.contains(color)) {
        where.write(' AND colors NOT LIKE ?');
        args.add('%"$color"%');
      }
    }
    final order = sortByCmc ? 'cmc, name COLLATE NOCASE' : 'name COLLATE NOCASE';
    final rows = await db.rawQuery(
      'SELECT * FROM creatures WHERE $where ORDER BY $order LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(Creature.fromRow).toList(growable: false);
  }
}
