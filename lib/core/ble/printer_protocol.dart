import 'dart:typed_data';

import '../print_media.dart';
import 'escpos_encoder.dart';
import 'printer_profile.dart';
import 'tspl_encoder.dart';

abstract class PrinterProtocolAdapter {
  const PrinterProtocolAdapter();

  Uint8List encodeRaster(
    Uint8List raster,
    int width,
    int height, {
    PrintMedia media = PrintMedia.roll57,
  });

  Uint8List encodeTestPrint({PrintMedia media = PrintMedia.roll57});
}

class TsplAdapter implements PrinterProtocolAdapter {
  TsplAdapter({PrinterProfile? profile})
    : profile = profile ?? PrinterProfile.xp365b;

  final PrinterProfile profile;

  @override
  Uint8List encodeRaster(
    Uint8List raster,
    int width,
    int height, {
    PrintMedia media = PrintMedia.roll57,
  }) {
    return encodeTsplBitmap(
      raster: raster,
      width: width,
      height: height,
      paperWidthMm: media.paperWidthMm,
      paperHeightMm: media.paperHeightMm,
      gapMm: media.gapMm,
    );
  }

  @override
  Uint8List encodeTestPrint({PrintMedia media = PrintMedia.roll57}) {
    const height = 72;
    final width = media.showsArt ? profile.printWidth : media.widthDots;
    return encodeTsplBitmap(
      raster: widthRulerRaster(width: width),
      width: width,
      height: height,
      paperWidthMm: media.paperWidthMm,
      paperHeightMm: media.paperHeightMm,
      gapMm: media.gapMm,
    );
  }
}

class EscPosAdapter implements PrinterProtocolAdapter {
  EscPosAdapter({PrinterProfile? profile})
    : profile = profile ?? PrinterProfile.xp365b;

  final PrinterProfile profile;

  @override
  Uint8List encodeRaster(
    Uint8List raster,
    int width,
    int height, {
    PrintMedia media = PrintMedia.roll57,
  }) {
    return encodeEscPosRaster(
      raster: raster,
      width: width,
      height: height,
      feedLines: profile.feedLines,
    );
  }

  @override
  Uint8List encodeTestPrint({PrintMedia media = PrintMedia.roll57}) =>
      encodeWidthRuler(width: profile.printWidth);
}

class CatPrinterAdapter implements PrinterProtocolAdapter {
  const CatPrinterAdapter();

  @override
  Uint8List encodeRaster(
    Uint8List raster,
    int width,
    int height, {
    PrintMedia media = PrintMedia.roll57,
  }) {
    throw UnimplementedError(
      'CatPrinter protocol is not implemented. Use EscPosAdapter for PT-210.',
    );
  }

  @override
  Uint8List encodeTestPrint({PrintMedia media = PrintMedia.roll57}) {
    throw UnimplementedError(
      'CatPrinter protocol is not implemented. Use EscPosAdapter for PT-210.',
    );
  }
}
