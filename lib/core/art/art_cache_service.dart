import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import 'art_prep.dart';

class ArtCacheService {
  Directory? _dir;

  Future<Directory> get directory async {
    if (_dir != null) return _dir!;
    final root = await getApplicationDocumentsDirectory();
    _dir = Directory(p.join(root.path, 'art'));
    await _dir!.create(recursive: true);
    return _dir!;
  }

  Future<File> fileFor(String id) async {
    return File(p.join((await directory).path, '$id.jpg'));
  }

  Future<bool> hasArt(String id) async => (await fileFor(id)).exists();

  Future<int> cachedCount() async {
    final dir = await directory;
    if (!await dir.exists()) return 0;
    return dir.list().where((e) => e.path.endsWith('.jpg')).length;
  }

  /// Downloads, cover-crops to the art box, and writes JPEG atomically.
  Future<void> storeFromBytes(String id, List<int> bytes) async {
    final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (decoded == null) {
      throw StateError('Could not decode art for $id');
    }
    final flattened = flattenOnWhite(decoded);
    final fitted = _coverResize(flattened, kArtWidth, kArtHeight);
    final jpg = img.encodeJpg(fitted, quality: kArtJpegQuality);
    final dest = await fileFor(id);
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(jpg, flush: true);
    if (await dest.exists()) {
      await dest.delete();
    }
    await tmp.rename(dest.path);
  }

  Future<void> pruneOrphans(Set<String> validIds) async {
    final dir = await directory;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.jpg')) continue;
      final id = p.basenameWithoutExtension(entity.path);
      if (!validIds.contains(id)) {
        await entity.delete();
      }
    }
  }

  img.Image _coverResize(img.Image src, int tw, int th) {
    final scale = math.max(tw / src.width, th / src.height);
    final nw = math.max(tw, (src.width * scale).round());
    final nh = math.max(th, (src.height * scale).round());
    final resized = img.copyResize(
      src,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.linear,
    );
    final x = ((resized.width - tw) / 2).round().clamp(0, resized.width - tw);
    final y = ((resized.height - th) / 2).round().clamp(0, resized.height - th);
    return img.copyCrop(resized, x: x, y: y, width: tw, height: th);
  }
}
