import 'dart:typed_data';

import 'package:buildAhome/services/document_byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache key ignores the session token and query order', () {
    expect(
      documentCacheKey(
        'https://office.buildahome.in/files/plan.pdf?api_token=secret&rev=2',
      ),
      documentCacheKey(
        'https://office.buildahome.in/files/plan.pdf?rev=2&api_token=other',
      ),
    );
    expect(
      documentCacheKey('/files/plan.pdf?api_token=secret'),
      'https://office.buildahome.in/files/plan.pdf',
    );
  });

  test('memory cache returns the same bytes for a repeat open', () {
    final cache = DocumentByteCache.instance;
    final key = documentCacheKey('https://office.buildahome.in/files/a.pdf');
    final bytes = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 1, 2, 3]);

    cache.remember(key, bytes);

    expect(cache.peek(key), bytes);
    expect(cache.isStreamable(key), isFalse);
    cache.markStreamable(key);
    expect(cache.isStreamable(key), isTrue);
  });
}
