import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_http.dart';
import '../services/session_manager.dart';

/// REST client for `/api/v1/chat` (ERP session cookie + mobile api_token).
class ChatV1Api {
  ChatV1Api._();
  static final ChatV1Api instance = ChatV1Api._();

  static const String baseUrl = 'https://office.buildahome.in';
  static const String chatPrefix = '/api/v1/chat';
  static const String _cookiePrefsKey = 'erp_session_cookie';

  String? _sessionCookie;

  Future<String?> getApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim();
    if (token == null || token.isEmpty || token.toLowerCase() == 'null') {
      return null;
    }
    return token;
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId') ?? prefs.getString('user_id');
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  Future<void> ensureCookieLoaded() async {
    if (_sessionCookie != null) return;
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString(_cookiePrefsKey) ??
        prefs.getString('client_portal_session_cookie');
  }

  /// Cookie header value for Socket.IO / authenticated requests.
  Future<String?> sessionCookie() async {
    await ensureCookieLoaded();
    return _sessionCookie;
  }

  Future<void> persistCookieFrom(http.BaseResponse response) async {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final parts = raw.split(',');
    final kept = <String>[];
    for (final part in parts) {
      final first = part.split(';').first.trim();
      final lower = first.toLowerCase();
      if (lower.startsWith('buildahome_session=') ||
          lower.startsWith('session=') ||
          lower.startsWith('flask=')) {
        kept.add(first);
      }
    }
    if (kept.isEmpty) return;
    _sessionCookie = kept.join('; ');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiePrefsKey, _sessionCookie!);
  }

  /// Call after OTP verify (or any login) so chat can send the ERP cookie.
  Future<void> captureLoginCookies(http.BaseResponse response) =>
      persistCookieFrom(response);

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    await ensureCookieLoaded();
    final token = await getApiToken();
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (jsonBody) headers['Content-Type'] = 'application/json';
    if (token != null) {
      headers['X-Api-Token'] = token;
      headers['Authorization'] = 'Bearer $token';
    }
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  Future<Uri> _uri(String path, {Map<String, String>? query}) async {
    final token = await getApiToken();
    final q = <String, String>{
      if (query != null) ...query,
      if (token != null) 'api_token': token,
    };
    return Uri.parse('$baseUrl$path')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _decode(http.Response response) async {
    await persistCookieFrom(response);
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        json = Map<String, dynamic>.from(decoded);
      } else {
        return decoded;
      }
    } catch (_) {
      throw ChatV1ApiException(
        'Invalid response (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    if (json['success'] == false) {
      throw ChatV1ApiException(
        json['message']?.toString() ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 400) {
      throw ChatV1ApiException(
        json['message']?.toString() ?? 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return json.containsKey('data') ? json['data'] : json;
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
  }) async {
    try {
      final uri = await _uri(path, query: query);
      print('[ChatV1Api] GET $uri');
      final response = await ApiHttp.get(
        uri,
        headers: await _headers(),
      ).timeout(const Duration(seconds: 25));
      final q = Map<String, String>.from(uri.queryParameters)
        ..remove('api_token');
      final qLabel = q.isEmpty
          ? ''
          : '?${q.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      print('[ChatV1Api] GET ${response.statusCode} $path$qLabel');
      return _decode(response);
    } on SessionInvalidatedException {
      rethrow;
    }
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    try {
      final uri = await _uri(path, query: query);
      print('[ChatV1Api] POST $uri');
      final response = await ApiHttp.post(
        uri,
        headers: await _headers(jsonBody: true),
        body: body == null ? null : jsonEncode(body),
      ).timeout(const Duration(seconds: 25));
      print('[ChatV1Api] POST ${response.statusCode} $path');
      return _decode(response);
    } on SessionInvalidatedException {
      rethrow;
    }
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    try {
      final uri = await _uri(path, query: query);
      print('[ChatV1Api] PATCH $uri');
      final response = await ApiHttp.patch(
        uri,
        headers: await _headers(jsonBody: true),
        body: body == null ? null : jsonEncode(body),
      ).timeout(const Duration(seconds: 25));
      print('[ChatV1Api] PATCH ${response.statusCode} $path');
      return _decode(response);
    } on SessionInvalidatedException {
      rethrow;
    }
  }

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    try {
      final uri = await _uri(path, query: query);
      print('[ChatV1Api] DELETE $uri');
      final response = await ApiHttp.delete(
        uri,
        headers: await _headers(jsonBody: true),
        body: body == null ? null : jsonEncode(body),
      ).timeout(const Duration(seconds: 25));
      print('[ChatV1Api] DELETE ${response.statusCode} $path');
      return _decode(response);
    } on SessionInvalidatedException {
      rethrow;
    }
  }

  // ── Conversations ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listConversations({
    required String contextType,
    required String contextId,
    int pageSize = 100,
  }) async {
    try {
      final data = await get(
        '$chatPrefix/conversations',
        query: {
          'context_type': contextType,
          'context_id': contextId,
          'page_size': '$pageSize',
        },
      );
      return _asMapList(data, keys: const ['conversations', 'items', 'results']);
    } on ChatV1ApiException catch (e) {
      // Older servers block Client on context-scoped list even when they are
      // channel members. Fall back to membership list, then filter to this SOP.
      final accessDenied = (e.statusCode == 403) ||
          e.message.toLowerCase().contains('do not have access');
      if (!accessDenied || contextType != 'sales_sop') rethrow;
      print(
        '[ChatV1Api] Context list blocked ($e) — falling back to member conversations',
      );
      return listMemberConversationsForSalesSop(contextId, pageSize: pageSize);
    }
  }

  /// Conversations the auth user belongs to, filtered to one sales_sop.
  Future<List<Map<String, dynamic>>> listMemberConversationsForSalesSop(
    String salesSopId, {
    int pageSize = 100,
  }) async {
    final data = await get(
      '$chatPrefix/conversations',
      query: {'page_size': '$pageSize'},
    );
    final all =
        _asMapList(data, keys: const ['conversations', 'items', 'results']);
    final sid = salesSopId.trim();
    return all.where((row) {
      final contextType = (row['context_type'] ?? '').toString();
      final contextId = (row['context_id'] ?? '').toString();
      final type = (row['conversation_type'] ?? '').toString();
      if (contextType != 'sales_sop' || contextId != sid) return false;
      return type == 'channel' || type == 'group';
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listDirectConversations({
    int pageSize = 100,
  }) async {
    final data = await get(
      '$chatPrefix/conversations',
      query: {
        'conversation_type': 'direct',
        'page_size': '$pageSize',
      },
    );
    return _asMapList(data, keys: const ['conversations', 'items', 'results']);
  }

  Future<List<Map<String, dynamic>>> listTaskConversations(
    String salesSopId,
  ) async {
    final data =
        await get('$chatPrefix/sales-sop/$salesSopId/task-conversations');
    return _asMapList(data, keys: const [
      'conversations',
      'task_conversations',
      'items',
      'results',
    ]);
  }

  Future<List<Map<String, dynamic>>> listWorkflowConversations(
    String salesSopId, {
    List<String>? workflowRunIds,
  }) async {
    final query = <String, String>{};
    if (workflowRunIds != null && workflowRunIds.isNotEmpty) {
      query['workflow_run_ids'] = workflowRunIds.join(',');
    }
    final data = await get(
      '$chatPrefix/sales-sop/$salesSopId/workflow-conversations',
      query: query.isEmpty ? null : query,
    );
    return _asMapList(data, keys: const [
      'conversations',
      'workflow_conversations',
      'items',
      'results',
    ]);
  }

  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    final data = await get('$chatPrefix/conversations/$conversationId');
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ChatV1ApiException('Unexpected conversation response');
  }

  /// Deprecated for bulk conversation loads — use [listMessages] with
  /// `includeExtras: true`. Kept for single-message refresh after upload.
  @Deprecated('Prefer listMessages(includeExtras: true) for conversation loads')
  Future<List<Map<String, dynamic>>> getMessageAttachments(
    String messageId,
  ) async {
    final data = await get('$chatPrefix/messages/$messageId/attachments');
    return _asMapList(data, keys: const ['attachments', 'items', 'results']);
  }

  Future<Map<String, dynamic>?> getErpTaskDiscussionDetails({
    required String salesSopId,
    required String erpTaskId,
  }) async {
    final token = await getApiToken();
    final uri = Uri.parse('$baseUrl/API/erp_task_discussion_details').replace(
      queryParameters: {
        'sales_sop_id': salesSopId,
        'erp_task_id': erpTaskId,
        if (token != null) 'api_token': token,
      },
    );
    print('[ChatV1Api] GET $uri');
    final response = await ApiHttp.get(
      uri,
      headers: await _headers(),
    ).timeout(const Duration(seconds: 25));
    await persistCookieFrom(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw ChatV1ApiException(
        map['message']?.toString() ?? 'Failed to load task details',
      );
    }
    final task = map['task'];
    if (task is Map) return Map<String, dynamic>.from(task);
    return null;
  }

  Future<List<Map<String, dynamic>>> listMembers(String salesSopId) async {
    final data = await get('$chatPrefix/sales-sop/$salesSopId/members');
    return _asMapList(data, keys: const ['members', 'users', 'items', 'results']);
  }

  Future<Map<String, dynamic>> createConversation({
    required String conversationType,
    required String title,
    required String contextType,
    required dynamic contextId,
    required List<int> participantUserIds,
  }) async {
    final data = await post('$chatPrefix/conversations', body: {
      'conversation_type': conversationType,
      'title': title,
      'context_type': contextType,
      'context_id': contextId,
      'participant_user_ids': participantUserIds,
    });
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ChatV1ApiException('Unexpected create conversation response');
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listMessages(
    String conversationId, {
    int pageSize = 50,
    String? beforeId,
    String? afterId,
    bool includeExtras = true,
  }) async {
    final query = <String, String>{
      'page_size': '$pageSize',
      if (includeExtras) 'include_extras': 'true',
    };
    if (beforeId != null) query['before_id'] = beforeId;
    if (afterId != null) query['after_id'] = afterId;
    final data = await get(
      '$chatPrefix/conversations/$conversationId/messages',
      query: query,
    );
    return _asMapList(data, keys: const ['messages', 'items', 'results']);
  }

  Future<Map<String, dynamic>> sendMessage(
    String conversationId, {
    required String body,
    String contentType = 'text',
    int? parentMessageId,
  }) async {
    final data = await post(
      '$chatPrefix/conversations/$conversationId/messages',
      body: {
        'body': body,
        'content_type': contentType,
        if (parentMessageId != null) 'parent_message_id': parentMessageId,
      },
    );
    if (data is Map) {
      final msg = data['message'];
      if (msg is Map) return Map<String, dynamic>.from(msg);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected send message response');
  }

  /// Reply via dedicated endpoint (web parity).
  Future<Map<String, dynamic>> replyToMessage(
    String messageId, {
    required String body,
    String contentType = 'text',
  }) async {
    final data = await post(
      '$chatPrefix/messages/$messageId/reply',
      body: {
        'body': body,
        'content_type': contentType,
      },
    );
    if (data is Map) {
      final msg = data['message'];
      if (msg is Map) return Map<String, dynamic>.from(msg);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected reply response');
  }

  /// Share / copy message into the project General conversation.
  Future<Map<String, dynamic>> shareMessageToGeneral(String messageId) async {
    final data = await post('$chatPrefix/messages/$messageId/share-to-general');
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ChatV1ApiException('Unexpected share-to-general response');
  }

  Future<Map<String, dynamic>> pinMessage(String messageId) async {
    final data = await post('$chatPrefix/messages/$messageId/pin');
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<void> unpinConversation(String conversationId) async {
    await delete('$chatPrefix/conversations/$conversationId/pin');
  }

  Future<Map<String, dynamic>> editMessage(
    String messageId, {
    required String body,
  }) async {
    final data = await patch(
      '$chatPrefix/messages/$messageId',
      body: {'body': body},
    );
    if (data is Map) {
      final msg = data['message'];
      if (msg is Map) return Map<String, dynamic>.from(msg);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected edit message response');
  }

  Future<void> deleteMessage(String messageId) async {
    await delete('$chatPrefix/messages/$messageId');
  }

  Future<void> markConversationRead(
    String conversationId, {
    String? upToMessageId,
  }) async {
    try {
      await post(
        '$chatPrefix/conversations/$conversationId/read',
        body: {
          if (upToMessageId != null)
            'up_to_message_id': int.tryParse(upToMessageId) ?? upToMessageId,
        },
      );
    } catch (_) {
      // Optional endpoint — ignore if missing.
    }
  }

  Future<void> addReaction(String messageId, String emoji) async {
    await post('$chatPrefix/messages/$messageId/reactions', body: {
      'reaction': emoji,
      'emoji': emoji,
    });
  }

  Future<void> removeReaction(String messageId, String emoji) async {
    try {
      final uri = await _uri('$chatPrefix/messages/$messageId/reactions');
      await ApiHttp.delete(
        uri,
        headers: await _headers(jsonBody: true),
        body: jsonEncode({'reaction': emoji, 'emoji': emoji}),
      );
    } catch (_) {
      await post('$chatPrefix/messages/$messageId/reactions/remove', body: {
        'reaction': emoji,
        'emoji': emoji,
      });
    }
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final data = await get(
        '$chatPrefix/search',
        query: {'q': query.trim(), 'page_size': '40'},
      );
      return _asMapList(data, keys: const ['results', 'hits', 'items']);
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> uploadDiscussionAttachment({
    required List<int> bytes,
    required String fileName,
  }) async {
    final token = await getApiToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/API/upload_discussion_attachment'),
    );
    final headers = await _headers();
    request.headers.addAll(headers);
    if (token != null) request.fields['api_token'] = token;
    request.files.add(http.MultipartFile.fromBytes(
      'attachment',
      bytes,
      filename: fileName,
    ));
    final streamed = await ApiHttp.send(request).timeout(
      const Duration(seconds: 60),
    );
    final response = await http.Response.fromStream(streamed);
    await persistCookieFrom(response);
    final decoded = jsonDecode(response.body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> attachMessageFiles(
    String messageId,
    List<Map<String, dynamic>> attachments,
  ) async {
    await post('$chatPrefix/messages/$messageId/attachments', body: {
      'attachments': attachments,
    });
  }

  // ── Difference of Cost (DOC) ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listDocs(
    String salesSopId, {
    String? query,
    bool includeMessages = false,
  }) async {
    final q = <String, String>{
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (includeMessages) 'include_messages': '1',
    };
    final data = await get(
      '$chatPrefix/sales-sop/$salesSopId/docs',
      query: q.isEmpty ? null : q,
    );
    return _asMapList(data, keys: const ['docs', 'items', 'results']);
  }

  Future<Map<String, dynamic>> createDoc(
    String salesSopId, {
    required String description,
    required num amount,
    String? notes,
    String? pdfName,
    String? pdfUrl,
  }) async {
    final data = await post(
      '$chatPrefix/sales-sop/$salesSopId/docs',
      body: {
        'description': description,
        'amount': amount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (pdfName != null && pdfName.isNotEmpty) 'pdf_name': pdfName,
        if (pdfUrl != null && pdfUrl.isNotEmpty) 'pdf_url': pdfUrl,
      },
    );
    if (data is Map) {
      final doc = data['doc'];
      if (doc is Map) return Map<String, dynamic>.from(doc);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected create DOC response');
  }

  Future<Map<String, dynamic>> getDoc(String docId) async {
    final data = await get('$chatPrefix/docs/$docId');
    if (data is Map) {
      final doc = data['doc'];
      if (doc is Map) return Map<String, dynamic>.from(doc);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected DOC response');
  }

  Future<List<Map<String, dynamic>>> listDocMessages(String docId) async {
    final data = await get('$chatPrefix/docs/$docId/messages');
    return _asMapList(data, keys: const ['messages', 'items', 'results']);
  }

  Future<Map<String, dynamic>> sendDocMessage(
    String docId, {
    required String body,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final data = await post(
      '$chatPrefix/docs/$docId/messages',
      body: {
        'body': body,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments,
      },
    );
    if (data is Map) {
      final msg = data['message'];
      if (msg is Map) return Map<String, dynamic>.from(msg);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected DOC message response');
  }

  Future<Map<String, dynamic>> approveDoc(String docId) async {
    final data = await post('$chatPrefix/docs/$docId/approve');
    if (data is Map) {
      final doc = data['doc'];
      if (doc is Map) return Map<String, dynamic>.from(doc);
      return Map<String, dynamic>.from(data);
    }
    throw ChatV1ApiException('Unexpected approve DOC response');
  }

  List<Map<String, dynamic>> _asMapList(
    dynamic data, {
    required List<String> keys,
  }) {
    if (data == null) return const [];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map) {
      for (final key in keys) {
        final nested = data[key];
        if (nested is List) {
          return nested
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    }
    return const [];
  }
}

class ChatV1ApiException implements Exception {
  final String message;
  final int? statusCode;
  ChatV1ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
