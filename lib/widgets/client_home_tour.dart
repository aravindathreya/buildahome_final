import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';

/// First-login home tour for newer (Sales SOP) clients.
class ClientHomeTour {
  ClientHomeTour._();

  static const String _prefPrefix = 'client_home_tour_done_';

  static Future<String> _userKey() async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();
    return '$_prefPrefix${userId.isEmpty ? 'default' : userId}';
  }

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _userKey()) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _userKey(), true);
  }
}

class ClientTourStep {
  final String title;
  final String body;
  final GlobalKey? targetKey;
  final double holeRadius;
  final EdgeInsets holePadding;

  const ClientTourStep({
    required this.title,
    required this.body,
    this.targetKey,
    this.holeRadius = 18,
    this.holePadding = const EdgeInsets.all(8),
  });
}

class ClientHomeTourOverlay extends StatefulWidget {
  final List<ClientTourStep> steps;
  final Future<void> Function(GlobalKey key)? ensureVisible;
  final VoidCallback onFinished;

  const ClientHomeTourOverlay({
    super.key,
    required this.steps,
    required this.onFinished,
    this.ensureVisible,
  });

  @override
  State<ClientHomeTourOverlay> createState() => _ClientHomeTourOverlayState();
}

class _ClientHomeTourOverlayState extends State<ClientHomeTourOverlay>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Rect? _hole;
  late final AnimationController _pulse;

  ClientTourStep get _step => widget.steps[_index];
  bool get _isLast => _index >= widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHole());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _syncHole() async {
    final key = _step.targetKey;
    if (key != null && widget.ensureVisible != null) {
      await widget.ensureVisible!(key);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (!mounted) return;

    final overlayBox = context.findRenderObject() as RenderBox?;
    final targetContext = key?.currentContext;
    final targetBox = targetContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null ||
        !overlayBox.hasSize ||
        targetBox == null ||
        !targetBox.hasSize) {
      setState(() => _hole = null);
      return;
    }

    final topLeft = overlayBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
    final raw = topLeft & targetBox.size;
    final padded = Rect.fromLTRB(
      raw.left - _step.holePadding.left,
      raw.top - _step.holePadding.top,
      raw.right + _step.holePadding.right,
      raw.bottom + _step.holePadding.bottom,
    ).intersect(Offset.zero & overlayBox.size);
    setState(() => _hole = padded);
  }

  Future<void> _goTo(int next) async {
    if (next < 0 || next >= widget.steps.length) {
      await _finish();
      return;
    }
    setState(() {
      _index = next;
      _hole = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHole());
  }

  Future<void> _finish() async {
    await ClientHomeTour.markCompleted();
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SpotlightPainter(
                    hole: _hole,
                    radius: _step.holeRadius,
                    pulse: _hole == null ? 0 : _pulse.value,
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                padding.top + 16,
                20,
                padding.bottom + 16,
              ),
              child: _buildCard(size),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Size size) {
    final card = _TourCard(
      step: _step,
      index: _index,
      total: widget.steps.length,
      isLast: _isLast,
      onSkip: _finish,
      onNext: () => _goTo(_index + 1),
    );

    if (_hole == null) {
      return Center(child: card);
    }

    final hole = _hole!;
    final spaceBelow = size.height - hole.bottom;
    final placeBelow = spaceBelow > 230 || hole.top < 210;

    if (placeBelow) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: (hole.bottom + 16).clamp(0, size.height - 220),
          ),
          child: card,
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          top: (hole.top - 196).clamp(0, size.height - 220),
        ),
        child: card,
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final ClientTourStep step;
  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _TourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1} / $total',
                      style: const TextStyle(
                        color: AppTheme.accentBlue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.mutedGrey,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                step.title,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: const TextStyle(
                  color: Color(0xFF5B6578),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(total, (i) {
                        final active = i == index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.only(right: 5),
                          width: active ? 16 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.navy
                                : const Color(0xFFD5DBE6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.navy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Got it' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final double radius;
  final double pulse;

  _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      scrim.addRRect(RRect.fromRectAndRadius(hole!, Radius.circular(radius)));
      scrim.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      scrim,
      Paint()..color = const Color(0xCC0F1424),
    );

    if (hole == null) return;
    final rrect = RRect.fromRectAndRadius(hole!, Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    final glow = hole!.inflate(5 + (pulse * 6));
    canvas.drawRRect(
      RRect.fromRectAndRadius(glow, Radius.circular(radius + 6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFF60A5FA).withValues(alpha: 0.18 + pulse * 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.hole != hole ||
        oldDelegate.radius != radius ||
        oldDelegate.pulse != pulse;
  }
}
