import 'dart:async';

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
    Duration cooldown = const Duration(milliseconds: 900),
  }) {
    if (isLocked) return false;
    _lockedUntil = DateTime.now().add(cooldown);
    return true;
  }

  static void beginPush() => _pushDepth++;

  static void endPush() {
    if (_pushDepth > 0) _pushDepth--;
    _lockedUntil = DateTime.now().add(const Duration(milliseconds: 400));
  }
}

/// Ignores follow-up taps for a short window so double/triple taps do not
/// open the same screen multiple times (which then needs multiple backs).
class AppTapGuard extends StatefulWidget {
  final Widget child;
  final Duration lockDuration;

  const AppTapGuard({
    super.key,
    required this.child,
    this.lockDuration = const Duration(milliseconds: 900),
  });

  @override
  State<AppTapGuard> createState() => _AppTapGuardState();
}

class _AppTapGuardState extends State<AppTapGuard> {
  bool _absorbing = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _lockAfterThisTap() {
    // First pointer-down already reached the child; block the next ones ASAP.
    if (_absorbing) return;
    _absorbing = true;
    if (mounted) setState(() {});
    _timer?.cancel();
    _timer = Timer(widget.lockDuration, () {
      if (!mounted) return;
      setState(() => _absorbing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _lockAfterThisTap(),
      child: AbsorbPointer(
        absorbing: _absorbing,
        child: widget.child,
      ),
    );
  }
}
