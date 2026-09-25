import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import 'printer_profile.dart';

class SavedPrinter {
  const SavedPrinter({
    required this.address,
    required this.kind,
    required this.customName,
    this.deviceName,
    this.lastUsed,
  });

  final String address;
  final PrinterLinkKind kind;
  final String customName;
  final String? deviceName;
  final String? lastUsed;

  factory SavedPrinter.fromRow(Map<String, Object?> row) {
    final kindName = row['kind'] as String? ?? PrinterLinkKind.classic.name;
    return SavedPrinter(
      address: row['address'] as String,
      kind: kindName == PrinterLinkKind.ble.name
          ? PrinterLinkKind.ble
          : PrinterLinkKind.classic,
      customName: row['custom_name'] as String? ?? row['address'] as String,
      deviceName: row['device_name'] as String?,
      lastUsed: row['last_used'] as String?,
    );
  }
}

class SavedPrinterStore {
  SavedPrinterStore(this._database);

  final AppDatabase _database;

  Future<List<SavedPrinter>> all() async {
    final db = await _database.db;
    final rows = await db.query('saved_printers', orderBy: 'last_used DESC');
    return rows.map(SavedPrinter.fromRow).toList(growable: false);
  }

  Future<void> remember({
    required String address,
    required PrinterLinkKind kind,
    required String deviceName,
  }) async {
    final db = await _database.db;
    final existing = await db.query(
      'saved_printers',
      where: 'address = ?',
      whereArgs: [address],
      limit: 1,
    );
    final custom = existing.isEmpty
        ? deviceName
        : (existing.first['custom_name'] as String? ?? deviceName);
    await db.insert('saved_printers', {
      'address': address,
      'kind': kind.name,
      'custom_name': custom,
      'device_name': deviceName,
      'last_used': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> rename(String address, String customName) async {
    final db = await _database.db;
    await db.update(
      'saved_printers',
      {'custom_name': customName},
      where: 'address = ?',
      whereArgs: [address],
    );
  }

  Future<void> forget(String address) async {
    final db = await _database.db;
    await db.delete(
      'saved_printers',
      where: 'address = ?',
      whereArgs: [address],
    );
  }
}
