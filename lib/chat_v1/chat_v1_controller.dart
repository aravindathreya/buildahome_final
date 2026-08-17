import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/data_provider.dart';
import 'chat_v1_api.dart';
import 'chat_v1_mapper.dart';
import 'chat_v1_models.dart';
import 'chat_v1_socket.dart';
import 'chat_v1_theme.dart';
import 'chat_v1_utils.dart';

/// Loads and buckets real chat data for a sales_sop project.
class ChatV1Controller extends ChangeNotifier {
  ChatV1Controller._();
  static final ChatV1Controller instance = ChatV1Controller._();

  final _api = ChatV1Api.instance;
  final _socket = ChatV1Socket.instance;
  bool _socketBound = false;

  String? salesSopId;
  String? currentUserId;
  String? currentUserName;

  bool loading = false;
  String? error;

  List<ChatV1ChatItem> channels = [];
  List<ChatV1ChatItem> customGroups = [];
  List<ChatV1ChatItem> dms = [];
  List<ChatV1TaskItem> taskConversations = [];
  List<ChatV1TaskItem> workflowConversations = [];
  List<ChatV1Member> members = [];

  /// In-memory message cache (parsed models). Bounded; no disk persistence.
  static const int maxCachedConversations = 20;
  static const int maxMessagesPerConversation = 300;
  final Map<String, List<ChatV1Message>> _messageCache = {};
  final List<String> _messageCacheLru = [];

  /// Snapshot of cached messages for [conversationId], or null if empty/missing.
  List<ChatV1Message>? cachedMessages(String conversationId) {
    final list = _messageCache[conversationId];
    if (list == null || list.isEmpty) return null;
    _touchMessageCache(conversationId);
    return List<ChatV1Message>.from(list);
  }

  /// Replace cache entry with a deduped, chronological, bounded list.
  void putCachedMessages(
    String conversationId,
    List<ChatV1Message> messages,
  ) {
    if (conversationId.isEmpty) return;
    final normalized = _normalizeMessageList(messages);
    if (normalized.isEmpty) {
      _messageCache.remove(conversationId);
      _messageCacheLru.remove(conversationId);
      return;
    }
    _messageCache[conversationId] = normalized;
    _touchMessageCache(conversationId);
    _evictMessageCacheIfNeeded();
  }

  /// Upsert one message into the cache (socket / local send / reaction).
  void upsertCachedMessage(
    String conversationId,
    ChatV1Message message,
  ) {
    if (conversationId.isEmpty || message.id.isEmpty) return;
    final existing = _messageCache[conversationId] ?? const <ChatV1Message>[];
    putCachedMessages(
      conversationId,
      mergeConversationMessages(existing, [message]),
    );
  }

  /// Merge [incoming] into [existing] by id; chronological; no duplicates.
  List<ChatV1Message> mergeConversationMessages(
    List<ChatV1Message> existing,
    List<ChatV1Message> incoming,
  ) {
    final byId = <String, ChatV1Message>{};
    for (final m in existing) {
      if (m.id.isEmpty) continue;
      byId[m.id] = m;
    }
    for (final m in incoming) {
      if (m.id.isEmpty) continue;
      final prev = byId[m.id];
      byId[m.id] = prev == null ? m : preferRicherMessage(prev, m);
    }
    return _normalizeMessageList(byId.values.toList());
  }

  /// Prefer attachments / preview bytes from either side; take fresher metadata.
  static ChatV1Message preferRicherMessage(ChatV1Message a, ChatV1Message b) {
    final aHas = a.attachments.isNotEmpty;
    final bHas = b.attachments.isNotEmpty;
    List<ChatV1Attachment> attachments;
    if (bHas && aHas) {
      attachments = [
        for (var i = 0; i < b.attachments.length; i++)
          ChatV1Attachment(
            id: b.attachments[i].id.isNotEmpty
                ? b.attachments[i].id
                : (i < a.attachments.length ? a.attachments[i].id : ''),
            messageId:
                b.attachments[i].messageId ??
                (i < a.attachments.length ? a.attachments[i].messageId : null),
            fileName: b.attachments[i].fileName.isNotEmpty
                ? b.attachments[i].fileName
                : (i < a.attachments.length
                    ? a.attachments[i].fileName
                    : b.attachments[i].fileName),
            contentType: b.attachments[i].contentType.isNotEmpty
                ? b.attachments[i].contentType
                : (i < a.attachments.length
                    ? a.attachments[i].contentType
                    : ''),
            fileSize: b.attachments[i].fileSize > 0
                ? b.attachments[i].fileSize
                : (i < a.attachments.length ? a.attachments[i].fileSize : 0),
            storagePath: b.attachments[i].storagePath.isNotEmpty
                ? b.attachments[i].storagePath
                : (i < a.attachments.length
                    ? a.attachments[i].storagePath
                    : ''),
            previewBytes: b.attachments[i].previewBytes ??
                (i < a.attachments.length
                    ? a.attachments[i].previewBytes
                    : null),
          ),
      ];
    } else if (bHas) {
      attachments = b.attachments;
    } else {
      attachments = a.attachments;
    }

    final aPlaceholder = a.body.toLowerCase().startsWith('uploaded:');
    final bPlaceholder = b.body.toLowerCase().startsWith('uploaded:');
    var body = b.body;
    if (aPlaceholder && !bPlaceholder) {
      body = b.body;
    } else if (!aPlaceholder && bPlaceholder) {
      body = a.body;
    } else if (b.isDeleted) {
      body = b.body;
    } else if (b.body.isNotEmpty) {
      body = b.body;
    } else {
      body = a.body;
    }

    var type = b.type;
    if (attachments.isNotEmpty) {
      if (attachments.every((x) => x.isImage)) {
        type = ChatV1MsgType.image;
      } else if (attachments.any((x) => x.isPdf)) {
        type = ChatV1MsgType.pdf;
      } else if (type == ChatV1MsgType.text) {
        type = ChatV1MsgType.document;
      }
    } else if (b.type == ChatV1MsgType.text && a.type != ChatV1MsgType.text) {
      type = a.type;
    }

    return b.copyWith(
      body: body,
      type: type,
      edited: a.edited || b.edited,
      isPinned: b.isPinned,
      isDeleted: b.isDeleted,
      read: a.read || b.read,
      replyPreview: b.replyPreview ?? a.replyPreview,
      parentMessageId: b.parentMessageId ?? a.parentMessageId,
      fileName: attachments.isNotEmpty
          ? attachments.first.fileName
          : (b.fileName ?? a.fileName),
      fileMeta: attachments.isNotEmpty
          ? attachments.first.contentType
          : (b.fileMeta ?? a.fileMeta),
      reactions: b.reactions.isNotEmpty ? b.reactions : a.reactions,
      mentions: b.mentions.isNotEmpty ? b.mentions : a.mentions,
      readSummary: (b.readSummary.readCount > 0 || b.readSummary.reads.isNotEmpty)
          ? b.readSummary
          : a.readSummary,
      attachments: attachments,
    );
  }

  void _touchMessageCache(String conversationId) {
    _messageCacheLru.remove(conversationId);
    _messageCacheLru.add(conversationId);
  }

  void _evictMessageCacheIfNeeded() {
    while (_messageCacheLru.length > maxCachedConversations) {
      final oldest = _messageCacheLru.removeAt(0);
      _messageCache.remove(oldest);
    }
  }

  List<ChatV1Message> _normalizeMessageList(List<ChatV1Message> messages) {
    final byId = <String, ChatV1Message>{};
    for (final m in messages) {
      if (m.id.isEmpty) continue;
      final prev = byId[m.id];
      byId[m.id] = prev == null ? m : preferRicherMessage(prev, m);
    }
    final out = byId.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    if (out.length > maxMessagesPerConversation) {
      return out.sublist(out.length - maxMessagesPerConversation);
    }
    return out;
  }

  /// ERP + workflow task chats in one list (web Project Tasks drawer).
  List<ChatV1TaskItem> get allProjectTasks {
    final merged = [...taskConversations, ...workflowConversations];
    merged.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return merged;
  }

  ChatV1ChatItem get tasksHub {
    final all = allProjectTasks;
    return ChatV1ChatItem(
      id: 'hub_tasks',
      title: 'Project Tasks',
      subtitle: 'Task & workflow discussions',
      lastMessage: all.isEmpty
          ? 'No task chats yet'
          : '${all.length} discussions',
      lastActivity: all
              .map((t) => t.lastActivity)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (best, dt) => best == null || dt.isAfter(best) ? dt : best,
              ) ??
          DateTime.now(),
      icon: Icons.checklist_rtl_rounded,
      accent: ChatV1Theme.pending,
      unread: all.fold<int>(0, (s, t) => s + t.unread),
      isFixed: true,
      isTaskHub: true,
      opensAs: ChatV1OpensAs.taskList,
      hubKind: 'tasks',
    );
  }

  Future<String?> resolveSalesSopId({String? override}) async {
    if (override != null && override.isNotEmpty && override != 'null') {
      salesSopId = override;
      print('[ChatV1] Using provided sales_sop_id=$salesSopId');
      return salesSopId;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = await _api.getApiToken();
    currentUserId = await _api.getUserId();
    currentUserName = await _api.getUserName();
    final projectId = prefs.getString('project_id');

    if (token == null || token.isEmpty) {
      print('[ChatV1] Missing api_token; cannot resolve sales_sop_id');
      return null;
    }

    Map<String, dynamic>? projectHint;
    if (projectId != null && projectId.isNotEmpty) {
      for (final p in DataProvider().projects) {
        if (p is! Map) continue;
        if (p['id']?.toString() == projectId) {
          projectHint = Map<String, dynamic>.from(p);
          break;
        }
      }
    }

    final resolved = await DataProvider().resolveSalesSopId(
      projectId: projectId,
      apiToken: token,
      projectHint: projectHint,
      useCache: true,
    );
    salesSopId = resolved;
    print(
      '[ChatV1] Resolved sales_sop_id=$salesSopId for ERP project $projectId',
    );
    return salesSopId;
  }

  Future<void> loadProjectChat({String? salesSopIdOverride}) async {
    final hadCache = channels.isNotEmpty ||
        customGroups.isNotEmpty ||
        dms.isNotEmpty ||
        allProjectTasks.isNotEmpty;
    loading = true;
    error = null;
    // Keep previous lists visible while refreshing so reopen feels instant.
    notifyListeners();

    try {
      // No role-based block — Client is a first-class Chat V1 participant.
      // Channel visibility comes from API membership filtering only.
      currentUserId = await _api.getUserId();
      currentUserName = await _api.getUserName();
      final sopId = await resolveSalesSopId(override: salesSopIdOverride);
      if (sopId == null || sopId.isEmpty) {
        throw ChatV1ApiException(
          'Select a project first so chat can load sales_sop conversations.',
        );
      }
      print('[ChatV1] Loading project chat for sales_sop_id=$sopId');

      final softErrors = <String>[];
      final runIds = DataProvider().knownWorkflowRunIds;

      Future<List<Map<String, dynamic>>> safeList(
        String label,
        Future<List<Map<String, dynamic>>> Function() run, {
        bool optional = false,
      }) async {
        try {
          return await run();
        } catch (e) {
          final msg = e.toString().replaceFirst('Exception: ', '');
          if (optional) {
            softErrors.add('$label: $msg');
          } else if (label == 'conversations') {
            // handled by caller
            softErrors.add('conversations:$msg');
          } else {
            softErrors.add('$label: $msg');
          }
          return const [];
        }
      }

      // Phase 1 — conversations only (what the home screen needs first).
      String? conversationsError;
      List<Map<String, dynamic>> conversations = const [];
      try {
        conversations = await _api.listConversations(
          contextType: 'sales_sop',
          contextId: sopId,
        );
      } catch (e) {
        conversationsError = e.toString().replaceFirst('Exception: ', '');
      }

      if (conversations.isEmpty && conversationsError != null) {
        throw ChatV1ApiException(conversationsError);
      }
      if (conversationsError != null) {
        print(
          '[ChatV1] Conversations load warning (continuing): $conversationsError',
        );
      }

      _applyConversations(conversations);
      loading = false;
      notifyListeners();
      print(
        '[ChatV1] Phase1 channels=${channels.length} groups=${customGroups.length}',
      );

      // Phase 2 — secondary lists in parallel (don't block home UI).
      // Also enrich ERP task assignee meta from get_tasks?project_id=… so
      // Project Tasks cards can show Role · Name (conversation list alone
      // does not include assignee fields).
      final prefs = await SharedPreferences.getInstance();
      final projectId = prefs.getString('project_id')?.trim() ?? '';
      final settled = await Future.wait([
        safeList(
          'tasks',
          () => _api.listTaskConversations(sopId),
          optional: true,
        ),
        safeList(
          'workflows',
          () => _api.listWorkflowConversations(
            sopId,
            workflowRunIds: runIds,
          ),
          optional: true,
        ),
        safeList(
          'members',
          () => _api.listMembers(sopId),
          optional: true,
        ),
        safeList(
          'dms',
          () => _api.listDirectConversations(),
          optional: true,
        ),
        () async {
          if (projectId.isEmpty) return const <Map<String, dynamic>>[];
          try {
            await DataProvider().enrichTaskMetaForProject(projectId);
          } catch (e) {
            softErrors.add('task_meta: $e');
          }
          return const <Map<String, dynamic>>[];
        }(),
      ]);

      if (softErrors.isNotEmpty) {
        print('[ChatV1] Optional endpoint errors (ignored): $softErrors');
      }

      _applySecondaryLists(
        tasks: settled[0],
        workflows: settled[1],
        memberRows: settled[2],
        directRows: settled[3],
      );

      print(
        '[ChatV1] Phase2 tasks=${taskConversations.length} '
        'workflows=${workflowConversations.length} dms=${dms.length}',
      );

      // ignore: unawaited_futures
      _socket.connect();
      _ensureSocketBound();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      print('[ChatV1] Load failed: $error');
      if (!hadCache) {
        channels = [];
        customGroups = [];
        dms = [];
        taskConversations = [];
        workflowConversations = [];
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _applyConversations(List<Map<String, dynamic>> conversations) {
    final channelItems = <ChatV1ChatItem>[];
    final customItems = <ChatV1ChatItem>[];
    final seenChannelKeys = <String>{};
    final seenCustomIds = <String>{};

    for (final row in conversations) {
      final type = (row['conversation_type'] ?? '').toString();
      final contextType = (row['context_type'] ?? '').toString();
      final title = (row['title'] ?? row['name'] ?? '').toString();

      if (type == 'direct') continue;

      if (type == 'channel' || ChatV1Utils.isKnownChannelTitle(title)) {
        final item =
            ChatV1Mapper.conversationToChatItem(row, forceFixed: true);
        final dedupeKey =
            ChatV1Utils.canonicalChannelTitle(item.title).toLowerCase();
        if (seenChannelKeys.contains(dedupeKey)) continue;
        seenChannelKeys.add(dedupeKey);
        channelItems.add(item);
      } else if (type == 'group' || contextType == 'sales_sop') {
        final item = ChatV1Mapper.conversationToChatItem(row);
        if (seenCustomIds.contains(item.id)) continue;
        seenCustomIds.add(item.id);
        customItems.add(item);
      }
    }

    channelItems.sort((a, b) => ChatV1Utils.channelSortIndex(a.title)
        .compareTo(ChatV1Utils.channelSortIndex(b.title)));

    channels = channelItems;
    customGroups = customItems
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }

  void _applySecondaryLists({
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> workflows,
    required List<Map<String, dynamic>> memberRows,
    required List<Map<String, dynamic>> directRows,
  }) {
    final dp = DataProvider();
    taskConversations = tasks
        .map((row) {
          final contextId = row['context_id']?.toString();
          final meta =
              contextId == null ? null : dp.erpTaskMetaById[contextId];
          return ChatV1Mapper.conversationToTaskItem(row, meta: meta);
        })
        .toList()
      ..sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    workflowConversations = workflows
        .map((row) {
          final contextId = row['context_id']?.toString();
          final meta =
              contextId == null ? null : dp.workflowRunMetaById[contextId];
          return ChatV1Mapper.conversationToTaskItem(
            row,
            meta: meta,
            isWorkflow: true,
          );
        })
        .toList()
      ..sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    members = memberRows.map(ChatV1Mapper.memberFromJson).toList();
    dms = directRows
        .where((r) => (r['conversation_type'] ?? '') == 'direct')
        .map(ChatV1Mapper.conversationToChatItem)
        .toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }

  void _ensureSocketBound() {
    if (_socketBound) return;
    _socketBound = true;
    _socket.on('message_created', _onSocketMessageCreated);
  }

  void _onSocketMessageCreated(dynamic data) {
    final unwrapped = ChatV1Socket.unwrapMessageEvent(data);
    if (unwrapped == null) return;
    final conversationId = (unwrapped['conversationId'] ?? '').toString();
    if (conversationId.isEmpty) return;
    final message = Map<String, dynamic>.from(unwrapped['message'] as Map);

    String senderName = '';
    final senderRaw = message['sender'];
    if (senderRaw is Map) {
      senderName =
          (senderRaw['name'] ?? senderRaw['user_name'] ?? '').toString();
    } else if (senderRaw != null) {
      senderName = senderRaw.toString();
    }
    if (senderName.isEmpty) {
      senderName = (message['sender_name'] ?? '').toString();
    }

    final senderId =
        (message['sender_id'] ??
                (senderRaw is Map ? senderRaw['id'] : null) ??
                message['user_id'] ??
                '')
            .toString();
    final fromMe = senderId.isNotEmpty && senderId == currentUserId;

    final preview = ChatV1Mapper.formatLastMessagePreview({
      'type': message['type'] ?? message['content_type'] ?? 'text',
      'text': message['text'] ?? message['body'] ?? '',
      'sender': senderName,
      'is_from_me': fromMe,
      'attachment_count': message['attachment_count'] ?? 0,
      'attachment_name': message['attachment_name'],
    });
    final at = ChatV1Utils.parseDate(
          message['created_at'] ?? message['last_message_at'],
        ) ??
        DateTime.now();

    var changed = false;

    // Don't bump unread for the conversation currently open in this client.
    final openId = _socket.joinedConversationId;
    final isOpen = openId != null && openId == conversationId;

    List<ChatV1TaskItem> patchTasks(List<ChatV1TaskItem> source) {
      return source.map((t) {
        final id = t.conversationId ?? t.id;
        if (id != conversationId) return t;
        changed = true;
        return t.copyWith(
          lastActivity: at,
          lastMessagePreview: preview.label,
          hasMessages: !preview.isEmpty,
          unread: (fromMe || isOpen) ? t.unread : t.unread + 1,
        );
      }).toList();
    }

    taskConversations = patchTasks(taskConversations);
    workflowConversations = patchTasks(workflowConversations);

    List<ChatV1ChatItem> patchChats(List<ChatV1ChatItem> source) {
      return source.map((c) {
        if (c.id != conversationId) return c;
        changed = true;
        return c.copyWith(
          lastMessage: preview.label,
          lastActivity: at,
          unread: (fromMe || isOpen) ? c.unread : c.unread + 1,
        );
      }).toList();
    }

    channels = patchChats(channels);
    customGroups = patchChats(customGroups);
    dms = patchChats(dms);

    if (changed) notifyListeners();
  }

  Future<ChatV1ChatItem?> createCustomGroup({
    required String title,
    required List<int> participantUserIds,
  }) async {
    final sopId = salesSopId;
    if (sopId == null) return null;
    final created = await _api.createConversation(
      conversationType: 'group',
      title: title,
      contextType: 'sales_sop',
      contextId: int.tryParse(sopId) ?? sopId,
      participantUserIds: participantUserIds,
    );
    final item = ChatV1Mapper.conversationToChatItem(created);
    customGroups = [item, ...customGroups];
    notifyListeners();
    return item;
  }

  List<ChatV1ChatItem> projectGroupSection() {
    // Channels first, then single Project Tasks hub (ERP + workflow).
    return [
      ...channels,
      if (channels.isNotEmpty || allProjectTasks.isNotEmpty) tasksHub,
    ];
  }

  ChatV1ConvMeta metaFor(
    ChatV1ChatItem item, {
    ChatV1TaskItem? task,
  }) {
    return ChatV1Mapper.metaFromChatItem(
      item,
      members: members,
      task: task,
    );
  }

  /// Look up a loaded chat item by conversation id (channels / groups / DMs).
  ChatV1ChatItem? findChatById(String conversationId) {
    final id = conversationId.toString();
    for (final list in [channels, customGroups, dms]) {
      for (final item in list) {
        if (item.id.toString() == id) return item;
      }
    }
    return null;
  }

  ChatV1ChatItem? findGeneralChannel() {
    for (final item in channels) {
      if (ChatV1Utils.canonicalChannelTitle(item.title).toLowerCase() ==
          'general') {
        return item;
      }
    }
    return null;
  }

  ChatV1ConvMeta metaForTask(ChatV1TaskItem task) {
    return ChatV1ConvMeta(
      id: task.conversationId ?? task.id,
      title: task.title,
      subtitle: 'Task Discussion',
      icon: task.isWorkflow
          ? Icons.account_tree_outlined
          : Icons.task_alt_rounded,
      accent: task.isWorkflow
          ? const Color(0xFF6366F1)
          : ChatV1Theme.accent,
      members: members,
      description: task.isWorkflow
          ? 'Workflow discussion for ${task.title}'
          : 'Task discussion for ${task.title}',
      isTask: true,
      task: task,
      pinnedBanner: null,
      conversationType: 'group',
      contextType: task.contextType ??
          (task.isWorkflow ? 'workflow_item_run' : 'erp_task'),
      contextId: task.contextId,
    );
  }

  void markConversationSeen(String conversationId) {
    var changed = false;
    taskConversations = taskConversations.map((t) {
      final id = t.conversationId ?? t.id;
      if (id != conversationId || t.unread == 0) return t;
      changed = true;
      return t.copyWith(unread: 0);
    }).toList();
    workflowConversations = workflowConversations.map((t) {
      final id = t.conversationId ?? t.id;
      if (id != conversationId || t.unread == 0) return t;
      changed = true;
      return t.copyWith(unread: 0);
    }).toList();
    channels = channels.map((c) {
      if (c.id != conversationId || c.unread == 0) return c;
      changed = true;
      return c.copyWith(unread: 0);
    }).toList();
    customGroups = customGroups.map((c) {
      if (c.id != conversationId || c.unread == 0) return c;
      changed = true;
      return c.copyWith(unread: 0);
    }).toList();
    dms = dms.map((c) {
      if (c.id != conversationId || c.unread == 0) return c;
      changed = true;
      return c.copyWith(unread: 0);
    }).toList();
    if (changed) notifyListeners();
  }
}
