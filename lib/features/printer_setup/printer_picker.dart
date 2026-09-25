import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/ble/printer_connection_service.dart';
import '../../core/ble/saved_printers.dart';

Future<void> showPrinterPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: momirField,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _PrinterPicker(),
  );
}

class _PrinterPicker extends StatelessWidget {
  const _PrinterPicker();

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterConnectionService>();
    final store = printer.savedPrinters;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FutureBuilder<List<SavedPrinter>>(
          future: store?.all() ?? Future.value(const <SavedPrinter>[]),
          builder: (context, snap) {
            final items = snap.data ?? const <SavedPrinter>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Принтеры',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  printer.isConnected
                      ? 'Сейчас: ${printer.savedName ?? printer.connectedName}'
                      : 'Для этой сессии принтер не подключён',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Text(
                    'Сохранённых принтеров нет. Найдите XP-365B и подключитесь один раз.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.customName),
                      subtitle: Text(
                        item.deviceName ?? item.address,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: printer.savedId == item.address &&
                              printer.isConnected
                          ? const Icon(Icons.check, color: momirGold)
                          : null,
                      onTap: () async {
                        await printer.connectSaved(item);
                        if (context.mounted && printer.isConnected) {
                          Navigator.of(context).pop();
                        }
                      },
                      onLongPress: () => _rename(context, printer, item),
                    ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/printer/scan');
                  },
                  child: const Text('Найти новый'),
                ),
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: () => _rename(
                      context,
                      printer,
                      items.firstWhere(
                        (p) => p.address == printer.savedId,
                        orElse: () => items.first,
                      ),
                    ),
                    child: const Text('Переименовать'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    PrinterConnectionService printer,
    SavedPrinter item,
  ) async {
    final controller = TextEditingController(text: item.customName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Имя принтера'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Как узнать этот принтер'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              await printer.forgetSaved(item.address);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Забыть'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await printer.renameSaved(item.address, name);
    }
  }
}
