import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_navigator.dart';
import '../../app_theme.dart';
import '../../widgets/dashboard_chrome.dart';

/// Full-screen chat splash over [child], then fades away — same pattern as
/// attendance check-in.
class ChatV1OpenSplash extends StatefulWidget {
  final Widget child;

  const ChatV1OpenSplash({
    super.key,
    required this.child,
  });

  /// Push chat with the branded splash (own route + chrome).
  static Future<void> push(
    BuildContext context, {
    required Widget chat,
    DashboardChromeStyle chromeStyle = DashboardChromeStyle.user,
  }) async {
    if (!NavigationDebounce.tryAcquire()) return;
    NavigationDebounce.beginPush();
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) {
            return ChatV1OpenSplash(
              child: DashboardChrome.wrap(chromeStyle, chat),
            );
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
  State<ChatV1OpenSplash> createState() => _ChatV1OpenSplashState();
}

class _ChatV1OpenSplashState extends State<ChatV1OpenSplash>
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
          widget.child,
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final opacity = _splashOpacity.value;
              if (opacity <= 0.01) return const SizedBox.shrink();
              return IgnorePointer(
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: const _ChatSplashBackdrop(),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              if (_splashOpacity.value <= 0.01) return const SizedBox.shrink();
              return IgnorePointer(
                child: Opacity(
                  opacity: _splashOpacity.value,
                  child: _ChatSplashScene(progress: _controller.value),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChatSplashBackdrop extends StatelessWidget {
  const _ChatSplashBackdrop();

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

class _ChatSplashScene extends StatelessWidget {
  final double progress;

  const _ChatSplashScene({required this.progress});

  double _span(double start, double end) {
    if (progress <= start) return 0;
    if (progress >= end) return 1;
    final t = (progress - start) / (end - start);
    return Curves.easeInOut.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final bubbleA = _span(0.06, 0.22);
    final bubbleB = _span(0.18, 0.34);
    final bubbleC = _span(0.30, 0.48);
    final typing = _span(0.46, 0.62);
    final badge = _span(0.58, 0.74);
    final caption = _span(0.10, 0.26);
    final glow = 0.55 + 0.45 * _span(0.2, 0.7);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 280,
            height: 250,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.accentBlue.withValues(alpha: 0.28 * glow),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  child: _ChatPhone(
                    glow: glow,
                    bubbleA: bubbleA,
                    bubbleB: bubbleB,
                    bubbleC: bubbleC,
                    typing: typing,
                    progress: progress,
                  ),
                ),
                Positioned(
                  right: 48,
                  top: 18,
                  child: Transform.scale(
                    scale: badge,
                    child: Opacity(
                      opacity: badge,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34D399),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF34D399)
                                  .withValues(alpha: 0.45),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.white,
                          size: 18,
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
              'Opening chat',
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
}

class _ChatPhone extends StatelessWidget {
  final double glow;
  final double bubbleA;
  final double bubbleB;
  final double bubbleC;
  final double typing;
  final double progress;

  const _ChatPhone({
    required this.glow,
    required this.bubbleA,
    required this.bubbleB,
    required this.bubbleC,
    required this.typing,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.25 * glow),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          children: [
            Container(
              height: 36,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.navy, AppTheme.accentBlue],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Center(
                child: Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFEEF2FF),
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MessageBubble(
                      alignEnd: false,
                      width: 78,
                      progress: bubbleA,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _MessageBubble(
                        alignEnd: true,
                        width: 64,
                        progress: bubbleB,
                        color: AppTheme.accentBlue.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MessageBubble(
                      alignEnd: false,
                      width: 92,
                      progress: bubbleC,
                      color: Colors.white,
                    ),
                    const Spacer(),
                    Opacity(
                      opacity: typing.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - typing) * 8),
                        child: _TypingDots(progress: progress),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool alignEnd;
  final double width;
  final double progress;
  final Color color;

  const _MessageBubble({
    required this.alignEnd,
    required this.width,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset((alignEnd ? 18 : -18) * (1 - t), (1 - t) * 10),
        child: Transform.scale(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          scale: 0.86 + 0.14 * t,
          child: Container(
            width: width,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(alignEnd ? 14 : 4),
                bottomRight: Radius.circular(alignEnd ? 4 : 14),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  final double progress;

  const _TypingDots({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final phase = ((progress * 4) + i * 0.22) % 1.0;
          final bounce = math.sin(phase * math.pi);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Transform.translate(
              offset: Offset(0, -3.5 * bounce),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.navy.withValues(alpha: 0.45 + 0.4 * bounce),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
