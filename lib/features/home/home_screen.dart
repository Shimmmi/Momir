import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../app/summon_controller.dart';
import '../../core/ble/printer_connection_service.dart';
import '../../core/scryfall/scryfall_sync_service.dart';
import '../../widgets/mana_symbol.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final printer = context.watch<PrinterConnectionService>();
    final sync = context.watch<ScryfallSyncService>();
    final summon = context.read<SummonController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Momir'),
        actions: [
          IconButton(
            tooltip: 'Принтер',
            onPressed: () => context.push('/printer'),
            icon: Icon(
              printer.isConnected
                  ? Icons.print
                  : Icons.print_disabled_outlined,
            ),
          ),
          IconButton(
            tooltip: 'База карт',
            onPressed: () => context.push('/sync'),
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (sync.progress.isRunning && sync.progress.background)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(
                    'Докачка артов: ${sync.progress.artsDone}/${sync.progress.artsTotal}',
                  ),
                  onTap: () => context.push('/sync'),
                ),
              ),
            ),
          Text(
            printer.isConnected
                ? 'Принтер: ${printer.savedName ?? 'подключён'}'
                : 'Принтер не подключён — можно смотреть превью чека',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Цвет', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Любой'),
                selected: settings.colorFilter.isEmpty,
                onSelected: (_) => settings.clearColors(),
              ),
              for (final c in const ['W', 'U', 'B', 'R', 'G'])
                FilterChip(
                  avatar: ManaSymbol(code: c, size: 16),
                  label: Text(c),
                  selected: settings.colorFilter.contains(c),
                  onSelected: (_) => settings.toggleColor(c),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Кнопка «Ещё раз» на превью'),
            value: settings.rerollEnabled,
            onChanged: settings.setReroll,
          ),
          const SizedBox(height: 12),
          Text('Конвертированная мана', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              for (var i = 0; i <= 9; i++)
                _CmcButton(
                  label: '$i',
                  onTap: () => _summon(context, summon, settings, i),
                ),
              _CmcButton(
                label: '10+',
                onTap: () => _summon(context, summon, settings, 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _summon(
    BuildContext context,
    SummonController summon,
    SettingsController settings,
    int cmc,
  ) async {
    await summon.summon(cmc, colors: settings.colorFilter);
    if (context.mounted) context.push('/preview');
  }
}

class _CmcButton extends StatelessWidget {
  const _CmcButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
