import 'dart:convert';
import 'dart:typed_data';

/// TSPL job for the XP-365B. [paperWidthMm] is the printable width
/// (48 mm on a 57 mm roll, 40 mm on a 40×58 label). [paperHeightMm] fixes
/// the label length; a roll leaves it null and follows the bitmap.
Uint8List encodeTsplBitmap({
  required Uint8List raster,
  required int width,
  required int height,
  int paperWidthMm = 48,
  int? paperHeightMm,
  double gapMm = 0,
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

  final heightMm = paperHeightMm ?? (height * 25.4 / 203).ceil().clamp(8, 400);
  final header = ascii.encode(
    'SIZE $paperWidthMm mm, $heightMm mm\r\n'
    'GAP ${_mm(gapMm)} mm, 0 mm\r\n'
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

String _mm(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}
