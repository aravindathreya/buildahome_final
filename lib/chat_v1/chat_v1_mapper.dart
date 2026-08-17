import 'package:flutter/material.dart';

import 'chat_v1_models.dart';
import 'chat_v1_theme.dart';
import 'chat_v1_utils.dart';

/// Maps `/api/v1/chat` payloads → ChatV1 UI models.
class ChatV1Mapper {
  ChatV1Mapper._();

  static ChatV1ChatItem conversationToChatItem(
    Map<String, dynamic> raw, {
    bool forceFixed = false,
    bool isTaskHub = false,
    bool isWorkflowHub = false,
  }) {
    final id = _id(raw['id'] ?? raw['conversation_id']);
    final rawTitle = (raw['title'] ?? raw['name'] ?? 'Chat').toString();
    final isDocChannel = ChatV1Utils.isUpdateAndDocChannel(rawTitle);
    final title = isDocChannel
        ? 'Update and Doc'
        : ChatV1Utils.canonicalChannelTitle(rawTitle);
    final conversationType =
        (raw['conversation_type'] ?? raw['type'] ?? '').toString();
    final contextType = (raw['context_type'] ?? '').toString();
    final contextId = raw['context_id']?.toString();
    final unread = _int(raw['unread_count'] ?? raw['unread']) ?? 0;
    final mentions = _int(raw['mention_count'] ?? raw['mentions']) ?? 0;
    final last = isDocChannel
        ? 'Difference of Cost requests'
        : formatLastMessagePreview(raw['last_message']).label;
    final lastAt = ChatV1Utils.parseDate(
          raw['last_message_at'] ??
              (raw['last_message'] is Map
                  ? raw['last_message']['created_at']
                  : null),
        ) ??
        DateTime.now();
    final isDm = conversationType == 'direct';
    final isChannel = conversationType == 'channel' ||
        forceFixed ||
        ChatV1Utils.isKnownChannelTitle(rawTitle);
    final participantCount =
        _int(raw['participant_count'] ?? raw['member_count']) ?? 0;

    IconData icon;
    Color accent;
    String subtitle;
    if (isDm) {
      icon = Icons.person_rounded;
      accent = ChatV1Utils.colorForId(id);
      subtitle = (raw['subtitle'] ?? raw['role'] ?? 'Direct message').toString();
    } else if (isDocChannel) {
      icon = ChatV1Utils.channelIcon(title);
      accent = ChatV1Utils.channelAccent(title);
      subtitle = 'Difference of Cost';
    } else if (isChannel) {
      icon = ChatV1Utils.channelIcon(title);
      accent = ChatV1Utils.channelAccent(title);
      subtitle = participantCount > 0
          ? '$participantCount members'
          : 'Channel';
    } else if (isTaskHub) {
      icon = Icons.checklist_rtl_rounded;
      accent = ChatV1Theme.pending;
      subtitle = 'Task discussions';
    } else if (isWorkflowHub) {
      icon = Icons.account_tree_outlined;
      accent = const Color(0xFF6366F1);
      subtitle = 'Workflow chats';
    } else if (contextType == 'erp_task') {
      icon = Icons.task_alt_rounded;
      accent = ChatV1Theme.accent;
      subtitle = 'Task chat';
    } else if (contextType == 'workflow_item_run') {
      icon = Icons.account_tree_outlined;
      accent = const Color(0xFF6366F1);
      subtitle = 'Workflow chat';
    } else {
      icon = Icons.groups_rounded;
      accent = const Color(0xFF64748B);
      subtitle = participantCount > 0
          ? '$participantCount members'
          : 'Custom group';
    }

    ChatV1OpensAs opensAs;
    if (isDocChannel) {
      opensAs = ChatV1OpensAs.docList;
    } else if (isTaskHub || isWorkflowHub) {
      opensAs = ChatV1OpensAs.taskList;
    } else {
      opensAs = ChatV1OpensAs.conversation;
    }

    return ChatV1ChatItem(
      id: id,
      title: title,
      subtitle: subtitle,
      lastMessage: last,
      lastActivity: lastAt,
      icon: icon,
      accent: accent,
      unread: unread,
      mentions: mentions,
      isFixed: isChannel,
      isPinned: raw['is_pinned'] == true,
      isMuted: raw['is_muted'] == true || raw['is_archived'] == true,
      isDm: isDm,
      isTaskHub: isTaskHub || isWorkflowHub,
      opensAs: opensAs,
      initials: isDm ? ChatV1Utils.initials(title) : null,
      conversationType: conversationType.isEmpty ? null : conversationType,
      contextType: contextType.isEmpty ? null : contextType,
      contextId: contextId,
      participantCount: participantCount,
      myRole: raw['my_role']?.toString(),
    );
  }

  static ChatV1TaskItem conversationToTaskItem(
    Map<String, dynamic> raw, {
    Map<String, String>? meta,
    bool isWorkflow = false,
  }) {
    final contextType = (raw['context_type'] ?? '').toString();
    final workflow = isWorkflow || contextType == 'workflow_item_run';
    final contextId = raw['context_id']?.toString();
    final metaTitle = meta?['title'];
    final title = (metaTitle != null && metaTitle.isNotEmpty
            ? metaTitle
            : (raw['title'] ??
                raw['name'] ??
                raw['task_title'] ??
                raw['workflow_title'] ??
                'Discussion'))
        .toString();
    final statusRaw =
        (meta?['status'] ?? raw['status'] ?? raw['task_status'] ?? 'pending')
            .toString();
    final lastAt = ChatV1Utils.parseDate(
      raw['last_message_at'] ??
          (raw['last_message'] is Map
              ? raw['last_message']['created_at']
              : null),
    );
    final preview = formatLastMessagePreview(raw['last_message']);
    final nestedTask = _nestedTaskMap(raw);
    final assignee = _taskAssigneeName(meta, raw, nestedTask);
    final assigneeRole = _taskAssigneeRole(meta, raw, nestedTask);
    return ChatV1TaskItem(
      id: _id(raw['id'] ?? raw['conversation_id'] ?? raw['task_id']),
      title: title,
      category: workflow ? 'Workflow task' : 'Project task',
      status: _taskStatus(statusRaw),
      assignee: assignee,
      assigneeRole: assigneeRole,
      assigneeInitials: ChatV1Utils.initials(assignee),
      lastActivity: lastAt,
      unread: _int(raw['unread_count'] ?? raw['unread']) ?? 0,
      discussions: _int(raw['message_count'] ?? raw['discussions']) ?? 0,
      conversationId: _id(raw['id'] ?? raw['conversation_id']),
      contextType: contextType.isEmpty
          ? (workflow ? 'workflow_item_run' : 'erp_task')
          : contextType,
      contextId: contextId,
      lastMessagePreview: preview.label,
      hasMessages: !preview.isEmpty,
      isWorkflow: workflow,
    );
  }

  static Map<String, dynamic>? _nestedTaskMap(Map<String, dynamic> raw) {
    for (final key in const ['task', 'erp_task', 'task_details', 'meta', 'context']) {
      final value = raw[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static String _taskAssigneeName(
    Map<String, String>? meta,
    Map<String, dynamic> raw,
    Map<String, dynamic>? nested,
  ) {
    final candidates = <dynamic>[
      meta?['assignee'],
      raw['assigned_to_name'],
      raw['assignee_name'],
      raw['assignee'],
      nested?['assigned_to_name'],
      nested?['assignee_name'],
      nested?['assignee'],
      nested?['user_name'],
      raw['user_name'],
      // Bare ids last — only used if they look like a display string.
      raw['assigned_to'],
      nested?['assigned_to'],
    ];
    for (final c in candidates) {
      final text = c?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      if (RegExp(r'^\d+$').hasMatch(text)) continue;
      final lower = text.toLowerCase();
      if (lower == 'pending assignment' ||
          lower == 'unassigned' ||
          lower == '—' ||
          lower == '-') {
        continue;
      }
      return text;
    }
    return '';
  }

  static String _taskAssigneeRole(
    Map<String, String>? meta,
    Map<String, dynamic> raw,
    Map<String, dynamic>? nested,
  ) {
    final candidates = <dynamic>[
      meta?['assignee_role'],
      raw['assigned_to_role'],
      raw['assigned_role'],
      raw['assignee_role'],
      nested?['assigned_to_role'],
      nested?['assigned_role'],
      nested?['assignee_role'],
    ];
    for (final c in candidates) {
      final text = c?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      return text;
    }
    return '';
  }

  /// Web-parity last message preview for list rows.
  static ChatV1LastMessagePreview formatLastMessagePreview(
    dynamic lastMessage,
  ) {
    if (lastMessage == null) {
      return const ChatV1LastMessagePreview(
        label: 'No messages yet',
        isEmpty: true,
      );
    }
    if (lastMessage is! Map) {
      final text = lastMessage.toString().trim();
      return text.isEmpty
          ? const ChatV1LastMessagePreview(
              label: 'No messages yet',
              isEmpty: true,
            )
          : ChatV1LastMessagePreview(label: text, isEmpty: false);
    }
    final type = (lastMessage['type'] ?? 'text').toString().toLowerCase();
    final text = (lastMessage['text'] ?? lastMessage['body'] ?? '')
        .toString()
        .trim();
    final count = _int(lastMessage['attachment_count']) ?? 0;
    String body;
    if (type == 'voice' || type == 'audio') {
      body = '🎤 Voice Message';
    } else if (type == 'image') {
      body = '🖼 Photo';
    } else if (type == 'attachments' || count > 1) {
      body = '📎 $count Attachments';
    } else if (type == 'file' ||
        type == 'document' ||
        (count == 1 && text.isEmpty)) {
      final name =
          (lastMessage['attachment_name'] ?? text).toString().trim();
      body = '📄 ${name.isEmpty ? 'Attachment' : name}';
    } else if (count == 1 && lastMessage['attachment_name'] != null) {
      body = '📄 ${lastMessage['attachment_name']}';
    } else {
      body = text.isEmpty ? 'No messages yet' : text;
    }
    final sender = (lastMessage['sender'] ?? lastMessage['sender_name'] ?? '')
        .toString();
    final isFromMe = lastMessage['is_from_me'] == true;
    if (sender.isNotEmpty && body != 'No messages yet') {
      final who = isFromMe ? 'You' : sender;
      body = '$who: $body';
    }
    return ChatV1LastMessagePreview(
      label: body,
      isEmpty: body == 'No messages yet',
    );
  }

  static ChatV1Attachment attachmentFromJson(Map<String, dynamic> raw) {
    final path =
        (raw['storage_path'] ?? raw['url'] ?? raw['path'] ?? '').toString();
    final fileName = (raw['file_name'] ?? raw['name'] ?? 'file').toString();
    var contentType =
        (raw['content_type'] ?? raw['mime_type'] ?? '').toString();
    if (contentType.isEmpty) {
      contentType = _guessContentType(fileName);
    }
    return ChatV1Attachment(
      id: _id(raw['id']),
      messageId: raw['message_id']?.toString(),
      fileName: fileName,
      contentType: contentType,
      fileSize: _int(raw['file_size'] ?? raw['size']) ?? 0,
      storagePath: ChatV1Utils.resolveMediaUrl(path),
    );
  }

  static String _guessContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  static ChatV1ErpTaskDetails? erpTaskDetailsFromJson(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return null;
    final note = raw['note_response'];
    final items = <ChatV1NoteResponseItem>[];
    if (note is Map && note['items'] is List) {
      for (final item in note['items'] as List) {
        if (item is! Map) continue;
        items.add(ChatV1NoteResponseItem(
          label: (item['label'] ?? '').toString(),
          value: (item['value'] ?? '').toString(),
          comment: (item['comment'] ?? '').toString(),
        ));
      }
    }
    final files = <ChatV1TaskFile>[];
    final atts = raw['attachments'];
    if (atts is List) {
      for (final f in atts) {
        if (f is! Map) continue;
        final url = (f['url'] ?? f['storage_path'] ?? '').toString();
        if (url.isEmpty) continue;
        files.add(ChatV1TaskFile(
          name: (f['name'] ?? f['file_name'] ?? 'Attachment').toString(),
          url: url,
        ));
      }
    }
    return ChatV1ErpTaskDetails(
      erpTaskId: _id(raw['erp_task_id'] ?? raw['id']),
      title: (raw['title'] ?? 'Task').toString(),
      status: (raw['status'] ?? 'pending').toString(),
      statusDisplay:
          (raw['status_display'] ?? raw['status'] ?? 'Pending').toString(),
      category: raw['category']?.toString(),
      assignedToName: raw['assigned_to_name']?.toString(),
      assignedToRole: raw['assigned_to_role']?.toString(),
      dueDateDisplay: raw['due_date_display']?.toString(),
      noteResponseTitle:
          note is Map ? note['title']?.toString() : null,
      noteItems: items,
      attachments: files,
      responseAuthorName: raw['response_author_name']?.toString(),
      responseAuthorRole: raw['response_author_role']?.toString(),
      responseAtDisplay: raw['response_at_display']?.toString(),
    );
  }

  static ChatV1Member memberFromJson(Map<String, dynamic> raw) {
    final id = _id(raw['id'] ?? raw['user_id']);
    final name =
        (raw['name'] ?? raw['username'] ?? raw['email'] ?? 'User').toString();
    return ChatV1Member(
      id: id,
      name: name,
      role: (raw['role'] ?? raw['job_title'] ?? '').toString(),
      initials: ChatV1Utils.initials(name),
      color: ChatV1Utils.colorForId(id),
      online: raw['online'] == true || raw['is_online'] == true,
      email: raw['email']?.toString(),
    );
  }

  static ChatV1Message messageFromJson(
    Map<String, dynamic> raw, {
    required String currentUserId,
  }) {
    final sender = raw['sender'];
    String authorId = '';
    String authorName = 'User';
    String? role;
    if (sender is Map) {
      authorId = _id(sender['id'] ?? sender['user_id']);
      authorName =
          (sender['name'] ?? sender['username'] ?? sender['email'] ?? 'User')
              .toString();
      role = sender['role']?.toString();
    } else {
      authorId = _id(raw['sender_id'] ?? raw['user_id']);
      authorName =
          (raw['sender_name'] ?? raw['sender'] ?? 'User').toString();
    }

    final isMine = authorId.isNotEmpty &&
        authorId == currentUserId.toString();
    final contentType =
        (raw['content_type'] ?? raw['type'] ?? 'text').toString().toLowerCase();
    final body = (raw['body'] ?? raw['text'] ?? raw['message'] ?? '').toString();
    final isDeleted = raw['is_deleted'] == true;

    String? replyPreview;
    final parentPreview = raw['parent_message_preview'];
    final parent = raw['parent_message'] ??
        raw['reply_to'] ??
        (parentPreview is Map ? parentPreview : null);
    if (parent is Map) {
      replyPreview = _parentReplyPreview(Map<String, dynamic>.from(parent));
    } else if (raw['parent_message_id'] != null &&
        raw['parent_preview'] != null) {
      final preview = raw['parent_preview'].toString().trim();
      if (preview.isNotEmpty) replyPreview = preview;
    }

    final reactions = _parseReactions(raw);

    final mentions = <ChatV1Mention>[];
    final rawMentions = raw['mentions'];
    if (rawMentions is List) {
      for (final m in rawMentions) {
        if (m is! Map) continue;
        final uid = _id(m['user_id'] ?? m['id'] ?? m['mentioned_user_id']);
        if (uid.isEmpty) continue;
        mentions.add(ChatV1Mention(
          userId: uid,
          name: (m['name'] ?? m['username'] ?? m['display_name'])?.toString(),
        ));
      }
    }

    final readSummary = _parseReadSummary(raw['read_summary'] ?? raw['readSummary']);

    String? fileName;
    String? fileMeta;
    final parsedAttachments = <ChatV1Attachment>[];
    final attachments = raw['attachments'];
    if (attachments is List) {
      for (final a in attachments) {
        if (a is! Map) continue;
        final att = attachmentFromJson(Map<String, dynamic>.from(a));
        if (att.storagePath.isEmpty && att.fileName.isEmpty) continue;
        parsedAttachments.add(att);
      }
    }
    if (parsedAttachments.isNotEmpty) {
      final first = parsedAttachments.first;
      fileName = first.fileName;
      fileMeta = [
        if (first.contentType.isNotEmpty) first.contentType,
        if (first.fileSize > 0) _formatBytes(first.fileSize),
      ].join(' · ');
    } else {
      fileName = raw['file_name']?.toString();
      fileMeta = raw['file_meta']?.toString();
    }

    var msgType = _msgType(contentType, fileName: fileName);
    if (parsedAttachments.isNotEmpty) {
      if (parsedAttachments.every((a) => a.isImage)) {
        msgType = ChatV1MsgType.image;
      } else if (parsedAttachments.any((a) => a.isPdf)) {
        msgType = ChatV1MsgType.pdf;
      } else {
        msgType = ChatV1MsgType.document;
      }
    }

    // Prefer embedded extras when present; otherwise empty (socket creates).
    return ChatV1Message(
      id: _id(raw['id']),
      authorId: authorId,
      authorName: isMine ? 'You' : authorName,
      authorInitials: ChatV1Utils.initials(isMine ? 'You' : authorName),
      authorColor: ChatV1Utils.colorForId(authorId.isEmpty ? authorName : authorId),
      body: isDeleted ? 'This message was deleted' : body,
      sentAt: ChatV1Utils.parseDate(raw['created_at']) ?? DateTime.now(),
      type: msgType,
      isMine: isMine,
      delivered: true,
      read: raw['read'] == true ||
          raw['is_read'] == true ||
          (isMine && readSummary.readCount > 0),
      edited: raw['edited_at'] != null || raw['is_edited'] == true,
      isPinned: raw['is_pinned'] == true || raw['pinned'] == true,
      replyPreview: replyPreview,
      fileName: fileName,
      fileMeta: fileMeta,
      reactions: reactions,
      parentMessageId: (raw['parent_message_id'] ??
              (parent is Map ? parent['id'] : null))
          ?.toString(),
      isDeleted: isDeleted,
      conversationId: raw['conversation_id']?.toString(),
      senderRole: role,
      attachments: parsedAttachments,
      mentions: mentions,
      readSummary: readSummary,
    );
  }

  static List<ChatV1Reaction> _parseReactions(Map<String, dynamic> raw) {
    final byEmoji = <String, ChatV1Reaction>{};

    void ingest(dynamic list) {
      if (list is! List) return;
      for (final r in list) {
        if (r is! Map) continue;
        final emoji = (r['emoji'] ?? r['reaction'] ?? '').toString();
        if (emoji.isEmpty) continue;
        final count = _int(r['count']) ??
            (r['user_ids'] is List ? (r['user_ids'] as List).length : null) ??
            1;
        final mine = r['mine'] == true ||
            r['reacted_by_me'] == true ||
            r['reacted'] == true;
        final prev = byEmoji[emoji];
        if (prev == null) {
          byEmoji[emoji] = ChatV1Reaction(
            emoji: emoji,
            count: count,
            mine: mine,
          );
        } else {
          byEmoji[emoji] = ChatV1Reaction(
            emoji: emoji,
            count: count > prev.count ? count : prev.count,
            mine: prev.mine || mine,
          );
        }
      }
    }

    // Prefer full reactions list; fall back to reaction_summary.
    ingest(raw['reactions']);
    if (byEmoji.isEmpty) {
      ingest(raw['reaction_summary'] ?? raw['reactionSummary']);
    }
    return byEmoji.values.toList();
  }

  static ChatV1ReadSummary _parseReadSummary(dynamic raw) {
    if (raw is! Map) return ChatV1ReadSummary.empty();
    final map = Map<String, dynamic>.from(raw);
    final readsRaw = map['reads'];
    final reads = <Map<String, dynamic>>[];
    if (readsRaw is List) {
      for (final r in readsRaw) {
        if (r is Map) reads.add(Map<String, dynamic>.from(r));
      }
    }
    final count = _int(map['read_count'] ?? map['readCount']) ?? reads.length;
    return ChatV1ReadSummary(readCount: count, reads: reads);
  }

  static ChatV1ConvMeta metaFromChatItem(
    ChatV1ChatItem item, {
    List<ChatV1Member> members = const [],
    ChatV1TaskItem? task,
  }) {
    return ChatV1ConvMeta(
      id: item.id,
      title: item.title,
      subtitle: item.subtitle,
      icon: item.icon,
      accent: item.accent,
      members: members,
      description: item.isFixed
          ? 'Project channel · ${item.title}'
          : item.isDm
              ? 'Direct message'
              : 'Group conversation',
      isTask: task != null || item.contextType == 'erp_task',
      task: task,
      pinnedBanner: item.isFixed
          ? 'Keep updates related to ${item.title} only.'
          : null,
      conversationType: item.conversationType,
      contextType: item.contextType,
      contextId: item.contextId,
    );
  }

  /// Build "Author: snippet" from an embedded parent_message / reply_to map.
  static String? _parentReplyPreview(Map<String, dynamic> parent) {
    final pName = parent['sender'] is Map
        ? (parent['sender']['name'] ?? '').toString()
        : (parent['sender_name'] ?? parent['sender'] ?? '').toString();

    var pBody = (parent['body'] ??
            parent['text'] ??
            parent['snippet'] ??
            parent['preview'] ??
            '')
        .toString()
        .trim();
    final lower = pBody.toLowerCase();
    if (lower.startsWith('uploaded:')) {
      pBody = pBody.substring(pBody.indexOf(':') + 1).trim();
    }

    var fileName = (parent['file_name'] ?? parent['filename'] ?? '')
        .toString()
        .trim();
    if (fileName.isEmpty) {
      final atts = parent['attachments'];
      if (atts is List && atts.isNotEmpty && atts.first is Map) {
        final a = atts.first as Map;
        fileName = (a['file_name'] ?? a['filename'] ?? a['name'] ?? '')
            .toString()
            .trim();
        final ct = (a['content_type'] ?? a['mime_type'] ?? '').toString();
        if (fileName.isEmpty) {
          if (ct.startsWith('image/')) fileName = 'Photo';
          else if (ct.contains('pdf')) fileName = 'PDF';
        }
      }
    }

    final contentType =
        (parent['content_type'] ?? parent['type'] ?? '').toString().toLowerCase();
    var snippet = pBody;
    if (snippet.isEmpty ||
        snippet.toLowerCase() == 'attachment' ||
        snippet.toLowerCase() == 'message') {
      if (fileName.isNotEmpty) {
        snippet = fileName;
      } else if (contentType.contains('image')) {
        snippet = 'Photo';
      } else if (contentType.contains('pdf')) {
        snippet = 'PDF';
      } else if (contentType.isNotEmpty &&
          contentType != 'text' &&
          contentType != 'message') {
        snippet = 'Document';
      } else {
        snippet = '';
      }
    }

    if (snippet.isEmpty && pName.isEmpty) return null;
    if (pName.isNotEmpty) {
      return ChatV1Utils.formatReplyPreview(
        authorName: pName,
        snippet: snippet.isEmpty ? 'Message' : snippet,
      );
    }
    return snippet;
  }

  static ChatV1MsgType _msgType(String contentType, {String? fileName}) {
    final ct = contentType.toLowerCase();
    final name = (fileName ?? '').toLowerCase();
    if (ct.contains('image') ||
        name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp')) {
      return ChatV1MsgType.image;
    }
    if (ct.contains('pdf') || name.endsWith('.pdf')) {
      return ChatV1MsgType.pdf;
    }
    if (ct.contains('video')) return ChatV1MsgType.video;
    if (ct.contains('system')) return ChatV1MsgType.system;
    if (ct != 'text' && ct.isNotEmpty && ct != 'message') {
      return ChatV1MsgType.document;
    }
    if (name.isNotEmpty) return ChatV1MsgType.document;
    return ChatV1MsgType.text;
  }

  static ChatV1TaskStatus _taskStatus(String raw) {
    switch (raw.toLowerCase()) {
      case 'completed':
      case 'done':
      case 'approved':
        return ChatV1TaskStatus.completed;
      case 'rejected':
      case 'cancelled':
        return ChatV1TaskStatus.rejected;
      case 'in_progress':
      case 'inprogress':
      case 'active':
        return ChatV1TaskStatus.inProgress;
      default:
        return ChatV1TaskStatus.pending;
    }
  }

  static String _id(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
