import 'dart:typed_data';

import 'escpos_encoder.dart';
import 'printer_profile.dart';

abstract class PrinterProtocolAdapter {
  const PrinterProtocolAdapter();

  Uint8List encodeRaster(Uint8List raster, int width, int height);

  Uint8List encodeTestPrint();
}

class EscPosAdapter implements PrinterProtocolAdapter {
  EscPosAdapter({PrinterProfile? profile})
    : profile = profile ?? PrinterProfile.pt210;

  final PrinterProfile profile;

  @override
  Uint8List encodeRaster(Uint8List raster, int width, int height) {
    return encodeEscPosRaster(
      raster: raster,
      width: width,
      height: height,
      feedLines: profile.feedLines,
    );
  }

  @override
  Uint8List encodeTestPrint() => encodeTestPattern(width: profile.printWidth);
}

class CatPrinterAdapter implements PrinterProtocolAdapter {
  const CatPrinterAdapter();

  @override
  Uint8List encodeRaster(Uint8List raster, int width, int height) {
    throw UnimplementedError(
      'CatPrinter protocol is not implemented. Use EscPosAdapter for PT-210.',
    );
  }

  @override
  Uint8List encodeTestPrint() {
    throw UnimplementedError(
      'CatPrinter protocol is not implemented. Use EscPosAdapter for PT-210.',
    );
  }
}
