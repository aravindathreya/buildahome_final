import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_v1_theme.dart';

/// Shared layout tokens for the WhatsApp-inspired composer.
class ChatComposerTokens {
  static const double outerHMargin = 11;
  static const double outerBottom = 8;
  static const double outerTop = 4;

  static const double barMinHeight = 60;
  static const double barRadius = 26;

  static const double iconCircle = 40;
  static const double iconSize = 22;
  static const double iconGap = 10;
  static const double barInnerH = 8;

  static const double inputPadL = 18;
  static const double inputPadR = 14;
  static const double inputFontSize = 16;

  static const double sendSize = 48;
  static const double sendGap = 10;

  static const Duration anim = Duration(milliseconds: 180);

  static Color barFill(BuildContext context) {
    if (ChatV1Theme.isDark(context)) {
      return const Color(0xFF2A2F36);
    }
    // Soft off-white (not pure white) — WhatsApp-like.
    return const Color(0xFFF0F2F5);
  }

  static List<BoxShadow> barShadow(BuildContext context) {
    final dark = ChatV1Theme.isDark(context);
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.38 : 0.10),
        blurRadius: dark ? 14 : 12,
        offset: const Offset(0, 3),
      ),
      if (!dark)
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
    ];
  }

  static List<BoxShadow> sendShadow(BuildContext context) {
    return [
      BoxShadow(
        color: ChatV1Theme.accent.withValues(alpha: 0.35),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
      BoxShadow(
        color: Colors.black.withValues(
          alpha: ChatV1Theme.isDark(context) ? 0.28 : 0.12,
        ),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }
}

/// Attachment option model — extend this list to add Video, Location, etc.
class AttachmentOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const AttachmentOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

/// Floating WhatsApp-inspired composer.
///
/// ```
///  [  floating bar:  (+)  Type a message…  (📷)  ]  (➤)
/// ```
class ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onDocument;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final List<AttachmentOption> extraAttachmentOptions;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
    required this.onDocument,
    this.onChanged,
    this.enabled = true,
    this.extraAttachmentOptions = const [],
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onControllerTick);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerTick);
      widget.controller.addListener(_onControllerTick);
      _syncHasText();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    super.dispose();
  }

  void _onControllerTick() => _syncHasText();

  void _syncHasText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText && mounted) {
      setState(() => _hasText = next);
    }
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
  }

  Future<void> _openAttachments() async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    await AttachmentBottomSheet.show(
      context,
      options: [
        AttachmentOption(
          id: 'camera',
          label: 'Camera',
          icon: Icons.photo_camera_rounded,
          color: const Color(0xFFEF4444),
          onTap: widget.onCamera,
        ),
        AttachmentOption(
          id: 'gallery',
          label: 'Gallery',
          icon: Icons.photo_library_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: widget.onGallery,
        ),
        AttachmentOption(
          id: 'document',
          label: 'Document',
          icon: Icons.insert_drive_file_rounded,
          color: const Color(0xFF3B82F6),
          onTap: widget.onDocument,
        ),
        ...widget.extraAttachmentOptions,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Transparent float — chat background shows through around the bar.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ChatComposerTokens.outerHMargin,
        ChatComposerTokens.outerTop,
        ChatComposerTokens.outerHMargin,
        ChatComposerTokens.outerBottom + bottomInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: ChatComposerTokens.anim,
              curve: Curves.easeOut,
              constraints: const BoxConstraints(
                minHeight: ChatComposerTokens.barMinHeight,
              ),
              decoration: BoxDecoration(
                color: ChatComposerTokens.barFill(context),
                borderRadius:
                    BorderRadius.circular(ChatComposerTokens.barRadius),
                boxShadow: ChatComposerTokens.barShadow(context),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ChatComposerTokens.barInnerH,
                  // (60 − 40) / 2 → centers 40px circles in a 60px bar.
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AttachmentButton(
                      onTap: _openAttachments,
                      enabled: widget.enabled,
                    ),
                    const SizedBox(width: ChatComposerTokens.iconGap),
                    Expanded(
                      child: ExpandableMessageField(
                        controller: widget.controller,
                        enabled: widget.enabled,
                        onChanged: _handleChanged,
                        onSubmitted: (_) {
                          if (_hasText) widget.onSend();
                        },
                      ),
                    ),
                    CameraButton(
                      visible: !_hasText,
                      onTap: widget.enabled ? widget.onCamera : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SendButton(
            visible: _hasText,
            onTap: widget.enabled ? widget.onSend : null,
          ),
        ],
      ),
    );
  }
}

/// Circular "+" attachment trigger (40×40).
class AttachmentButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool enabled;

  const AttachmentButton({
    super.key,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final muted = ChatV1Theme.textMuted(context);
    return SizedBox(
      width: ChatComposerTokens.iconCircle,
      height: ChatComposerTokens.iconCircle,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Icon(
              Icons.add_rounded,
              size: ChatComposerTokens.iconSize,
              color: enabled ? muted : muted.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto-expanding multiline field (up to 4 lines), vertically centered.
class ExpandableMessageField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const ExpandableMessageField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Single-line text height ≈ 16 * 1.25 = 20; pad to fill the 40px control row.
    const vPad = (ChatComposerTokens.iconCircle - 20) / 2;

    return AnimatedSize(
      duration: ChatComposerTokens.anim,
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: 1,
        maxLines: 4,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          color: ChatV1Theme.text(context),
          fontSize: ChatComposerTokens.inputFontSize,
          height: 1.25,
          fontWeight: FontWeight.w400,
        ),
        cursorColor: ChatV1Theme.accent,
        cursorWidth: 2,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Type a message',
          hintStyle: TextStyle(
            color: ChatV1Theme.textMuted(context),
            fontSize: ChatComposerTokens.inputFontSize,
            height: 1.25,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(
            ChatComposerTokens.inputPadL,
            vPad,
            ChatComposerTokens.inputPadR,
            vPad,
          ),
        ),
      ),
    );
  }
}

/// Camera shortcut — visible only when the composer is empty.
class CameraButton extends StatelessWidget {
  final bool visible;
  final VoidCallback? onTap;

  const CameraButton({
    super.key,
    required this.visible,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: ChatComposerTokens.anim,
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: ChatComposerTokens.anim,
        curve: Curves.easeOut,
        child: visible
            ? Padding(
                padding: const EdgeInsets.only(left: ChatComposerTokens.iconGap),
                child: SizedBox(
                  width: ChatComposerTokens.iconCircle,
                  height: ChatComposerTokens.iconCircle,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onTap,
                      child: Center(
                        child: Icon(
                          Icons.photo_camera_rounded,
                          size: ChatComposerTokens.iconSize,
                          color: ChatV1Theme.textMuted(context),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox(height: ChatComposerTokens.iconCircle),
      ),
    );
  }
}

/// Separate floating send button (48px) with fade + scale entrance.
class SendButton extends StatefulWidget {
  final bool visible;
  final VoidCallback? onTap;

  const SendButton({
    super.key,
    required this.visible,
    this.onTap,
  });

  @override
  State<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ChatComposerTokens.anim,
      value: widget.visible ? 1 : 0,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.55, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  @override
  void didUpdateWidget(covariant SendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
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
      builder: (context, child) {
        final t = _controller.value;
        if (t <= 0.01) {
          // Collapse fully so the floating bar can use full width when empty.
          return const SizedBox(height: ChatComposerTokens.barMinHeight);
        }

        // 48px send in a 60px bar → sit slightly proud / overlapping vertically.
        const verticalNudge =
            (ChatComposerTokens.barMinHeight - ChatComposerTokens.sendSize) / 2;

        return Padding(
          padding: EdgeInsets.only(
            left: ChatComposerTokens.sendGap,
            bottom: verticalNudge,
          ),
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(scale: _scale, child: child),
          ),
        );
      },
      child: Container(
        width: ChatComposerTokens.sendSize,
        height: ChatComposerTokens.sendSize,
        decoration: BoxDecoration(
          color: ChatV1Theme.accent,
          shape: BoxShape.circle,
          boxShadow: ChatComposerTokens.sendShadow(context),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            },
            child: const Center(
              child: Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: ChatComposerTokens.iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modern, extensible attachment picker bottom sheet.
class AttachmentBottomSheet extends StatelessWidget {
  final List<AttachmentOption> options;

  const AttachmentBottomSheet({
    super.key,
    required this.options,
  });

  static Future<void> show(
    BuildContext context, {
    required List<AttachmentOption> options,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      transitionAnimationController: null,
      builder: (sheetContext) {
        return AnimatedPadding(
          duration: ChatComposerTokens.anim,
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: AttachmentBottomSheet(options: options),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: Material(
        color: ChatV1Theme.secondary(context),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ChatV1Theme.border(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Share',
                  style: TextStyle(
                    color: ChatV1Theme.text(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 520 ? 4 : 3;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: options.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.92,
                    ),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return _AttachmentTile(
                        option: option,
                        onTap: () {
                          Navigator.of(context).pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            option.onTap();
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final AttachmentOption option;
  final VoidCallback onTap;

  const _AttachmentTile({
    required this.option,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: option.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(option.icon, color: option.color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ChatV1Theme.textSecondary(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
