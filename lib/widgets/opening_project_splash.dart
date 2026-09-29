import 'dart:math' as math;

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
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _orbitController;
  late final Animation<double> _fade;
  bool _showDestination = false;
  int _completedSteps = 1;
  double _progress = 0.38;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _fade = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
    _advanceSteps();
    _runGate();
  }

  void _advanceSteps() {
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _showDestination) return;
      setState(() {
        _completedSteps = 2;
        _progress = 0.7;
      });
    });
    Future<void>.delayed(const Duration(milliseconds: 1700), () {
      if (!mounted || _showDestination) return;
      setState(() {
        _completedSteps = 3;
        _progress = 1;
      });
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
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showDestination) {
      return widget.child;
    }

    final name = widget.projectName.trim();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _SplashPalette.background,
        body: FadeTransition(
          opacity: _fade,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF3F7FE),
                  Color(0xFFF7FAFF),
                  Color(0xFFFFFFFF),
                ],
                stops: [0, 0.42, 1],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _orbitController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _OrbitHousePainter(
                            phase: _orbitController.value * math.pi * 2,
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    child: Column(
                      children: [
                        const _BrandMark(),
                        const SizedBox(height: 22),
                        const Text(
                          'Initializing...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _SplashPalette.ink,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                        ),
                        if (name.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _SplashPalette.muted,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _ProgressBar(progress: _progress),
                        const SizedBox(height: 28),
                        _InitSteps(completed: _completedSteps),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashPalette {
  static const background = Color(0xFFF7FAFF);
  static const ink = Color(0xFF1B2340);
  static const muted = Color(0xFF9AA3B5);
  static const pending = Color(0xFF8E98A8);
  static const pendingSub = Color(0xFFC3CAD6);
  static const accent = Color(0xFF3B73F0);
  static const track = Color(0xFFE6EEF6);
  static const line = Color(0xFFE3EAF2);
  static const dot = Color(0xFFC5CEDA);
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/new logo.png',
          height: 58,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.home_rounded,
            color: _SplashPalette.ink,
            size: 40,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'buildAhome',
          style: TextStyle(
            color: _SplashPalette.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 236),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final fill = width * progress.clamp(0.0, 1.0);
            return Container(
              height: 6,
              decoration: BoxDecoration(
                color: _SplashPalette.track,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                width: fill,
                height: 6,
                decoration: BoxDecoration(
                  color: _SplashPalette.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InitStep {
  final String title;
  final String subtitle;

  const _InitStep(this.title, this.subtitle);
}

const List<_InitStep> _steps = [
  _InitStep('Loading project details', 'Fetching latest updates'),
  _InitStep('Preparing your dashboard', 'Setting up your project view'),
  _InitStep('Almost there', 'Getting things ready'),
];

class _InitSteps extends StatelessWidget {
  final int completed;

  const _InitSteps({required this.completed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          children: [
            for (var i = 0; i < _steps.length; i++)
              _StepRow(
                step: _steps[i],
                done: i < completed,
                showLine: i < _steps.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _InitStep step;
  final bool done;
  final bool showLine;

  const _StepRow({
    required this.step,
    required this.done,
    required this.showLine,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Column(
            children: [
              done
                  ? Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _SplashPalette.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _SplashPalette.accent.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    )
                  : const SizedBox(
                      height: 22,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _SplashPalette.dot,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(width: 8, height: 8),
                        ),
                      ),
                    ),
              if (showLine)
                Container(
                  width: 1.5,
                  height: 28,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: _SplashPalette.line,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 1, bottom: showLine ? 6 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    color: done ? _SplashPalette.ink : _SplashPalette.pending,
                    fontSize: 15,
                    fontWeight: done ? FontWeight.w700 : FontWeight.w600,
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.subtitle,
                  style: TextStyle(
                    color: done
                        ? _SplashPalette.muted
                        : _SplashPalette.pendingSub,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OrbitHousePainter extends CustomPainter {
  final double phase;

  const _OrbitHousePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.52);
    final scale = math.min(size.width, size.height) / 300;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    _glow(canvas);
    _orbits(canvas);
    _wireframe(canvas);
    _platformAndHouse(canvas);

    canvas.restore();
  }

  void _glow(Canvas canvas) {
    final rect = Rect.fromCircle(center: const Offset(0, 8), radius: 132);
    canvas.drawCircle(
      const Offset(0, 8),
      132,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0xFFD9E8FF),
            Color(0x00D9E8FF),
          ],
        ).createShader(rect),
    );
  }

  void _orbits(Canvas canvas) {
    const c = Offset(0, -6);
    const outer = 118.0;
    const mid = 92.0;

    canvas.drawCircle(
      c,
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFFD7E5F6),
    );
    canvas.drawCircle(
      c,
      mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE4EEF8),
    );

    void arc(double radius, double start, double sweep, double width, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        start + phase * 0.35,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    arc(outer, -1.25, 1.45, 7, const Color(0xFF5B8CFF));
    arc(outer, 2.25, 0.95, 4.2, const Color(0xFF8EB4FF));
    arc(mid, 0.35, 0.7, 3.2, const Color(0xFFB7CFFF));
    arc(outer + 8, 3.55, 0.42, 2.4, const Color(0xFFC5D8F8));

    void dot(double radius, double angle, double radiusPx, Color color) {
      final a = angle + phase * 0.35;
      canvas.drawCircle(
        c + Offset(math.cos(a) * radius, math.sin(a) * radius),
        radiusPx,
        Paint()..color = color,
      );
    }

    dot(outer, 2.95, 4.2, const Color(0xFF6F9AF2));
    dot(mid, -2.15, 3.4, const Color(0xFF9BB6E4));
    dot(outer, 1.55, 3.1, const Color(0xFFD5E3F6));
    dot(mid * 0.62, -0.55, 3.2, const Color(0xFF7EAEF5));
    dot(outer, -0.15, 2.6, const Color(0xFFD0DFF2));
  }

  Offset _iso(double x, double y, double z) {
    return Offset((x - y) * 0.86, (x + y) * 0.5 - z);
  }

  void _face(Canvas canvas, List<Offset> pts, Color color) {
    canvas.drawPath(
      Path()..addPolygon(pts, true),
      Paint()..color = color,
    );
  }

  void _wireframe(Canvas canvas) {
    const s = 78.0;
    const z = 78.0;
    final pts = [
      _iso(-s, -s, z),
      _iso(s, -s, z),
      _iso(s, s, z),
      _iso(-s, s, z),
    ];
    final paint = Paint()
      ..color = const Color(0xFFC5D6EA)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < pts.length; i++) {
      _dashedLine(canvas, pts[i], pts[(i + 1) % pts.length], paint);
      canvas.drawCircle(
        pts[i],
        2.3,
        Paint()..color = const Color(0xFFB7CBE4),
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final dir = delta / length;
    const dash = 5.0;
    const gap = 4.0;
    var drawn = 0.0;
    while (drawn < length) {
      final end = math.min(drawn + dash, length);
      canvas.drawLine(a + dir * drawn, a + dir * end, paint);
      drawn += dash + gap;
    }
  }

  void _platformAndHouse(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(2, 86), width: 210, height: 34),
      Paint()
        ..color = const Color(0xFF9BB6DC).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    Offset p(double x, double y, double z) => _iso(x, y, z) + const Offset(-2, 22);

    const pw = 92.0;
    const pd = 70.0;
    const pt = 11.0;

    _face(canvas, [
      p(-pw, -pd, pt),
      p(pw, -pd, pt),
      p(pw, pd, pt),
      p(-pw, pd, pt),
    ], const Color(0xFFF5F9FD));
    _face(canvas, [
      p(pw, -pd, pt),
      p(pw, pd, pt),
      p(pw, pd, 0),
      p(pw, -pd, 0),
    ], const Color(0xFFE6F0FA));
    _face(canvas, [
      p(-pw, pd, pt),
      p(pw, pd, pt),
      p(pw, pd, 0),
      p(-pw, pd, 0),
    ], const Color(0xFFD5E5F5));

    final grid = Paint()
      ..color = const Color(0xFFD5E3F2)
      ..strokeWidth = 1;
    for (final t in [-40.0, 0.0, 40.0]) {
      canvas.drawLine(p(-pw + 8, t, pt), p(pw - 8, t, pt), grid);
      canvas.drawLine(p(t, -pd + 8, pt), p(t, pd - 8, pt), grid);
    }

    Offset h(double x, double y, double z) => p(x - 6, y - 4, z);

    const hw = 38.0;
    const hd = 34.0;
    const base = pt;
    const top = pt + 50.0;

    _face(canvas, [
      h(-hw, -hd, top),
      h(hw, -hd, top),
      h(hw, hd, top),
      h(-hw, hd, top),
    ], Colors.white);
    _face(canvas, [
      h(hw, -hd, top),
      h(hw, hd, top),
      h(hw, hd, base),
      h(hw, -hd, base),
    ], const Color(0xFFF7FBFF));
    _face(canvas, [
      h(-hw, hd, top),
      h(hw, hd, top),
      h(hw, hd, base),
      h(-hw, hd, base),
    ], const Color(0xFFE7F0F8));

    final window = [
      h(-12, hd, base + 36),
      h(14, hd, base + 36),
      h(14, hd, base + 10),
      h(-12, hd, base + 10),
    ];
    final windowPath = Path()..addPolygon(window, true);
    canvas.drawPath(
      windowPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF8EC),
            Color(0xFFFFE3B0),
            Color(0xFFFFC56D),
          ],
        ).createShader(windowPath.getBounds()),
    );
    canvas.drawLine(
      h(1, hd, base + 36),
      h(1, hd, base + 10),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(
      windowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFF3DC),
    );

    const cx = 12.0;
    const cy = -16.0;
    const cw = 6.5;
    const cd = 6.0;
    const ch = 14.0;
    _face(canvas, [
      h(cx - cw, cy - cd, top + ch),
      h(cx + cw, cy - cd, top + ch),
      h(cx + cw, cy + cd, top + ch),
      h(cx - cw, cy + cd, top + ch),
    ], const Color(0xFFF4F7FB));
    _face(canvas, [
      h(cx + cw, cy - cd, top + ch),
      h(cx + cw, cy + cd, top + ch),
      h(cx + cw, cy + cd, top),
      h(cx + cw, cy - cd, top),
    ], const Color(0xFFE4EBF3));
    _face(canvas, [
      h(cx - cw, cy + cd, top + ch),
      h(cx + cw, cy + cd, top + ch),
      h(cx + cw, cy + cd, top),
      h(cx - cw, cy + cd, top),
    ], const Color(0xFFD5DEE8));

    final tree = p(58, -28, pt + 13);
    canvas.drawCircle(
      tree + const Offset(0, 10),
      8,
      Paint()
        ..color = const Color(0xFFB7CBE2).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      tree,
      11,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: const [
            Color(0xFFF7FBFF),
            Color(0xFFD5E4F4),
            Color(0xFFC3D6EC),
          ],
        ).createShader(Rect.fromCircle(center: tree, radius: 11)),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitHousePainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}
