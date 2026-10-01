import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'package:flutter/services.dart';

import '../AttendanceScreen.dart';
import '../app_navigator.dart';
import 'dashboard_chrome.dart';

/// Full-screen check-in splash, then the attendance page.
class AttendanceOpenSplash extends StatefulWidget {
  const AttendanceOpenSplash({super.key});

  static Future<void> push(BuildContext context) async {
    if (!NavigationDebounce.tryAcquire()) return;
    NavigationDebounce.beginPush();
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) {
            return const AttendanceOpenSplash();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } finally {
      NavigationDebounce.endPush();
    }
  }

  @override
  State<AttendanceOpenSplash> createState() => _AttendanceOpenSplashState();
}

class _AttendanceOpenSplashState extends State<AttendanceOpenSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _splashOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    _splashOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.78, 1, curve: Curves.easeIn),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
      children: [
        DashboardChrome.wrap(
          DashboardChromeStyle.admin,
          const AttendanceScreen(),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final opacity = _splashOpacity.value;
            if (opacity <= 0.01) return const SizedBox.shrink();
            return IgnorePointer(
              child: Opacity(opacity: opacity, child: child),
            );
          },
          child: const _CheckInSplashScene(),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_splashOpacity.value <= 0.01) return const SizedBox.shrink();
            return IgnorePointer(
              child: Opacity(
                opacity: _splashOpacity.value,
                child: _DoorCheckInScene(progress: _controller.value),
              ),
            );
          },
        ),
      ],
      ),
    );
  }
}

class _CheckInSplashScene extends StatelessWidget {
  const _CheckInSplashScene();

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryColorConstDark, AppTheme.navySoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _DoorCheckInScene extends StatelessWidget {
  final double progress;

  const _DoorCheckInScene({required this.progress});

  double _span(double start, double end) {
    if (progress <= start) return 0;
    if (progress >= end) return 1;
    final t = (progress - start) / (end - start);
    return Curves.easeInOut.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final walk = _span(0.02, 0.42);
    final doorOpen = _span(0.36, 0.58);
    final enter = _span(0.54, 0.74);
    final badge = _span(0.68, 0.84);
    final caption = _span(0.12, 0.28);

    final stride = walk < 1 ? (walk * 6.0) : 0.0;
    final step = walk < 1 ? (stride - stride.floorToDouble()) : 0.0;
    final leg = step < 0.5 ? step * 2 : (1 - step) * 2;
    final bob = walk < 1 ? (leg * 5) : 0.0;

    final personX = _lerp(-78, 36, walk) + _lerp(0, 34, enter);
    final personOpacity = (1 - enter * 0.92).clamp(0.0, 1.0).toDouble();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 280,
            height: 230,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 28,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Positioned(
                  right: 46,
                  bottom: 34,
                  child: _Door(
                    open: doorOpen,
                    glow: enter,
                  ),
                ),
                Positioned(
                  left: 108 + personX,
                  bottom: 32 + bob.toDouble(),
                  child: Opacity(
                    opacity: personOpacity,
                    child: _Walker(leg: leg, arriving: walk > 0.82),
                  ),
                ),
                Positioned(
                  right: 58,
                  top: 8,
                  child: Transform.scale(
                    scale: badge,
                    child: Opacity(
                      opacity: badge,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34D399),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: caption.clamp(0, 1),
            child: const Text(
              'Checking in',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _Door extends StatelessWidget {
  final double open;
  final double glow;

  const _Door({required this.open, required this.glow});

  @override
  Widget build(BuildContext context) {
    final angle = open * 1.15;
    return SizedBox(
      width: 108,
      height: 168,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(
                        alpha: 0.35 + glow * 0.45,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                    ),
                  ),
                ),
                Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.002)
                    ..rotateY(angle),
                  child: Container(
                    width: 92,
                    height: 160,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(6, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 18,
                          child: Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9D5FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 78,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.darkTextPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Walker extends StatelessWidget {
  final double leg;
  final bool arriving;

  const _Walker({required this.leg, required this.arriving});

  @override
  Widget build(BuildContext context) {
    final swing = (leg - 0.5) * 0.9;
    return SizedBox(
      width: 46,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE4C4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 18,
            child: Container(
              width: 28,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            top: 28,
            left: arriving ? 24 : 4,
            child: Transform.rotate(
              angle: arriving ? -0.8 : swing,
              alignment: Alignment.topCenter,
              child: Container(
                width: 7,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 8,
            child: Transform.rotate(
              angle: arriving ? 0 : swing,
              alignment: Alignment.topCenter,
              child: _leg(),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 8,
            child: Transform.rotate(
              angle: arriving ? 0 : -swing,
              alignment: Alignment.topCenter,
              child: _leg(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leg() {
    return Container(
      width: 7,
      height: 28,
      decoration: BoxDecoration(
        color: AppTheme.primaryColorConstDark,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
