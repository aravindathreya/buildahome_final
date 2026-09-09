import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sales_sop_slot.dart';
import 'api_http.dart';
import 'data_provider.dart';
import 'session_manager.dart';

/// Loads and accepts unified sales SOP slots.
///
/// GET `/API/sales_sop_details/{id}/slots`
/// POST site inspection via `confirm_url` or
/// `/API/sales_sop_details/{id}/slots/site-inspection/accept`
/// POST workflow via `confirm_url` or
/// `/API/workflow/item-runs/{id}/slot-confirmation`
class SalesSopSlotsService {
  SalesSopSlotsService._();
  static final SalesSopSlotsService instance = SalesSopSlotsService._();
  factory SalesSopSlotsService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];

  Future<SalesSopSlotsResult> fetchSlots({String? salesSopId}) async {
    final auth = await _authParams();
    final sopId = await _resolveSalesSopId(salesSopId, auth.token);
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
    };

    final body = await _getJson(
      pathSuffix: 'sales_sop_details/$sopId/slots',
      query: query,
      auth: auth,
    );
    return SalesSopSlotsResult.fromJson(body);
  }

  Future<void> acceptSlot({
    required SalesSopSlot slot,
    required int acceptedSlotIndex,
    String note = '',
    String? salesSopId,
  }) async {
    final auth = await _authParams();
    final sopId = await _resolveSalesSopId(salesSopId, auth.token);

    Map<String, dynamic> payload;
    String fallbackPath;

    if (slot.isSiteInspection) {
      payload = {'accepted_slot_index': acceptedSlotIndex};
      fallbackPath =
          'sales_sop_details/$sopId/slots/site-inspection/accept';
    } else {
      payload = <String, dynamic>{
        'accepted_slot_index': acceptedSlotIndex,
        if (slot.confirmActionId.isNotEmpty)
          'action_id': slot.confirmActionId,
        'note': note,
      };
      final runId = slot.itemRunId.isNotEmpty
          ? slot.itemRunId
          : _itemRunIdFromConfirmUrl(slot.confirmUrl);
      if (runId.isEmpty && slot.confirmUrl.isEmpty) {
        throw const SalesSopSlotsException(
          'Cannot confirm this slot. Missing confirm URL.',
        );
      }
      fallbackPath = runId.isEmpty
          ? ''
          : 'workflow/item-runs/$runId/slot-confirmation';
    }

    await _postJson(
      confirmUrl: slot.confirmUrl,
      fallbackPath: fallbackPath,
      payload: payload,
      auth: auth,
    );
  }

  Future<String> _resolveSalesSopId(String? override, String apiToken) async {
    final explicit = override?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('sales_sop_id')?.trim() ?? '';
    final projectId = prefs.getString('project_id');
    final resolved = await DataProvider().resolveSalesSopId(
      projectId: projectId,
      apiToken: apiToken,
    );
    final sopId = (resolved ?? cached).trim();
    if (sopId.isEmpty) {
      throw const SalesSopSlotsException(
        'Could not resolve this project. Select the project again.',
        statusCode: 400,
      );
    }
    return sopId;
  }

  Future<Map<String, dynamic>> _getJson({
    required String pathSuffix,
    required Map<String, String> query,
    required _AuthParams auth,
  }) async {
    final headers = _headers(auth.token);
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
          final decoded = _decodeMap(res.body);

          if (res.statusCode == 401 || res.statusCode == 403) {
            lastMessage = _messageFromBody(decoded) ??
                (res.statusCode == 401
                    ? 'Invalid api token'
                    : 'You do not have permission');
            continue;
          }
          if (res.statusCode != 200 || decoded == null) {
            lastMessage = _messageFromBody(decoded) ??
                'Could not load slots (${res.statusCode})';
            continue;
          }
          if (decoded.containsKey('success') &&
              decoded['success'] == false) {
            lastMessage = _messageFromBody(decoded) ?? 'Could not load slots';
            continue;
          }
          return decoded;
        } on SessionInvalidatedException {
          rethrow;
        } on SalesSopSlotsException {
          rethrow;
        } catch (e) {
          lastMessage = e.toString().replaceFirst('Exception: ', '');
        }
      }
    }

    throw SalesSopSlotsException(
      lastMessage ?? 'Could not load slots',
      statusCode: lastStatus,
    );
  }

  Future<void> _postJson({
    required String confirmUrl,
    required String fallbackPath,
    required Map<String, dynamic> payload,
    required _AuthParams auth,
  }) async {
    final headers = {
      ..._headers(auth.token),
      'Content-Type': 'application/json',
    };
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
    };
    final body = jsonEncode({
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
      ...payload,
    });

    int? lastStatus;
    String? lastMessage;
    final candidates = _postUris(confirmUrl, fallbackPath, query);

    for (final uri in candidates) {
      try {
        final res = await ApiHttp.post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 30));
        lastStatus = res.statusCode;
        final decoded = _decodeMap(res.body);

        if (res.statusCode == 401 || res.statusCode == 403) {
          lastMessage = _messageFromBody(decoded) ??
              (res.statusCode == 401
                  ? 'Invalid api token'
                  : 'You do not have permission');
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastMessage = _messageFromBody(decoded) ??
              'Could not accept slot (${res.statusCode})';
          continue;
        }
        if (decoded != null &&
            decoded.containsKey('success') &&
            decoded['success'] == false) {
          lastMessage = _messageFromBody(decoded) ?? 'Could not accept slot';
          continue;
        }
        return;
      } on SessionInvalidatedException {
        rethrow;
      } on SalesSopSlotsException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
      }
    }

    throw SalesSopSlotsException(
      lastMessage ?? 'Could not accept slot',
      statusCode: lastStatus,
    );
  }

  List<Uri> _postUris(
    String confirmUrl,
    String fallbackPath,
    Map<String, String> query,
  ) {
    final uris = <Uri>[];
    final trimmed = confirmUrl.trim();
    if (trimmed.isNotEmpty) {
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        final uri = Uri.parse(trimmed);
        uris.add(uri.replace(queryParameters: {
          ...uri.queryParameters,
          ...query,
        }));
      } else {
        var path = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
        for (final base in baseUrls) {
          if (path.toLowerCase().startsWith('api/')) {
            uris.add(
              Uri.parse('$base/$path').replace(queryParameters: query),
            );
          } else {
            for (final prefix in const ['API', 'api']) {
              uris.add(
                Uri.parse('$base/$prefix/$path')
                    .replace(queryParameters: query),
              );
            }
          }
        }
      }
    }

    if (fallbackPath.trim().isNotEmpty) {
      for (final base in baseUrls) {
        for (final prefix in const ['API', 'api']) {
          uris.add(
            Uri.parse('$base/$prefix/${fallbackPath.trim()}')
                .replace(queryParameters: query),
          );
        }
      }
    }
    return uris;
  }

  String _itemRunIdFromConfirmUrl(String confirmUrl) {
    final match = RegExp(
      r'item-runs/([^/]+)/slot-confirmation',
      caseSensitive: false,
    ).firstMatch(confirmUrl);
    return match?.group(1)?.trim() ?? '';
  }

  Map<String, String> _headers(String token) {
    return {
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final raw = jsonDecode(body);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  String? _messageFromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    for (final key in const ['message', 'error', 'detail']) {
      final text = body[key]?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  Future<_AuthParams> _authParams() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim() ?? '';
    if (token.isEmpty) {
      throw const SalesSopSlotsException('Not signed in', statusCode: 401);
    }
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id'))?.trim() ??
            '';
    return _AuthParams(token: token, userId: userId);
  }
}

class _AuthParams {
  final String token;
  final String userId;

  const _AuthParams({required this.token, required this.userId});
}
