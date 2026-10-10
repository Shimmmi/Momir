import 'dart:typed_data';

import '../core/ble/printer_connection_service.dart';
import '../core/ble/printer_protocol.dart';
import '../core/print_media.dart';
import '../widgets/card_renderer.dart';

class PrintService {
  PrintService({required this._connection, PrinterProtocolAdapter? adapter})
    : _adapter = adapter ?? TsplAdapter();

  final PrinterConnectionService _connection;
  final PrinterProtocolAdapter _adapter;

  bool get canPrint => _connection.isConnected;

  Future<void> printCard(PrintableCard card) async {
    final bytes = _adapter.encodeRaster(
      card.raster,
      card.width,
      card.height,
      media: card.media,
    );
    await _connection.writeBytes(bytes);
  }

  Future<void> printTest({PrintMedia media = PrintMedia.roll57}) async {
    final bytes = _adapter.encodeTestPrint(media: media);
    await _connection.writeBytes(bytes);
  }

  Future<void> printRaw(Uint8List bytes) => _connection.writeBytes(bytes);
}
