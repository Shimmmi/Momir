import 'dart:convert';
import 'dart:typed_data';

/// TSPL label job for a 57 mm roll. Printable width is 48 mm, 384 dots
/// at 203 dpi, so each row is 48 bytes.
Uint8List encodeTsplBitmap({
  required Uint8List raster,
  required int width,
  required int height,
}) {
  if (width % 8 != 0) {
    throw ArgumentError('width must be divisible by 8, got $width');
  }
  final bytesPerRow = width ~/ 8;
  final expected = bytesPerRow * height;
  if (raster.length != expected) {
    throw ArgumentError('raster length ${raster.length} != $expected');
  }

  // XP-365B prints a 0-bit as black. Our raster uses 1 for ink, so flip it.
  final bitmap = Uint8List(raster.length);
  for (var i = 0; i < raster.length; i++) {
    bitmap[i] = (~raster[i]) & 0xff;
  }

  final heightMm = (height * 25.4 / 203).ceil().clamp(8, 400);
  final header = ascii.encode(
    'SIZE 48 mm, $heightMm mm\r\n'
    'GAP 0 mm, 0 mm\r\n'
    'CLS\r\n'
    'BITMAP 0,0,$bytesPerRow,$height,0,',
  );
  final footer = ascii.encode('\r\nPRINT 1\r\n');
  final out = BytesBuilder(copy: false);
  out.add(header);
  out.add(bitmap);
  out.add(footer);
  return out.toBytes();
}
