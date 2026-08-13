import 'package:flutter/foundation.dart';

import '../core/art/art_cache_service.dart';
import '../core/db/creature_repository.dart';
import '../models/creature.dart';
import '../widgets/card_renderer.dart';

class SummonController extends ChangeNotifier {
  SummonController({
    required this._repository,
    required this._artCache,
    required this._renderer,
  });

  final CreatureRepository _repository;
  final ArtCacheService _artCache;
  final CardRenderService _renderer;

  Creature? creature;
  PrintableCard? card;
  int? cmc;
  var loading = false;
  String? error;

  Future<void> summon(int selectedCmc, {Set<String> colors = const {}}) async {
    cmc = selectedCmc;
    await _pick(colors: colors);
  }

  Future<void> reroll({Set<String> colors = const {}}) async {
    if (cmc == null) return;
    await _pick(colors: colors);
  }

  Future<void> _pick({Set<String> colors = const {}}) async {
    loading = true;
    error = null;
    card = null;
    notifyListeners();
    try {
      final picked = await _repository.pickRandom(cmc!, colors: colors);
      creature = picked;
      if (picked == null) {
        error = 'Существ с такой стоимостью маны нет в базе';
        loading = false;
        notifyListeners();
        return;
      }
      await renderCurrent();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> renderCurrent() async {
    final picked = creature;
    if (picked == null) return;
    loading = true;
    notifyListeners();
    try {
      var artBytes = (await _artCache.fileFor(picked.id)).existsSync()
          ? await (await _artCache.fileFor(picked.id)).readAsBytes()
          : null;
      if (artBytes == null && picked.artUrl != null) {
        // File may appear after background download.
        if (await _artCache.hasArt(picked.id)) {
          artBytes = await (await _artCache.fileFor(picked.id)).readAsBytes();
        }
      }
      card = await _renderer.renderCreature(picked, artJpeg: artBytes);
      error = null;
    } catch (e) {
      error = 'Не удалось собрать карточку: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
