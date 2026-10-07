import 'package:flutter/material.dart';

import '../chat_v1_project_summaries.dart';
import '../chat_v1_theme.dart';

/// Unread chat total for a dashboard Chat shortcut. Hidden at zero.
class ChatV1UnreadCountBadge extends StatelessWidget {
  final Color ringColor;

  const ChatV1UnreadCountBadge({super.key, required this.ringColor});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatProjectSummaryStore.instance.totalUnread,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ChatV1Theme.unread,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: ringColor, width: 2),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        );
      },
    );
  }
}
