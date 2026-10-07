import 'package:buildAhome/services/screen_capture_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only Super Admin may capture the screen', () {
    expect(ScreenCapturePolicy.allowsCapture('Super Admin'), isTrue);
    expect(ScreenCapturePolicy.allowsCapture(' Super Admin '), isTrue);

    for (final role in [
      'Admin',
      'super admin',
      'Site Engineer',
      'Project Coordinator',
      'Billing',
      'Client',
      '',
      null,
    ]) {
      expect(ScreenCapturePolicy.allowsCapture(role), isFalse, reason: '$role');
    }
  });
}
