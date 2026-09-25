import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/db/creature_repository.dart';
import '../features/card_preview/card_preview_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library_sync/sync_screen.dart';
import '../features/match/match_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/printer_setup/printer_scan_screen.dart';
import '../features/printer_setup/printer_settings_screen.dart';
import 'theme.dart';

class MomirApp extends StatelessWidget {
  const MomirApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const _GateScreen()),
        GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
        GoRoute(
          path: '/sync/settings',
          builder: (_, _) => const SyncScreen(fromSettings: true),
        ),
        GoRoute(path: '/menu', builder: (_, _) => const MenuScreen()),
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/library', builder: (_, _) => const LibraryScreen()),
        GoRoute(path: '/match', builder: (_, _) => const MatchEntry()),
        GoRoute(
          path: '/preview',
          builder: (_, _) => const CardPreviewScreen(),
        ),
        GoRoute(
          path: '/printer',
          builder: (_, _) => const PrinterSettingsScreen(),
        ),
        GoRoute(
          path: '/printer/scan',
          builder: (_, _) => const PrinterScanScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Momir IRL',
      theme: buildMomirTheme(),
      routerConfig: router,
    );
  }
}

class _GateScreen extends StatefulWidget {
  const _GateScreen();

  @override
  State<_GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<_GateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    final count = await context.read<CreatureRepository>().count();
    if (!mounted) return;
    context.go(count == 0 ? '/sync' : '/menu');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Momir', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
