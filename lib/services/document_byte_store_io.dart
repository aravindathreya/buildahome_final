import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// On-device copies of documents so the next open skips the network.
class DocumentByteStore {
  static const int _maxFiles = 8;
  static const int _maxTotalBytes = 60 * 1024 * 1024;
  static const int _maxFileBytes = 40 * 1024 * 1024;

  static Future<Directory> _dir() async {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}bah_doc_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _name(String key) {
    var hash = 5381;
    for (final unit in key.codeUnits) {
      hash = 0x7fffffff & ((hash * 33) ^ unit);
    }
    return 'doc_$hash.bin';
  }

  static Future<File> _file(String key) async {
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}${_name(key)}');
  }

  static Future<Uint8List?> read(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {}
    return file.readAsBytes();
  }

  static Future<void> write(String key, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _maxFileBytes) return;
    final dir = await _dir();
    final file = File('${dir.path}${Platform.pathSeparator}${_name(key)}');
    await file.writeAsBytes(bytes, flush: true);
    await _evict(dir);
  }

  static Future<void> _evict(Directory dir) async {
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) {
      final am = a.lastModifiedSync();
      final bm = b.lastModifiedSync();
      return am.compareTo(bm);
    });
    var total = 0;
    for (final file in files) {
      total += file.lengthSync();
    }
    while (files.length > _maxFiles || total > _maxTotalBytes) {
      if (files.isEmpty) return;
      final oldest = files.removeAt(0);
      final size = oldest.existsSync() ? oldest.lengthSync() : 0;
      try {
        await oldest.delete();
      } catch (_) {}
      total -= size;
    }
  }
}
