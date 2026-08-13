import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/settings_controller.dart';
import 'app/summon_controller.dart';
import 'core/art/art_cache_service.dart';
import 'core/ble/printer_connection_service.dart';
import 'core/db/creature_repository.dart';
import 'core/db/database.dart';
import 'core/scryfall/scryfall_sync_service.dart';
import 'services/print_service.dart';
import 'widgets/card_renderer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  final prefs = await SharedPreferences.getInstance();
  final database = AppDatabase();
  await database.open();
  final repository = CreatureRepository(database);
  final artCache = ArtCacheService();
  final renderer = CardRenderService();
  final printer = PrinterConnectionService(prefs);
  final prints = PrintService(connection: printer);
  final sync = ScryfallSyncService(
    database: database,
    repository: repository,
    artCache: artCache,
  );
  final settings = SettingsController(prefs);
  final summon = SummonController(
    repository: repository,
    artCache: artCache,
    renderer: renderer,
  );

  // Best-effort: reconnect to the last printer without blocking UI.
  printer.autoConnect();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: database),
        Provider.value(value: repository),
        Provider.value(value: artCache),
        Provider.value(value: renderer),
        Provider.value(value: prints),
        ChangeNotifierProvider.value(value: printer),
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: summon),
      ],
      child: const MomirApp(),
    ),
  );
}
