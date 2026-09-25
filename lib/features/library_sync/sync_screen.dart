import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/art/art_download_guard.dart';
import '../../core/scryfall/scryfall_sync_service.dart';
import '../../core/db/creature_repository.dart';
import '../../core/db/database.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<ScryfallSyncService>();
    final p = sync.progress;
    final running = p.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Обновление'),
        leading: fromSettings || p.creatureCount > 0
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
              'Один раз по Wi‑Fi: существа Scryfall, затем иллюстрации '
              '(150–400 МБ). Дальше игра идёт без сети.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _PhaseTile(
              title: 'Карты',
              subtitle: p.creatureCount > 0
                  ? '${p.creatureCount} существ'
                  : 'ещё не загружены',
              value: p.phase == SyncPhase.downloadingBulk
                  ? (p.bulkFraction ?? 0)
                  : (p.creatureCount > 0 ? 1 : 0),
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
              if (p.creatureCount > 0)
                FilledButton(
                  onPressed: () => context.go('/menu'),
                  child: const Text('В меню'),
                ),
              if (p.creatureCount > 0) const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => sync.sync(replaceCards: true),
                child: Text(
                  p.creatureCount == 0
                      ? 'Скачать базу карт'
                      : 'Обновить карты',
                ),
              ),
              if (p.creatureCount > 0) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: sync.retryFailedArts,
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
              if (p.creatureCount > 0)
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
                return Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall,
                );
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
    final count = await repo.count();
    final when = last == null ? 'никогда' : last.replaceFirst('T', ' ').split('.').first;
    return 'Последняя синхронизация: $when\nСуществ в базе: $count';
  }
}

class _BatteryHint extends StatefulWidget {
  const _BatteryHint();

  @override
  State<_BatteryHint> createState() => _BatteryHintState();
}

class _BatteryHintState extends State<_BatteryHint> with WidgetsBindingObserver {
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
