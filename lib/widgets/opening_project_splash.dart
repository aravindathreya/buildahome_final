import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../app_navigator.dart';
import '../services/project_open_timing.dart';

/// Full-screen gate shown while a project workspace is being opened.
/// Matches the app splash: solid navy, white logo, ring spinner.
class OpeningProjectGate extends StatefulWidget {
  final String projectName;
  final Widget child;
  final Duration splashDuration;
  final Future<void> Function()? prepare;
  final ProjectOpenTiming? timing;

  const OpeningProjectGate({
    super.key,
    required this.projectName,
    required this.child,
    this.splashDuration = const Duration(milliseconds: 350),
    this.prepare,
    this.timing,
  });

  /// Push the splash immediately, optionally running [prepare] while it shows.
  /// Destination appears after both the minimum splash duration and [prepare]
  /// have finished.
  ///
  /// Rapid re-taps are ignored until this route is popped.
  static Future<T?> push<T extends Object?>(
    BuildContext context, {
    required String projectName,
    required Widget destination,
    Future<void> Function(ProjectOpenTiming timing)? prepare,
    Duration splashDuration = const Duration(milliseconds: 350),
  }) async {
    if (!NavigationDebounce.tryAcquire()) return null;
    NavigationDebounce.beginPush();
    final timing = ProjectOpenTiming(projectName);
    try {
      return await Navigator.of(context).push<T>(
        PageRouteBuilder<T>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) {
            return OpeningProjectGate(
              projectName: projectName,
              prepare: prepare == null ? null : () => prepare(timing),
              splashDuration: splashDuration,
              timing: timing,
              child: destination,
            );
          },
        ),
      );
    } finally {
      NavigationDebounce.endPush();
    }
  }

  @override
  State<OpeningProjectGate> createState() => _OpeningProjectGateState();
}

class _OpeningProjectGateState extends State<OpeningProjectGate>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B254B);

  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  bool _showDestination = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
    _runGate();
  }

  Future<void> _runGate() async {
    final timing = widget.timing;

    final splashWatch = Stopwatch()..start();
    final splashFuture = Future<void>.delayed(widget.splashDuration).then((_) {
      splashWatch.stop();
      timing?.recordMs('min_splash_wait', splashWatch.elapsedMilliseconds);
    });

    final prepareFuture = () async {
      final prepare = widget.prepare;
      if (prepare == null) return;
      try {
        if (timing != null) {
          await timing.measure('prepare_total', prepare);
        } else {
          await prepare();
        }
      } catch (e) {
        debugPrint('[OpeningProjectGate] prepare failed: $e');
      }
    }();

    await Future.wait<void>([splashFuture, prepareFuture]);

    if (!mounted) return;
    if (timing != null) {
      await timing.measure('fade_to_destination', () async {
        await _fadeController.reverse();
      });
    } else {
      await _fadeController.reverse();
    }
    if (!mounted) return;
    setState(() => _showDestination = true);

    timing?.logReport();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showDestination) {
      return widget.child;
    }

    final name = widget.projectName.trim();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _navy,
        body: FadeTransition(
          opacity: _fade,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/LOGO WHITE.png',
                  height: 56,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => const Text(
                    'buildAhome',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const SpinKitRing(
                  color: Colors.white,
                  size: 36,
                  lineWidth: 2.5,
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Opening project…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
