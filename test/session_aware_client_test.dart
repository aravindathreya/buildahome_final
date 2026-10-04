import 'dart:convert';

import 'package:buildAhome/services/api_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sessionBodyMayBeInvalid ignores large 200 payloads without token errors',
      () {
    final body = utf8.encode('{"tasks":[{"id":1,"note":"all good"}]}');
    expect(sessionBodyMayBeInvalid(body), isFalse);
  });

  test('sessionBodyMayBeInvalid detects invalid-token wording', () {
    final body = utf8.encode('{"success":false,"message":"Invalid api token"}');
    expect(sessionBodyMayBeInvalid(body), isTrue);
  });

  test('sessionBodyMayBeInvalid is false for empty bodies', () {
    expect(sessionBodyMayBeInvalid(const []), isFalse);
  });
}
