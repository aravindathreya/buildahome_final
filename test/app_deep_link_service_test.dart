import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/services/app_deep_link_service.dart';

void main() {
  group('AppDeepLinkService.resolveScreen', () {
    test('reads native_screen=payment_proof', () {
      final uri = Uri.parse(
        'buildahome://open?native_screen=payment_proof',
      );
      expect(AppDeepLinkService.resolveScreen(uri), 'payment_proof');
    });

    test('accepts upload_proof alias', () {
      final uri = Uri.parse(
        'buildahome://open?native_screen=upload_proof',
      );
      expect(AppDeepLinkService.resolveScreen(uri), 'payment_proof');
    });

    test('reads path segment', () {
      final uri = Uri.parse('buildahome://open/upload_proof');
      expect(AppDeepLinkService.resolveScreen(uri), 'payment_proof');
    });

    test('reads https /app/open query', () {
      final uri = Uri.parse(
        'https://office.buildahome.in/app/open?native_screen=payment_proof',
      );
      expect(AppDeepLinkService.resolveScreen(uri), 'payment_proof');
    });

    test('ignores plain open without screen', () {
      final uri = Uri.parse('buildahome://open');
      expect(AppDeepLinkService.resolveScreen(uri), isNull);
    });
  });
}
