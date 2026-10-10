import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../core/art/art_cache_service.dart';
import '../../core/ble/printer_connection_service.dart';
import '../../core/constants.dart';
import '../../core/db/creature_repository.dart';
import '../../core/db/match_repository.dart';
import '../../core/game_mode.dart';
import '../../core/print_media.dart';
import '../../services/print_service.dart';
import '../../widgets/card_renderer.dart';
import '../../widgets/creature_image_dialog.dart';
import '../printer_setup/printer_picker.dart';

class MatchEntry extends StatefulWidget {
  const MatchEntry({super.key, this.mode = GameMode.creature});

  final GameMode mode;

  @override
  State<MatchEntry> createState() => _MatchEntryState();
}

class _MatchEntryState extends State<MatchEntry> {
  ActiveMatch? _match;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final match = await context.read<MatchRepository>().latest(widget.mode);
    if (!mounted) return;
    setState(() {
      _match = match;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final match = _match;
    if (match == null) {
      return MatchSetupScreen(
        mode: widget.mode,
        onCreated: (created) => setState(() => _match = created),
      );
    }
    return MatchPlayScreen(
      match: match,
      onChanged: (next) => setState(() => _match = next),
      onNew: () => setState(() => _match = null),
    );
  }
}

class MatchSetupScreen extends StatefulWidget {
  const MatchSetupScreen({
    super.key,
    required this.onCreated,
    this.mode = GameMode.creature,
  });

  final ValueChanged<ActiveMatch> onCreated;
  final GameMode mode;

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  final _names = <TextEditingController>[
    TextEditingController(text: 'Игрок 1'),
    TextEditingController(text: 'Игрок 2'),
  ];

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode.label),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/match'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Порядок хода сверху вниз. Минимум два имени.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _names.length; i++)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _names[i],
                    decoration: InputDecoration(labelText: 'Игрок ${i + 1}'),
                  ),
                ),
                IconButton(
                  onPressed: i == 0
                      ? null
                      : () => setState(() {
                          final item = _names.removeAt(i);
                          _names.insert(i - 1, item);
                        }),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  onPressed: _names.length <= 2
                      ? null
                      : () => setState(() {
                          final removed = _names.removeAt(i);
                          removed.dispose();
                        }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          TextButton(
            onPressed: () => setState(
              () => _names.add(
                TextEditingController(text: 'Игрок ${_names.length + 1}'),
              ),
            ),
            child: const Text('Добавить игрока'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _start, child: const Text('Начать')),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final printer = context.read<PrinterConnectionService>();
    final repo = context.read<MatchRepository>();
    if (!printer.isConnected) {
      await showPrinterPicker(context);
      if (!mounted || !printer.isConnected) return;
    }
    final names = _names
        .map((c) => c.text.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.length < 2) return;
    final id = await repo.create(names, mode: widget.mode);
    final match = await repo.byId(id);
    if (match != null) widget.onCreated(match);
  }
}

class MatchPlayScreen extends StatefulWidget {
  const MatchPlayScreen({
    super.key,
    required this.match,
    required this.onChanged,
    required this.onNew,
  });

  final ActiveMatch match;
  final ValueChanged<ActiveMatch> onChanged;
  final VoidCallback onNew;

  @override
  State<MatchPlayScreen> createState() => _MatchPlayScreenState();
}

class _MatchPlayScreenState extends State<MatchPlayScreen> {
  var _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final player = match.currentPlayer;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${match.mode.label} · ${player.name}',
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/menu'),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onNew,
            child: const Text('Новая'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _status!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              for (var i = 0; i <= kMaxExactCmc; i++)
                _ManaButton(
                  label: '$i',
                  onTap: _busy ? null : () => _summon(i),
                ),
              _ManaButton(
                label: '${kMaxExactCmc + 1}+',
                onTap: _busy ? null : () => _summon(kMaxExactCmc + 1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('История', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (match.summons.isEmpty)
            Text('Пока пусто', style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final summon in match.summons)
              _SummonTile(summon: summon, onReprint: () => _reprint(summon)),
        ],
      ),
    );
  }

  Future<void> _summon(int cmc) async {
    final printer = context.read<PrinterConnectionService>();
    final matches = context.read<MatchRepository>();
    final creatures = context.read<CreatureRepository>();
    final prints = context.read<PrintService>();
    final renderer = context.read<CardRenderService>();
    final art = context.read<ArtCacheService>();
    final media = context.read<SettingsController>().printMedia;
    if (!printer.isConnected) {
      await showPrinterPicker(context);
      if (!mounted || !printer.isConnected) return;
    }
    setState(() {
      _busy = true;
      _status = 'Печатаю…';
    });
    final match = widget.match;
    final player = match.currentPlayer;
    try {
      final creature = await creatures.pickRandom(cmc, mode: match.mode);
      if (creature == null) {
        if (mounted) setState(() => _status = match.mode.emptyPool);
        return;
      }
      final summonId = await matches.addSummon(
        matchId: match.id,
        playerPosition: player.position,
        creatureId: creature.id,
        cmc: cmc,
      );
      final error = await _printCreature(
        creature.id,
        art: art,
        renderer: renderer,
        prints: prints,
        creatures: creatures,
        media: media,
      );
      await matches.setPrintError(summonId, error);
      await matches.advanceTurn(match.id, match.players.length);
      final next = await matches.byId(match.id);
      if (next != null) widget.onChanged(next);
      if (mounted) {
        setState(() {
          _status = error == null
              ? '${creature.name} отправлено на принтер'
              : 'В истории, печать не прошла';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reprint(MatchSummon summon) async {
    final matches = context.read<MatchRepository>();
    final creatures = context.read<CreatureRepository>();
    final prints = context.read<PrintService>();
    final renderer = context.read<CardRenderService>();
    final art = context.read<ArtCacheService>();
    final media = context.read<SettingsController>().printMedia;
    setState(() => _busy = true);
    final error = await _printCreature(
      summon.creature.id,
      art: art,
      renderer: renderer,
      prints: prints,
      creatures: creatures,
      media: media,
    );
    await matches.setPrintError(summon.id, error);
    final next = await matches.byId(widget.match.id);
    if (next != null) widget.onChanged(next);
    if (mounted) {
      setState(() {
        _busy = false;
        _status = error == null ? 'Отправлено ещё раз' : 'Печать не прошла';
      });
    }
  }

  Future<String?> _printCreature(
    String id, {
    required ArtCacheService art,
    required CardRenderService renderer,
    required PrintService prints,
    required CreatureRepository creatures,
    required PrintMedia media,
  }) async {
    try {
      final creature = await creatures.byId(id);
      if (creature == null) return 'Карта не найдена';
      final file = await art.fileFor(id);
      final bytes = media.showsArt && await file.exists()
          ? await file.readAsBytes()
          : null;
      final card = await renderer.renderCreature(
        creature,
        artJpeg: bytes,
        media: media,
      );
      await prints.printCard(card);
      return null;
    } catch (_) {
      return 'Печать не прошла';
    }
  }
}

class _ManaButton extends StatelessWidget {
  const _ManaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        textStyle: Theme.of(context).textTheme.titleLarge,
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

class _SummonTile extends StatelessWidget {
  const _SummonTile({required this.summon, required this.onReprint});

  final MatchSummon summon;
  final VoidCallback onReprint;

  @override
  Widget build(BuildContext context) {
    final art = context.read<ArtCacheService>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Thumb(id: summon.creature.id, art: art),
      title: Text(summon.creature.name),
      subtitle: Text(
        '${summon.playerName} · мана ${summon.cmc}'
        '${summon.printError == null ? '' : ' · не напечатано'}',
      ),
      trailing: summon.printError == null
          ? null
          : TextButton(onPressed: onReprint, child: const Text('Ещё раз')),
      onTap: () =>
          showCreatureImage(context, creature: summon.creature, art: art),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.id, required this.art});

  final String id;
  final ArtCacheService art;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: art.displayFileFor(id),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return const SizedBox(width: 48, height: 48);
        }
        return Image.file(file, width: 48, height: 67, fit: BoxFit.cover);
      },
    );
  }
}
