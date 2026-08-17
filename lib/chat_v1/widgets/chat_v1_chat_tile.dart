import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import 'chat_v1_common.dart';

class Cv1ChatTile extends StatelessWidget {
  final ChatV1ChatItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPin;
  final VoidCallback? onMute;
  final VoidCallback? onMarkRead;

  const Cv1ChatTile({
    super.key,
    required this.item,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
    this.onPin,
    this.onMute,
    this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final unread = item.unread > 0;

    return Dismissible(
      key: ValueKey('swipe_${item.id}_${item.isPinned}_${item.isMuted}'),
      background: _swipeBg(
        context,
        alignment: Alignment.centerLeft,
        color: ChatV1Theme.accent,
        icon: item.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        label: item.isPinned ? 'Unpin' : 'Pin',
      ),
      secondaryBackground: _swipeBg(
        context,
        alignment: Alignment.centerRight,
        color: ChatV1Theme.pending,
        icon: item.isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        label: item.isMuted ? 'Unmute' : 'Mute',
      ),
      confirmDismiss: (dir) async {
        HapticFeedback.selectionClick();
        if (dir == DismissDirection.startToEnd) {
          onPin?.call();
        } else {
          onMute?.call();
        }
        return false;
      },
      child: Material(
        color: selected
            ? ChatV1Theme.accentSoft
            : ChatV1Theme.bg(context),
        child: InkWell(
          onTap: onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onLongPress?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: Row(
              children: [
                Cv1Avatar(
                  initials: item.initials ??
                      (item.title.isNotEmpty ? item.title[0].toUpperCase() : '?'),
                  color: item.accent,
                  online: item.isOnline,
                  icon: item.initials == null ? item.icon : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (item.isPinned) ...[
                            Icon(Icons.push_pin_rounded,
                                size: 13, color: ChatV1Theme.textMuted(context)),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ChatV1Theme.text(context),
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            ChatV1Utils.timeAgo(item.lastActivity),
                            style: TextStyle(
                              color: unread
                                  ? ChatV1Theme.unread
                                  : ChatV1Theme.textMuted(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.isMuted)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.volume_off_rounded,
                                  size: 14,
                                  color: ChatV1Theme.textMuted(context)),
                            ),
                          if (item.opensAs == ChatV1OpensAs.taskList ||
                              item.opensAs == ChatV1OpensAs.docList)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                item.opensAs == ChatV1OpensAs.docList
                                    ? Icons.description_outlined
                                    : Icons.layers_outlined,
                                size: 14,
                                color: ChatV1Theme.textMuted(context),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              item.isTyping ? 'typing…' : item.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: item.isTyping
                                    ? ChatV1Theme.accent
                                    : ChatV1Theme.textSecondary(context),
                                fontSize: 14,
                                fontStyle: item.isTyping
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                fontWeight: unread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (item.mentions > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: ChatV1Theme.mention,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                '@',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Cv1UnreadBadge(count: item.unread),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBg(
    BuildContext context, {
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
