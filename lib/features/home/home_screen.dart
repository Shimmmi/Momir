import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../app/summon_controller.dart';
import '../../app/theme.dart';
import '../../core/ble/printer_connection_service.dart';
import '../../core/constants.dart';
import '../../core/scryfall/scryfall_sync_service.dart';
import '../../widgets/mana_symbol.dart';
import '../printer_setup/printer_picker.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final printer = context.watch<PrinterConnectionService>();
    final sync = context.watch<ScryfallSyncService>();
    final summon = context.read<SummonController>();
    final colorLabel = settings.colorFilter.isEmpty
        ? 'любой цвет'
        : settings.colorFilter.join(' ');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Симулятор', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go('/menu'),
                    child: const Text('Меню'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _StatusLine(
                printerOn: printer.isConnected,
                printerLabel: printer.isConnected
                    ? (printer.savedName ?? 'принтер')
                    : 'Принтер не подключён',
                libraryLabel: sync.progress.creatureCount > 0
                    ? '${sync.progress.creatureCount} существ'
                    : 'База карт',
                artsLabel: sync.progress.isRunning && sync.progress.background
                    ? 'арты ${sync.progress.artsDone}/${sync.progress.artsTotal}'
                    : null,
                onPrinter: () => showPrinterPicker(context),
                onLibrary: () => context.push('/sync'),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.05,
                  children: [
                    for (var i = 0; i <= kMaxExactCmc; i++)
                      _CmcButton(
                        label: '$i',
                        onTap: () => _summon(context, summon, settings, i),
                      ),
                    _CmcButton(
                      label: '${kMaxExactCmc + 1}+',
                      onTap: () => _summon(
                        context,
                        summon,
                        settings,
                        kMaxExactCmc + 1,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openFilters(context),
                child: Text('Цвет: $colorLabel'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Ещё раз на превью',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                value: settings.rerollEnabled,
                onChanged: settings.setReroll,
              ),
            ],
          ),
        ),
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

  void _openFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: momirField,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Consumer<SettingsController>(
            builder: (context, settings, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Цвет существа',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.printerOn,
    required this.printerLabel,
    required this.libraryLabel,
    required this.onPrinter,
    required this.onLibrary,
    this.artsLabel,
  });

  final bool printerOn;
  final String printerLabel;
  final String libraryLabel;
  final String? artsLabel;
  final VoidCallback onPrinter;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: momirLine),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatusTap(
              label: printerLabel,
              onTap: onPrinter,
              mark: printerOn ? momirGold : const Color(0xFF8A8175),
            ),
          ),
          Container(width: 1, height: 36, color: momirLine),
          Expanded(
            child: _StatusTap(
              label: artsLabel ?? libraryLabel,
              onTap: onLibrary,
              mark: momirPaper,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTap extends StatelessWidget {
  const _StatusTap({
    required this.label,
    required this.onTap,
    required this.mark,
  });

  final String label;
  final VoidCallback onTap;
  final Color mark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: mark, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
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
        textStyle: Theme.of(context).textTheme.titleLarge,
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
