import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
        title: const Text('База карт'),
        leading: fromSettings || p.creatureCount > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/home'),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const Text(
              'Нужен Wi‑Fi. Сначала скачивается база существ Scryfall, '
              'затем все иллюстрации (примерно 150–400 МБ, это может занять '
              'десятки минут). После этого приложение работает офлайн.',
              style: TextStyle(height: 1.4),
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
              Text(p.error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 24),
            if (!running)
              FilledButton.icon(
                onPressed: () => sync.sync(replaceCards: true),
                icon: const Icon(Icons.download),
                label: Text(
                  p.creatureCount == 0
                      ? 'Скачать базу карт'
                      : 'Обновить базу карт',
                ),
              ),
            if (running) ...[
              FilledButton.tonal(
                onPressed: p.phase == SyncPhase.downloadingArt ||
                        p.phase == SyncPhase.retryingArt
                    ? (sync.isPaused
                          ? sync.resumeDownloads
                          : sync.pause)
                    : null,
                child: Text(sync.isPaused ? 'Продолжить' : 'Пауза'),
              ),
              const SizedBox(height: 8),
              if (p.creatureCount > 0)
                OutlinedButton(
                  onPressed: () {
                    sync.playInBackground();
                    context.go('/home');
                  },
                  child: const Text('Играть, арты докачаются'),
                ),
            ],
            if (p.phase == SyncPhase.done) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('К игре'),
              ),
            ],
            if (p.phase == SyncPhase.error) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => sync.sync(replaceCards: p.creatureCount == 0),
                child: const Text('Повторить'),
              ),
            ],
            const SizedBox(height: 24),
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
