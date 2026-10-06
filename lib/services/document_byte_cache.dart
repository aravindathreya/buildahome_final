import 'dart:async';
import 'dart:typed_data';

import 'document_byte_store_stub.dart'
    if (dart.library.io) 'document_byte_store_io.dart';

/// Stable id for a document URL. The session token is not part of the key,
/// so a refreshed login still hits the saved file.
String documentCacheKey(String url) {
  var trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('/')) {
    trimmed = 'https://office.buildahome.in$trimmed';
  } else if (!trimmed.startsWith('http://') &&
      !trimmed.startsWith('https://')) {
    trimmed = 'https://office.buildahome.in/$trimmed';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return trimmed;
  final params = Map<String, String>.from(uri.queryParameters)
    ..remove('api_token');
  final keys = params.keys.toList()..sort();
  final resolved = keys.isEmpty
      ? uri.replace(queryParameters: const {})
      : uri.replace(
          queryParameters: {for (final key in keys) key: params[key]!},
        );
  final text = resolved.toString();
  return text.endsWith('?') ? text.substring(0, text.length - 1) : text;
}

class _MemEntry {
  _MemEntry(this.bytes);

  final Uint8List bytes;
}

/// Small memory cache plus a disk copy on phones.
class DocumentByteCache {
  DocumentByteCache._();

  static final DocumentByteCache instance = DocumentByteCache._();

  static const int maxEntries = 3;
  static const int maxMemoryBytes = 24 * 1024 * 1024;
  static const int maxEntryBytes = 12 * 1024 * 1024;

  final Map<String, _MemEntry> _items = {};
  final Set<String> streamableKeys = {};
  int _bytes = 0;

  Uint8List? peek(String key) {
    final hit = _items.remove(key);
    if (hit == null) return null;
    _items[key] = hit;
    return hit.bytes;
  }

  Future<Uint8List?> read(String key) async {
    final mem = peek(key);
    if (mem != null) return mem;
    try {
      final disk = await DocumentByteStore.read(key);
      if (disk == null || disk.isEmpty) return null;
      _rememberMemory(key, disk);
      return disk;
    } catch (_) {
      return null;
    }
  }

  void remember(String key, Uint8List bytes) {
    if (key.isEmpty || bytes.isEmpty) return;
    _rememberMemory(key, bytes);
    unawaited(() async {
      try {
        await DocumentByteStore.write(key, bytes);
      } catch (_) {}
    }());
  }

  void markStreamable(String key) {
    if (key.isNotEmpty) streamableKeys.add(key);
  }

  bool isStreamable(String key) => streamableKeys.contains(key);

  void _rememberMemory(String key, Uint8List bytes) {
    if (bytes.length > maxEntryBytes) return;
    final existing = _items.remove(key);
    if (existing != null) _bytes -= existing.bytes.length;
    _items[key] = _MemEntry(bytes);
    _bytes += bytes.length;
    while (_items.length > maxEntries ||
        (_bytes > maxMemoryBytes && _items.isNotEmpty)) {
      final oldestKey = _items.keys.first;
      final removed = _items.remove(oldestKey);
      if (removed == null) break;
      _bytes -= removed.bytes.length;
    }
  }
}
