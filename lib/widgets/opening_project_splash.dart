import 'dart:math' as math;
import '../app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigator.dart';
import '../services/project_open_timing.dart';

/// Full-screen gate shown while a project workspace is being opened.
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
    this.splashDuration = const Duration(milliseconds: 1700),
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
    Duration splashDuration = const Duration(milliseconds: 1700),
  }) async {
    if (!NavigationDebounce.tryAcquire()) return null;
    NavigationDebounce.beginPush();
    final timing = ProjectOpenTiming(projectName);
    try {
      return await Navigator.of(context).push<T>(
        PageRouteBuilder<T>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 280),
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
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _introController;
  late final AnimationController _driftController;
  late final AnimationController _riseController;
  late final Animation<double> _fade;
  late final Animation<double> _intro;
  late final Animation<double> _rise;
  bool _showDestination = false;
  int _phraseIndex = 0;

  static const List<String> _phrases = [
    'Gathering the details',
    'Setting the light',
    'Opening your home',
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
    _riseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _intro = CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic);
    _rise = CurvedAnimation(parent: _riseController, curve: Curves.easeOutBack);
    _fadeController.forward();
    _introController.forward();
    _riseController.forward();
    _cyclePhrases();
    _runGate();
  }

  void _cyclePhrases() {
    Future<void>.delayed(const Duration(milliseconds: 620), () {
      if (!mounted || _showDestination) return;
      setState(() => _phraseIndex = 1);
    });
    Future<void>.delayed(const Duration(milliseconds: 1240), () {
      if (!mounted || _showDestination) return;
      setState(() => _phraseIndex = 2);
    });
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
    _fadeController.duration = const Duration(milliseconds: 520);
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
    _introController.dispose();
    _driftController.dispose();
    _riseController.dispose();
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
        backgroundColor: AppTheme.darkBackgroundPrimary,
        body: FadeTransition(
          opacity: _fade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.darkBackgroundSecondary,
                      Color(0xFF161222),
                      Color(0xFF0E0C14),
                    ],
                    stops: [0, 0.48, 1],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _driftController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AtmospherePainter(phase: _driftController.value),
                    child: const SizedBox.expand(),
                  );
                },
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _intro,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _intro.value.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, (1 - _intro.value) * 10),
                              child: child,
                            ),
                          );
                        },
                        child: const _BrandMark(),
                      ),
                      const Spacer(),
                      AnimatedBuilder(
                        animation: Listenable.merge([_rise, _driftController]),
                        builder: (context, _) {
                          final rise = _rise.value.clamp(0.0, 1.2);
                          return Transform.translate(
                            offset: Offset(0, (1 - rise.clamp(0.0, 1.0)) * 28),
                            child: Transform.scale(
                              scale: 0.86 + 0.14 * rise.clamp(0.0, 1.0),
                              child: CustomPaint(
                                size: const Size(260, 230),
                                painter: _SoftHousePainter(
                                  phase: _driftController.value,
                                  reveal: rise.clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      AnimatedBuilder(
                        animation: _intro,
                        builder: (context, child) {
                          final t = Curves.easeOut.transform(
                            ((_intro.value - 0.25) / 0.75).clamp(0.0, 1.0),
                          );
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, (1 - t) * 16),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            const Text(
                              'Welcome home',
                              style: TextStyle(
                                color: AppTheme.darkTextSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              name.isEmpty ? 'Your project' : name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.darkTextPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.8,
                                height: 1.12,
                              ),
                            ),
                            const SizedBox(height: 14),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 420),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: Text(
                                _phrases[_phraseIndex],
                                key: ValueKey(_phraseIndex),
                                style: const TextStyle(
                                  color: AppTheme.darkTextSecondary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const _BreathingMark(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/new logo.png',
      height: 42,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.home_rounded,
        color: AppTheme.darkTextPrimary,
        size: 32,
      ),
    );
  }
}

class _BreathingMark extends StatefulWidget {
  const _BreathingMark();

  @override
  State<_BreathingMark> createState() => _BreathingMarkState();
}

class _BreathingMarkState extends State<_BreathingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return SizedBox(
          width: 72,
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFF4C4458),
                      AppTheme.darkTextPrimary,
                      (math.sin((t + i * 0.22) * math.pi)).abs(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  final double phase;

  const _AtmospherePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    void orb(double x, double y, double radius, Color color, double drift) {
      final dx = math.sin((phase + drift) * math.pi * 2) * 16;
      final dy = math.cos((phase + drift) * math.pi * 2) * 10;
      final center = Offset(size.width * x + dx, size.height * y + dy);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    orb(0.18, 0.16, 120, AppTheme.navy.withValues(alpha: 0.28), 0.1);
    orb(0.82, 0.22, 150, AppTheme.primaryColorConstDark.withValues(alpha: 0.55), 0.45);
    orb(0.5, 0.72, 180, AppTheme.accentBlue.withValues(alpha: 0.14), 0.7);
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}

class _SoftHousePainter extends CustomPainter {
  final double phase;
  final double reveal;

  const _SoftHousePainter({required this.phase, required this.reveal});

  Offset _iso(double x, double y, double z) {
    return Offset((x - y) * 0.9, (x + y) * 0.5 - z);
  }

  void _face(Canvas canvas, List<Offset> pts, Color color) {
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.62);
    canvas.save();
    canvas.translate(center.dx, center.dy);

    final glow = 0.55 + 0.15 * math.sin(phase * math.pi * 2);
    canvas.drawCircle(
      const Offset(0, 18),
      108,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(82, 61, 158, 0.32 * glow),
            const Color(0x007063CC),
          ],
        ).createShader(Rect.fromCircle(center: const Offset(0, 18), radius: 108)),
    );

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 78), width: 190, height: 28),
      Paint()..color = const Color(0x66000000),
    );

    Offset p(double x, double y, double z) => _iso(x, y, z * reveal);

    const w = 46.0;
    const d = 36.0;
    const h = 58.0;

    _face(canvas, [
      p(-w, -d, h),
      p(w, -d, h),
      p(w, d, h),
      p(-w, d, h),
    ], const Color(0xFF2A2340));
    _face(canvas, [
      p(w, -d, h),
      p(w, d, h),
      p(w, d, 0),
      p(w, -d, 0),
    ], AppTheme.darkBackgroundSecondary);
    _face(canvas, [
      p(-w, d, h),
      p(w, d, h),
      p(w, d, 0),
      p(-w, d, 0),
    ], const Color(0xFF161222));

    final window = [
      p(-14, d, 42),
      p(16, d, 42),
      p(16, d, 16),
      p(-14, d, 16),
    ];
    final windowPath = Path()..addPolygon(window, true);
    canvas.drawPath(
      windowPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF6E8), Color(0xFFFFD89A), Color(0xFFFFC56D)],
        ).createShader(windowPath.getBounds()),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SoftHousePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.reveal != reveal;
  }
}
