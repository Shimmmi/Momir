import '../../models/creature.dart';
import '../game_mode.dart';
import 'database.dart';

class MatchPlayer {
  const MatchPlayer({required this.position, required this.name});

  final int position;
  final String name;
}

class MatchSummon {
  const MatchSummon({
    required this.id,
    required this.playerName,
    required this.cmc,
    required this.creature,
    this.printError,
  });

  final int id;
  final String playerName;
  final int cmc;
  final Creature creature;
  final String? printError;
}

class ActiveMatch {
  const ActiveMatch({
    required this.id,
    required this.turnIndex,
    required this.players,
    required this.summons,
    this.mode = GameMode.creature,
  });

  final int id;
  final int turnIndex;
  final GameMode mode;
  final List<MatchPlayer> players;
  final List<MatchSummon> summons;

  MatchPlayer get currentPlayer => players[turnIndex % players.length];
}

class MatchRepository {
  MatchRepository(this._database);

  final AppDatabase _database;

  Future<int> create(
    List<String> names, {
    GameMode mode = GameMode.creature,
  }) async {
    final db = await _database.db;
    final id = await db.insert('matches', {
      'created_at': DateTime.now().toIso8601String(),
      'turn_index': 0,
      'mode': mode.name,
    });
    for (var i = 0; i < names.length; i++) {
      await db.insert('match_players', {
        'match_id': id,
        'position': i,
        'name': names[i],
      });
    }
    return id;
  }

  Future<ActiveMatch?> latest(GameMode mode) async {
    final db = await _database.db;
    final rows = await db.query(
      'matches',
      where: 'mode = ?',
      whereArgs: [mode.name],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _load(rows.first['id'] as int);
  }

  Future<ActiveMatch?> byId(int id) => _load(id);

  Future<ActiveMatch> _load(int id) async {
    final db = await _database.db;
    final matchRows = await db.query(
      'matches',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final playerRows = await db.query(
      'match_players',
      where: 'match_id = ?',
      whereArgs: [id],
      orderBy: 'position',
    );
    final summonRows = await db.rawQuery(
      '''
SELECT s.id AS summon_id, s.cmc AS summon_cmc, s.print_error,
       p.name AS player_name, c.*
FROM summons s
JOIN match_players p
  ON p.match_id = s.match_id AND p.position = s.player_position
JOIN creatures c ON c.id = s.creature_id
WHERE s.match_id = ?
ORDER BY s.id DESC
''',
      [id],
    );
    return ActiveMatch(
      id: id,
      turnIndex: (matchRows.first['turn_index'] as num).toInt(),
      mode:
          GameMode.parse(matchRows.first['mode'] as String?) ??
          GameMode.creature,
      players: [
        for (final row in playerRows)
          MatchPlayer(
            position: (row['position'] as num).toInt(),
            name: row['name'] as String,
          ),
      ],
      summons: [
        for (final row in summonRows)
          MatchSummon(
            id: (row['summon_id'] as num).toInt(),
            playerName: row['player_name'] as String,
            cmc: (row['summon_cmc'] as num).toInt(),
            creature: Creature.fromRow(row),
            printError: row['print_error'] as String?,
          ),
      ],
    );
  }

  Future<int> addSummon({
    required int matchId,
    required int playerPosition,
    required String creatureId,
    required int cmc,
    String? printError,
  }) async {
    final db = await _database.db;
    return db.insert('summons', {
      'match_id': matchId,
      'player_position': playerPosition,
      'creature_id': creatureId,
      'cmc': cmc,
      'created_at': DateTime.now().toIso8601String(),
      'print_error': printError,
    });
  }

  Future<void> setPrintError(int summonId, String? error) async {
    final db = await _database.db;
    await db.update(
      'summons',
      {'print_error': error},
      where: 'id = ?',
      whereArgs: [summonId],
    );
  }

  Future<void> advanceTurn(int matchId, int playerCount) async {
    final db = await _database.db;
    final rows = await db.query(
      'matches',
      columns: ['turn_index'],
      where: 'id = ?',
      whereArgs: [matchId],
      limit: 1,
    );
    final current = (rows.first['turn_index'] as num).toInt();
    await db.update(
      'matches',
      {'turn_index': (current + 1) % playerCount},
      where: 'id = ?',
      whereArgs: [matchId],
    );
  }
}
