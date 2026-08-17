import 'package:flutter/material.dart';

import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import 'chat_v1_common.dart';

/// Web-parity Project / Workflow task row for Chat V1.
class Cv1TaskCard extends StatelessWidget {
  final ChatV1TaskItem task;
  final VoidCallback onOpen;

  const Cv1TaskCard({super.key, required this.task, required this.onOpen});

  Color _statusColor(ChatV1TaskStatus s) {
    switch (s) {
      case ChatV1TaskStatus.pending:
        return ChatV1Theme.pending;
      case ChatV1TaskStatus.completed:
        return ChatV1Theme.completed;
      case ChatV1TaskStatus.rejected:
        return ChatV1Theme.rejected;
      case ChatV1TaskStatus.inProgress:
        return ChatV1Theme.accent;
    }
  }

  String _statusLabel(ChatV1TaskStatus s) {
    switch (s) {
      case ChatV1TaskStatus.pending:
        return 'pending';
      case ChatV1TaskStatus.completed:
        return 'completed';
      case ChatV1TaskStatus.rejected:
        return 'rejected';
      case ChatV1TaskStatus.inProgress:
        return 'in progress';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
    return Container(
      decoration: BoxDecoration(
        color: ChatV1Theme.card(context),
        borderRadius: BorderRadius.circular(ChatV1Theme.rLg),
        border: Border.all(color: ChatV1Theme.border(context)),
        boxShadow: ChatV1Theme.shadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ChatV1Theme.rLg),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.kindLabel,
                        style: TextStyle(
                          color: ChatV1Theme.textMuted(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (task.unread > 0) Cv1UnreadBadge(count: task.unread),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ChatV1Theme.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (task.assigneeLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    task.assigneeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ChatV1Theme.textSecondary(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Cv1Badge(
                      label: _statusLabel(task.status),
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  task.hasMessages
                      ? (task.lastMessagePreview ?? '')
                      : 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: task.hasMessages
                        ? ChatV1Theme.textSecondary(context)
                        : ChatV1Theme.textMuted(context),
                    fontSize: 12.5,
                    fontStyle:
                        task.hasMessages ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
                if (task.lastActivity != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    ChatV1Utils.timeAgo(task.lastActivity!),
                    style: TextStyle(
                      color: ChatV1Theme.textMuted(context),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
