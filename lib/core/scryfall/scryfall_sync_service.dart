import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/creature.dart';
import '../art/art_cache_service.dart';
import '../art/art_download_guard.dart';
import '../constants.dart';
import '../db/creature_repository.dart';
import '../db/database.dart';
import '../game_mode.dart';
import 'bulk_uri.dart';
import 'card_extractor.dart';
import 'json_array_reader.dart';
import 'sync_error.dart';

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
    this.typeCounts = const {},
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
  final Map<GameMode, int> typeCounts;
  final int artsDone;
  final int artsTotal;
  final int artsFailed;
  final double? bulkFraction;
  final String? message;
  final String? error;
  final bool background;

  int countOf(GameMode mode) => typeCounts[mode] ?? 0;

  bool get isRunning =>
      phase != SyncPhase.idle &&
      phase != SyncPhase.done &&
      phase != SyncPhase.error;

  SyncProgress copyWith({
    SyncPhase? phase,
    int? creatureCount,
    Map<GameMode, int>? typeCounts,
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
      typeCounts: typeCounts ?? this.typeCounts,
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
  }) : _dio = dio ?? createScryfallDio();

  final AppDatabase _database;
  final CreatureRepository _repository;
  final ArtCacheService _artCache;
  final Dio _dio;

  SyncProgress _progress = const SyncProgress();
  SyncProgress get progress => _progress;
  bool get isPaused => _paused;
  Set<GameMode> _selected = Set.of(GameMode.values);

  Future<void> loadStoredCount() async {
    final count = await _repository.count();
    final counts = await _repository.countsByMode();
    _emit(_progress.copyWith(creatureCount: count, typeCounts: counts));
  }

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
    ArtDownloadGuard.stop();
  }

  void resumeDownloads() {
    _paused = false;
    _pauseGate?.complete();
    _pauseGate = null;
    ArtDownloadGuard.start('Качаю арты…');
    notifyListeners();
  }

  void playInBackground() {
    _emit(
      _progress.copyWith(background: true, message: 'Докачка артов в фоне'),
    );
  }

  Future<void> _waitIfPaused() async {
    while (_paused && !_cancel) {
      await (_pauseGate?.future ??
          Future<void>.delayed(const Duration(milliseconds: 200)));
    }
  }

  Future<void> sync({bool replaceCards = true, Set<GameMode>? modes}) async {
    _cancel = false;
    _paused = false;
    _selected = (modes == null || modes.isEmpty)
        ? Set.of(GameMode.values)
        : Set.of(modes);
    await _database.setMeta(kMetaSyncModes, GameMode.encode(_selected));
    try {
      if (replaceCards) {
        await _syncCards();
      } else {
        final count = await _repository.count();
        final counts = await _repository.countsByMode();
        _emit(
          _progress.copyWith(
            phase: SyncPhase.downloadingArt,
            creatureCount: count,
            typeCounts: counts,
            clearError: true,
          ),
        );
      }
      try {
        await _syncArts();
      } finally {
        await ArtDownloadGuard.stop();
      }
      await _artCache.pruneOrphans(await _repository.allIds());
      await _database.setMeta(kMetaLastSync, DateTime.now().toIso8601String());
      final total = await _repository.count();
      final counts = await _repository.countsByMode();
      await _database.setMeta(kMetaCreatureCount, total.toString());
      final missed = _progress.artsFailed;
      _emit(
        _progress.copyWith(
          phase: SyncPhase.done,
          creatureCount: total,
          typeCounts: counts,
          message: missed > 0
              ? 'Готово. Не скачалось изображений: $missed'
              : 'Готово',
          artsFailed: missed,
        ),
      );
    } catch (e) {
      _emit(
        _progress.copyWith(
          phase: SyncPhase.error,
          error: syncErrorMessage(e),
          message: 'Ошибка синхронизации',
        ),
      );
    }
  }

  Future<void> retryFailedArts({Set<GameMode>? modes}) =>
      sync(replaceCards: false, modes: modes);

  Future<void> _syncCards() async {
    _emit(
      _progress.copyWith(
        phase: SyncPhase.fetchingIndex,
        message: 'Запрашиваю индекс Scryfall…',
        clearError: true,
      ),
    );
    Map<String, dynamic>? oracle;
    try {
      final direct = await _retry(
        () => _dio.get<dynamic>(kOracleCardsUrl, options: _jsonOptions),
      );
      oracle = _asJsonMap(direct.data);
      if (oracle['type'] != 'oracle_cards' && oracle['object'] != 'bulk_data') {
        oracle = null;
      }
    } catch (_) {
      oracle = null;
    }
    if (oracle == null) {
      final index = await _retry(
        () => _dio.get<dynamic>(kBulkDataUrl, options: _jsonOptions),
      );
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
    await _retry(() async {
      if (await bulkFile.exists()) {
        await bulkFile.delete();
      }
      await _dio.download(
        uri,
        bulkFile.path,
        deleteOnError: true,
        options: Options(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(minutes: 20),
        ),
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
    });

    _emit(
      _progress.copyWith(
        phase: SyncPhase.parsing,
        message: 'Разбираю карты…',
        bulkFraction: 1,
      ),
    );
    await _repository.deleteByModes(_selected);
    var inserted = 0;
    var batch = <Creature>[];
    await for (final card in readBulkCardObjects(
      bulkFile,
      gzipped: isGzipUri(uri),
      jsonl: isJsonlUri(uri),
    )) {
      final creature = extractCreature(card);
      if (creature == null || !creature.matchesAny(_selected)) continue;
      batch.add(creature);
      if (batch.length >= 500) {
        await _repository.replaceAll(batch);
        inserted += batch.length;
        batch = [];
        _emit(
          _progress.copyWith(
            creatureCount: inserted,
            message: 'Записано карт: $inserted',
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
        message: 'Записано карт: $inserted',
      ),
    );
    try {
      await bulkFile.delete();
    } catch (_) {}
  }

  Future<T> _retry<T>(Future<T> Function() action) async {
    const attempts = 3;
    Object? last;
    for (var i = 0; i < attempts; i++) {
      try {
        return await action();
      } catch (e) {
        last = e;
        if (!isRetryableSyncError(e) || i == attempts - 1) rethrow;
        _emit(
          _progress.copyWith(
            message: 'Нет ответа от Scryfall, повтор ${i + 2} из $attempts…',
          ),
        );
        await Future<void>.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw last!;
  }

  Future<void> _syncArts() async {
    final jobs = await _repository.imageJobs(modes: _selected);
    final missing = <({String id, String url, bool display})>[];
    var done = 0;
    for (final job in jobs) {
      final printUrl = job.printUrl;
      if (printUrl == null ||
          printUrl.isEmpty ||
          await _artCache.hasArt(job.id)) {
        done++;
      } else {
        missing.add((id: job.id, url: printUrl, display: false));
      }
      final displayUrl = job.displayUrl;
      if (displayUrl == null ||
          displayUrl.isEmpty ||
          await _artCache.hasDisplay(job.id)) {
        done++;
      } else {
        missing.add((id: job.id, url: displayUrl, display: true));
      }
    }
    _emit(
      _progress.copyWith(
        phase: SyncPhase.downloadingArt,
        artsDone: done,
        artsTotal: jobs.length * 2,
        artsFailed: 0,
        message: 'Качаю арты…',
      ),
    );

    if (missing.isNotEmpty) {
      await ArtDownloadGuard.start('Арты: $done / ${jobs.length * 2}');
    }
    final failed = <({String id, String url, bool display})>[];
    await _downloadPool(missing, failed, countFailures: false);
    if (failed.isNotEmpty && !_cancel) {
      _emit(
        _progress.copyWith(
          phase: SyncPhase.retryingArt,
          artsFailed: 0,
          message: 'Повтор неудачных артов: ${failed.length}',
        ),
      );
      await ArtDownloadGuard.update('Повтор: ${failed.length}');
      final still = <({String id, String url, bool display})>[];
      await _downloadPool(failed, still, countFailures: true);
      _emit(_progress.copyWith(artsFailed: still.length));
    }
  }

  Future<void> _downloadPool(
    List<({String id, String url, bool display})> items,
    List<({String id, String url, bool display})> failedOut, {
    required bool countFailures,
  }) async {
    final queue = List<({String id, String url, bool display})>.from(items);
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
          if (job.display) {
            await _artCache.storeDisplayFromBytes(job.id, bytes);
          } else {
            await _artCache.storeFromBytes(job.id, bytes);
          }
          final message =
              'Арты: ${_progress.artsDone + 1} / ${_progress.artsTotal}';
          _emit(
            _progress.copyWith(
              artsDone: _progress.artsDone + 1,
              message: message,
            ),
          );
          await ArtDownloadGuard.update(message);
        } catch (_) {
          failedOut.add(job);
          if (countFailures) {
            _emit(_progress.copyWith(artsFailed: _progress.artsFailed + 1));
          }
        }
        await Future<void>.delayed(kScryfallDelay);
      }
    }

    await Future.wait(List.generate(kArtConcurrency, (_) => worker()));
  }
}

final _jsonOptions = Options(
  connectTimeout: const Duration(seconds: 60),
  receiveTimeout: const Duration(seconds: 60),
);

Dio createScryfallDio() {
  final dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': kScryfallUserAgent,
        'Accept': 'application/json, */*',
      },
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 20),
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      client.connectionFactory = _connectPreferIpv4;
      return client;
    },
  );
  return dio;
}

/// Scryfall often stalls on IPv6 from mobile networks. Connect to IPv4 first.
///
/// A custom [HttpClient.connectionFactory] socket is not upgraded by Dart, so
/// HTTPS has to be wrapped here. Otherwise Cloudflare answers 400:
/// "The plain HTTP request was sent to HTTPS port".
Future<ConnectionTask<Socket>> _connectPreferIpv4(
  Uri uri,
  String? proxyHost,
  int? proxyPort,
) {
  final pending = _openSocket(uri, proxyHost, proxyPort);
  return Future.value(
    ConnectionTask.fromSocket(pending, () {
      pending.then((socket) => socket.destroy()).ignore();
    }),
  );
}

Future<Socket> _openSocket(Uri uri, String? proxyHost, int? proxyPort) async {
  const timeout = Duration(seconds: 8);
  final host = proxyHost ?? uri.host;
  final port = proxyPort ?? uri.port;
  Socket? socket;
  if (proxyHost == null) {
    try {
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 8));
      for (final address in addresses) {
        try {
          socket = await Socket.connect(address, port, timeout: timeout);
          break;
        } catch (_) {}
      }
    } catch (_) {}
  }
  socket ??= await Socket.connect(host, port, timeout: timeout);
  if (proxyHost == null && uri.scheme == 'https') {
    return SecureSocket.secure(socket, host: uri.host);
  }
  return socket;
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
