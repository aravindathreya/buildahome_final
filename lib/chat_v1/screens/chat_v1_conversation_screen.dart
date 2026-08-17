import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../chat_v1_api.dart';
import '../chat_v1_controller.dart';
import '../chat_v1_mapper.dart';
import '../chat_v1_models.dart';
import '../chat_v1_socket.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import '../widgets/chat_v1_common.dart';
import '../widgets/chat_v1_composer.dart';
import '../widgets/chat_v1_message_bubble.dart';
import 'chat_v1_group_info_screen.dart';
import 'chat_v1_task_details_sheet.dart';

class ChatV1ConversationScreen extends StatefulWidget {
  final ChatV1ConvMeta meta;
  final VoidCallback onOpenInfo;

  const ChatV1ConversationScreen({
    super.key,
    required this.meta,
    required this.onOpenInfo,
  });

  @override
  State<ChatV1ConversationScreen> createState() =>
      _ChatV1ConversationScreenState();
}

class _ChatV1ConversationScreenState extends State<ChatV1ConversationScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _api = ChatV1Api.instance;
  final _socket = ChatV1Socket.instance;

  List<ChatV1Message> _messages = [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _showJump = false;
  String? _error;
  String? _replyToId;
  String? _replyPreview;
  String? _replyAuthor;
  String? _highlightMessageId;
  ChatV1ErpTaskDetails? _erpDetails;
  bool _loadingDetails = false;
  final Map<String, GlobalKey> _messageKeys = {};

  /// Other users currently typing in this conversation.
  final Set<String> _typingUserIds = {};
  final Map<String, String> _typingNames = {};
  Timer? _typingDebounce;
  Timer? _typingIdle;
  bool _amTyping = false;

  String get _conversationId => widget.meta.id;
  String get _userId => ChatV1Controller.instance.currentUserId ?? '';
  bool get _isErpTask => widget.meta.contextType == 'erp_task';
  bool get _othersTyping => _typingUserIds.isNotEmpty;

  /// Same rule as web: hide Share to General when already in General.
  bool get _isGeneralChannel {
    final title =
        ChatV1Utils.canonicalChannelTitle(widget.meta.title).toLowerCase();
    if (title != 'general') return false;
    final ctx = (widget.meta.contextType ?? '').toLowerCase();
    // Channels are usually sales_sop-scoped; also accept empty/legacy.
    return ctx.isEmpty || ctx == 'sales_sop';
  }

  GlobalKey _keyForMessage(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  String get _typingLabel {
    final names = _typingUserIds
        .map((id) => _typingNames[id] ?? 'Someone')
        .toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
    return '${names.length} people are typing…';
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Warm open: restore cache before first frame (no full-screen spinner).
    final cached =
        ChatV1Controller.instance.cachedMessages(_conversationId);
    if (cached != null && cached.isNotEmpty) {
      _messages = _enrichReplyPreviews(cached);
      _loading = false;
    }
    _load();
    _bindSocket();
    if (_isErpTask) _loadErpDetails();
  }

  void _onScroll() {
    final show = _scroll.hasClients &&
        _scroll.position.maxScrollExtent - _scroll.offset > 240;
    if (show != _showJump) setState(() => _showJump = show);
    if (_scroll.hasClients &&
        _scroll.offset <= 40 &&
        !_loadingOlder &&
        _messages.isNotEmpty) {
      _loadOlder();
    }
  }

  Future<void> _load() async {
    final ctrl = ChatV1Controller.instance;
    final hadCache = _messages.isNotEmpty && !_loading;

    if (hadCache) {
      // Jump once to latest; background refresh must not flash top→bottom again.
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } else {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      } else {
        _loading = true;
        _error = null;
      }
    }

    try {
      // Messages API embeds extras (include_extras=true). No getConversation on
      // the critical path — its result was unused for the message UI.
      final rows = await _api.listMessages(_conversationId, pageSize: 50);
      final uid = _userId;
      final mapped = rows
          .map((r) => ChatV1Mapper.messageFromJson(r, currentUserId: uid))
          .toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (!mounted) return;

      final merged = _enrichReplyPreviews(
        hadCache
            ? ctrl.mergeConversationMessages(_messages, mapped)
            : mapped,
      );

      if (!hadCache) {
        setState(() {
          _messages = merged;
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      } else if (!_messageListsVisuallySame(_messages, merged)) {
        // Background refresh: update without blanking; avoid unexpected jumps.
        final pos = _scroll.hasClients ? _scroll.position : null;
        final prevPixels = pos?.pixels;
        final prevMax = pos?.maxScrollExtent;
        final nearBottom = pos != null &&
            prevMax != null &&
            prevPixels != null &&
            (prevMax - prevPixels) < 120;

        setState(() => _messages = merged);

        if (prevPixels != null && prevMax != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final newMax = _scroll.position.maxScrollExtent;
            if (nearBottom) {
              _jumpToBottom();
            } else {
              // Keep the same distance from the bottom when content grows.
              final fromBottom = prevMax - prevPixels;
              _scroll.jumpTo(
                (newMax - fromBottom).clamp(0.0, newMax),
              );
            }
          });
        }
      }

      ctrl.putCachedMessages(_conversationId, _messages);

      final newest = _messages.isNotEmpty ? _messages.last.id : null;
      await _api.markConversationRead(
        _conversationId,
        upToMessageId: newest,
      );
      ctrl.markConversationSeen(_conversationId);
      _socket.conversationRead(_conversationId);
    } catch (e) {
      if (!mounted) return;
      // Keep cached messages visible on refresh failure.
      if (hadCache) {
        setState(() => _error = null);
      } else {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Fill weak "Author: Attachment" quotes from the parent message in-list.
  List<ChatV1Message> _enrichReplyPreviews(List<ChatV1Message> messages) {
    if (messages.isEmpty) return messages;
    final byId = <String, ChatV1Message>{
      for (final m in messages)
        if (m.id.isNotEmpty) m.id: m,
    };
    var changed = false;
    final out = <ChatV1Message>[];
    for (final m in messages) {
      final parentId = m.parentMessageId;
      if (parentId == null || parentId.isEmpty) {
        out.add(m);
        continue;
      }
      final parent = byId[parentId];
      if (parent == null) {
        out.add(m);
        continue;
      }
      final better = ChatV1Utils.formatReplyPreview(
        authorName: parent.isMine ? 'You' : parent.authorName,
        snippet: ChatV1Utils.replySnippet(parent),
      );
      if (m.replyPreview != better) {
        changed = true;
        out.add(m.copyWith(replyPreview: better));
      } else {
        out.add(m);
      }
    }
    return changed ? out : messages;
  }

  bool _messageListsVisuallySame(
    List<ChatV1Message> a,
    List<ChatV1Message> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.body != y.body ||
          x.edited != y.edited ||
          x.isPinned != y.isPinned ||
          x.isDeleted != y.isDeleted ||
          x.read != y.read ||
          x.attachments.length != y.attachments.length ||
          x.reactions.length != y.reactions.length) {
        return false;
      }
      for (var r = 0; r < x.reactions.length; r++) {
        if (x.reactions[r].emoji != y.reactions[r].emoji ||
            x.reactions[r].count != y.reactions[r].count ||
            x.reactions[r].mine != y.reactions[r].mine) {
          return false;
        }
      }
      for (var t = 0; t < x.attachments.length; t++) {
        if (x.attachments[t].storagePath != y.attachments[t].storagePath ||
            x.attachments[t].id != y.attachments[t].id) {
          return false;
        }
      }
    }
    return true;
  }

  void _persistMessagesCache() {
    ChatV1Controller.instance.putCachedMessages(_conversationId, _messages);
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final oldest = _messages.first.id;
      final rows = await _api.listMessages(
        _conversationId,
        pageSize: 50,
        beforeId: oldest,
      );
      if (rows.isEmpty) return;
      final mapped = rows
          .map((r) =>
              ChatV1Mapper.messageFromJson(r, currentUserId: _userId))
          .toList();
      if (!mounted) return;
      final existing = _messages.map((m) => m.id).toSet();
      final older =
          mapped.where((m) => !existing.contains(m.id)).toList()
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (older.isEmpty) return;

      final pos = _scroll.hasClients ? _scroll.position : null;
      final prevPixels = pos?.pixels;
      final prevMax = pos?.maxScrollExtent;

      final next = _enrichReplyPreviews([...older, ..._messages]);
      setState(() => _messages = next);
      _persistMessagesCache();

      if (prevPixels != null && prevMax != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final newMax = _scroll.position.maxScrollExtent;
          final delta = newMax - prevMax;
          _scroll.jumpTo((prevPixels + delta).clamp(0.0, newMax));
        });
      }
    } catch (_) {
      // ignore pagination errors
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// Refresh attachments for a single message after upload (not used on load).
  Future<List<ChatV1Attachment>> _refreshMessageAttachments(
    String messageId,
  ) async {
    // ignore: deprecated_member_use_from_same_package
    final rows = await _api.getMessageAttachments(messageId);
    return rows
        .map(ChatV1Mapper.attachmentFromJson)
        .where((a) => a.storagePath.isNotEmpty)
        .toList();
  }

  Future<void> _loadErpDetails() async {
    final sopId = ChatV1Controller.instance.salesSopId;
    final erpTaskId = widget.meta.contextId;
    if (sopId == null || erpTaskId == null || erpTaskId.isEmpty) return;
    setState(() => _loadingDetails = true);
    try {
      final raw = await _api.getErpTaskDiscussionDetails(
        salesSopId: sopId,
        erpTaskId: erpTaskId,
      );
      if (!mounted) return;
      setState(() {
        _erpDetails = ChatV1Mapper.erpTaskDetailsFromJson(raw);
        _loadingDetails = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _bindSocket() async {
    _socket.on('message_created', _onMessageCreated);
    _socket.on('attachment_uploaded', _onAttachmentUploaded);
    _socket.on('typing_started', _onTypingStart);
    _socket.on('typing_stopped', _onTypingStop);
    _socket.on('typing_snapshot', _onTypingSnapshot);
    _socket.on('reaction_added', _onReactionAdded);
    _socket.on('reaction_removed', _onReactionRemoved);
    // Connect with api_token (once, via ChatV1Socket lifecycle), then join room.
    await _socket.joinConversation(_conversationId);
    print(
      '[ChatV1] joined conversation=$_conversationId '
      'socketConnected=${_socket.isConnected}',
    );
  }

  void _onComposerChanged(String v) {
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    if (v.trim().isEmpty) {
      _stopMyTyping();
      return;
    }
    // Debounce ~300ms then emit typing_start (same event name as web).
    // Re-emit on continued typing so peers refresh; idle stop at ~3s.
    _typingDebounce = Timer(const Duration(milliseconds: 300), () {
      _amTyping = true;
      _socket.typingStart(_conversationId);
    });
    _typingIdle = Timer(const Duration(seconds: 3), _stopMyTyping);
  }

  bool _isForThisConversation(dynamic data) {
    final map = ChatV1Socket.asMap(data) ??
        (data is Map ? Map<String, dynamic>.from(data) : null);
    if (map == null) return true;
    final id =
        (map['conversation_id'] ?? map['conversationId'] ?? '').toString();
    if (id.isEmpty) return true;
    return id == _conversationId.toString();
  }

  void _onMessageCreated(dynamic data) async {
    final unwrapped = ChatV1Socket.unwrapMessageEvent(data);
    if (unwrapped == null) return;
    final convId = (unwrapped['conversationId'] ?? '').toString();
    if (convId.isNotEmpty && convId != _conversationId) return;

    final msg = Map<String, dynamic>.from(unwrapped['message'] as Map);
    // Extras default to empty in the mapper. Do NOT fan-out HTTP for
    // attachments/reactions/mentions/reads — attachment_uploaded refreshes one msg.
    final mapped =
        ChatV1Mapper.messageFromJson(msg, currentUserId: _userId);
    if (!mounted) return;

    // Clear typing for this sender.
    final senderId = mapped.authorId;
    if (senderId.isNotEmpty) {
      _typingUserIds.remove(senderId);
      _typingNames.remove(senderId);
    }

    if (!mounted) return;
    _upsertMessage(mapped);
  }

  void _onAttachmentUploaded(dynamic data) async {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    final messageId =
        (map['message_id'] ?? map['messageId'] ?? '').toString();
    if (messageId.isEmpty) return;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    try {
      // Single-message refresh only (upload completed via socket).
      final atts = await _refreshMessageAttachments(messageId);
      if (!mounted || atts.isEmpty) return;
      final existing = _messages[idx];
      // Preserve local preview bytes when server attachments arrive.
      final withPreview = [
        for (var i = 0; i < atts.length; i++)
          ChatV1Attachment(
            id: atts[i].id,
            messageId: atts[i].messageId,
            fileName: atts[i].fileName,
            contentType: atts[i].contentType,
            fileSize: atts[i].fileSize,
            storagePath: atts[i].storagePath,
            previewBytes: i < existing.attachments.length
                ? existing.attachments[i].previewBytes
                : null,
          ),
      ];
      _upsertMessage(
        existing.copyWith(
          attachments: withPreview,
          type: withPreview.every((a) => a.isImage)
              ? ChatV1MsgType.image
              : (withPreview.any((a) => a.isPdf)
                  ? ChatV1MsgType.pdf
                  : ChatV1MsgType.document),
          fileName: withPreview.first.fileName,
          fileMeta: withPreview.first.contentType,
        ),
      );
    } catch (_) {}
  }

  String? _userIdFromTypingPayload(Map<String, dynamic> map) {
    final uid = map['user_id'] ?? map['userId'] ?? map['sender_id'];
    if (uid != null) return uid.toString();
    final user = map['user'];
    if (user is Map) return (user['id'] ?? user['user_id'])?.toString();
    return null;
  }

  String? _userNameFromTypingPayload(Map<String, dynamic> map) {
    final name = map['user_name'] ?? map['name'] ?? map['sender_name'];
    if (name != null && name.toString().isNotEmpty) return name.toString();
    final user = map['user'];
    if (user is Map) {
      final n = user['name'] ?? user['username'];
      if (n != null) return n.toString();
    }
    return null;
  }

  void _onTypingStart(dynamic data) {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    if (!_isForThisConversation(map)) return;
    final uid = _userIdFromTypingPayload(map);
    if (uid == null || uid.isEmpty || uid == _userId) return;
    final name = _userNameFromTypingPayload(map);
    String resolved = name ?? 'Someone';
    if (name == null) {
      for (final m in widget.meta.members) {
        if (m.id == uid) {
          resolved = m.name;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _typingUserIds.add(uid);
      _typingNames[uid] = resolved;
    });
  }

  void _onTypingStop(dynamic data) {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    if (!_isForThisConversation(map)) return;
    final uid = _userIdFromTypingPayload(map);
    if (uid == null || uid.isEmpty || uid == _userId) return;
    if (!mounted) return;
    setState(() {
      _typingUserIds.remove(uid);
      _typingNames.remove(uid);
    });
  }

  void _onTypingSnapshot(dynamic data) {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    if (!_isForThisConversation(map)) return;
    final idsRaw = map['user_ids'] ?? map['userIds'] ?? [];
    if (idsRaw is! List) return;
    if (!mounted) return;
    setState(() {
      _typingUserIds.clear();
      _typingNames.clear();
      for (final id in idsRaw) {
        final uid = id.toString();
        if (uid.isEmpty || uid == _userId) continue;
        _typingUserIds.add(uid);
        var name = 'Someone';
        for (final m in widget.meta.members) {
          if (m.id == uid) {
            name = m.name;
            break;
          }
        }
        _typingNames[uid] = name;
      }
    });
  }

  void _stopMyTyping() {
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    if (_amTyping) {
      _amTyping = false;
      _socket.typingStop(_conversationId);
    }
  }

  String? _messageIdFromReactionPayload(Map<String, dynamic> map) {
    final id = map['message_id'] ?? map['messageId'];
    if (id != null && id.toString().isNotEmpty) return id.toString();
    final message = map['message'];
    if (message is Map) {
      final mid = message['id'] ?? message['message_id'];
      if (mid != null) return mid.toString();
    }
    return null;
  }

  String? _emojiFromReactionPayload(Map<String, dynamic> map) {
    final emoji = map['reaction'] ?? map['emoji'] ?? map['reaction_emoji'];
    if (emoji != null && emoji.toString().isNotEmpty) return emoji.toString();
    return null;
  }

  void _onReactionAdded(dynamic data) {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    final messageId = _messageIdFromReactionPayload(map);
    if (messageId == null) return;

    // Prefer authoritative reactions list when the server sends it.
    if (_replaceReactionsFromPayload(messageId, map)) return;

    final emoji = _emojiFromReactionPayload(map);
    if (emoji == null) return;
    final uid = (map['user_id'] ?? map['userId'] ?? map['sender_id'])?.toString();
    final mine = uid != null && uid.isNotEmpty && uid == _userId;
    _applyReaction(messageId, emoji, add: true, mine: mine);
  }

  void _onReactionRemoved(dynamic data) {
    final map = ChatV1Socket.asMap(data);
    if (map == null) return;
    final messageId = _messageIdFromReactionPayload(map);
    if (messageId == null) return;

    if (_replaceReactionsFromPayload(messageId, map)) return;

    final emoji = _emojiFromReactionPayload(map);
    if (emoji == null) return;
    final uid = (map['user_id'] ?? map['userId'] ?? map['sender_id'])?.toString();
    final mine = uid != null && uid.isNotEmpty && uid == _userId;
    _applyReaction(messageId, emoji, add: false, mine: mine);
  }

  bool _replaceReactionsFromPayload(
    String messageId,
    Map<String, dynamic> map,
  ) {
    final raw = map['reactions'];
    final message = map['message'];
    final list = raw is List
        ? raw
        : (message is Map && message['reactions'] is List
            ? message['reactions'] as List
            : null);
    if (list == null) return false;

    final reactions = <ChatV1Reaction>[];
    for (final r in list) {
      if (r is! Map) continue;
      final emoji = (r['emoji'] ?? r['reaction'] ?? '').toString();
      if (emoji.isEmpty) continue;
      reactions.add(ChatV1Reaction(
        emoji: emoji,
        count: (r['count'] is num) ? (r['count'] as num).toInt() : 1,
        mine: r['mine'] == true ||
            r['reacted_by_me'] == true ||
            (r['user_id']?.toString() == _userId),
      ));
    }

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0 || !mounted) return true;
    setState(() {
      _messages = [
        for (var i = 0; i < _messages.length; i++)
          if (i == idx)
            _messages[i].copyWith(reactions: reactions)
          else
            _messages[i],
      ];
    });
    _persistMessagesCache();
    return true;
  }

  /// Optimistically (or via socket) update reaction chips on a message.
  void _applyReaction(
    String messageId,
    String emoji, {
    required bool add,
    bool mine = false,
  }) {
    if (!mounted) return;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = _messages[idx];
    final next = <ChatV1Reaction>[];
    var found = false;

    for (final r in msg.reactions) {
      if (r.emoji != emoji) {
        next.add(r);
        continue;
      }
      found = true;
      if (add) {
        // Already counted our own optimistic reaction — ignore echo.
        if (mine && r.mine) {
          next.add(r);
        } else {
          next.add(ChatV1Reaction(
            emoji: r.emoji,
            count: r.count + 1,
            mine: r.mine || mine,
          ));
        }
      } else {
        final count = r.count - 1;
        if (count > 0) {
          next.add(ChatV1Reaction(
            emoji: r.emoji,
            count: count,
            mine: mine ? false : r.mine,
          ));
        }
      }
    }

    if (add && !found) {
      next.add(ChatV1Reaction(emoji: emoji, count: 1, mine: mine));
    }

    setState(() {
      _messages = [
        for (var i = 0; i < _messages.length; i++)
          if (i == idx) msg.copyWith(reactions: next) else _messages[i],
      ];
    });
    _persistMessagesCache();
  }

  Future<void> _reactToMessage(ChatV1Message msg, String emoji) async {
    final latest = _messages.cast<ChatV1Message?>().firstWhere(
          (m) => m?.id == msg.id,
          orElse: () => msg,
        ) ??
        msg;
    final alreadyMine =
        latest.reactions.any((r) => r.emoji == emoji && r.mine);
    // Optimistic UI so the chip shows immediately.
    _applyReaction(latest.id, emoji, add: !alreadyMine, mine: true);
    try {
      if (alreadyMine) {
        _socket.removeReaction(messageId: latest.id, emoji: emoji);
        await _api.removeReaction(latest.id, emoji);
      } else {
        _socket.addReaction(messageId: latest.id, emoji: emoji);
        await _api.addReaction(latest.id, emoji);
      }
    } catch (e) {
      // Roll back optimistic change.
      _applyReaction(latest.id, emoji, add: alreadyMine, mine: true);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _stopMyTyping();
    _typingDebounce?.cancel();
    _typingIdle?.cancel();
    _socket.off('message_created', _onMessageCreated);
    _socket.off('attachment_uploaded', _onAttachmentUploaded);
    _socket.off('typing_started', _onTypingStart);
    _socket.off('typing_stopped', _onTypingStop);
    _socket.off('typing_snapshot', _onTypingSnapshot);
    _socket.off('reaction_added', _onReactionAdded);
    _socket.off('reaction_removed', _onReactionRemoved);
    _socket.leaveConversation(_conversationId);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _appendOwnMessage(ChatV1Message mapped) async {
    if (!mounted) return;
    _upsertMessage(mapped, clearReply: true);
  }

  /// Insert or merge a message. Prefer the version that has attachments /
  /// richer media so a socket stub ("Uploaded: file.jpg") does not win over
  /// the local upload completion (or vice versa).
  void _upsertMessage(ChatV1Message incoming, {bool clearReply = false}) {
    if (!mounted) return;
    var message = incoming;
    final parentId = message.parentMessageId;
    if (parentId != null &&
        parentId.isNotEmpty &&
        ChatV1Utils.isWeakReplyPreview(message.replyPreview)) {
      final parentIdx = _messages.indexWhere((m) => m.id == parentId);
      if (parentIdx >= 0) {
        final parent = _messages[parentIdx];
        message = message.copyWith(
          replyPreview: ChatV1Utils.formatReplyPreview(
            authorName: parent.isMine ? 'You' : parent.authorName,
            snippet: ChatV1Utils.replySnippet(parent),
          ),
        );
      }
    }
    final idx = _messages.indexWhere((m) => m.id == message.id);
    setState(() {
      if (clearReply) {
        _replyToId = null;
        _replyPreview = null;
        _replyAuthor = null;
      }
      if (idx < 0) {
        _messages = [..._messages, message];
      } else {
        final existing = _messages[idx];
        final merged = _mergeMessages(existing, message);
        _messages = [
          for (var i = 0; i < _messages.length; i++)
            if (i == idx) merged else _messages[i],
        ];
      }
    });
    _persistMessagesCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  ChatV1Message _mergeMessages(ChatV1Message a, ChatV1Message b) {
    final aHas = a.attachments.isNotEmpty;
    final bHas = b.attachments.isNotEmpty;
    if (bHas && !aHas) return b;
    if (aHas && !bHas) return a;
    if (bHas && aHas) {
      // Prefer remote/hydrated paths, but keep local preview bytes if useful.
      final mergedAtts = <ChatV1Attachment>[];
      for (var i = 0; i < b.attachments.length; i++) {
        final nb = b.attachments[i];
        final na = i < a.attachments.length ? a.attachments[i] : null;
        mergedAtts.add(
          ChatV1Attachment(
            id: nb.id.isNotEmpty ? nb.id : (na?.id ?? nb.id),
            messageId: nb.messageId ?? na?.messageId,
            fileName: nb.fileName.isNotEmpty
                ? nb.fileName
                : (na?.fileName ?? nb.fileName),
            contentType: nb.contentType.isNotEmpty
                ? nb.contentType
                : (na?.contentType ?? ''),
            fileSize: nb.fileSize > 0 ? nb.fileSize : (na?.fileSize ?? 0),
            storagePath: nb.storagePath.isNotEmpty
                ? nb.storagePath
                : (na?.storagePath ?? ''),
            previewBytes: nb.previewBytes ?? na?.previewBytes,
          ),
        );
      }
      return b.copyWith(
        attachments: mergedAtts,
        type: mergedAtts.every((x) => x.isImage)
            ? ChatV1MsgType.image
            : (mergedAtts.any((x) => x.isPdf)
                ? ChatV1MsgType.pdf
                : ChatV1MsgType.document),
        fileName: mergedAtts.first.fileName,
        fileMeta: mergedAtts.first.contentType,
      );
    }
    // Neither has attachments — prefer non-placeholder body / later type.
    final aPlaceholder = a.body.toLowerCase().startsWith('uploaded:');
    final bPlaceholder = b.body.toLowerCase().startsWith('uploaded:');
    if (aPlaceholder && !bPlaceholder) return b;
    if (!aPlaceholder && bPlaceholder) return a;
    if (b.type != ChatV1MsgType.text && a.type == ChatV1MsgType.text) return b;
    return b;
  }

  Future<void> _send({List<int>? fileBytes, String? fileName}) async {
    final text = _composer.text.trim();
    final hasFile = fileBytes != null && fileName != null;
    if ((text.isEmpty && !hasFile) || _sending) return;
    setState(() => _sending = true);
    final body = text.isNotEmpty
        ? text
        : (hasFile ? 'Uploaded: $fileName' : '');
    final replyParentId = _replyToId;
    final parentMsg = replyParentId == null
        ? null
        : _messages.cast<ChatV1Message?>().firstWhere(
              (m) => m?.id == replyParentId,
              orElse: () => null,
            );
    final replyPreviewLocal = replyParentId == null
        ? null
        : ChatV1Utils.formatReplyPreview(
            authorName: _replyAuthor ?? parentMsg?.authorName ?? 'Someone',
            snippet: (_replyPreview != null && _replyPreview!.trim().isNotEmpty)
                ? _replyPreview!
                : (parentMsg != null
                    ? ChatV1Utils.replySnippet(parentMsg)
                    : 'Message'),
          );
    _composer.clear();
    _stopMyTyping();
    try {
      final parentId = int.tryParse(replyParentId ?? '');
      Map<String, dynamic>? created;

      // Prefer socket send (same as web); fall back to REST.
      // File messages go through REST so we can attach uploads reliably.
      if (!hasFile) {
        try {
          created = await _socket.sendMessage(
            conversationId: _conversationId,
            body: body,
            parentMessageId: parentId,
          );
        } catch (e) {
          print('[ChatV1] socket send failed: $e');
        }
      }
      if (created == null) {
        created = await _api.sendMessage(
          _conversationId,
          body: body,
          parentMessageId: parentId,
        );
      }

      var mapped =
          ChatV1Mapper.messageFromJson(created, currentUserId: _userId);
      if (replyParentId != null) {
        final apiPreview = mapped.replyPreview;
        final useLocal = replyPreviewLocal != null &&
            (ChatV1Utils.isWeakReplyPreview(apiPreview) ||
                apiPreview == null ||
                apiPreview.isEmpty);
        mapped = mapped.copyWith(
          parentMessageId:
              (mapped.parentMessageId == null || mapped.parentMessageId!.isEmpty)
                  ? replyParentId
                  : mapped.parentMessageId,
          replyPreview: useLocal ? replyPreviewLocal : apiPreview,
        );
      }
      if (hasFile) {
        final upload = await _api.uploadDiscussionAttachment(
          bytes: fileBytes,
          fileName: fileName,
        );
        final url = ChatV1Utils.resolveMediaUrl(
          _extractUploadUrl(upload) ?? '',
        );
        final name =
            (upload?['filename'] ?? upload?['file_name'] ?? fileName)
                .toString();
        if (url.isNotEmpty) {
          final contentType = _guessContentType(name);
          await _api.attachMessageFiles(mapped.id, [
            {
              'file_name': name,
              'storage_path': url,
              'content_type': contentType,
              'file_size': fileBytes.length,
            },
          ]);

          // Prefer server attachment records (canonical URLs), fall back to local.
          List<ChatV1Attachment> atts = [];
          try {
            atts = await _refreshMessageAttachments(mapped.id);
          } catch (_) {}
          if (atts.isEmpty) {
            atts = [
              ChatV1Attachment(
                id: 'local',
                messageId: mapped.id,
                fileName: name,
                contentType: contentType,
                fileSize: fileBytes.length,
                storagePath: url,
                previewBytes: fileBytes,
              ),
            ];
          } else if (contentType.startsWith('image/')) {
            // Keep instant local preview bytes on the first image.
            atts = [
              for (var i = 0; i < atts.length; i++)
                if (i == 0)
                  ChatV1Attachment(
                    id: atts[i].id,
                    messageId: atts[i].messageId,
                    fileName: atts[i].fileName,
                    contentType: atts[i].contentType.isNotEmpty
                        ? atts[i].contentType
                        : contentType,
                    fileSize: atts[i].fileSize > 0
                        ? atts[i].fileSize
                        : fileBytes.length,
                    storagePath: atts[i].storagePath,
                    previewBytes: fileBytes,
                  )
                else
                  atts[i],
            ];
          }

          mapped = mapped.copyWith(
            attachments: atts,
            type: atts.every((a) => a.isImage)
                ? ChatV1MsgType.image
                : (atts.any((a) => a.isPdf)
                    ? ChatV1MsgType.pdf
                    : ChatV1MsgType.document),
            fileName: atts.first.fileName,
            fileMeta: atts.first.contentType,
            body: text.isNotEmpty ? text : '',
          );
        }
      }
      if (!mounted) return;
      await _appendOwnMessage(mapped);
      setState(() => _sending = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String? _extractUploadUrl(Map<String, dynamic>? upload) {
    if (upload == null) return null;
    final direct = upload['url'] ?? upload['storage_path'] ?? upload['path'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString();
    }
    final data = upload['data'];
    if (data is Map) {
      final nested = data['url'] ?? data['storage_path'] ?? data['path'];
      if (nested != null && nested.toString().trim().isNotEmpty) {
        return nested.toString();
      }
    }
    final file = upload['file'];
    if (file is Map) {
      final nested = file['url'] ?? file['storage_path'] ?? file['path'];
      if (nested != null && nested.toString().trim().isNotEmpty) {
        return nested.toString();
      }
    }
    return null;
  }

  String _guessContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _send(fileBytes: bytes, fileName: file.name);
  }

  Future<void> _pickCamera() => _pickImage(ImageSource.camera);

  Future<void> _pickGallery() => _pickImage(ImageSource.gallery);

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    await _send(fileBytes: f.bytes, fileName: f.name);
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    return Scaffold(
      backgroundColor: ChatV1Theme.chatBg(context),
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: InkWell(
          onTap: widget.onOpenInfo,
          child: Row(
            children: [
              Hero(
                tag: 'avatar_${meta.id}',
                child: Cv1Avatar(
                  initials: meta.title.isNotEmpty ? meta.title[0] : '?',
                  color: meta.accent,
                  icon: meta.icon,
                  size: 38,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ChatV1Theme.text(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      meta.isTask ? 'Task Discussion' : meta.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ChatV1Theme.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_isErpTask)
            IconButton(
              tooltip: 'Task details',
              onPressed: _erpDetails == null && !_loadingDetails
                  ? _loadErpDetails
                  : (_erpDetails == null
                      ? null
                      : () => ChatV1TaskDetailsSheet.show(
                            context,
                            _erpDetails!,
                          )),
              icon: _loadingDetails
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.info_outline_rounded),
            ),
          IconButton(
            onPressed: widget.onOpenInfo,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isErpTask && _erpDetails != null)
                _taskDetailsBanner(context, _erpDetails!),
              if (_replyToId != null)
                Container(
                  width: double.infinity,
                  color: ChatV1Theme.card(context),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 36,
                        decoration: BoxDecoration(
                          color: ChatV1Theme.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.reply_rounded,
                          size: 18, color: ChatV1Theme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replying to ${_replyAuthor ?? 'message'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ChatV1Theme.accent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_replyPreview != null)
                              Text(
                                _replyPreview!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ChatV1Theme.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _clearReply,
                      ),
                    ],
                  ),
                ),
              Expanded(child: _body(context)),
              ChatComposer(
                controller: _composer,
                onSend: () => _send(),
                onCamera: _pickCamera,
                onGallery: _pickGallery,
                onDocument: _pickFile,
                onChanged: _onComposerChanged,
                enabled: !_sending,
              ),
            ],
          ),
          if (_showJump)
            Positioned(
              right: 14,
              bottom: 76 + MediaQuery.of(context).padding.bottom,
              child: FloatingActionButton.small(
                heroTag: 'jump_bottom',
                backgroundColor: ChatV1Theme.card(context),
                foregroundColor: ChatV1Theme.text(context),
                onPressed: () {
                  _scroll.animateTo(
                    _scroll.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                  );
                },
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
        ],
      ),
    );
  }

  Widget _taskDetailsBanner(BuildContext context, ChatV1ErpTaskDetails d) {
    return InkWell(
      onTap: () => ChatV1TaskDetailsSheet.show(context, d),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ChatV1Theme.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ChatV1Theme.border(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: ChatV1Theme.text(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      Cv1Badge(
                          label: d.statusDisplay, color: ChatV1Theme.accent),
                      if (d.assigneeLabel.isNotEmpty)
                        Cv1Badge(
                            label: d.assigneeLabel,
                            color: ChatV1Theme.mention),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      itemCount: _messages.length + (_othersTyping ? 2 : 1) + (_loadingOlder ? 1 : 0),
      itemBuilder: (_, i) {
        var index = i;
        if (_loadingOlder) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          index -= 1;
        }
        if (index == 0) {
          final label = _messages.isEmpty
              ? 'Start of conversation'
              : ChatV1Utils.dateLabel(_messages.first.sentAt);
          return _dateChip(context, label);
        }
        final msgIndex = index - 1;
        if (_othersTyping && msgIndex == _messages.length) {
          return _typingRow(context);
        }
        if (msgIndex >= _messages.length) return const SizedBox.shrink();
        final msg = _messages[msgIndex];
        final showAuthor = msgIndex == 0 ||
            _messages[msgIndex - 1].authorId != msg.authorId;
        return Cv1MessageBubble(
          message: msg,
          showAuthor: showAuthor,
          highlighted: _highlightMessageId == msg.id,
          messageKey: _keyForMessage(msg.id),
          onLongPress: () => _messageActions(context, msg),
          onReplyTap: msg.parentMessageId == null ||
                  msg.parentMessageId!.isEmpty
              ? null
              : () => _scrollToMessage(msg.parentMessageId!),
          onReactionTap: msg.isDeleted
              ? null
              : (emoji) => _reactToMessage(msg, emoji),
        );
      },
    );
  }

  Widget _dateChip(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: ChatV1Theme.card(context),
            borderRadius: BorderRadius.circular(8),
            boxShadow: ChatV1Theme.shadow(context),
          ),
          child: Text(label,
              style: TextStyle(
                  color: ChatV1Theme.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _typingRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 4),
      child: Text(
        _typingLabel,
        style: TextStyle(
          color: ChatV1Theme.textMuted(context),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  void _clearReply() {
    setState(() {
      _replyToId = null;
      _replyPreview = null;
      _replyAuthor = null;
    });
  }

  void _startReply(ChatV1Message msg) {
    setState(() {
      _replyToId = msg.id;
      _replyAuthor = msg.isMine ? 'You' : msg.authorName;
      _replyPreview = ChatV1Utils.replySnippet(msg);
    });
  }

  Future<void> _scrollToMessage(String messageId) async {
    if (messageId.isEmpty) return;

    var idx = _messages.indexWhere((m) => m.id == messageId);
    // Parent may be older than the loaded window — page up a few times.
    var attempts = 0;
    while (idx < 0 && attempts < 5 && mounted) {
      attempts++;
      final before = _messages.length;
      await _loadOlder();
      if (!mounted || _messages.length == before) break;
      idx = _messages.indexWhere((m) => m.id == messageId);
    }

    if (!mounted) return;
    if (idx < 0) {
      _toast('Original message is not loaded yet');
      return;
    }

    // Prefer ensureVisible when the row is already built.
    final existingCtx = _messageKeys[messageId]?.currentContext;
    if (existingCtx != null) {
      await Scrollable.ensureVisible(
        existingCtx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
      _flashMessage(messageId);
      return;
    }

    // Not in the viewport yet — jump near its index, then ensureVisible.
    if (_scroll.hasClients && _messages.isNotEmpty) {
      // +1 accounts for the leading date chip in the list.
      final itemIndex = idx + 1 + (_loadingOlder ? 1 : 0);
      final ratio = itemIndex / (_messages.length + 2);
      final target =
          (ratio * _scroll.position.maxScrollExtent).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
      _flashMessage(messageId);
    } else {
      _toast('Original message is not loaded yet');
    }
  }

  void _flashMessage(String messageId) {
    if (!mounted) return;
    setState(() => _highlightMessageId = messageId);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (_highlightMessageId == messageId) {
        setState(() => _highlightMessageId = null);
      }
    });
  }

  void _toast(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), action: action),
    );
  }

  Future<void> _copyMessage(ChatV1Message msg) async {
    final text = msg.copyableText.trim();
    if (text.isEmpty) {
      _toast('Nothing to copy');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Copied');
  }

  Future<void> _pinMessage(ChatV1Message msg) async {
    try {
      if (msg.isPinned) {
        await _api.unpinConversation(_conversationId);
        setState(() {
          _messages = [
            for (final m in _messages)
              m.id == msg.id ? m.copyWith(isPinned: false) : m.copyWith(isPinned: false),
          ];
        });
        _persistMessagesCache();
        _toast('Unpinned');
      } else {
        await _api.pinMessage(msg.id);
        setState(() {
          _messages = [
            for (final m in _messages)
              m.id == msg.id
                  ? m.copyWith(isPinned: true)
                  : m.copyWith(isPinned: false),
          ];
        });
        _persistMessagesCache();
        _toast('Pinned');
      }
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editMessage(ChatV1Message msg) async {
    final controller = TextEditingController(text: msg.body);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || next == msg.body) return;
    try {
      final updated = await _api.editMessage(msg.id, body: next);
      final mapped =
          ChatV1Mapper.messageFromJson(updated, currentUserId: _userId);
      _upsertMessage(
        msg.copyWith(
          body: mapped.body.isNotEmpty ? mapped.body : next,
          edited: true,
        ),
      );
      _toast('Message updated');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteMessage(ChatV1Message msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be deleted for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ChatV1Theme.rejected,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteMessage(msg.id);
      _upsertMessage(
        msg.copyWith(
          body: 'This message was deleted',
          isDeleted: true,
          attachments: const [],
        ),
      );
      _toast('Message deleted');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _shareToGeneral(ChatV1Message msg) async {
    try {
      final result = await _api.shareMessageToGeneral(msg.id);
      final generalId = (result['general_conversation_id'] ??
              result['conversation_id'] ??
              '')
          .toString();
      _toast(
        'Shared to General',
        action: generalId.isEmpty
            ? null
            : SnackBarAction(
                label: 'Open',
                onPressed: () => _openConversationById(
                  generalId,
                  titleFallback: 'General',
                ),
              ),
      );
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openConversationById(
    String conversationId, {
    String titleFallback = 'Chat',
  }) async {
    final ctrl = ChatV1Controller.instance;
    final existing = ctrl.findChatById(conversationId) ??
        (titleFallback.toLowerCase() == 'general'
            ? ctrl.findGeneralChannel()
            : null);
    final meta = existing != null
        ? ctrl.metaFor(existing)
        : ChatV1ConvMeta(
            id: conversationId,
            title: titleFallback,
            subtitle: 'Project channel',
            icon: Icons.forum_rounded,
            accent: ChatV1Theme.accent,
            members: ctrl.members,
            description: 'Project channel · $titleFallback',
            conversationType: 'channel',
            contextType: 'sales_sop',
            contextId: ctrl.salesSopId,
          );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatV1ConversationScreen(
          meta: meta,
          onOpenInfo: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatV1GroupInfoScreen(meta: meta),
              ),
            );
          },
        ),
      ),
    );
  }

  void _messageActions(BuildContext context, ChatV1Message msg) {
    if (msg.isDeleted) return;
    final canShareGeneral = !_isGeneralChannel;
    showModalBottomSheet(
      context: context,
      backgroundColor: ChatV1Theme.secondary(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ChatV1Theme.border(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['👍', '❤️', '😂', '😮', '😢', '🔥']
                    .map(
                      (e) => InkWell(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _reactToMessage(msg, e);
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 16),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startReply(msg);
                },
              ),
              if (canShareGeneral)
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Share to General'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _shareToGeneral(msg);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyMessage(msg);
                },
              ),
              ListTile(
                leading: Icon(
                  msg.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                ),
                title: Text(msg.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pinMessage(msg);
                },
              ),
              if (msg.isMine) ...[
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _editMessage(msg);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: ChatV1Theme.rejected),
                  title: const Text('Delete',
                      style: TextStyle(color: ChatV1Theme.rejected)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deleteMessage(msg);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
