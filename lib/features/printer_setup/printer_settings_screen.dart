import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ble/printer_connection_service.dart';
import '../../services/print_service.dart';
import '../../widgets/card_renderer.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  String? _testStatus;

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterConnectionService>();
    final prints = context.read<PrintService>();
    final renderer = context.read<CardRenderService>();
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Принтер'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/menu'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            printer.isConnected
                ? (printer.savedName ?? 'Подключено')
                : 'Не подключён',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'XP-365B, лента 57 мм. После печати оторвите бумагу.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.push('/printer/scan'),
            child: const Text('Найти принтер'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: !printer.isConnected
                ? null
                : () => _test(prints, renderer),
            child: const Text('Тестовая линейка'),
          ),
          const SizedBox(height: 4),
          Text(
            'Длинная риска каждые 64 точки. Обрезанный правый край — не та ширина.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: printer.savedId == null ? null : printer.forget,
            child: const Text('Забыть принтер'),
          ),
          if (_testStatus != null) ...[
            const SizedBox(height: 12),
            Text(_testStatus!, style: text.bodyMedium),
          ],
        ],
      ),
    );
  }

  Future<void> _test(PrintService prints, CardRenderService renderer) async {
    setState(() => _testStatus = 'Печатаю линейку…');
    try {
      try {
        await prints.printTest();
      } catch (_) {
        final card = await renderer.renderPlainText('Momir test OK');
        await prints.printCard(card);
      }
      if (mounted) setState(() => _testStatus = 'Линейка отправлена');
    } catch (_) {
      if (mounted) setState(() => _testStatus = 'Печать не прошла. Повторите.');
    }
  }
}