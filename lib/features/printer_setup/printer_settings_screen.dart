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

    return Scaffold(
      appBar: AppBar(title: const Text('Принтер')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Статус'),
            subtitle: Text(
              printer.statusText ??
                  (printer.isConnected ? 'Подключено' : 'Не подключено'),
            ),
            trailing: Icon(
              printer.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: printer.isConnected ? Colors.green : Colors.grey,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Сохранённое устройство'),
            subtitle: Text(printer.savedName ?? 'нет'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.push('/printer/scan'),
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Сканировать и выбрать'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: !printer.isConnected
                ? null
                : () async {
                    setState(() => _testStatus = 'Печатаю тест…');
                    try {
                      try {
                        await prints.printTest();
                      } catch (_) {
                        final card = await renderer.renderPlainText(
                          'Momir test OK',
                        );
                        await prints.printCard(card);
                      }
                      if (mounted) {
                        setState(() => _testStatus = 'Тест отправлен');
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _testStatus = 'Ошибка: $e');
                      }
                    }
                  },
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Тестовая печать'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: printer.savedId == null ? null : printer.forget,
            icon: const Icon(Icons.link_off),
            label: const Text('Забыть принтер'),
          ),
          if (_testStatus != null) ...[
            const SizedBox(height: 16),
            Text(_testStatus!),
          ],
          const SizedBox(height: 24),
          Text(
            'Goojprt PT-210 печатает без автоножа. После карточки лента '
            'проматывается — оторвите чек вручную.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
