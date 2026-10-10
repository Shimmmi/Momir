import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/art/art_download_guard.dart';
import '../../core/constants.dart';
import '../../core/db/creature_repository.dart';
import '../../core/db/database.dart';
import '../../core/game_mode.dart';
import '../../core/scryfall/scryfall_sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, this.fromSettings = false, this.initialModes});

  final bool fromSettings;
  final Set<GameMode>? initialModes;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  var _modes = Set<GameMode>.of(GameMode.values);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialModes;
    if (initial != null && initial.isNotEmpty) {
      _modes = Set.of(initial);
    }
    _loadModes();
  }

  Future<void> _loadModes() async {
    final db = context.read<AppDatabase>();
    if (widget.initialModes != null && widget.initialModes!.isNotEmpty) {
      await db.setMeta(kMetaSyncModes, GameMode.encode(_modes));
      return;
    }
    final saved = GameMode.tryParseSet(await db.meta(kMetaSyncModes));
    if (!mounted || saved == null) return;
    setState(() => _modes = saved);
  }

  Future<void> _setModes(Set<GameMode> modes) async {
    if (modes.isEmpty) return;
    setState(() => _modes = modes);
    await context.read<AppDatabase>().setMeta(
      kMetaSyncModes,
      GameMode.encode(modes),
    );
  }

  bool get _allSelected => _modes.length == GameMode.values.length;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<ScryfallSyncService>();
    final p = sync.progress;
    final running = p.isRunning;
    final hasCards =
        p.creatureCount > 0 || p.typeCounts.values.any((n) => n > 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Обновление'),
        leading: widget.fromSettings || hasCards
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/menu'),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text(
              'Скачивается общий пакет Scryfall. В базу и в изображения '
              'попадают только отмеченные типы. Дальше игра идёт без сети.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Все'),
                  selected: _allSelected,
                  onSelected: running
                      ? null
                      : (_) => _setModes(Set.of(GameMode.values)),
                ),
                for (final mode in GameMode.values)
                  FilterChip(
                    label: Text('${mode.typeLabel} · ${p.countOf(mode)}'),
                    selected: _modes.contains(mode),
                    onSelected: running
                        ? null
                        : (on) {
                            final next = Set<GameMode>.of(_modes);
                            if (on) {
                              next.add(mode);
                            } else if (next.length > 1) {
                              next.remove(mode);
                            }
                            _setModes(next);
                          },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _PhaseTile(
              title: 'Карты',
              subtitle: _libraryLine(p),
              value: p.phase == SyncPhase.downloadingBulk
                  ? (p.bulkFraction ?? 0)
                  : (hasCards ? 1 : 0),
            ),
            const SizedBox(height: 12),
            _PhaseTile(
              title: 'Арты',
              subtitle: p.artsTotal == 0
                  ? 'ожидание'
                  : '${p.artsDone} / ${p.artsTotal}'
                        '${p.artsFailed > 0 ? ' · ошибок ${p.artsFailed}' : ''}',
              value: p.artsTotal == 0 ? 0 : p.artsDone / p.artsTotal,
            ),
            const SizedBox(height: 16),
            if (p.message != null)
              Text(p.message!, style: Theme.of(context).textTheme.bodyMedium),
            if (p.error != null) ...[
              const SizedBox(height: 8),
              Text(
                p.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (!running) ...[
              if (hasCards)
                FilledButton(
                  onPressed: () => context.go('/menu'),
                  child: const Text('В меню'),
                ),
              if (hasCards) const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => sync.sync(replaceCards: true, modes: _modes),
                child: Text(hasCards ? 'Обновить карты' : 'Скачать базу карт'),
              ),
              if (hasCards) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      sync.sync(replaceCards: false, modes: _modes),
                  child: const Text('Докачать изображения'),
                ),
              ],
            ],
            if (running &&
                (p.phase == SyncPhase.downloadingArt ||
                    p.phase == SyncPhase.retryingArt)) ...[
              FilledButton.tonal(
                onPressed: sync.isPaused ? sync.resumeDownloads : sync.pause,
                child: Text(sync.isPaused ? 'Продолжить' : 'Пауза'),
              ),
              const SizedBox(height: 8),
              if (hasCards)
                OutlinedButton(
                  onPressed: () {
                    sync.playInBackground();
                    context.go('/menu');
                  },
                  child: const Text('Играть, арты докачаются'),
                ),
            ],
            const SizedBox(height: 16),
            const _BatteryHint(),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _meta(context),
              builder: (context, snap) {
                final text = snap.data;
                if (text == null) return const SizedBox.shrink();
                return Text(text, style: Theme.of(context).textTheme.bodySmall);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _meta(BuildContext context) async {
    final db = context.read<AppDatabase>();
    final repo = context.read<CreatureRepository>();
    final last = await db.meta('last_sync_iso');
    final counts = await repo.countsByMode();
    final when = last == null
        ? 'никогда'
        : last.replaceFirst('T', ' ').split('.').first;
    final lines = [
      'Последняя синхронизация: $when',
      for (final mode in GameMode.values)
        '${mode.typeLabel}: ${counts[mode] ?? 0}',
    ];
    return lines.join('\n');
  }
}

String _libraryLine(SyncProgress p) {
  final parts = [
    for (final mode in GameMode.values)
      if (p.countOf(mode) > 0) '${mode.typeLabel}: ${p.countOf(mode)}',
  ];
  if (parts.isEmpty) return 'ещё не загружены';
  return parts.join(' · ');
}

class _BatteryHint extends StatefulWidget {
  const _BatteryHint();

  @override
  State<_BatteryHint> createState() => _BatteryHintState();
}

class _BatteryHintState extends State<_BatteryHint>
    with WidgetsBindingObserver {
  var _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final granted = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!mounted) return;
    setState(() => _show = !granted);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Если телефон обрывает загрузку при выключенном экране, разрешите Momir работу без ограничений батареи.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: () async {
            await ArtDownloadGuard.askBatteryExemption();
            await _refresh();
          },
          child: const Text('Разрешить работу без ограничений'),
        ),
      ],
    );
  }
}

class _PhaseTile extends StatelessWidget {
  const _PhaseTile({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final String title;
  final String subtitle;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: value.clamp(0, 1)),
      ],
    );
  }
}
