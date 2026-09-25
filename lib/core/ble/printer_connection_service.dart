import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import 'printer_profile.dart';
import 'saved_printers.dart';

enum PrinterLinkState { idle, scanning, connecting, connected, disconnected }

class ScannedPrinter {
  ScannedPrinter({
    required this.id,
    required this.name,
    required this.rssi,
    required this.likely,
    required this.kind,
    this.bleDevice,
  });

  final String id;
  final String name;
  final int rssi;
  final bool likely;
  final PrinterLinkKind kind;
  final BluetoothDevice? bleDevice;
}

class PrinterConnectionService extends ChangeNotifier {
  PrinterConnectionService(
    this._prefs, {
    FlutterClassicBluetooth? classic,
    this.savedPrinters,
  }) : _classic = classic ?? FlutterClassicBluetooth();

  final SharedPreferences _prefs;
  final SavedPrinterStore? savedPrinters;
  final FlutterClassicBluetooth _classic;

  PrinterLinkState state = PrinterLinkState.idle;
  String? statusText;
  String? connectedId;
  String? connectedName;
  PrinterLinkKind? connectedKind;
  BluetoothDevice? device;
  BluetoothCharacteristic? _writeChar;
  BtcConnection? _classicConn;
  StreamSubscription<BtcConnectionState>? _classicStateSub;
  PrinterProfile? profile;
  final scans = <String, ScannedPrinter>{};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  var _suppressDrop = false;

  bool get isConnected =>
      state == PrinterLinkState.connected &&
      (_writeChar != null || _classicConn != null);

  String? get savedId => _prefs.getString(kPrefsPrinterId);
  String? get savedName => _prefs.getString(kPrefsPrinterName);

  PrinterLinkKind get savedKind {
    final raw = _prefs.getString(kPrefsPrinterKind);
    if (raw == PrinterLinkKind.ble.name) return PrinterLinkKind.ble;
    return PrinterLinkKind.classic;
  }

  bool isLikelyPrinter(String name) {
    final upper = name.toUpperCase();
    final hints = [
      ...PrinterProfile.xp365b.nameHints,
      ...PrinterProfile.pt210.nameHints,
    ];
    return hints.any((hint) => upper.contains(hint.toUpperCase()));
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.bluetooth,
    ].request();

    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];
    if (scan != null && connect != null) {
      return scan.isGranted && connect.isGranted;
    }
    return statuses.values.any((s) => s.isGranted);
  }

  Future<void> startScan() async {
    final ok = await requestPermissions();
    if (!ok) {
      statusText = 'Нужен доступ к Bluetooth';
      notifyListeners();
      return;
    }
    try {
      await _classic.requestPermissions();
    } catch (_) {}

    scans.clear();
    state = PrinterLinkState.scanning;
    statusText = 'Сканирование…';
    notifyListeners();
    await stopScan(keepState: true);

    if (Platform.isAndroid) {
      try {
        final paired = await _classic.getPairedDevices();
        for (final d in paired) {
          _addClassic(d);
        }
      } catch (_) {}
      try {
        final found = await _classic.scan(timeout: const Duration(seconds: 8));
        for (final d in found) {
          _addClassic(d);
        }
      } catch (e) {
        statusText = 'Classic Bluetooth: $e';
      }
    }

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        if (name.isEmpty) continue;
        scans[id] = ScannedPrinter(
          id: id,
          name: name,
          rssi: r.rssi,
          likely: isLikelyPrinter(name),
          kind: PrinterLinkKind.ble,
          bleDevice: r.device,
        );
      }
      notifyListeners();
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: true,
      );
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning.where((v) => v == false).first;
      }
    } catch (_) {}

    state = isConnected ? PrinterLinkState.connected : PrinterLinkState.idle;
    statusText = scans.isEmpty
        ? 'Принтеры не найдены. Сначала спарьте XP-365B в настройках Android.'
        : 'Выберите устройство';
    notifyListeners();
  }

  void _addClassic(BtcDevice device) {
    final name = device.displayName;
    scans[device.address] = ScannedPrinter(
      id: device.address,
      name: name,
      rssi: device.rssi ?? -100,
      likely: isLikelyPrinter(name),
      kind: PrinterLinkKind.classic,
    );
  }

  Future<void> stopScan({bool keepState = false}) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    if (!keepState && state == PrinterLinkState.scanning) {
      state = PrinterLinkState.idle;
      notifyListeners();
    }
  }

  Future<void> connectScanned(ScannedPrinter target) async {
    await stopScan();
    if (target.kind == PrinterLinkKind.classic) {
      await _connectClassic(target.id, target.name);
    } else {
      final ble = target.bleDevice;
      if (ble == null) {
        statusText = 'Нет BLE-устройства';
        notifyListeners();
        return;
      }
      await _connectBle(ble);
    }
  }

  Future<void> _connectClassic(String address, String name) async {
    state = PrinterLinkState.connecting;
    statusText = 'Подключение по Bluetooth…';
    notifyListeners();
    try {
      await _dropClassic();
      final conn = await _classic.connect(
        address: address,
        uuid: BtcUuid.spp,
        timeout: const Duration(seconds: 20),
      );
      _classicConn = conn;
      _writeChar = null;
      device = null;
      connectedId = address;
      connectedName = name;
      connectedKind = PrinterLinkKind.classic;
      profile = PrinterProfile.forName(name);
      await _classicStateSub?.cancel();
      _classicStateSub = conn.stateStream.listen((s) {
        if (_suppressDrop) return;
        if (s == BtcConnectionState.disconnected) {
          state = PrinterLinkState.disconnected;
          statusText = 'Соединение потеряно, переподключаюсь…';
          notifyListeners();
          _reconnect();
        }
      });
      await _prefs.setString(kPrefsPrinterId, address);
      await _prefs.setString(kPrefsPrinterName, name);
      await _prefs.setString(kPrefsPrinterKind, PrinterLinkKind.classic.name);
      await savedPrinters?.remember(
        address: address,
        kind: PrinterLinkKind.classic,
        deviceName: name,
      );
      state = PrinterLinkState.connected;
      statusText = 'Подключено: $name';
      notifyListeners();
    } catch (e) {
      state = PrinterLinkState.disconnected;
      statusText = 'Не удалось подключиться: $e';
      notifyListeners();
    }
  }

  Future<void> _connectBle(BluetoothDevice target) async {
    state = PrinterLinkState.connecting;
    statusText = 'Подключение по BLE…';
    notifyListeners();
    try {
      await _dropClassic();
      await target.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 20),
      );
      device = target;
      await _bindWriteCharacteristic(target);
      final name = target.platformName.isNotEmpty
          ? target.platformName
          : target.remoteId.str;
      connectedId = target.remoteId.str;
      connectedName = name;
      connectedKind = PrinterLinkKind.ble;
      profile = PrinterProfile.forName(name);
      await _connSub?.cancel();
      _connSub = target.connectionState.listen((s) {
        if (_suppressDrop) return;
        if (s == BluetoothConnectionState.disconnected) {
          state = PrinterLinkState.disconnected;
          statusText = 'Соединение потеряно, переподключаюсь…';
          _writeChar = null;
          notifyListeners();
          _reconnect();
        }
      });
      await _prefs.setString(kPrefsPrinterId, target.remoteId.str);
      await _prefs.setString(kPrefsPrinterName, name);
      await _prefs.setString(kPrefsPrinterKind, PrinterLinkKind.ble.name);
      await savedPrinters?.remember(
        address: target.remoteId.str,
        kind: PrinterLinkKind.ble,
        deviceName: name,
      );
      state = PrinterLinkState.connected;
      statusText = 'Подключено: $name';
      notifyListeners();
    } catch (e) {
      state = PrinterLinkState.disconnected;
      statusText = 'Не удалось подключиться: $e';
      notifyListeners();
    }
  }

  Future<void> autoConnect() async {
    final id = savedId;
    if (id == null || id.isEmpty) return;
    try {
      final ok = await requestPermissions();
      if (!ok) return;
      if (savedKind == PrinterLinkKind.classic && Platform.isAndroid) {
        await _connectClassic(id, savedName ?? id);
        return;
      }
      final target = BluetoothDevice.fromId(id);
      await _connectBle(target);
    } catch (e) {
      statusText = 'Автоподключение не удалось: $e';
      notifyListeners();
    }
  }

  Future<void> _reconnect() async {
    final id = connectedId;
    final kind = connectedKind;
    if (id == null || kind == null) return;
    _suppressDrop = true;
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration(seconds: 2 + i));
      try {
        if (kind == PrinterLinkKind.classic) {
          await _connectClassic(id, connectedName ?? id);
        } else if (device != null) {
          await _connectBle(device!);
        }
        if (isConnected) {
          _suppressDrop = false;
          return;
        }
      } catch (_) {}
    }
    _suppressDrop = false;
    statusText = 'Не удалось переподключиться';
    notifyListeners();
  }

  bool _uuidEq(Guid actual, String expected) {
    final want = Guid(expected);
    return actual.str128 == want.str128 || actual.str == want.str;
  }

  Future<void> _bindWriteCharacteristic(BluetoothDevice target) async {
    final services = await target.discoverServices();
    for (final candidate in PrinterProfile.bleCandidates) {
      for (final service in services) {
        final matchService = candidate.serviceUuids.any(
          (id) => _uuidEq(service.uuid, id),
        );
        if (!matchService) continue;
        for (final c in service.characteristics) {
          if (_uuidEq(c.uuid, candidate.writeUuid)) {
            _writeChar = c;
            if (candidate.notifyUuid != null) {
              for (final n in service.characteristics) {
                if (_uuidEq(n.uuid, candidate.notifyUuid!)) {
                  try {
                    await n.setNotifyValue(true);
                  } catch (_) {}
                }
              }
            }
            return;
          }
        }
      }
    }
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          _writeChar = c;
          return;
        }
      }
    }
    throw StateError('Не найдена характеристика записи принтера');
  }

  Future<void> writeBytes(List<int> data) async {
    if (!isConnected) {
      throw StateError('Принтер не подключён');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final active = profile ?? PrinterProfile.xp365b;
    final size = active.chunkBytes;
    final pause = active.chunkPause;
    for (var offset = 0; offset < bytes.length; offset += size) {
      final end = (offset + size > bytes.length) ? bytes.length : offset + size;
      final chunk = bytes.sublist(offset, end);
      final classic = _classicConn;
      if (classic != null) {
        await classic.output.add(chunk);
      } else {
        final char = _writeChar;
        if (char == null) throw StateError('Принтер не подключён');
        await char.write(chunk, withoutResponse: false);
      }
      if (pause > Duration.zero) {
        await Future<void>.delayed(pause);
      }
    }
  }

  Future<void> _dropClassic() async {
    await _classicStateSub?.cancel();
    _classicStateSub = null;
    final conn = _classicConn;
    _classicConn = null;
    if (conn != null) {
      try {
        await conn.close();
      } catch (_) {}
      try {
        conn.dispose();
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    await _dropClassic();
    try {
      await device?.disconnect();
    } catch (_) {}
    _writeChar = null;
    state = PrinterLinkState.disconnected;
    statusText = 'Отключено';
    notifyListeners();
  }

  Future<void> connectSaved(SavedPrinter printer) async {
    if (printer.kind == PrinterLinkKind.classic) {
      await _connectClassic(printer.address, printer.customName);
      return;
    }
    await _connectBle(BluetoothDevice.fromId(printer.address));
  }

  Future<void> forgetSaved(String address) async {
    await savedPrinters?.forget(address);
    if (savedId == address) await forget();
    notifyListeners();
  }

  Future<void> renameSaved(String address, String name) async {
    await savedPrinters?.rename(address, name);
    if (savedId == address) {
      await _prefs.setString(kPrefsPrinterName, name);
      connectedName = name;
    }
    notifyListeners();
  }

  Future<void> forget() async {
    await disconnect();
    await _prefs.remove(kPrefsPrinterId);
    await _prefs.remove(kPrefsPrinterName);
    await _prefs.remove(kPrefsPrinterKind);
    device = null;
    profile = null;
    connectedId = null;
    connectedName = null;
    connectedKind = null;
    state = PrinterLinkState.idle;
    statusText = 'Принтер забыт';
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _classicStateSub?.cancel();
    super.dispose();
  }
}
