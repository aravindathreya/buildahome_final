import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/approved_po.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// Loads approved POs from `GET /API/approved_pos`.
class ApprovedPoService {
  ApprovedPoService._();
  static final ApprovedPoService instance = ApprovedPoService._();
  factory ApprovedPoService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];

  Future<ApprovedPoListResult> fetchList({
    String? projectId,
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final auth = await _authParams();
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
      if (projectId != null && projectId.trim().isNotEmpty)
        'project_id': projectId.trim(),
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'offset': offset.toString(),
      'limit': limit.toString(),
    };

    final body = await _getJson(
      pathSuffix: 'approved_pos',
      query: query,
      auth: auth,
    );

    final itemsRaw = body['items'];
    final items = <ApprovedPo>[];
    if (itemsRaw is List) {
      for (final row in itemsRaw) {
        if (row is Map) {
          items.add(ApprovedPo.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    final result = ApprovedPoListResult(
      items: items,
      hasMore: _truthy(body['has_more']),
      message: _asString(body['message']),
    );
    final withMasked =
        items.where((item) => item.canViewMaskedDocument).length;
    final awaitingMasked =
        items.where((item) => item.awaitingMaskedDocument).length;
    print(
      '[ApprovedPo] list project_id=${projectId ?? ''} '
      'count=${items.length} masked_pdf=$withMasked awaiting_masked=$awaitingMasked',
    );
    return result;
  }

  Future<ApprovedPo> fetchDetail(int indentId) async {
    final auth = await _authParams();
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
    };

    final body = await _getJson(
      pathSuffix: 'approved_pos/$indentId',
      query: query,
      auth: auth,
    );

    final itemRaw = body['item'];
    if (itemRaw is! Map) {
      throw const ApprovedPoException('Approved PO not found', statusCode: 404);
    }
    return ApprovedPo.fromJson(Map<String, dynamic>.from(itemRaw));
  }

  Future<Map<String, dynamic>> _getJson({
    required String pathSuffix,
    required Map<String, String> query,
    required _AuthParams auth,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': auth.token,
      'Authorization': 'Bearer ${auth.token}',
    };

    int? lastStatus;
    String? lastMessage;

    for (final base in baseUrls) {
      for (final prefix in const ['API', 'api']) {
        final uri = Uri.parse('$base/$prefix/$pathSuffix')
            .replace(queryParameters: query);
        try {
          final res = await ApiHttp.get(uri, headers: headers)
              .timeout(const Duration(seconds: 25));
          lastStatus = res.statusCode;

          Map<String, dynamic>? decoded;
          try {
            final raw = jsonDecode(res.body);
            if (raw is Map) {
              decoded = Map<String, dynamic>.from(raw);
            }
          } catch (_) {}

          if (res.statusCode == 401 || res.statusCode == 403) {
            lastMessage = _messageFromBody(decoded) ??
                (res.statusCode == 401
                    ? 'Invalid api token'
                    : 'You do not have permission');
            continue;
          }

          if (res.statusCode == 404) {
            throw ApprovedPoException(
              _messageFromBody(decoded) ?? 'Approved PO not found',
              statusCode: 404,
            );
          }

          if (res.statusCode != 200 || decoded == null) {
            lastMessage = _messageFromBody(decoded) ??
                'Could not load approved POs (${res.statusCode})';
            continue;
          }

          if (_truthy(decoded['success']) == false) {
            lastMessage =
                _messageFromBody(decoded) ?? 'Could not load approved POs';
            continue;
          }

          return decoded;
        } on SessionInvalidatedException {
          rethrow;
        } on ApprovedPoException {
          rethrow;
        } catch (e) {
          lastMessage = e.toString().replaceFirst('Exception: ', '');
        }
      }
    }

    throw ApprovedPoException(
      lastMessage ?? 'Could not load approved POs',
      statusCode: lastStatus,
    );
  }

  Future<_AuthParams> _authParams() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim() ?? '';
    if (token.isEmpty) {
      throw const ApprovedPoException('Not signed in', statusCode: 401);
    }
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id'))?.trim() ?? '';
    return _AuthParams(token: token, userId: userId);
  }

  String? _messageFromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    final msg = _asString(body['message']);
    return msg.isEmpty ? null : msg;
  }
}

class _AuthParams {
  final String token;
  final String userId;

  const _AuthParams({required this.token, required this.userId});
}

String _asString(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
