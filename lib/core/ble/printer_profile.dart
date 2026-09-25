import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../constants.dart';

enum PrinterLinkKind { classic, ble }

class PrinterProfile {
  const PrinterProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.serviceUuids,
    required this.writeUuid,
    this.notifyUuid,
    required this.printWidth,
    required this.chunkBytes,
    required this.chunkPause,
    required this.feedLines,
    this.nameHints = const [],
  });

  final String id;
  final String name;
  final PrinterLinkKind kind;
  final List<String> serviceUuids;
  final String writeUuid;
  final String? notifyUuid;
  final int printWidth;
  final int chunkBytes;
  final Duration chunkPause;
  final int feedLines;
  final List<String> nameHints;

  /// 80 mm Xprinter. 576 dots is the safe 203 dpi width; a ruler print
  /// shows whether the head is actually 576 or 608.
  static final xp365b = PrinterProfile(
    id: 'xp365b',
    name: 'Xprinter XP-365B',
    kind: PrinterLinkKind.classic,
    serviceUuids: const [],
    writeUuid: '',
    printWidth: 576,
    chunkBytes: 512,
    chunkPause: const Duration(milliseconds: 8),
    feedLines: kFeedLines,
    nameHints: const ['XP-365B', 'XP365B', 'Xprinter', 'Printer'],
  );

  static final pt210 = PrinterProfile(
    id: 'pt210',
    name: 'GOOJPRT PT-210',
    kind: PrinterLinkKind.ble,
    serviceUuids: const ['000018f0-0000-1000-8000-00805f9b34fb'],
    writeUuid: '00002af1-0000-1000-8000-00805f9b34fb',
    notifyUuid: '00002af0-0000-1000-8000-00805f9b34fb',
    printWidth: PaperSize.mm58.width,
    chunkBytes: kPrintChunkBytes,
    chunkPause: kPrintChunkPause,
    feedLines: kFeedLines,
    nameHints: const ['PT-210', 'PT210', 'MTP', 'Printer', 'GOOJPRT', 'BlueTooth'],
  );

  static final pt210IsscFallback = PrinterProfile(
    id: 'pt210-issc',
    name: 'GOOJPRT PT-210 (ISSC UART)',
    kind: PrinterLinkKind.ble,
    serviceUuids: const ['49535343-fe7d-4ae5-8fa9-9fafd205e455'],
    writeUuid: '49535343-8841-43f4-a8d4-ecbe34729bb3',
    printWidth: PaperSize.mm58.width,
    chunkBytes: kPrintChunkBytes,
    chunkPause: kPrintChunkPause,
    feedLines: kFeedLines,
    nameHints: pt210.nameHints,
  );

  static List<PrinterProfile> get bleCandidates => [pt210, pt210IsscFallback];

  static PrinterProfile forName(String name) {
    final upper = name.toUpperCase();
    const xpSpecific = ['XP-365B', 'XP365B', 'XPRINTER'];
    const classicMini = ['PT-210', 'PT210', 'GOOJPRT'];
    if (xpSpecific.any(upper.contains)) return xp365b;
    if (classicMini.any(upper.contains)) return pt210;
    return xp365b;
  }
}
