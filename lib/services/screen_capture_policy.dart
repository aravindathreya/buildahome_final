import 'package:flutter/foundation.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_live_test_access.dart';

/// Screenshots and screen recording are blocked for every session except
/// Super Admin. Android's MainActivity sets FLAG_SECURE before the first
/// frame, so the app stays protected until the stored role is known.
class ScreenCapturePolicy {
  ScreenCapturePolicy._();

  static bool allowsCapture(String? role) =>
      (role ?? '').trim() == MobileLiveTestAccess.superAdminRole;

  /// Applies the rule for the logged-in role. Call after login and logout.
  static Future<void> apply() async {
    if (kIsWeb) return;
    String? role;
    try {
      final prefs = await SharedPreferences.getInstance();
      role = prefs.getString('role');
    } catch (_) {}
    await _set(allowCapture: allowsCapture(role));
  }

  /// Blocks capture immediately, e.g. while a session is being cleared.
  static Future<void> protect() => _set(allowCapture: false);

  static Future<void> _set({required bool allowCapture}) async {
    if (kIsWeb) return;
    try {
      if (allowCapture) {
        await ScreenProtector.preventScreenshotOff();
        await ScreenProtector.protectDataLeakageOff();
      } else {
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageOn();
      }
    } catch (_) {
      // Native channel may be unavailable on desktop/unsupported targets.
    }
  }
}
