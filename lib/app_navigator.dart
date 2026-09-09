import 'package:flutter/material.dart';

/// Shared navigation / snackbar keys for app-wide flows (e.g. session logout).
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Ignores a second tap for a short window so double-taps do not open
/// the same screen twice.
class AppTapGuard extends StatefulWidget {
  final Widget child;
  final Duration lockDuration;

  const AppTapGuard({
    super.key,
    required this.child,
    this.lockDuration = const Duration(milliseconds: 600),
  });

  @override
  State<AppTapGuard> createState() => _AppTapGuardState();
}

class _AppTapGuardState extends State<AppTapGuard> {
  Offset? _downPosition;
  bool _locked = false;

  void _armLock() {
    if (_locked || !mounted) return;
    setState(() => _locked = true);
    Future<void>.delayed(widget.lockDuration, () {
      if (mounted) setState(() => _locked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
      },
      onPointerUp: (event) {
        final down = _downPosition;
        _downPosition = null;
        if (down == null) return;
        if ((event.position - down).distance > 14) return;
        _armLock();
      },
      child: AbsorbPointer(
        absorbing: _locked,
        child: widget.child,
      ),
    );
  }
}
