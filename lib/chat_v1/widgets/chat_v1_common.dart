import 'package:flutter/material.dart';

import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';

class Cv1Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  final bool online;
  final IconData? icon;

  const Cv1Avatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 50,
    this.online = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, color: color, size: size * 0.42)
                : Text(
                    initials,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.32,
                    ),
                  ),
          ),
          if (online)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  color: ChatV1Theme.unread,
                  shape: BoxShape.circle,
                  border: Border.all(color: ChatV1Theme.bg(context), width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class Cv1Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  const Cv1Badge({
    super.key,
    required this.label,
    required this.color,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class Cv1UnreadBadge extends StatelessWidget {
  final int count;
  const Cv1UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ChatV1Theme.unread,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class Cv1SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;

  const Cv1SearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      style: TextStyle(color: ChatV1Theme.text(context), fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ChatV1Theme.textMuted(context)),
        prefixIcon:
            Icon(Icons.search_rounded, color: ChatV1Theme.textMuted(context)),
        filled: true,
        fillColor: ChatV1Theme.isDark(context)
            ? ChatV1Theme.darkCard
            : const Color(0xFFE8ECF1),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ChatV1Theme.accent, width: 1.2),
        ),
      ),
    );
  }
}

class Cv1SectionHeader extends StatelessWidget {
  final String label;
  const Cv1SectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: ChatV1Theme.accent,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class Cv1FilterChips extends StatelessWidget {
  final ChatV1Filter selected;
  final ValueChanged<ChatV1Filter> onChanged;

  const Cv1FilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  String _label(ChatV1Filter f) {
    switch (f) {
      case ChatV1Filter.all:
        return 'All';
      case ChatV1Filter.groups:
        return 'Groups';
      case ChatV1Filter.tasks:
        return 'Tasks';
      case ChatV1Filter.unread:
        return 'Unread';
    }
  }

  @override
  Widget build(BuildContext context) {
    const items = ChatV1Filter.values;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final item = items[i];
          final active = item == selected;
          return GestureDetector(
            onTap: () => onChanged(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? ChatV1Theme.accentSoft
                    : (ChatV1Theme.isDark(context)
                        ? ChatV1Theme.darkCard
                        : const Color(0xFFE8ECF1)),
                borderRadius: BorderRadius.circular(999),
                border: active
                    ? Border.all(
                        color: ChatV1Theme.accent.withValues(alpha: 0.45))
                    : null,
              ),
              child: Text(
                _label(item),
                style: TextStyle(
                  color: active
                      ? ChatV1Theme.accent
                      : ChatV1Theme.textSecondary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
