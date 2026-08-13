import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import 'printer_profile.dart';

enum PrinterLinkState { idle, scanning, connecting, connected, disconnected }

class ScannedPrinter {
  ScannedPrinter({required this.device, required this.rssi, required this.likely});

  final BluetoothDevice device;
  final int rssi;
  final bool likely;

  String get name {
    final n = device.platformName.isNotEmpty
        ? device.platformName
        : device.advName;
    return n.isEmpty ? device.remoteId.str : n;
  }
}

class PrinterConnectionService extends ChangeNotifier {
  PrinterConnectionService(this._prefs);

  final SharedPreferences _prefs;

  PrinterLinkState state = PrinterLinkState.idle;
  String? statusText;
  BluetoothDevice? device;
  BluetoothCharacteristic? _writeChar;
  PrinterProfile? profile;
  final scans = <String, ScannedPrinter>{};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool get isConnected =>
      state == PrinterLinkState.connected && _writeChar != null;

  String? get savedId => _prefs.getString(kPrefsPrinterId);
  String? get savedName => _prefs.getString(kPrefsPrinterName);

  bool isLikelyPrinter(String name) {
    final upper = name.toUpperCase();
    return PrinterProfile.pt210.nameHints.any(
      (hint) => upper.contains(hint.toUpperCase()),
    );
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
    scans.clear();
    state = PrinterLinkState.scanning;
    statusText = 'Сканирование…';
    notifyListeners();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        scans[id] = ScannedPrinter(
          device: r.device,
          rssi: r.rssi,
          likely: isLikelyPrinter(name),
        );
      }
      notifyListeners();
    });
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 8),
      androidUsesFineLocation: false,
    );
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.isScanning.where((v) => v == false).first;
    }
    state = device?.isConnected == true
        ? PrinterLinkState.connected
        : PrinterLinkState.idle;
    statusText = scans.isEmpty ? 'Принтеры не найдены' : 'Выберите устройство';
    notifyListeners();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connect(BluetoothDevice target) async {
    await stopScan();
    state = PrinterLinkState.connecting;
    statusText = 'Подключение…';
    notifyListeners();
    try {
      await target.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 20),
      );
      device = target;
      await _bindWriteCharacteristic(target);
      await _connSub?.cancel();
      _connSub = target.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          state = PrinterLinkState.disconnected;
          statusText = 'Соединение потеряно, переподключаюсь…';
          _writeChar = null;
          notifyListeners();
          _reconnect();
        }
      });
      await _prefs.setString(kPrefsPrinterId, target.remoteId.str);
      final name = target.platformName.isNotEmpty
          ? target.platformName
          : target.remoteId.str;
      await _prefs.setString(kPrefsPrinterName, name);
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
      final target = BluetoothDevice.fromId(id);
      await connect(target);
    } catch (e) {
      statusText = 'Автоподключение не удалось: $e';
      notifyListeners();
    }
  }

  Future<void> _reconnect() async {
    final current = device;
    if (current == null) return;
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration(seconds: 2 + i));
      try {
        await current.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 15),
        );
        await _bindWriteCharacteristic(current);
        state = PrinterLinkState.connected;
        statusText = 'Снова подключено';
        notifyListeners();
        return;
      } catch (_) {}
    }
    statusText = 'Не удалось переподключиться';
    notifyListeners();
  }

  bool _uuidEq(Guid actual, String expected) {
    final want = Guid(expected);
    return actual.str128 == want.str128 || actual.str == want.str;
  }

  Future<void> _bindWriteCharacteristic(BluetoothDevice target) async {
    final services = await target.discoverServices();
    for (final candidate in PrinterProfile.candidates) {
      for (final service in services) {
        final matchService = candidate.serviceUuids.any(
          (id) => _uuidEq(service.uuid, id),
        );
        if (!matchService) continue;
        for (final c in service.characteristics) {
          if (_uuidEq(c.uuid, candidate.writeUuid)) {
            _writeChar = c;
            profile = candidate;
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
    // Last resort: first writable characteristic.
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          _writeChar = c;
          profile = PrinterProfile.pt210;
          return;
        }
      }
    }
    throw StateError('Не найдена характеристика записи принтера');
  }

  Future<void> writeBytes(List<int> data) async {
    final char = _writeChar;
    if (char == null || !isConnected) {
      throw StateError('Принтер не подключён');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final size = (profile ?? PrinterProfile.pt210).chunkBytes;
    final pause = (profile ?? PrinterProfile.pt210).chunkPause;
    for (var offset = 0; offset < bytes.length; offset += size) {
      final end = (offset + size > bytes.length) ? bytes.length : offset + size;
      await char.write(bytes.sublist(offset, end), withoutResponse: false);
      if (pause > Duration.zero) {
        await Future<void>.delayed(pause);
      }
    }
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    try {
      await device?.disconnect();
    } catch (_) {}
    _writeChar = null;
    state = PrinterLinkState.disconnected;
    statusText = 'Отключено';
    notifyListeners();
  }

  Future<void> forget() async {
    await disconnect();
    await _prefs.remove(kPrefsPrinterId);
    await _prefs.remove(kPrefsPrinterName);
    device = null;
    profile = null;
    state = PrinterLinkState.idle;
    statusText = 'Принтер забыт';
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
