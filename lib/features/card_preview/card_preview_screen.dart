import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../app/summon_controller.dart';
import '../../core/ble/printer_connection_service.dart';
import '../../services/print_service.dart';

class CardPreviewScreen extends StatefulWidget {
  const CardPreviewScreen({super.key});

  @override
  State<CardPreviewScreen> createState() => _CardPreviewScreenState();
}

class _CardPreviewScreenState extends State<CardPreviewScreen> {
  String? _printStatus;

  @override
  Widget build(BuildContext context) {
    final summon = context.watch<SummonController>();
    final settings = context.watch<SettingsController>();
    final printer = context.watch<PrinterConnectionService>();
    final printService = context.read<PrintService>();
    final card = summon.card;

    return Scaffold(
      appBar: AppBar(title: Text(summon.creature?.name ?? 'Карточка')),
      body: Column(
        children: [
          Expanded(
            child: summon.loading
                ? const Center(child: CircularProgressIndicator())
                : summon.error != null && card == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(summon.error!, textAlign: TextAlign.center),
                    ),
                  )
                : card == null
                ? const Center(child: Text('Нет карточки'))
                : InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Container(
                        color: Colors.white,
                        margin: const EdgeInsets.all(12),
                        child: Image.memory(
                          card.pngBytes,
                          filterQuality: FilterQuality.none,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
          ),
          if (_printStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_printStatus!),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (!printer.isConnected)
                    TextButton(
                      onPressed: () => context.push('/printer'),
                      child: const Text(
                        'Подключите принтер, чтобы печатать',
                      ),
                    ),
                  Row(
                    children: [
                      if (settings.rerollEnabled)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: summon.loading
                                ? null
                                : () => summon.reroll(
                                    colors: settings.colorFilter,
                                  ),
                            child: const Text('Ещё раз'),
                          ),
                        ),
                      if (settings.rerollEnabled) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: !printer.isConnected ||
                                  card == null ||
                                  summon.loading
                              ? null
                              : () => _print(printService, summon),
                          icon: const Icon(Icons.print),
                          label: const Text('Напечатать'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _print(PrintService printService, SummonController summon) async {
    final card = summon.card;
    if (card == null) return;
    setState(() => _printStatus = 'Идёт печать…');
    try {
      await printService.printCard(card);
      if (mounted) setState(() => _printStatus = 'Готово. Оторвите чек вручную.');
    } catch (e) {
      if (mounted) {
        setState(() => _printStatus = 'Ошибка печати: $e');
      }
    }
  }
}
