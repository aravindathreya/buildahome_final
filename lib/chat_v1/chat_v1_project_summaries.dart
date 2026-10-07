import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/data_provider.dart';
import 'chat_v1_api.dart';
import 'chat_v1_mapper.dart';

/// Chat state for one project row: unread total, latest message, and the
/// conversation to land in when the row is tapped.
class ChatProjectSummary {
  final String projectId;
  final String? salesSopId;
  final int unread;

  /// Same shape as a conversation's `last_message` so list previews match.
  final Map<String, dynamic>? lastMessage;
  final DateTime? lastActivity;

  /// Conversation row to open (`id`, `title`, ...), or empty when unknown.
  final Map<String, dynamic> conversation;

  const ChatProjectSummary({
    required this.projectId,
    required this.unread,
    this.salesSopId,
    this.lastMessage,
    this.lastActivity,
    this.conversation = const {},
  });

  DateTime get activityAt =>
      lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasActivity => activityAt.millisecondsSinceEpoch > 0;

  String get preview {
    final last = lastMessage ?? conversation['last_message'];
    if (last != null) {
      final formatted = ChatV1Mapper.formatLastMessagePreview(last);
      if (!formatted.isEmpty) return formatted.label;
    }
    for (final key in const [
      'last_message_preview',
      'last_message_text',
      'preview',
    ]) {
      final text = conversation[key]?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  /// Row from `GET /api/v1/chat/project_summaries`.
  static ChatProjectSummary? fromJson(Map<String, dynamic> raw) {
    final projectId = _string(raw['project_id'] ?? raw['erp_project_id']);
    final salesSopId = _string(raw['sales_sop_id']);
    if (projectId == null && salesSopId == null) return null;

    final last = raw['last_message'] is Map
        ? Map<String, dynamic>.from(raw['last_message'] as Map)
        : null;
    final openId = _string(raw['open_conversation_id']) ??
        _string(last?['conversation_id']);
    final openTitle = _string(raw['open_conversation_title']) ??
        _string(last?['conversation_title']);

    return ChatProjectSummary(
      projectId: projectId ?? salesSopId!,
      salesSopId: salesSopId,
      unread: int.tryParse(raw['unread_count']?.toString() ?? '') ?? 0,
      lastMessage: last,
      lastActivity: DateTime.tryParse(
        (raw['last_message_at'] ?? last?['created_at'] ?? '').toString(),
      ),
      conversation: openId == null
          ? const {}
          : {
              'id': openId,
              if (openTitle != null) 'title': openTitle,
              if (last != null) 'last_message': last,
            },
    );
  }

  static ChatProjectSummary fromUnreadHint(
    String key,
    ChatProjectUnread hint,
  ) {
    return ChatProjectSummary(
      projectId: key,
      unread: hint.unread,
      lastActivity: hint.lastActivity,
      conversation: hint.conversation,
    );
  }

  static String? _string(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}

/// Parsed `GET /api/v1/chat/project_summaries` payload.
class ChatProjectSummaryPayload {
  final int totalUnread;
  final Map<String, ChatProjectSummary> byKey;

  const ChatProjectSummaryPayload({
    required this.totalUnread,
    required this.byKey,
  });

  /// Null when the body is not a project summary response.
  static ChatProjectSummaryPayload? parse(dynamic data) {
    if (data is! Map) return null;
    final rows = data['projects'];
    if (rows is! List) return null;
    final byKey = <String, ChatProjectSummary>{};
    var sum = 0;
    for (final row in rows) {
      if (row is! Map) continue;
      final summary =
          ChatProjectSummary.fromJson(Map<String, dynamic>.from(row));
      if (summary == null) continue;
      sum += summary.unread;
      byKey[summary.projectId] = summary;
      final sop = summary.salesSopId;
      if (sop != null) byKey.putIfAbsent(sop, () => summary);
    }
    final total = int.tryParse(data['total_unread']?.toString() ?? '');
    return ChatProjectSummaryPayload(totalUnread: total ?? sum, byKey: byKey);
  }
}

/// Unread chat counts for the staff dashboard badge and the chat project list.
///
/// Reads `GET /api/v1/chat/project_summaries`. Until the server ships it,
/// falls back to scanning the member conversation list.
class ChatProjectSummaryStore {
  ChatProjectSummaryStore._();
  static final ChatProjectSummaryStore instance = ChatProjectSummaryStore._();

  static const String path = '${ChatV1Api.chatPrefix}/project_summaries';
  static const Duration _minInterval = Duration(seconds: 20);

  final ValueNotifier<int> totalUnread = ValueNotifier<int>(0);
  final ValueNotifier<Map<String, ChatProjectSummary>> byKey =
      ValueNotifier<Map<String, ChatProjectSummary>>(const {});

  DateTime? _lastLoad;
  Future<void>? _inFlight;
  Timer? _debounce;
  bool _endpointMissing = false;

  Future<void> refresh({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final last = _lastLoad;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minInterval) {
      return Future.value();
    }
    final future = _load().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  /// A chat message arrived somewhere; refresh once the burst settles.
  void scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(refresh(force: true));
    });
  }

  ChatProjectSummary? forProject(dynamic project) {
    if (project is! Map) return null;
    final map = byKey.value;
    if (map.isEmpty) return null;
    ChatProjectSummary? best;
    for (final id in _projectKeys(project)) {
      final hit = map[id];
      if (hit == null) continue;
      if (best == null ||
          hit.unread > best.unread ||
          (hit.unread == best.unread && hit.activityAt.isAfter(best.activityAt))) {
        best = hit;
      }
    }
    return best;
  }

  void clear() {
    _debounce?.cancel();
    _lastLoad = null;
    _endpointMissing = false;
    totalUnread.value = 0;
    byKey.value = const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').trim();
    if (role.isEmpty || role == 'Client') return;
    try {
      final payload = await _loadFromEndpoint() ?? await _loadFromConversations();
      byKey.value = payload.byKey;
      totalUnread.value = payload.totalUnread;
      _lastLoad = DateTime.now();
    } catch (e) {
      debugPrint('[ChatSummaries] refresh failed: $e');
    }
  }

  Future<ChatProjectSummaryPayload?> _loadFromEndpoint() async {
    if (_endpointMissing) return null;
    try {
      final data = await ChatV1Api.instance.get(path);
      final payload = ChatProjectSummaryPayload.parse(data);
      if (payload == null) _endpointMissing = true;
      return payload;
    } on ChatV1ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) _endpointMissing = true;
      debugPrint('[ChatSummaries] $path unavailable: $e');
      return null;
    } catch (e) {
      debugPrint('[ChatSummaries] $path failed: $e');
      return null;
    }
  }

  Future<ChatProjectSummaryPayload> _loadFromConversations() async {
    final hints = await ChatV1Api.instance.unreadHintsByProjectKey();
    final summaries = {
      for (final entry in hints.entries)
        entry.key: ChatProjectSummary.fromUnreadHint(entry.key, entry.value),
    };
    var total = 0;
    for (final project in DataProvider().projects) {
      ChatProjectSummary? best;
      for (final id in _projectKeys(project)) {
        final hit = summaries[id];
        if (hit != null && (best == null || hit.unread > best.unread)) {
          best = hit;
        }
      }
      total += best?.unread ?? 0;
    }
    return ChatProjectSummaryPayload(totalUnread: total, byKey: summaries);
  }

  static Set<String> _projectKeys(dynamic project) {
    final keys = <String>{};
    if (project is! Map) return keys;
    for (final key in const [
      'id',
      'project_id',
      'sales_sop_id',
      'salesSopId',
      'sop_id',
      'sales_sop_project_id',
    ]) {
      final value = project[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') keys.add(value);
    }
    final cached = DataProvider().cachedSalesSopId(project['id']?.toString());
    if (cached != null && cached.isNotEmpty) keys.add(cached);
    return keys;
  }
}
