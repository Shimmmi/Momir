import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants.dart';
import 'art_prep.dart';

class ArtCacheService {
  Directory? _dir;

  static const publicArtPath = '/storage/emulated/0/Documents/Momir/art';

  Future<Directory> get directory async {
    if (_dir != null) return _dir!;
    final public = await _publicArtDir();
    if (public != null) {
      _dir = public;
    } else {
      final root = await getApplicationDocumentsDirectory();
      _dir = Directory(p.join(root.path, 'art'));
    }
    await _dir!.create(recursive: true);
    return _dir!;
  }

  Future<Directory?> _publicArtDir() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final granted = await _ensurePublicStorage();
    if (!granted) return null;
    final dir = Directory(publicArtPath);
    await dir.create(recursive: true);
    return dir;
  }

  Future<bool> _ensurePublicStorage() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final managed = await Permission.manageExternalStorage.request();
    if (managed.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// Copies pictures out of the app-private folder once, so an uninstall
  /// that keeps Documents does not throw away the download.
  Future<void> migrateFromInternal() async {
    final public = await _publicArtDir();
    if (public == null) return;
    final root = await getApplicationDocumentsDirectory();
    final internal = Directory(p.join(root.path, 'art'));
    if (!await internal.exists()) return;
    await for (final entity in internal.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jpg')) continue;
      final rel = p.relative(entity.path, from: internal.path);
      final dest = File(p.join(public.path, rel));
      await dest.parent.create(recursive: true);
      if (!await dest.exists()) {
        await entity.copy(dest.path);
      }
      await entity.delete();
    }
    _dir = public;
  }

  Future<int> deleteAllImages() async {
    var removed = 0;
    Future<void> wipe(Directory dir) async {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.jpg')) continue;
        await entity.delete();
        removed++;
      }
    }

    await wipe(Directory(publicArtPath));
    final root = await getApplicationDocumentsDirectory();
    await wipe(Directory(p.join(root.path, 'art')));
    _dir = null;
    return removed;
  }

  Future<File> fileFor(String id) async {
    return File(p.join((await directory).path, '$id.jpg'));
  }

  Future<bool> hasArt(String id) async => (await fileFor(id)).exists();

  Future<Directory> get displayDirectory async {
    final root = await directory;
    final dir = Directory(p.join(root.path, 'display'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> displayFileFor(String id) async {
    return File(p.join((await displayDirectory).path, '$id.jpg'));
  }

  Future<bool> hasDisplay(String id) async => (await displayFileFor(id)).exists();

  /// Screen image: keep the Scryfall frame, only shrink if it is wider than
  /// [kDisplayMaxWidth]. This is not the thermal crop.
  Future<void> storeDisplayFromBytes(String id, List<int> bytes) async {
    final decoded = img.decodeImage(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    if (decoded == null) {
      throw StateError('Could not decode display art for $id');
    }
    final flat = flattenOnWhite(decoded);
    final fitted = flat.width > kDisplayMaxWidth
        ? img.copyResize(
            flat,
            width: kDisplayMaxWidth,
            interpolation: img.Interpolation.linear,
          )
        : flat;
    final jpg = img.encodeJpg(fitted, quality: kDisplayJpegQuality);
    final dest = await displayFileFor(id);
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(jpg, flush: true);
    if (await dest.exists()) await dest.delete();
    await tmp.rename(dest.path);
  }

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
    final display = await displayDirectory;
    await for (final entity in display.list()) {
      if (entity is! File || !entity.path.endsWith('.jpg')) continue;
      final id = p.basenameWithoutExtension(entity.path);
      if (!validIds.contains(id)) await entity.delete();
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
