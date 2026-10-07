/// Groups chat pushes per conversation so a busy thread updates one
/// notification instead of stacking a new one for every message.
class ChatPushIncoming {
  final String conversationId;
  final String senderName;
  final String preview;
  final String? senderId;
  final String? currentUserId;
  final String? openConversationId;
  final String? conversationTitle;
  final String? messageId;
  final String? messageType;
  final bool fromMe;
  final bool isGroup;

  const ChatPushIncoming({
    required this.conversationId,
    required this.senderName,
    required this.preview,
    this.senderId,
    this.currentUserId,
    this.openConversationId,
    this.conversationTitle,
    this.messageId,
    this.messageType,
    this.fromMe = false,
    this.isGroup = false,
  });
}

class ChatPushThread {
  final String conversationId;
  String title;
  final List<String> lines;
  final List<String> seenMessageIds;
  int count;
  bool isGroup;

  ChatPushThread({
    required this.conversationId,
    required this.title,
    List<String>? lines,
    List<String>? seenMessageIds,
    this.count = 0,
    this.isGroup = false,
  })  : lines = lines ?? <String>[],
        seenMessageIds = seenMessageIds ?? <String>[];

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'title': title,
        'lines': lines,
        'seen': seenMessageIds,
        'count': count,
        'is_group': isGroup,
      };

  factory ChatPushThread.fromJson(Map<String, dynamic> json) {
    final lines = json['lines'];
    final seen = json['seen'];
    return ChatPushThread(
      conversationId: (json['conversation_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      lines: lines is List ? lines.map((e) => e.toString()).toList() : <String>[],
      seenMessageIds:
          seen is List ? seen.map((e) => e.toString()).toList() : <String>[],
      count: int.tryParse('${json['count']}') ?? 0,
      isGroup: json['is_group'] == true,
    );
  }
}

class ChatPushNotice {
  final int notificationId;
  final String conversationId;
  final String title;
  final String body;
  final List<String> lines;
  final Map<String, String> payload;
  final int count;
  final bool clearExisting;

  const ChatPushNotice({
    required this.notificationId,
    required this.conversationId,
    required this.title,
    required this.body,
    required this.lines,
    required this.payload,
    this.count = 0,
    this.clearExisting = false,
  });
}

class ChatPushGrouper {
  static const int inboxLimit = 7;
  static const int seenLimit = 40;

  static int idForConversation(String conversationId) =>
      conversationId.hashCode & 0x7fffffff;

  /// Updates [threads] in place.
  ///
  /// Returns null when the user must not be notified (their own message,
  /// the conversation they already have open, or a duplicate delivery).
  /// A notice with [ChatPushNotice.clearExisting] means any grouped
  /// notification for that conversation should be removed.
  static ChatPushNotice? record({
    required Map<String, ChatPushThread> threads,
    required ChatPushIncoming incoming,
  }) {
    final conversationId = incoming.conversationId.trim();
    if (conversationId.isEmpty) return null;

    final type = (incoming.messageType ?? '').trim().toLowerCase();
    if (type == 'system' || type == 'pinned') return null;

    if (incoming.fromMe || _isSelf(incoming)) {
      return null;
    }

    final openId = (incoming.openConversationId ?? '').trim();
    if (openId.isNotEmpty && openId == conversationId) {
      threads.remove(conversationId);
      return ChatPushNotice(
        notificationId: idForConversation(conversationId),
        conversationId: conversationId,
        title: '',
        body: '',
        lines: const [],
        payload: const {},
        clearExisting: true,
      );
    }

    final messageId = (incoming.messageId ?? '').trim();
    final existing = threads[conversationId];
    if (messageId.isNotEmpty &&
        existing != null &&
        existing.seenMessageIds.contains(messageId)) {
      return _noticeFor(existing);
    }

    final sender = incoming.senderName.trim().isEmpty
        ? 'Someone'
        : incoming.senderName.trim();
    final preview = _clip(
      incoming.preview.trim().isEmpty ? 'New message' : incoming.preview.trim(),
    );
    // Socket.IO and FCM can both deliver the same message. When the push
    // has no message id, an identical latest line is the same delivery.
    if (messageId.isEmpty &&
        existing != null &&
        existing.lines.isNotEmpty &&
        existing.lines.last == '$sender: $preview') {
      return _noticeFor(existing);
    }
    final title = incoming.isGroup
        ? ((incoming.conversationTitle ?? '').trim().isEmpty
            ? 'Group chat'
            : incoming.conversationTitle!.trim())
        : sender;

    final thread = existing ??
        ChatPushThread(
          conversationId: conversationId,
          title: title,
          isGroup: incoming.isGroup,
        );
    thread.title = title;
    thread.isGroup = incoming.isGroup;
    thread.count += 1;
    thread.lines.add('$sender: $preview');
    if (thread.lines.length > inboxLimit) {
      thread.lines.removeRange(0, thread.lines.length - inboxLimit);
    }
    if (messageId.isNotEmpty) {
      thread.seenMessageIds.add(messageId);
      if (thread.seenMessageIds.length > seenLimit) {
        thread.seenMessageIds.removeRange(
          0,
          thread.seenMessageIds.length - seenLimit,
        );
      }
    }
    threads[conversationId] = thread;
    return _noticeFor(thread);
  }

  static ChatPushNotice? clear({
    required Map<String, ChatPushThread> threads,
    required String conversationId,
  }) {
    final id = conversationId.trim();
    if (id.isEmpty || !threads.containsKey(id)) {
      if (id.isEmpty) return null;
      return ChatPushNotice(
        notificationId: idForConversation(id),
        conversationId: id,
        title: '',
        body: '',
        lines: const [],
        payload: const {},
        clearExisting: true,
      );
    }
    threads.remove(id);
    return ChatPushNotice(
      notificationId: idForConversation(id),
      conversationId: id,
      title: '',
      body: '',
      lines: const [],
      payload: const {},
      clearExisting: true,
    );
  }

  static bool _isSelf(ChatPushIncoming incoming) {
    final me = (incoming.currentUserId ?? '').trim();
    final sender = (incoming.senderId ?? '').trim();
    return me.isNotEmpty && sender.isNotEmpty && me == sender;
  }

  static ChatPushNotice _noticeFor(ChatPushThread thread) {
    final lastLine = thread.lines.isEmpty ? 'New message' : thread.lines.last;
    final marker = lastLine.indexOf(': ');
    final single = marker >= 0 ? lastLine.substring(marker + 2) : lastLine;
    final body = thread.count <= 1 ? single : '${thread.count} new messages';
    return ChatPushNotice(
      notificationId: idForConversation(thread.conversationId),
      conversationId: thread.conversationId,
      title: thread.title,
      body: body,
      lines: List<String>.unmodifiable(thread.lines),
      count: thread.count,
      payload: {
        'type': 'chat',
        'conversation_id': thread.conversationId,
        'title': thread.title,
      },
    );
  }

  static String _clip(String value) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 140) return singleLine;
    return '${singleLine.substring(0, 137)}...';
  }
}
