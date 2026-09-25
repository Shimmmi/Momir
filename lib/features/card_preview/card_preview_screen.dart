import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/settings_controller.dart';
import '../../app/summon_controller.dart';
import '../../app/theme.dart';
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
    final blocked = !summon.loading && card == null;

    return Scaffold(
      appBar: AppBar(title: Text(summon.creature?.name ?? 'Карточка')),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF2A261F),
              child: summon.loading
                  ? const Center(child: CircularProgressIndicator())
                  : summon.error != null && card == null
                  ? _MessageAction(
                      text: summon.error!,
                      primary: summon.cmc == null ? 'На главную' : 'Ещё раз',
                      onPrimary: summon.cmc == null
                          ? () => context.go('/home')
                          : () => summon.reroll(colors: settings.colorFilter),
                      secondary: summon.cmc == null ? null : 'На главную',
                      onSecondary: summon.cmc == null
                          ? null
                          : () => context.go('/home'),
                    )
                  : card == null
                  ? _MessageAction(
                      text: 'Нет карточки',
                      primary: 'На главную',
                      onPrimary: () => context.go('/home'),
                    )
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Container(
                          color: momirPaper,
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(8),
                          child: Image.memory(
                            card.pngBytes,
                            filterQuality: FilterQuality.none,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (!blocked)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_printStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _printStatus!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  if (!printer.isConnected)
                    FilledButton(
                      onPressed: () => context.push('/printer'),
                      child: const Text('Подключить принтер'),
                    )
                  else
                    FilledButton(
                      onPressed: card == null || summon.loading
                          ? null
                          : () => _print(printService, summon),
                      child: const Text('Напечатать'),
                    ),
                  if (settings.rerollEnabled)
                    TextButton(
                      onPressed: summon.loading
                          ? null
                          : () => summon.reroll(colors: settings.colorFilter),
                      child: const Text('Ещё раз'),
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
      if (mounted) {
        setState(() => _printStatus = 'Готово. Оторвите чек вручную.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _printStatus = 'Печать не прошла. Повторите.');
      }
    }
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.text,
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
  });

  final String text;
  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPrimary, child: Text(primary)),
            if (secondary != null && onSecondary != null)
              TextButton(onPressed: onSecondary, child: Text(secondary!)),
          ],
        ),
      ),
    );
  }
}
