import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/creature.dart';
import '../art/art_cache_service.dart';
import '../constants.dart';
import '../db/creature_repository.dart';
import '../db/database.dart';
import 'bulk_uri.dart';
import 'card_extractor.dart';
import 'json_array_reader.dart';

enum SyncPhase {
  idle,
  fetchingIndex,
  downloadingBulk,
  parsing,
  downloadingArt,
  retryingArt,
  done,
  error,
}

class SyncProgress {
  const SyncProgress({
    this.phase = SyncPhase.idle,
    this.creatureCount = 0,
    this.artsDone = 0,
    this.artsTotal = 0,
    this.artsFailed = 0,
    this.bulkFraction,
    this.message,
    this.error,
    this.background = false,
  });

  final SyncPhase phase;
  final int creatureCount;
  final int artsDone;
  final int artsTotal;
  final int artsFailed;
  final double? bulkFraction;
  final String? message;
  final String? error;
  final bool background;

  bool get isRunning =>
      phase != SyncPhase.idle &&
      phase != SyncPhase.done &&
      phase != SyncPhase.error;

  SyncProgress copyWith({
    SyncPhase? phase,
    int? creatureCount,
    int? artsDone,
    int? artsTotal,
    int? artsFailed,
    double? bulkFraction,
    String? message,
    String? error,
    bool? background,
    bool clearError = false,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      creatureCount: creatureCount ?? this.creatureCount,
      artsDone: artsDone ?? this.artsDone,
      artsTotal: artsTotal ?? this.artsTotal,
      artsFailed: artsFailed ?? this.artsFailed,
      bulkFraction: bulkFraction ?? this.bulkFraction,
      message: message ?? this.message,
      error: clearError ? null : (error ?? this.error),
      background: background ?? this.background,
    );
  }
}

class ScryfallSyncService extends ChangeNotifier {
  ScryfallSyncService({
    required this._database,
    required this._repository,
    required this._artCache,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               headers: {
                 'User-Agent': kScryfallUserAgent,
                 'Accept': 'application/json, */*',
               },
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(minutes: 10),
             ),
           );

  final AppDatabase _database;
  final CreatureRepository _repository;
  final ArtCacheService _artCache;
  final Dio _dio;

  SyncProgress _progress = const SyncProgress();
  SyncProgress get progress => _progress;
  bool get isPaused => _paused;

  var _paused = false;
  var _cancel = false;
  Completer<void>? _pauseGate;

  void _emit(SyncProgress next) {
    _progress = next;
    notifyListeners();
  }

  void pause() {
    _paused = true;
    _pauseGate ??= Completer<void>();
    _emit(_progress.copyWith(message: 'Пауза'));
  }

  void resumeDownloads() {
    _paused = false;
    _pauseGate?.complete();
    _pauseGate = null;
    notifyListeners();
  }

  void playInBackground() {
    _emit(_progress.copyWith(background: true, message: 'Докачка артов в фоне'));
  }

  Future<void> _waitIfPaused() async {
    while (_paused && !_cancel) {
      await (_pauseGate?.future ?? Future<void>.delayed(const Duration(milliseconds: 200)));
    }
  }

  Future<void> sync({bool replaceCards = true}) async {
    _cancel = false;
    _paused = false;
    try {
      if (replaceCards) {
        await _syncCards();
      } else {
        final count = await _repository.count();
        _emit(_progress.copyWith(phase: SyncPhase.downloadingArt, creatureCount: count));
      }
      await _syncArts();
      await _artCache.pruneOrphans(await _repository.allIds());
      await _database.setMeta(kMetaLastSync, DateTime.now().toIso8601String());
      await _database.setMeta(
        kMetaCreatureCount,
        (await _repository.count()).toString(),
      );
      _emit(
        _progress.copyWith(
          phase: SyncPhase.done,
          message: 'Готово',
          artsFailed: _progress.artsFailed,
        ),
      );
    } catch (e) {
      _emit(
        _progress.copyWith(
          phase: SyncPhase.error,
          error: e.toString(),
          message: 'Ошибка синхронизации',
        ),
      );
    }
  }

  Future<void> retryFailedArts() => sync(replaceCards: false);

  Future<void> _syncCards() async {
    _emit(
      const SyncProgress(
        phase: SyncPhase.fetchingIndex,
        message: 'Запрашиваю индекс Scryfall…',
      ),
    );
    Map<String, dynamic>? oracle;
    try {
      final direct = await _dio.get<dynamic>(kOracleCardsUrl);
      oracle = _asJsonMap(direct.data);
      if (oracle['type'] != 'oracle_cards' && oracle['object'] != 'bulk_data') {
        oracle = null;
      }
    } catch (_) {
      oracle = null;
    }
    if (oracle == null) {
      final index = await _dio.get<dynamic>(kBulkDataUrl);
      final root = _asJsonMap(index.data);
      final data = root['data'] as List<dynamic>? ?? const [];
      for (final raw in data) {
        if (raw is Map && raw['type'] == 'oracle_cards') {
          oracle = Map<String, dynamic>.from(raw);
          break;
        }
      }
    }
    final uri = oracle == null ? null : bulkDownloadUri(oracle);
    if (uri == null) {
      throw StateError(
        'Не найден пакет oracle_cards. Проверьте интернет и повторите.',
      );
    }
    final tmpDir = await getTemporaryDirectory();
    final ext = isJsonlUri(uri)
        ? (isGzipUri(uri) ? 'jsonl.gz' : 'jsonl')
        : (isGzipUri(uri) ? 'json.gz' : 'json');
    final bulkFile = File(p.join(tmpDir.path, 'oracle_cards.$ext'));

    _emit(
      _progress.copyWith(
        phase: SyncPhase.downloadingBulk,
        message: 'Скачиваю базу карт…',
        bulkFraction: 0,
      ),
    );
    await _dio.download(
      uri,
      bulkFile.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          _emit(
            _progress.copyWith(
              bulkFraction: received / total,
              message:
                  'Скачиваю базу карт… ${(received / (1024 * 1024)).toStringAsFixed(1)} МБ',
            ),
          );
        }
      },
    );

    _emit(
      _progress.copyWith(
        phase: SyncPhase.parsing,
        message: 'Разбираю существ…',
        bulkFraction: 1,
      ),
    );
    await _repository.clearCreatures();
    var inserted = 0;
    var batch = <Creature>[];
    await for (final card in readBulkCardObjects(
      bulkFile,
      gzipped: isGzipUri(uri),
      jsonl: isJsonlUri(uri),
    )) {
      final creature = extractCreature(card);
      if (creature == null) continue;
      batch.add(creature);
      if (batch.length >= 500) {
        await _repository.replaceAll(batch);
        inserted += batch.length;
        batch = [];
        _emit(
          _progress.copyWith(
            creatureCount: inserted,
            message: 'Записано существ: $inserted',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (batch.isNotEmpty) {
      await _repository.replaceAll(batch);
      inserted += batch.length;
    }
    _emit(
      _progress.copyWith(
        creatureCount: inserted,
        message: 'Карт в базе: $inserted',
      ),
    );
    try {
      await bulkFile.delete();
    } catch (_) {}
  }

  Future<void> _syncArts() async {
    final jobs = await _repository.artJobs();
    final missing = <({String id, String url})>[];
    var done = 0;
    for (final job in jobs) {
      if (await _artCache.hasArt(job.id)) {
        done++;
      } else if (job.url != null && job.url!.isNotEmpty) {
        missing.add((id: job.id, url: job.url!));
      } else {
        done++;
      }
    }
    _emit(
      _progress.copyWith(
        phase: SyncPhase.downloadingArt,
        artsDone: done,
        artsTotal: jobs.length,
        artsFailed: 0,
        message: 'Качаю арты…',
      ),
    );

    final failed = <({String id, String url})>[];
    await _downloadPool(missing, failed);
    if (failed.isNotEmpty && !_cancel) {
      _emit(
        _progress.copyWith(
          phase: SyncPhase.retryingArt,
          artsFailed: failed.length,
          message: 'Повтор неудачных артов: ${failed.length}',
        ),
      );
      final still = <({String id, String url})>[];
      await _downloadPool(failed, still);
      _emit(_progress.copyWith(artsFailed: still.length));
    }
  }

  Future<void> _downloadPool(
    List<({String id, String url})> items,
    List<({String id, String url})> failedOut,
  ) async {
    final queue = List<({String id, String url})>.from(items);
    Future<void> worker() async {
      while (queue.isNotEmpty && !_cancel) {
        await _waitIfPaused();
        if (queue.isEmpty) break;
        final job = queue.removeAt(0);
        try {
          final response = await _dio.get<List<int>>(
            job.url,
            options: Options(
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 45),
            ),
          );
          final bytes = response.data;
          if (bytes == null || bytes.isEmpty) {
            throw StateError('empty art');
          }
          await _artCache.storeFromBytes(job.id, bytes);
          _emit(
            _progress.copyWith(
              artsDone: _progress.artsDone + 1,
              message:
                  'Арты: ${_progress.artsDone + 1} / ${_progress.artsTotal}',
            ),
          );
        } catch (_) {
          failedOut.add(job);
          _emit(_progress.copyWith(artsFailed: _progress.artsFailed + 1));
        }
        await Future<void>.delayed(kScryfallDelay);
      }
    }

    await Future.wait(
      List.generate(kArtConcurrency, (_) => worker()),
    );
  }
}

Map<String, dynamic> _asJsonMap(dynamic payload) {
  if (payload is Map<String, dynamic>) return payload;
  if (payload is Map) return Map<String, dynamic>.from(payload);
  if (payload is String && payload.trim().isNotEmpty) {
    final decoded = jsonDecode(payload);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  return <String, dynamic>{};
}
