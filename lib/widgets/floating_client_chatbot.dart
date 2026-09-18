import 'package:flutter/material.dart';

import '../client_chatbot_panel.dart';

enum AssistantBotMood { floating, greeting, thinking }

/// Draggable assistant bubble for the client home dashboard.
class FloatingClientChatbot extends StatefulWidget {
  const FloatingClientChatbot({super.key});

  static const Map<AssistantBotMood, String> assets = {
    AssistantBotMood.floating: 'assets/images/chatbot/bot_head.png',
    AssistantBotMood.greeting: 'assets/images/chatbot/bot_greeting.png',
    AssistantBotMood.thinking: 'assets/images/chatbot/bot_thinking.png',
  };

  @override
  State<FloatingClientChatbot> createState() => _FloatingClientChatbotState();
}

class _FloatingClientChatbotState extends State<FloatingClientChatbot> {
  static const double _size = 64;
  Offset? _offset;
  Offset? _panStart;
  Offset? _offsetAtPanStart;
  bool _dragging = false;
  bool _sheetOpen = false;

  Offset _defaultOffset(Size screen, double bottomSafe) {
    return Offset(
      screen.width - _size - 10,
      screen.height - bottomSafe - 88 - _size,
    );
  }

  void _clampToScreen(Size screen, double bottomSafe, double topSafe) {
    final current = _offset;
    if (current == null) return;
    final minX = 8.0;
    final maxX = screen.width - _size - 8;
    final minY = topSafe + 8;
    final maxY = screen.height - bottomSafe - 64 - _size;
    _offset = Offset(
      current.dx.clamp(minX, maxX < minX ? minX : maxX),
      current.dy.clamp(minY, maxY < minY ? minY : maxY),
    );
  }

  Future<void> _openChatbot() async {
    if (_sheetOpen || _dragging) return;
    setState(() => _sheetOpen = true);
    try {
      await showClientChatbotPanel(context);
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final bottomSafe = media.padding.bottom;
    final topSafe = media.padding.top;
    _offset ??= _defaultOffset(screen, bottomSafe);
    _clampToScreen(screen, bottomSafe, topSafe);
    final pos = _offset!;

    if (_sheetOpen) return const SizedBox.shrink();

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanStart: (details) {
          _panStart = details.globalPosition;
          _offsetAtPanStart = _offset;
          _dragging = false;
        },
        onPanUpdate: (details) {
          final start = _panStart;
          final origin = _offsetAtPanStart;
          if (start == null || origin == null) return;
          final delta = details.globalPosition - start;
          if (!_dragging && delta.distance > 6) {
            _dragging = true;
          }
          if (!_dragging) return;
          setState(() {
            _offset = origin + delta;
            _clampToScreen(screen, bottomSafe, topSafe);
          });
        },
        onPanEnd: (_) async {
          final wasDragging = _dragging;
          _panStart = null;
          _offsetAtPanStart = null;
          _dragging = false;
          if (!wasDragging) {
            await _openChatbot();
          } else if (mounted) {
            setState(() {});
          }
        },
        child: const AssistantBotFace(
          mood: AssistantBotMood.greeting,
          size: _size,
          circle: true,
        ),
      ),
    );
  }
}

class AssistantBotFace extends StatelessWidget {
  const AssistantBotFace({
    super.key,
    required this.mood,
    required this.size,
    this.circle = false,
  });

  final AssistantBotMood mood;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final asset = FloatingClientChatbot.assets[mood]!;
    final picture = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Icon(
        Icons.smart_toy_rounded,
        size: size * 0.55,
        color: const Color(0xFF1B254B),
      ),
    );

    if (!circle) {
      return SizedBox(width: size, height: size, child: picture);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7DEE8), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B254B).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(size * 0.08),
        child: picture,
      ),
    );
  }
}
