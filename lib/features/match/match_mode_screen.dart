import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ble/printer_connection_service.dart';
import '../../core/db/creature_repository.dart';
import '../../core/game_mode.dart';
import '../printer_setup/printer_picker.dart';

class MatchModeScreen extends StatelessWidget {
  const MatchModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Режим'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/menu'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Сначала режим, затем партия. Принтер должен быть подключён.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final mode in GameMode.values) ...[
            mode == GameMode.creature
                ? FilledButton(
                    onPressed: () => _open(context, mode),
                    child: Text(mode.label),
                  )
                : OutlinedButton(
                    onPressed: () => _open(context, mode),
                    child: Text(mode.label),
                  ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, GameMode mode) async {
    final count = await context.read<CreatureRepository>().countFor(mode);
    if (!context.mounted) return;
    if (count == 0) {
      context.push('/sync?modes=${mode.name}');
      return;
    }
    final printer = context.read<PrinterConnectionService>();
    if (!printer.isConnected) {
      await showPrinterPicker(context);
      if (!context.mounted || !printer.isConnected) return;
    }
    if (!context.mounted) return;
    context.push('/match/play?mode=${mode.name}');
  }
}
