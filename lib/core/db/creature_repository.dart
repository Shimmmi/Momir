import 'package:sqflite/sqflite.dart';

import '../../models/creature.dart';
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

  /// [cmc] 0–9 exact; 10 means 10+.
  Future<Creature?> pickRandom(int cmc, {Set<String> colors = const {}}) async {
    final db = await _database.db;
    final where = StringBuffer();
    final args = <Object>[];
    if (cmc >= 10) {
      where.write('cmc >= ?');
      args.add(10);
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
}
