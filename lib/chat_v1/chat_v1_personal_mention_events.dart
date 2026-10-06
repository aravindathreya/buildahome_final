import 'chat_v1_models.dart';

class _PendingPersonalMention {
  final String conversationId;
  final String userId;

  const _PendingPersonalMention(this.conversationId, this.userId);
}

/// Matches an authenticated personal mention event to its message without a
/// network request. Events may arrive before or after message_created.
class ChatV1PersonalMentionEvents {
  final int _maxPending;
  final Map<String, _PendingPersonalMention> _pending = {};

  ChatV1PersonalMentionEvents({int maxPending = 128})
      : _maxPending = maxPending {
    if (maxPending < 1) {
      throw ArgumentError.value(maxPending, 'maxPending', 'Must be positive');
    }
  }

  int get pendingCount => _pending.length;

  /// Only the canonical server event addressed to this person and conversation
  /// can establish a personal mention. Body text is never used as evidence.
  String? record(
    Map<String, dynamic>? event, {
    required String conversationId,
    required String currentUserId,
  }) {
    final mention = event?['mention'];
    if (mention is! Map) return null;
    final recipient = _id(mention['mentioned_user_id']);
    final conversation = _id(mention['conversation_id']);
    final messageId = _id(mention['message_id']);
    final me = currentUserId.trim();
    final activeConversation = conversationId.trim();
    if (me.isEmpty ||
        activeConversation.isEmpty ||
        messageId.isEmpty ||
        recipient != me ||
        conversation != activeConversation) {
      return null;
    }
    _pending[messageId] = _PendingPersonalMention(conversation, recipient);
    while (_pending.length > _maxPending) {
      _pending.remove(_pending.keys.first);
    }
    return messageId;
  }

  /// Consume a matching event once, retaining all existing message metadata.
  /// A confirmed event can fill missing mention details even when a partial
  /// message event supplied an empty list. Without that event nothing changes.
  ChatV1Message apply(
    ChatV1Message message, {
    required String currentUserId,
    String? currentUserName,
  }) {
    final pending = _pending[message.id];
    final me = currentUserId.trim();
    if (pending == null || me.isEmpty || pending.userId != me) return message;
    final messageConversation = (message.conversationId ?? '').trim();
    if (messageConversation.isNotEmpty &&
        messageConversation != pending.conversationId) {
      return message;
    }
    _pending.remove(message.id);
    if (message.isMine ||
        message.isDeleted ||
        message.mentions.any((mention) => mention.userId == me)) {
      return message;
    }
    final name = currentUserName?.trim();
    return message.copyWith(
      mentions: [
        ...message.mentions,
        ChatV1Mention(
          userId: me,
          name: name == null || name.isEmpty ? null : name,
        ),
      ],
      mentionsResolved: true,
    );
  }

  static String _id(dynamic value) =>
      value is String || value is num ? value.toString().trim() : '';
}
