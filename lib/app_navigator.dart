import 'package:flutter/material.dart';

/// Shared navigation / snackbar keys for app-wide flows (e.g. session logout).
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Process-wide gate so rapid taps cannot push the same route many times.
class NavigationDebounce {
  NavigationDebounce._();

  static DateTime? _lockedUntil;
  static int _pushDepth = 0;

  static bool get isLocked {
    if (_pushDepth > 0) return true;
    final until = _lockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Returns false when another navigation is already in flight / recently fired.
  static bool tryAcquire({
    Duration cooldown = const Duration(milliseconds: 280),
  }) {
    if (isLocked) return false;
    _lockedUntil = DateTime.now().add(cooldown);
    return true;
  }

  static void beginPush() => _pushDepth++;

  static void endPush() {
    if (_pushDepth > 0) _pushDepth--;
    _lockedUntil = DateTime.now().add(const Duration(milliseconds: 120));
  }
}
