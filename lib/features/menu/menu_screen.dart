import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../printer_setup/printer_picker.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Momir', style: text.displaySmall),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.push('/match'),
                child: const Text('Игра'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push('/home'),
                child: const Text('Симулятор'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push('/library'),
                child: const Text('База карт'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => showPrinterPicker(context),
                child: const Text('Принтеры'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
