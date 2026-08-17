import 'package:flutter/material.dart';

enum ChatV1Filter { all, groups, tasks, unread }

enum ChatV1OpensAs { conversation, taskList, docList }


enum ChatV1MsgType {
  text,
  image,
  video,
  document,
  pdf,
  approval,
  workflow,
  differenceOfCost,
  purchaseOrder,
  indent,
  siteUpdate,
  system,
  pinned,
  taskAssignment,
}

enum ChatV1TaskStatus { pending, completed, rejected, inProgress }

class ChatV1ChatItem {
  final String id;
  final String title;
  final String subtitle;
  final String lastMessage;
  final DateTime lastActivity;
  final IconData icon;
  final Color accent;
  final int unread;
  final int mentions;
  final bool isFixed;
  final bool isPinned;
  final bool isMuted;
  final bool isOnline;
  final bool isTyping;
  final bool isDm;
  final bool isTaskHub;
  final ChatV1OpensAs opensAs;
  final String? initials;
  final String? conversationType;
  final String? contextType;
  final String? contextId;
  final int participantCount;
  final String? myRole;
  final String? hubKind; // 'tasks' | 'workflows'

  const ChatV1ChatItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lastMessage,
    required this.lastActivity,
    required this.icon,
    required this.accent,
    this.unread = 0,
    this.mentions = 0,
    this.isFixed = false,
    this.isPinned = false,
    this.isMuted = false,
    this.isOnline = false,
    this.isTyping = false,
    this.isDm = false,
    this.isTaskHub = false,
    this.opensAs = ChatV1OpensAs.conversation,
    this.initials,
    this.conversationType,
    this.contextType,
    this.contextId,
    this.participantCount = 0,
    this.myRole,
    this.hubKind,
  });

  ChatV1ChatItem copyWith({
    int? unread,
    bool? isPinned,
    bool? isMuted,
    bool? isTyping,
    String? lastMessage,
    DateTime? lastActivity,
  }) {
    return ChatV1ChatItem(
      id: id,
      title: title,
      subtitle: subtitle,
      lastMessage: lastMessage ?? this.lastMessage,
      lastActivity: lastActivity ?? this.lastActivity,
      icon: icon,
      accent: accent,
      unread: unread ?? this.unread,
      mentions: mentions,
      isFixed: isFixed,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isOnline: isOnline,
      isTyping: isTyping ?? this.isTyping,
      isDm: isDm,
      isTaskHub: isTaskHub,
      opensAs: opensAs,
      initials: initials,
      conversationType: conversationType,
      contextType: contextType,
      contextId: contextId,
      participantCount: participantCount,
      myRole: myRole,
      hubKind: hubKind,
    );
  }
}

class ChatV1Member {
  final String id;
  final String name;
  final String role;
  final String initials;
  final Color color;
  final bool online;
  final String? email;

  const ChatV1Member({
    required this.id,
    required this.name,
    required this.role,
    required this.initials,
    required this.color,
    this.online = false,
    this.email,
  });
}

class ChatV1Reaction {
  final String emoji;
  final int count;
  final bool mine;
  const ChatV1Reaction({
    required this.emoji,
    required this.count,
    this.mine = false,
  });
}

class ChatV1Mention {
  final String userId;
  final String? name;
  const ChatV1Mention({
    required this.userId,
    this.name,
  });
}

class ChatV1ReadSummary {
  final int readCount;
  final List<Map<String, dynamic>> reads;
  const ChatV1ReadSummary({
    this.readCount = 0,
    this.reads = const [],
  });

  factory ChatV1ReadSummary.empty() =>
      const ChatV1ReadSummary(readCount: 0, reads: []);
}

class ChatV1Message {
  final String id;
  final String authorId;
  final String authorName;
  final String authorInitials;
  final Color authorColor;
  final String body;
  final DateTime sentAt;
  final ChatV1MsgType type;
  final bool isMine;
  final bool delivered;
  final bool read;
  final bool edited;
  final bool isPinned;
  final String? replyPreview;
  final String? fileName;
  final String? fileMeta;
  final List<ChatV1Reaction> reactions;
  final Map<String, dynamic>? card;
  final String? parentMessageId;
  final bool isDeleted;
  final String? conversationId;
  final String? senderRole;
  final List<ChatV1Attachment> attachments;
  final List<ChatV1Mention> mentions;
  final ChatV1ReadSummary readSummary;

  const ChatV1Message({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorInitials,
    required this.authorColor,
    required this.body,
    required this.sentAt,
    required this.type,
    this.isMine = false,
    this.delivered = true,
    this.read = false,
    this.edited = false,
    this.isPinned = false,
    this.replyPreview,
    this.fileName,
    this.fileMeta,
    this.reactions = const [],
    this.card,
    this.parentMessageId,
    this.isDeleted = false,
    this.conversationId,
    this.senderRole,
    this.attachments = const [],
    this.mentions = const [],
    this.readSummary = const ChatV1ReadSummary(),
  });

  String get copyableText {
    if (body.trim().isNotEmpty &&
        !body.trim().toLowerCase().startsWith('uploaded:')) {
      return body;
    }
    if (fileName != null && fileName!.isNotEmpty) return fileName!;
    return body;
  }

  ChatV1Message copyWith({
    List<ChatV1Attachment>? attachments,
    ChatV1MsgType? type,
    String? fileName,
    String? fileMeta,
    String? body,
    bool? edited,
    bool? isPinned,
    bool? isDeleted,
    bool? read,
    String? replyPreview,
    String? parentMessageId,
    List<ChatV1Reaction>? reactions,
    List<ChatV1Mention>? mentions,
    ChatV1ReadSummary? readSummary,
  }) {
    return ChatV1Message(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorInitials: authorInitials,
      authorColor: authorColor,
      body: body ?? this.body,
      sentAt: sentAt,
      type: type ?? this.type,
      isMine: isMine,
      delivered: delivered,
      read: read ?? this.read,
      edited: edited ?? this.edited,
      isPinned: isPinned ?? this.isPinned,
      replyPreview: replyPreview ?? this.replyPreview,
      fileName: fileName ?? this.fileName,
      fileMeta: fileMeta ?? this.fileMeta,
      reactions: reactions ?? this.reactions,
      card: card,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      isDeleted: isDeleted ?? this.isDeleted,
      conversationId: conversationId,
      senderRole: senderRole,
      attachments: attachments ?? this.attachments,
      mentions: mentions ?? this.mentions,
      readSummary: readSummary ?? this.readSummary,
    );
  }
}

class ChatV1Attachment {
  final String id;
  final String? messageId;
  final String fileName;
  final String contentType;
  final int fileSize;
  final String storagePath;

  /// Local-only bytes for instant preview before / without network.
  final List<int>? previewBytes;

  const ChatV1Attachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.storagePath,
    this.messageId,
    this.fileSize = 0,
    this.previewBytes,
  });

  bool get isImage {
    if (contentType.toLowerCase().startsWith('image/')) return true;
    final n = fileName.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif') ||
        n.endsWith('.heic') ||
        n.endsWith('.bmp');
  }

  bool get isVideo => contentType.toLowerCase().startsWith('video/');
  bool get isPdf =>
      contentType.toLowerCase().contains('pdf') ||
      fileName.toLowerCase().endsWith('.pdf');

  String get displayExt {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      if (isPdf) return 'PDF';
      if (isImage) return 'IMG';
      return 'FILE';
    }
    return fileName.substring(dot + 1).toUpperCase();
  }
}

/// Preview text for conversation list rows (avoids Dart records for SDK 2.17).
class ChatV1LastMessagePreview {
  final String label;
  final bool isEmpty;
  const ChatV1LastMessagePreview({
    required this.label,
    required this.isEmpty,
  });
}

class ChatV1TaskItem {
  final String id;
  final String title;
  final String category;
  final ChatV1TaskStatus status;
  final int unread;
  final int discussions;
  final String assignee;
  final String assigneeRole;
  final String assigneeInitials;
  final DateTime? lastActivity;
  final String? conversationId;
  final String? contextType;
  final String? contextId;
  final String? lastMessagePreview;
  final bool hasMessages;
  final bool isWorkflow;

  const ChatV1TaskItem({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.assignee,
    this.assigneeRole = '',
    required this.assigneeInitials,
    this.lastActivity,
    this.unread = 0,
    this.discussions = 0,
    this.conversationId,
    this.contextType,
    this.contextId,
    this.lastMessagePreview,
    this.hasMessages = false,
    this.isWorkflow = false,
  });

  String get kindLabel => isWorkflow ? 'Workflow task' : 'Project task';

  /// "Role · Name" when both exist; otherwise whichever is available.
  String get assigneeLabel {
    final name = assignee.trim();
    final role = assigneeRole.trim();
    if (name.isEmpty && role.isEmpty) return '';
    if (name.isEmpty) return role;
    if (role.isEmpty) return name;
    return '$role · $name';
  }

  ChatV1TaskItem copyWith({
    int? unread,
    DateTime? lastActivity,
    String? lastMessagePreview,
    bool? hasMessages,
  }) {
    return ChatV1TaskItem(
      id: id,
      title: title,
      category: category,
      status: status,
      assignee: assignee,
      assigneeRole: assigneeRole,
      assigneeInitials: assigneeInitials,
      lastActivity: lastActivity ?? this.lastActivity,
      unread: unread ?? this.unread,
      discussions: discussions,
      conversationId: conversationId,
      contextType: contextType,
      contextId: contextId,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      hasMessages: hasMessages ?? this.hasMessages,
      isWorkflow: isWorkflow,
    );
  }
}

class ChatV1ErpTaskDetails {
  final String erpTaskId;
  final String title;
  final String status;
  final String statusDisplay;
  final String? category;
  final String? assignedToName;
  final String? assignedToRole;
  final String? dueDateDisplay;
  final String? noteResponseTitle;
  final List<ChatV1NoteResponseItem> noteItems;
  final List<ChatV1TaskFile> attachments;
  final String? responseAuthorName;
  final String? responseAuthorRole;
  final String? responseAtDisplay;

  const ChatV1ErpTaskDetails({
    required this.erpTaskId,
    required this.title,
    required this.status,
    required this.statusDisplay,
    this.category,
    this.assignedToName,
    this.assignedToRole,
    this.dueDateDisplay,
    this.noteResponseTitle,
    this.noteItems = const [],
    this.attachments = const [],
    this.responseAuthorName,
    this.responseAuthorRole,
    this.responseAtDisplay,
  });

  /// "Role · Name" when both exist; empty when neither is set.
  String get assigneeLabel {
    final name = assignedToName?.trim() ?? '';
    final role = assignedToRole?.trim() ?? '';
    if (name.isEmpty && role.isEmpty) return '';
    if (name.isEmpty) return role;
    if (role.isEmpty) return name;
    return '$role · $name';
  }
}

class ChatV1NoteResponseItem {
  final String label;
  final String value;
  final String comment;
  const ChatV1NoteResponseItem({
    required this.label,
    required this.value,
    this.comment = '',
  });
}

class ChatV1TaskFile {
  final String name;
  final String url;
  const ChatV1TaskFile({required this.name, required this.url});
}

class ChatV1ConvMeta {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<ChatV1Member> members;
  final String description;
  final bool isTask;
  final ChatV1TaskItem? task;
  final String? pinnedBanner;
  final String? conversationType;
  final String? contextType;
  final String? contextId;

  const ChatV1ConvMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.members,
    required this.description,
    this.isTask = false,
    this.task,
    this.pinnedBanner,
    this.conversationType,
    this.contextType,
    this.contextId,
  });
}

class ChatV1SearchHit {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  const ChatV1SearchHit({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
  });
}

enum ChatV1DocStatus { pending, approved, rejected }

class ChatV1DocMessage {
  final String id;
  final String author;
  final String body;
  final DateTime createdAt;
  final bool own;
  final List<ChatV1Attachment> attachments;

  const ChatV1DocMessage({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.own,
    this.attachments = const [],
  });

  factory ChatV1DocMessage.fromJson(Map<String, dynamic> raw) {
    final atts = <ChatV1Attachment>[];
    final rawAtts = raw['attachments'];
    if (rawAtts is List) {
      for (final a in rawAtts) {
        if (a is Map) {
          atts.add(ChatV1Attachment(
            id: (a['id'] ?? '').toString(),
            fileName: (a['file_name'] ?? a['name'] ?? 'file').toString(),
            contentType: (a['content_type'] ?? '').toString(),
            fileSize: a['file_size'] is num
                ? (a['file_size'] as num).toInt()
                : int.tryParse('${a['file_size']}') ?? 0,
            storagePath:
                (a['storage_path'] ?? a['url'] ?? a['path'] ?? '').toString(),
          ));
        }
      }
    }
    return ChatV1DocMessage(
      id: (raw['id'] ?? '').toString(),
      author: (raw['author'] ?? raw['author_name'] ?? '').toString(),
      body: (raw['body'] ?? raw['text'] ?? '').toString(),
      createdAt: DateTime.tryParse(
            (raw['created_at'] ?? raw['createdAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
      own: raw['own'] == true,
      attachments: atts,
    );
  }
}

/// Difference of Cost request from `/api/v1/chat/.../docs`.
class ChatV1DocRequest {
  final String id;
  final String? salesSopId;
  final String description;
  final double amount;
  final String notes;
  final String? pdfName;
  final String? pdfUrl;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ChatV1DocStatus status;
  final bool unread;
  final bool canApprove;
  final int messageCount;
  final List<ChatV1DocMessage> messages;

  const ChatV1DocRequest({
    required this.id,
    required this.description,
    required this.amount,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.salesSopId,
    this.notes = '',
    this.pdfName,
    this.pdfUrl,
    this.status = ChatV1DocStatus.pending,
    this.unread = false,
    this.canApprove = false,
    this.messageCount = 0,
    this.messages = const [],
  });

  String get statusLabel {
    switch (status) {
      case ChatV1DocStatus.pending:
        return 'Pending Approval';
      case ChatV1DocStatus.approved:
        return 'Approved';
      case ChatV1DocStatus.rejected:
        return 'Rejected';
    }
  }

  ChatV1DocRequest copyWith({
    String? description,
    double? amount,
    String? notes,
    String? pdfName,
    String? pdfUrl,
    DateTime? updatedAt,
    ChatV1DocStatus? status,
    bool? unread,
    bool? canApprove,
    int? messageCount,
    List<ChatV1DocMessage>? messages,
  }) {
    return ChatV1DocRequest(
      id: id,
      salesSopId: salesSopId,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      notes: notes ?? this.notes,
      pdfName: pdfName ?? this.pdfName,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      unread: unread ?? this.unread,
      canApprove: canApprove ?? this.canApprove,
      messageCount: messageCount ?? this.messageCount,
      messages: messages ?? this.messages,
    );
  }

  factory ChatV1DocRequest.fromJson(Map<String, dynamic> raw) {
    final statusRaw = (raw['status'] ?? 'pending').toString().toLowerCase();
    ChatV1DocStatus status;
    if (statusRaw == 'approved') {
      status = ChatV1DocStatus.approved;
    } else if (statusRaw == 'rejected') {
      status = ChatV1DocStatus.rejected;
    } else {
      status = ChatV1DocStatus.pending;
    }
    final msgs = <ChatV1DocMessage>[];
    final rawMsgs = raw['messages'];
    if (rawMsgs is List) {
      for (final m in rawMsgs) {
        if (m is Map) {
          msgs.add(ChatV1DocMessage.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }
    final amountRaw = raw['amount'];
    double amount = 0;
    if (amountRaw is num) {
      amount = amountRaw.toDouble();
    } else {
      amount = double.tryParse(amountRaw?.toString() ?? '') ?? 0;
    }

    String createdBy = (raw['created_by_name'] ?? '').toString();
    if (createdBy.isEmpty) {
      final cb = raw['created_by'];
      if (cb is Map) {
        createdBy = (cb['name'] ?? '').toString();
      } else if (cb != null) {
        createdBy = cb.toString();
      }
    }

    final countRaw = raw['message_count'];
    int messageCount = msgs.length;
    if (countRaw is num) {
      messageCount = countRaw.toInt();
    } else if (countRaw != null) {
      messageCount = int.tryParse(countRaw.toString()) ?? msgs.length;
    }

    return ChatV1DocRequest(
      id: (raw['id'] ?? '').toString(),
      salesSopId: raw['sales_sop_id']?.toString(),
      description: (raw['description'] ?? '').toString(),
      amount: amount,
      notes: (raw['notes'] ?? '').toString(),
      pdfName: (raw['pdf_name'] ?? raw['pdfName'])?.toString(),
      pdfUrl: (raw['pdf_url'] ?? raw['pdfDataUrl'] ?? raw['pdf_data_url'])
          ?.toString(),
      createdBy: createdBy,
      createdAt: DateTime.tryParse(
            (raw['created_at'] ?? raw['createdAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
            (raw['updated_at'] ?? raw['updatedAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
      status: status,
      unread: raw['unread'] == true,
      canApprove: raw['can_approve'] == true,
      messageCount: messageCount,
      messages: msgs,
    );
  }
}

