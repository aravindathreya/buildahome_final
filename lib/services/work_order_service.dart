import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/work_order.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// Loads project work orders from `GET /API/work_orders`.
class WorkOrderService {
  WorkOrderService._();
  static final WorkOrderService instance = WorkOrderService._();
  factory WorkOrderService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];

  Future<WorkOrderListResult> fetchList({
    String? salesSopId,
    String? projectId,
    String status = 'all',
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final sop = salesSopId?.trim() ?? '';
    final project = projectId?.trim() ?? '';
    if (sop.isEmpty && project.isEmpty) {
      throw const WorkOrderException(
        'No project selected',
        statusCode: 400,
      );
    }

    final auth = await _authParams();
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
      if (sop.isNotEmpty) 'sales_sop_id': sop,
      if (project.isNotEmpty && sop.isEmpty) 'project_id': project,
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'offset': offset.toString(),
      'limit': limit.clamp(1, 100).toString(),
    };

    final body = await _getJson(
      pathSuffix: 'work_orders',
      query: query,
      auth: auth,
      listWithSalesSopId: sop.isNotEmpty,
      isDetail: false,
    );

    final result = WorkOrderListResult.fromJson(body);
    print(
      '[WorkOrder] list sales_sop_id=$sop project_id=$project '
      'status=${status.trim()} count=${result.items.length} '
      'has_more=${result.hasMore}',
    );
    return result;
  }

  Future<WorkOrder> fetchDetail(int workOrderId) async {
    if (workOrderId <= 0) {
      throw const WorkOrderException(
        'Work order not found',
        statusCode: 404,
      );
    }

    final auth = await _authParams();
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
    };

    final body = await _getJson(
      pathSuffix: 'work_orders/$workOrderId',
      query: query,
      auth: auth,
      isDetail: true,
    );

    final itemRaw = body['item'] ?? body['work_order'];
    if (itemRaw is Map) {
      return WorkOrder.fromJson(Map<String, dynamic>.from(itemRaw));
    }
    if (body.containsKey('work_order_id') || body.containsKey('trade')) {
      return WorkOrder.fromJson(body);
    }
    throw const WorkOrderException('Work order not found', statusCode: 404);
  }

  Future<Map<String, dynamic>> _getJson({
    required String pathSuffix,
    required Map<String, String> query,
    required _AuthParams auth,
    required bool isDetail,
    bool listWithSalesSopId = false,
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

          if (res.statusCode == 401) {
            throw const WorkOrderException(
              'Session expired',
              statusCode: 401,
            );
          }

          if (res.statusCode == 403) {
            throw WorkOrderException(
              _messageFromBody(decoded) ??
                  "You don't have access to this project's work orders",
              statusCode: 403,
            );
          }

          if (res.statusCode == 404) {
            throw WorkOrderException(
              _messageFromBody(decoded) ??
                  (isDetail
                      ? 'Work order not found'
                      : listWithSalesSopId
                          ? 'This project has no converted ERP project yet'
                          : 'Work orders not found'),
              statusCode: 404,
            );
          }

          if (res.statusCode != 200 || decoded == null) {
            lastMessage = _messageFromBody(decoded) ??
                'Could not load work orders (${res.statusCode})';
            continue;
          }

          if (decoded.containsKey('success') &&
              _truthy(decoded['success']) == false) {
            lastMessage =
                _messageFromBody(decoded) ?? 'Could not load work orders';
            continue;
          }

          return decoded;
        } on SessionInvalidatedException {
          rethrow;
        } on WorkOrderException {
          rethrow;
        } catch (e) {
          lastMessage = e.toString().replaceFirst('Exception: ', '');
        }
      }
    }

    throw WorkOrderException(
      lastMessage ?? 'Could not load work orders',
      statusCode: lastStatus,
    );
  }

  Future<_AuthParams> _authParams() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim() ?? '';
    if (token.isEmpty) {
      throw const WorkOrderException('Not signed in', statusCode: 401);
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

class WorkOrderException implements Exception {
  final String message;
  final int? statusCode;

  const WorkOrderException(this.message, {this.statusCode});

  @override
  String toString() => message;
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
