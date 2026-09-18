import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'FullScreenImage.dart';
import 'models/mobile_chatbot.dart';
import 'services/mobile_chatbot_service.dart';
import 'services/session_manager.dart';
import 'widgets/floating_client_chatbot.dart';

Future<void> showClientChatbotPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const ClientChatbotPanel(),
  );
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.fromBot,
    this.quickReplies = const [],
    this.stage,
  });

  final String text;
  final bool fromBot;
  final List<String> quickReplies;
  final MobileChatbotStage? stage;
}

class ClientChatbotPanel extends StatefulWidget {
  const ClientChatbotPanel({super.key});

  @override
  State<ClientChatbotPanel> createState() => _ClientChatbotPanelState();
}

class _ClientChatbotPanelState extends State<ClientChatbotPanel> {
  static const Color _navy = Color(0xFF1B254B);
  static const Color _muted = Color(0xFF8A94A6);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<_ChatMessage> _messages = [];
  bool _botTyping = false;
  Map<String, dynamic>? _conversation;

  @override
  void initState() {
    super.initState();
    _loadGreeting();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadGreeting() async {
    setState(() => _botTyping = true);
    try {
      final greeting = await MobileChatbotService.instance.fetchGreeting();
      if (!mounted) return;
      final message = _ChatMessage(
        text: greeting.greeting,
        fromBot: true,
        quickReplies: greeting.questions,
      );
      setState(() {
        if (_messages.isEmpty) {
          _messages.add(message);
        } else {
          _messages.insert(0, message);
        }
        _botTyping = false;
      });
    } on SessionInvalidatedException {
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_messages.isEmpty) {
          _messages.add(
            const _ChatMessage(
              text: MobileChatbotGreeting.fallbackGreeting,
              fromBot: true,
              quickReplies: MobileChatbotGreeting.fallbackQuestions,
            ),
          );
        }
        _botTyping = false;
      });
    }
    await _scrollToBottom();
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _botTyping) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, fromBot: false));
      _botTyping = true;
    });
    await _scrollToBottom();

    try {
      final result = await MobileChatbotService.instance.ask(
        question: text,
        conversation: _conversation,
      );
      if (!mounted) return;
      if (result.success && result.conversation != null) {
        _conversation = result.conversation;
      }
      setState(() {
        _botTyping = false;
        _messages.add(
          _ChatMessage(
            text: result.text,
            fromBot: true,
            stage: result.stage,
          ),
        );
      });
    } on SessionInvalidatedException {
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _botTyping = false;
        _messages.add(
          const _ChatMessage(
            text: 'Could not reach the assistant. Try again.',
            fromBot: true,
          ),
        );
      });
    }
    await _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height * 0.86;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DEE8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    AssistantBotFace(
                      key: ValueKey(_botTyping),
                      mood: _botTyping
                          ? AssistantBotMood.thinking
                          : AssistantBotMood.greeting,
                      size: 56,
                      circle: true,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Home Assistant',
                            style: TextStyle(
                              color: _navy,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Ask anything about your home journey',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded, color: _muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEF1F5)),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  itemCount: _messages.length + (_botTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_botTyping && index == _messages.length) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: _TypingBubble(),
                        ),
                      );
                    }
                    final message = _messages[index];
                    return _MessageBlock(
                      message: message,
                      onQuickReply: _send,
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: !_botTyping,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          decoration: InputDecoration(
                            hintText: 'Ask your assistant…',
                            hintStyle: const TextStyle(color: _muted),
                            filled: true,
                            fillColor: const Color(0xFFF5F7FA),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: _botTyping
                            ? _navy.withValues(alpha: 0.45)
                            : _navy,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _botTyping
                              ? null
                              : () => _send(_controller.text),
                          child: const SizedBox(
                            width: 46,
                            height: 46,
                            child: Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
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
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.message,
    required this.onQuickReply,
  });

  final _ChatMessage message;
  final Future<void> Function(String) onQuickReply;

  @override
  Widget build(BuildContext context) {
    final align =
        message.fromBot ? Alignment.centerLeft : Alignment.centerRight;
    final bg = message.fromBot
        ? const Color(0xFFF3F6FB)
        : const Color(0xFF1B254B);
    final fg = message.fromBot ? const Color(0xFF1B254B) : Colors.white;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              message.fromBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (message.fromBot &&
                message.stage != null &&
                message.stage!.hasContent) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _StageCard(stage: message.stage!),
              ),
              const SizedBox(height: 8),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(message.fromBot ? 4 : 16),
                    bottomRight: Radius.circular(message.fromBot ? 16 : 4),
                  ),
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (message.fromBot && message.quickReplies.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reply in message.quickReplies)
                    ActionChip(
                      label: Text(
                        reply,
                        style: const TextStyle(
                          color: Color(0xFF1B254B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFD7DEE8)),
                      onPressed: () => onQuickReply(reply),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage});

  final MobileChatbotStage stage;

  @override
  Widget build(BuildContext context) {
    final images = stage.images
        .where((image) => image.isVisual && image.url.isNotEmpty)
        .toList();
    final urls = images.map((image) => image.url).toList();
    final tracker = stage.tracker;
    final percent = tracker.percent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stage.name.isNotEmpty)
            Text(
              stage.name,
              style: const TextStyle(
                color: Color(0xFF1B254B),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (tracker.label.isNotEmpty) ...[
            if (stage.name.isNotEmpty) const SizedBox(height: 4),
            Text(
              tracker.label,
              style: const TextStyle(
                color: Color(0xFF8A94A6),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (percent != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (percent / 100).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFEEF1F5),
                      color: const Color(0xFF1B254B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${percent.round()}%',
                  style: const TextStyle(
                    color: Color(0xFF1B254B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = images[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullScreenImage(
                            image.url,
                            imageUrls: urls,
                            initialIndex: index,
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: image.url,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 88,
                          height: 88,
                          color: const Color(0xFFF3F6FB),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 88,
                          height: 88,
                          color: const Color(0xFFF3F6FB),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF8A94A6),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(delayMs: 0),
          SizedBox(width: 4),
          _Dot(delayMs: 120),
          SizedBox(width: 4),
          _Dot(delayMs: 240),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delayMs});
  final int delayMs;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF8A94A6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
