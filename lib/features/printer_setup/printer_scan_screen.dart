import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ble/printer_connection_service.dart';
import '../../core/ble/printer_profile.dart';

class PrinterScanScreen extends StatefulWidget {
  const PrinterScanScreen({super.key});

  @override
  State<PrinterScanScreen> createState() => _PrinterScanScreenState();
}

class _PrinterScanScreenState extends State<PrinterScanScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterConnectionService>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterConnectionService>();
    final devices = printer.scans.values.toList()
      ..sort((a, b) {
        if (a.likely != b.likely) return a.likely ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск принтера'),
        actions: [
          IconButton(
            onPressed: printer.state == PrinterLinkState.scanning
                ? null
                : printer.startScan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (printer.state == PrinterLinkState.scanning)
            const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              printer.statusText ??
                  'Сначала спарьте XP-365B в настройках Android.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Пока ничего не видно',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: printer.state == PrinterLinkState.scanning
                              ? null
                              : printer.startScan,
                          child: const Text('Искать снова'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, i) {
                      final d = devices[i];
                      return ListTile(
                        leading: Icon(
                          d.likely ? Icons.print : Icons.bluetooth,
                          color: d.likely
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(d.name),
                        subtitle: Text(
                          d.kind == PrinterLinkKind.classic
                              ? 'Bluetooth'
                              : 'BLE',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: d.likely
                            ? Icon(
                                Icons.print,
                                color: Theme.of(context).colorScheme.secondary,
                              )
                            : null,
                        onTap: () async {
                          await printer.connectScanned(d);
                          if (context.mounted && printer.isConnected) {
                            context.go('/printer');
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
