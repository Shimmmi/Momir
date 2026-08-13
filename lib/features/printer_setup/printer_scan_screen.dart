import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ble/printer_connection_service.dart';

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
                  'Разрешите Bluetooth. Устройства с именем PT-210 / Printer выделены.',
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? const Center(child: Text('Пока ничего не видно'))
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
                          '${d.device.remoteId.str}  ·  ${d.rssi} dBm',
                        ),
                        trailing: d.likely
                            ? const Chip(label: Text('принтер?'))
                            : null,
                        onTap: () async {
                          await printer.connect(d.device);
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
