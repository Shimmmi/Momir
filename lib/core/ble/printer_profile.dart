import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../constants.dart';

class PrinterProfile {
  const PrinterProfile({
    required this.id,
    required this.name,
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
  final List<String> serviceUuids;
  final String writeUuid;
  final String? notifyUuid;
  final int printWidth;
  final int chunkBytes;
  final Duration chunkPause;
  final int feedLines;
  final List<String> nameHints;

  static final pt210 = PrinterProfile(
    id: 'pt210',
    name: 'GOOJPRT PT-210',
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
    serviceUuids: const ['49535343-fe7d-4ae5-8fa9-9fafd205e455'],
    writeUuid: '49535343-8841-43f4-a8d4-ecbe34729bb3',
    printWidth: PaperSize.mm58.width,
    chunkBytes: kPrintChunkBytes,
    chunkPause: kPrintChunkPause,
    feedLines: kFeedLines,
    nameHints: pt210.nameHints,
  );

  static List<PrinterProfile> get candidates => [pt210, pt210IsscFallback];
}
