import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/data_provider.dart';
import 'chat_v1_api.dart';
import 'chat_v1_doc_client_notice.dart';
import 'chat_v1_mapper.dart';
import 'chat_v1_models.dart';
import 'chat_v1_socket.dart';
import 'chat_v1_theme.dart';
import 'chat_v1_utils.dart';

/// Loads and buckets real chat data for a sales_sop project.
class ChatV1Controller extends ChangeNotifier {
  ChatV1Controller._() : _socket = ChatV1Socket.instance;

  @visibleForTesting
  ChatV1Controller.forTesting({
    required ChatV1Socket socket,
    required Future<List<Map<String, dynamic>>> Function(
            String conversationId, String? afterId, int pageSize)
        messageLoader,
    required Future<List<Map<String, dynamic>>> Function(String salesSopId)
        conversationLoader,
  })  : _socket = socket,
        _recoveryMessageLoader = messageLoader,
        _recoveryConversationLoader = conversationLoader;
  static final ChatV1Controller instance = ChatV1Controller._();

  final _api = ChatV1Api.instance;
  final ChatV1Socket _socket;
  Future<List<Map<String, dynamic>>> Function(String, String?, int)?
      _recoveryMessageLoader;
  Future<List<Map<String, dynamic>>> Function(String)?
      _recoveryConversationLoader;
  Timer? _recoveryTimer;
  DateTime? _lastRecoveryAt;
  bool _disposed = false;
  static const int maxRecoveryPages = 3;
  static const Duration recoveryCooldown = Duration(seconds: 15);
  bool _socketBound = false;
  bool _catchingUp = false;
  bool _catchUpAgain = false;

  String? salesSopId;
  String? currentUserId;
  String? currentUserName;
  final Set<String> _seenMentionMessageIds = <String>{};

  bool loading = false;
  String? error;

  List<ChatV1ChatItem> channels = [];
  List<ChatV1ChatItem> customGroups = [];
  List<ChatV1ChatItem> dms = [];
  List<ChatV1TaskItem> taskConversations = [];
  List<ChatV1TaskItem> docTasks = [];
  Timer? _docTaskRefresh;
  static const String _seenDocsKey = 'chat_v1_seen_created_docs_v1';
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
      mentions:
          b.mentionsResolved || b.mentions.isNotEmpty ? b.mentions : a.mentions,
      mentionsResolved: b.mentionsResolved ||
          b.mentions.isNotEmpty ||
          a.mentionsResolved ||
          a.mentions.isNotEmpty,
      readSummary:
          (b.readSummary.readCount > 0 || b.readSummary.reads.isNotEmpty)
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

  /// ERP + workflow task chats, plus pending DOC tasks for the client.
  List<ChatV1TaskItem> get allProjectTasks {
    final merged = [
      ...taskConversations,
      ...workflowConversations,
      ...docTasks,
    ];
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
      mentions: all.fold<int>(0, (s, t) => s + t.mentions),
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

  /// Local pin / mute / archive so a refresh does not drop swipe actions.
  static const String _flagsPrefsKey = 'chat_v1_conversation_flags_v1';
  final Map<String, _SavedChatFlags> _localFlags = {};
  bool _flagsLoaded = false;

  Future<void> _ensureFlagsLoaded() async {
    if (_flagsLoaded) return;
    _localFlags
      ..clear()
      ..addAll(await _readFlags());
    _flagsLoaded = true;
  }

  Future<Map<String, _SavedChatFlags>> _readFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_flagsPrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, _SavedChatFlags>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        out[key.toString()] = _SavedChatFlags(
          pinned: value['p'] == true,
          muted: value['m'] == true,
          archived: value['a'] == true,
        );
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, Map<String, bool>>{};
    _localFlags.forEach((id, flag) {
      encoded[id] = {
        'p': flag.pinned,
        'm': flag.muted,
        'a': flag.archived,
      };
    });
    await prefs.setString(_flagsPrefsKey, jsonEncode(encoded));
  }

  void _applyLocalFlags() {
    channels = _withLocalFlags(channels);
    customGroups = _withLocalFlags(customGroups);
    dms = _withLocalFlags(dms);
  }

  List<ChatV1ChatItem> _withLocalFlags(List<ChatV1ChatItem> items) {
    if (_localFlags.isEmpty) return items;
    final next = <ChatV1ChatItem>[];
    for (final item in items) {
      final flag = _localFlags[item.id];
      if (flag == null) {
        next.add(item);
        continue;
      }
      if (flag.archived) continue;
      next.add(item.copyWith(isPinned: flag.pinned, isMuted: flag.muted));
    }
    return next;
  }

  Future<void> setConversationFlag(
    String id, {
    bool? pinned,
    bool? muted,
    bool? archived,
  }) async {
    if (id.isEmpty) return;
    await _ensureFlagsLoaded();
    final live = findChatById(id);
    final current = _localFlags[id] ??
        _SavedChatFlags(
          pinned: live?.isPinned ?? false,
          muted: live?.isMuted ?? false,
        );
    final next = _SavedChatFlags(
      pinned: pinned ?? current.pinned,
      muted: muted ?? current.muted,
      archived: archived ?? current.archived,
    );
    _localFlags[id] = next;
    await _writeFlags();
    _applyLocalFlags();
    notifyListeners();
    // ignore: unawaited_futures
    _api.tryUpdateConversation(
      conversationId: id,
      isPinned: next.pinned,
      isMuted: next.muted,
      isArchived: next.archived,
    );
  }

  Future<void> leaveConversation(String id) async {
    await setConversationFlag(id, archived: true);
    // ignore: unawaited_futures
    _api.tryLeaveConversation(id);
  }

  Future<void> loadProjectChat({String? salesSopIdOverride}) async {
    final hadCache = channels.isNotEmpty ||
        customGroups.isNotEmpty ||
        dms.isNotEmpty ||
        allProjectTasks.isNotEmpty;
    loading = true;
    error = null;
    final socketSession = _socket.sessionGeneration;
    await _ensureFlagsLoaded();
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
      _applyLocalFlags();
      loading = false;
      notifyListeners();
      print(
        '[ChatV1] Phase1 channels=${channels.length} '
        '[${channels.map((c) => c.title).join(', ')}] '
        'groups=${customGroups.length}',
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
        safeList(
          'docs',
          () async {
            if (!await _viewerIsClient()) return const <Map<String, dynamic>>[];
            return _api.listDocs(sopId);
          },
          optional: true,
        ),
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
      await _applyClientDocTasks(settled[5]);
      _applyLocalFlags();

      print(
        '[ChatV1] Phase2 tasks=${taskConversations.length} '
        'workflows=${workflowConversations.length} dms=${dms.length}',
      );

      if (_socket.sessionGeneration != socketSession) {
        print('[ChatV1] CHAT SOCKET connect skipped (logged out during load)');
        return;
      }
      // Bind before connect so a fast handshake cannot miss `connected`.
      _ensureSocketBound();
      // ignore: unawaited_futures
      _socket.connect();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      print('[ChatV1] Load failed: $error');
      if (!hadCache) {
        channels = [];
        customGroups = [];
        dms = [];
        taskConversations = [];
        workflowConversations = [];
        docTasks = [];
      }
    } finally {
      _applyLocalFlags();
      loading = false;
      notifyListeners();
    }
  }

  void _applyConversations(List<Map<String, dynamic>> conversations) {
    final channelItems = <ChatV1ChatItem>[];
    final customItems = <ChatV1ChatItem>[];
    final seenChannelIds = <String>{};
    final seenCustomIds = <String>{};

    for (final row in conversations) {
      final type = (row['conversation_type'] ?? '').toString().toLowerCase();
      final contextType = (row['context_type'] ?? '').toString();
      final title = (row['title'] ?? row['name'] ?? '').toString();

      if (type == 'direct') continue;
      if (contextType == 'erp_task' || contextType == 'workflow_item_run') {
        continue;
      }

      // Web creates these as conversation_type=channel on the sales SOP.
      // Exact known titles still count (older rows stored as groups).
      if (type == 'channel' || ChatV1Utils.isKnownChannelTitle(title)) {
        final item =
            ChatV1Mapper.conversationToChatItem(row, forceFixed: true);
        if (!seenChannelIds.add(item.id)) continue;
        channelItems.add(item);
      } else if (type == 'group' || contextType == 'sales_sop') {
        final item = ChatV1Mapper.conversationToChatItem(row);
        if (seenCustomIds.contains(item.id)) continue;
        seenCustomIds.add(item.id);
        customItems.add(item);
      }
    }

    channels = _preferUniqueChannelTitles(channelItems);
    customGroups = customItems
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }

  /// Collapse only exact known titles (two "General" rows). Keep every other
  /// channel. When both a real channel and a same-named group exist, keep
  /// the `conversation_type=channel` row.
  List<ChatV1ChatItem> _preferUniqueChannelTitles(
    List<ChatV1ChatItem> items,
  ) {
    final byTitle = <String, ChatV1ChatItem>{};
    final others = <ChatV1ChatItem>[];
    for (final item in items) {
      if (!ChatV1Utils.isKnownChannelTitle(item.title)) {
        others.add(item);
        continue;
      }
      final key = ChatV1Utils.canonicalChannelTitle(item.title).toLowerCase();
      final prev = byTitle[key];
      if (prev == null || _preferChannelRow(item, prev)) {
        byTitle[key] = item;
      }
    }
    final out = [...byTitle.values, ...others];
    out.sort((a, b) => ChatV1Utils.channelSortIndex(a.title)
        .compareTo(ChatV1Utils.channelSortIndex(b.title)));
    return out;
  }

  bool _preferChannelRow(ChatV1ChatItem next, ChatV1ChatItem prev) {
    final nextIs = (next.conversationType ?? '').toLowerCase() == 'channel';
    final prevIs = (prev.conversationType ?? '').toLowerCase() == 'channel';
    if (nextIs != prevIs) return nextIs;
    return next.lastActivity.isAfter(prev.lastActivity);
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

  Future<bool> _viewerIsClient() async {
    final cached = (DataProvider().currentRole ?? '').trim().toLowerCase();
    if (cached.isNotEmpty) return cached == 'client';
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('role') ?? '').trim().toLowerCase() == 'client';
  }

  Future<Set<String>> _readSeenDocIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_seenDocsKey) ?? const <String>[]).toSet();
  }

  Future<void> _writeSeenDocIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final list = ids.toList()..sort();
    final trimmed =
        list.length > 400 ? list.sublist(list.length - 400) : list;
    await prefs.setStringList(_seenDocsKey, trimmed);
  }

  bool _isDocChannel(ChatV1ChatItem item) {
    return item.opensAs == ChatV1OpensAs.docList ||
        ChatV1Utils.isUpdateAndDocChannel(item.title);
  }

  ChatV1ChatItem? _findLoadedDocChannel() {
    for (final item in channels) {
      if (_isDocChannel(item)) return item;
    }
    return null;
  }

  Future<void> _applyClientDocTasks(List<Map<String, dynamic>> rows) async {
    if (!await _viewerIsClient()) {
      docTasks = [];
      return;
    }
    final docs = rows.map(ChatV1DocRequest.fromJson).toList();
    final seen = await _readSeenDocIds();
    docTasks = clientDocCreatedTasks(docs: docs, seenIds: seen);
    _boostDocChannelUnread(
      clientDocUnseenCount(docs: docs, seenIds: seen),
    );
  }

  void _boostDocChannelUnread(int count) {
    if (count <= 0) return;
    channels = [
      for (final item in channels)
        if (_isDocChannel(item) && item.unread < count)
          item.copyWith(unread: count)
        else
          item,
    ];
  }

  /// Tags project clients in the DOC channel and gives them a green unread.
  Future<void> announceCreatedDoc(ChatV1DocRequest doc) async {
    final sopId = (salesSopId ?? doc.salesSopId ?? '').trim();
    if (sopId.isEmpty) return;
    try {
      final rows = await _api.listMembers(sopId);
      final notice = docCreatedNoticeFromMemberRows(
        rows,
        description: doc.description,
      );
      if (!notice.hasTags) {
        print('[ChatV1] DOC created with no client to tag');
        return;
      }
      final channelId = await _docChannelId(sopId);
      if (channelId == null || channelId.isEmpty) {
        print('[ChatV1] DOC created but Update and Doc channel was not found');
        return;
      }
      await _api.sendMessage(
        channelId,
        body: notice.body,
        mentionedUserIds: notice.userIds,
      );
      print('[ChatV1] Tagged clients on DOC create: ${notice.userIds}');
    } catch (e) {
      print('[ChatV1] Could not tag client about new DOC: $e');
    }
  }

  Future<String?> _docChannelId(String sopId) async {
    final loaded = _findLoadedDocChannel();
    if (loaded != null && loaded.id.isNotEmpty) return loaded.id;
    final rows = await _api.listConversations(
      contextType: 'sales_sop',
      contextId: sopId,
    );
    for (final row in rows) {
      final title = (row['title'] ?? row['name'] ?? '').toString();
      if (!ChatV1Utils.isUpdateAndDocChannel(title)) continue;
      final id = (row['id'] ?? row['conversation_id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  /// Client opened a DOC chat. Clears that task's green count.
  Future<void> markDocsSeen(Iterable<String> docIds) async {
    if (!await _viewerIsClient()) return;
    final seen = await _readSeenDocIds();
    var added = false;
    for (final id in docIds) {
      final trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) added = true;
    }
    if (added) await _writeSeenDocIds(seen);
    docTasks = [
      for (final task in docTasks)
        if (seen.contains(task.contextId) && task.unread > 0)
          task.copyWith(unread: 0)
        else
          task,
    ];
    final unseen = docTasks.fold<int>(0, (sum, task) => sum + task.unread);
    channels = [
      for (final item in channels)
        if (!_isDocChannel(item))
          item
        else if (unseen <= 0)
          item.copyWith(unread: 0, mentionsSeen: true)
        else
          item.copyWith(unread: unseen),
    ];
    if (unseen <= 0) {
      final channel = _findLoadedDocChannel();
      if (channel != null && channel.id.isNotEmpty) {
        // ignore: unawaited_futures
        _api.markConversationRead(channel.id);
      }
    }
    notifyListeners();
  }

  Future<void> _refreshClientDocTasks() async {
    if (!await _viewerIsClient()) return;
    final sopId = salesSopId;
    if (sopId == null || sopId.isEmpty) return;
    try {
      final rows = await _api.listDocs(sopId);
      await _applyClientDocTasks(rows);
      notifyListeners();
    } catch (e) {
      print('[ChatV1] DOC task refresh failed: $e');
    }
  }

  void _scheduleClientDocTaskRefresh(String conversationId) {
    final channel = _findLoadedDocChannel();
    if (channel == null || channel.id != conversationId) return;
    _docTaskRefresh?.cancel();
    _docTaskRefresh = Timer(const Duration(milliseconds: 400), () {
      unawaited(_refreshClientDocTasks());
    });
  }

  void _ensureSocketBound() {
    if (_socketBound) return;
    _socketBound = true;
    _socket.on('message_created', _onSocketMessageCreated);
    _socket.on('mention_received', _onMentionReceived);
    _socket.on('connected', _onSocketConnected);
    _socket.on('logged_out', _onSocketLoggedOut);
  }

  void _onSocketConnected(dynamic data) {
    if (ChatV1Socket.asMap(data)?['recovered'] != true) return;
    _scheduleRecovery();
  }

  void _scheduleRecovery() {
    if (_disposed || _recoveryTimer != null) return;
    if (_catchingUp) {
      _catchUpAgain = true;
      return;
    }
    final session = _socket.sessionGeneration;
    final elapsed = _lastRecoveryAt == null
        ? recoveryCooldown
        : DateTime.now().difference(_lastRecoveryAt!);
    final remaining = recoveryCooldown - elapsed;
    final delay = (remaining.isNegative ? Duration.zero : remaining) +
        Duration(milliseconds: 250 + Random().nextInt(1000));
    _recoveryTimer = Timer(delay, () {
      _recoveryTimer = null;
      if (!_recoveryIsCurrent(session)) return;
      unawaited(_catchUpAfterReconnect());
    });
  }

  bool _recoveryIsCurrent(int session) =>
      !_disposed && _socket.sessionGeneration == session && _socket.isConnected;

  void _onSocketLoggedOut(dynamic _) {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _catchUpAgain = false;
    _lastRecoveryAt = null;
    _messageCache.clear();
    _messageCacheLru.clear();
    _seenMentionMessageIds.clear();
    channels = [];
    customGroups = [];
    dms = [];
    _docTaskRefresh?.cancel();
    _docTaskRefresh = null;
    taskConversations = [];
    workflowConversations = [];
    docTasks = [];
    members = [];
    salesSopId = null;
    currentUserId = null;
    currentUserName = null;
    _flagsLoaded = false;
    _localFlags.clear();
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _recoveryMessages(String id,
      {String? afterId, int pageSize = 100}) {
    final loader = _recoveryMessageLoader;
    return loader != null
        ? loader(id, afterId, pageSize)
        : _api.listMessages(id, afterId: afterId, pageSize: pageSize);
  }

  @visibleForTesting
  Future<void> recoverAfterReconnectForTesting() {
    _ensureSocketBound();
    return _catchUpAfterReconnect();
  }

  /// One open conversation is recovered; inactive caches are refreshed on
  /// their next open. The page cap prevents long outages from causing an
  /// unbounded query storm across every chat previously visited on the phone.
  Future<void> _catchUpAfterReconnect() async {
    if (_catchingUp) {
      _catchUpAgain = true;
      return;
    }
    final session = _socket.sessionGeneration;
    if (!_recoveryIsCurrent(session)) return;
    final id = _socket.joinedConversationId;
    final sopId = salesSopId;
    _catchingUp = true;
    _lastRecoveryAt = DateTime.now();
    _messageCache.removeWhere((key, _) => key != id);
    _messageCacheLru.removeWhere((key) => key != id);
    try {
      if (id != null) {
        var cursor = _messageCache[id]?.last.id;
        final fresh = <ChatV1Message>[];
        final recoveredRows = <String, Map<String, dynamic>>{};

        void mergeRows(List<Map<String, dynamic>> rows) {
          final known = _messageCache[id]?.map((m) => m.id).toSet() ?? {};
          final mapped = rows
              .map((row) => ChatV1Mapper.messageFromJson(row,
                  currentUserId: currentUserId ?? ''))
              .toList();
          for (var index = 0; index < mapped.length; index++) {
            final message = mapped[index];
            if (message.id.isEmpty || !known.add(message.id)) continue;
            fresh.add(message);
            recoveredRows[message.id] = rows[index];
          }
          putCachedMessages(id,
              mergeConversationMessages(_messageCache[id] ?? const [], mapped));
        }

        for (var page = 0; page < maxRecoveryPages; page++) {
          final rows = await _recoveryMessages(id, afterId: cursor);
          if (!_recoveryIsCurrent(session) ||
              _socket.joinedConversationId != id) return;
          if (rows.isEmpty) break;
          mergeRows(rows);
          final next =
              (rows.last['id'] ?? rows.last['message_id'] ?? '').toString();
          if (cursor == null ||
              rows.length < 100 ||
              next.isEmpty ||
              next == cursor) {
            break;
          }
          cursor = next;
          if (page == maxRecoveryPages - 1) {
            // Bound a long gap and still show the newest messages immediately.
            final recent = await _recoveryMessages(id);
            if (!_recoveryIsCurrent(session) ||
                _socket.joinedConversationId != id) return;
            mergeRows(recent);
          }
        }
        if (fresh.isNotEmpty) _applyCaughtUpPreview(id, fresh);
        for (final row in recoveredRows.values) {
          if (!_recoveryIsCurrent(session)) return;
          _socket.deliverRecoveredMessage(id, row);
        }
      }
      if (!_recoveryIsCurrent(session) || sopId == null) return;
      // Refresh authoritative channel previews and unread/mention counts once
      // per recovery, rather than replaying all inactive histories.
      final loader = _recoveryConversationLoader;
      final rows = loader != null
          ? await loader(sopId)
          : await _api.listConversations(
              contextType: 'sales_sop', contextId: sopId);
      if (!_recoveryIsCurrent(session) || salesSopId != sopId) return;
      _applyConversations(rows);
      _applyLocalFlags();
      notifyListeners();
    } catch (error) {
      print('[ChatV1] CHAT SOCKET message catch-up error: $error');
    } finally {
      _catchingUp = false;
      if (_catchUpAgain) {
        _catchUpAgain = false;
        _scheduleRecovery();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recoveryTimer?.cancel();
    if (_socketBound) {
      _socket.off('message_created', _onSocketMessageCreated);
      _socket.off('mention_received', _onMentionReceived);
      _socket.off('connected', _onSocketConnected);
      _socket.off('logged_out', _onSocketLoggedOut);
    }
    super.dispose();
  }

  void _applyCaughtUpPreview(String conversationId, List<ChatV1Message> fresh) {
    fresh.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final latest = _messageCache[conversationId]?.last ?? fresh.last;
    final preview = ChatV1Mapper.formatLastMessagePreview({
      'type': _previewType(latest),
      'text': latest.body,
      'sender': latest.authorName,
      'is_from_me': latest.isMine,
      'attachment_count': latest.attachments.length,
      'attachment_name': latest.fileName,
    });
    final openId = _socket.joinedConversationId;
    final isOpen = openId != null && openId == conversationId;
    if (!isOpen) {
      final me = (currentUserId ?? '').trim();
      if (me.isNotEmpty) {
        for (final message in fresh) {
          if (message.isMine) continue;
          final mentioned = message.mentions.any((m) => m.userId == me);
          if (!mentioned) continue;
          _noteUnreadMentionOnce(conversationId, message.id);
        }
      }
    }
    final extraUnread = isOpen ? 0 : fresh.where((m) => !m.isMine).length;
    var changed = false;

    List<ChatV1TaskItem> patchTasks(List<ChatV1TaskItem> source) {
      return source.map((t) {
        final id = t.conversationId ?? t.id;
        if (id != conversationId) return t;
        changed = true;
        return t.copyWith(
          lastActivity: latest.sentAt,
          lastMessagePreview: preview.label,
          hasMessages: !preview.isEmpty,
          unread: t.unread + extraUnread,
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
          lastActivity: latest.sentAt,
          unread: c.unread + extraUnread,
        );
      }).toList();
    }

    channels = patchChats(channels);
    customGroups = patchChats(customGroups);
    dms = patchChats(dms);
    if (changed) notifyListeners();
  }

  String _previewType(ChatV1Message message) {
    switch (message.type) {
      case ChatV1MsgType.image:
        return 'image';
      case ChatV1MsgType.pdf:
      case ChatV1MsgType.document:
        return 'document';
      default:
        return message.attachments.length > 1 ? 'attachments' : 'text';
    }
  }

  void _onSocketMessageCreated(dynamic data) {
    // Catch-up already merged the cache and counters. Replay only updates
    // screen listeners; it must not increment unread a second time.
    if (ChatV1Socket.asMap(data)?['_recovered'] == true) return;
    final unwrapped = ChatV1Socket.unwrapMessageEvent(data);
    if (unwrapped == null) return;
    final conversationId = (unwrapped['conversationId'] ?? '').toString();
    if (conversationId.isEmpty) return;
    final message = Map<String, dynamic>.from(unwrapped['message'] as Map);
    if (_messageCache.containsKey(conversationId)) {
      upsertCachedMessage(
        conversationId,
        ChatV1Mapper.messageFromJson(
          message,
          currentUserId: currentUserId ?? '',
        ),
      );
    }

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
    final messageId = (message['id'] ?? message['message_id'] ?? '').toString();

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
    if (!fromMe &&
        !isOpen &&
        _payloadMentionsCurrentUser(message['mentions'])) {
      _noteUnreadMentionOnce(conversationId, messageId);
    }

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
    if (!fromMe) _scheduleClientDocTaskRefresh(conversationId);

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

  /// Project Important channel (web copies marked messages here).
  ChatV1ChatItem? findImportantChannel() {
    for (final item in channels) {
      if (item.title.trim() == 'Important' &&
          (item.contextType ?? '').toLowerCase() == 'sales_sop') {
        return item;
      }
    }
    for (final item in channels) {
      if (item.title.trim().toLowerCase() == 'important') return item;
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
      focusMessageId:
          task.mentions > 0 ? task.unreadMentionMessageId : null,
    );
  }

  bool _payloadMentionsCurrentUser(dynamic rawMentions) {
    final me = (currentUserId ?? '').trim();
    if (me.isEmpty || rawMentions is! List) return false;
    for (final item in rawMentions) {
      final uid = item is Map
          ? (item['user_id'] ?? item['id'] ?? item['mentioned_user_id'] ?? '')
              .toString()
          : item.toString();
      if (uid.isNotEmpty && uid == me) return true;
    }
    return false;
  }

  void _noteUnreadMentionOnce(String conversationId, String messageId) {
    final mid = messageId.trim();
    if (mid.isEmpty || !_seenMentionMessageIds.add(mid)) return;
    _noteUnreadMention(conversationId, mid);
  }

  void _noteUnreadMention(String conversationId, String messageId) {
    var changed = false;
    String? keepTarget(String? current) {
      if (current != null && current.isNotEmpty) return current;
      return messageId.isEmpty ? current : messageId;
    }

    List<ChatV1TaskItem> bumpTasks(List<ChatV1TaskItem> source) {
      return source.map((t) {
        final id = t.conversationId ?? t.id;
        if (id != conversationId) return t;
        changed = true;
        return t.copyWith(
          mentions: t.mentions + 1,
          unreadMentionMessageId: keepTarget(t.unreadMentionMessageId),
        );
      }).toList();
    }

    List<ChatV1ChatItem> bumpChats(List<ChatV1ChatItem> source) {
      return source.map((c) {
        if (c.id != conversationId) return c;
        changed = true;
        return c.copyWith(
          mentions: c.mentions + 1,
          unreadMentionMessageId: keepTarget(c.unreadMentionMessageId),
        );
      }).toList();
    }

    taskConversations = bumpTasks(taskConversations);
    workflowConversations = bumpTasks(workflowConversations);
    channels = bumpChats(channels);
    customGroups = bumpChats(customGroups);
    dms = bumpChats(dms);
    if (changed) notifyListeners();
  }

  void _onMentionReceived(dynamic data) {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    final raw = map['mention'];
    if (raw is! Map) return;
    final mention = Map<String, dynamic>.from(raw);
    final mentioned = (mention['mentioned_user_id'] ?? '').toString();
    final me = currentUserId ?? '';
    if (me.isEmpty || mentioned != me) return;
    final conversationId = (mention['conversation_id'] ?? '').toString();
    if (conversationId.isEmpty) return;
    final openId = _socket.joinedConversationId;
    if (openId != null && openId == conversationId) return;
    final messageId = (mention['message_id'] ?? '').toString();
    _noteUnreadMentionOnce(conversationId, messageId);
  }

  void markConversationSeen(String conversationId) {
    var changed = false;
    taskConversations = taskConversations.map((t) {
      final id = t.conversationId ?? t.id;
      if (id != conversationId || (t.unread == 0 && t.mentions == 0)) return t;
      changed = true;
      return t.copyWith(unread: 0, mentionsSeen: true);
    }).toList();
    workflowConversations = workflowConversations.map((t) {
      final id = t.conversationId ?? t.id;
      if (id != conversationId || (t.unread == 0 && t.mentions == 0)) return t;
      changed = true;
      return t.copyWith(unread: 0, mentionsSeen: true);
    }).toList();
    channels = channels.map((c) {
      if (c.id != conversationId || (c.unread == 0 && c.mentions == 0)) return c;
      changed = true;
      return c.copyWith(unread: 0, mentionsSeen: true);
    }).toList();
    customGroups = customGroups.map((c) {
      if (c.id != conversationId || (c.unread == 0 && c.mentions == 0)) return c;
      changed = true;
      return c.copyWith(unread: 0, mentionsSeen: true);
    }).toList();
    dms = dms.map((c) {
      if (c.id != conversationId || (c.unread == 0 && c.mentions == 0)) return c;
      changed = true;
      return c.copyWith(unread: 0, mentionsSeen: true);
    }).toList();
    if (changed) notifyListeners();
  }
}

class _SavedChatFlags {
  final bool pinned;
  final bool muted;
  final bool archived;

  const _SavedChatFlags({
    this.pinned = false,
    this.muted = false,
    this.archived = false,
  });
}
