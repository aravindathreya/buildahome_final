import 'dart:typed_data';

/// Web has no app document folder. Bytes stay in memory there.
class DocumentByteStore {
  static Future<Uint8List?> read(String key) async => null;

  static Future<void> write(String key, Uint8List bytes) async {}
}
