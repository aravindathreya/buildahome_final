import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sales_sop_slot.dart';
import 'api_http.dart';
import 'client_portal_service.dart';
import 'data_provider.dart';
import 'session_manager.dart';

/// Loads and acts on unified sales SOP slots.
///
/// GET `/API/sales_sop_details/{id}/slots`
/// Clients can also GET `/api/client_portal/sections/slots`
/// POST select `/API/sales_sop_details/{id}/slots/select`
///   or `/api/client_portal/slots/select`
/// POST confirm `/API/sales_sop_details/{id}/slots/confirm`
///   or `/api/client_portal/slots/confirm`
/// Site inspection still uses
/// `/API/sales_sop_details/{id}/slots/site-inspection/accept`
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
    if (auth.isClient) {
      try {
        final body = await ClientPortalService().getSlots();
        print('[SlotsAPI] client_portal keys=${body.keys.toList()}');
        return SalesSopSlotsResult.fromJson(body);
      } catch (_) {
        // Fall through to the sales SOP API with api_token.
      }
    }

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
    print(
      '[SlotsAPI] sop=$sopId keys=${body.keys.toList()} '
      'slots=${body['slots'] is List ? (body['slots'] as List).length : body['slots']} '
      'section=${body['section'] is Map ? (body['section'] as Map).keys.toList() : body['section']}',
    );
    final rawSlots = body['slots'] ??
        (body['section'] is Map ? (body['section'] as Map)['slots'] : null);
    if (rawSlots is List && rawSlots.isNotEmpty) {
      print('[SlotsAPI] first=${rawSlots.first}');
    }
    return SalesSopSlotsResult.fromJson(body);
  }

  Future<SalesSopSlotsResult?> selectSlots({
    required SalesSopSlot slot,
    required List<Map<String, dynamic>> slots,
    String note = '',
    String? salesSopId,
  }) async {
    if (!slot.canSelect) {
      throw const SalesSopSlotsException(
        'You cannot pick slots for this visit.',
      );
    }
    final runId = slot.selectRunId;
    if (runId.isEmpty && slot.selectUrl.isEmpty) {
      throw const SalesSopSlotsException(
        'Cannot submit slots. Missing select item.',
      );
    }

    final auth = await _authParams();
    final sopId = await _tryResolveSalesSopId(salesSopId, auth.token);
    final payload = <String, dynamic>{
      if (runId.isNotEmpty) 'item_run_id': _idPayload(runId),
      if (slot.selectActionId.isNotEmpty) 'action_id': slot.selectActionId,
      'slots': slots,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    };

    final fallbacks = <String>[
      if (sopId.isNotEmpty) 'sales_sop_details/$sopId/slots/select',
    ];

    if (auth.isClient) {
      try {
        final body = await ClientPortalService().selectSlots(payload);
        return _resultFromBody(body);
      } catch (e) {
        if (e is SalesSopSlotsException) rethrow;
        if (fallbacks.isEmpty && slot.selectUrl.isEmpty) {
          throw SalesSopSlotsException(
            e.toString().replaceFirst('Exception: ', ''),
          );
        }
      }
    }

    final body = await _postJson(
      explicitUrl: slot.selectUrl,
      fallbackPaths: fallbacks,
      payload: payload,
      auth: auth,
      errorFallback: 'Could not submit slots',
    );
    return _resultFromBody(body);
  }

  Future<SalesSopSlotsResult?> confirmSlot({
    required SalesSopSlot slot,
    required int acceptedSlotIndex,
    String note = '',
    String? salesSopId,
  }) async {
    if (!slot.canAccept) {
      throw const SalesSopSlotsException(
        'You cannot confirm this visit.',
      );
    }

    final auth = await _authParams();
    final sopId = await _tryResolveSalesSopId(salesSopId, auth.token);

    if (slot.isSiteInspection) {
      final body = await _postJson(
        explicitUrl: slot.confirmUrl,
        fallbackPaths: [
          if (sopId.isNotEmpty)
            'sales_sop_details/$sopId/slots/site-inspection/accept',
        ],
        payload: {'accepted_slot_index': acceptedSlotIndex},
        auth: auth,
        errorFallback: 'Could not accept slot',
      );
      return _resultFromBody(body);
    }

    final runId = slot.confirmRunId;
    if (runId.isEmpty && slot.confirmUrl.isEmpty) {
      throw const SalesSopSlotsException(
        'Cannot confirm this slot. Missing confirm item.',
      );
    }

    final payload = <String, dynamic>{
      if (runId.isNotEmpty) 'item_run_id': _idPayload(runId),
      if (slot.confirmActionId.isNotEmpty) 'action_id': slot.confirmActionId,
      'accepted_slot_index': acceptedSlotIndex,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    };

    final fallbacks = <String>[
      if (sopId.isNotEmpty) 'sales_sop_details/$sopId/slots/confirm',
    ];

    if (auth.isClient) {
      try {
        final body = await ClientPortalService().confirmSlots(payload);
        return _resultFromBody(body);
      } catch (e) {
        if (e is SalesSopSlotsException) rethrow;
        if (fallbacks.isEmpty && slot.confirmUrl.isEmpty) {
          throw SalesSopSlotsException(
            e.toString().replaceFirst('Exception: ', ''),
          );
        }
      }
    }

    final body = await _postJson(
      explicitUrl: slot.confirmUrl,
      fallbackPaths: fallbacks,
      payload: payload,
      auth: auth,
      errorFallback: 'Could not confirm slot',
    );
    return _resultFromBody(body);
  }

  /// Kept for older callers; workflow confirm now uses [confirmSlot].
  Future<void> acceptSlot({
    required SalesSopSlot slot,
    required int acceptedSlotIndex,
    String note = '',
    String? salesSopId,
  }) async {
    await confirmSlot(
      slot: slot,
      acceptedSlotIndex: acceptedSlotIndex,
      note: note,
      salesSopId: salesSopId,
    );
  }

  SalesSopSlotsResult? _resultFromBody(Map<String, dynamic> body) {
    if (body['slots'] is List) {
      return SalesSopSlotsResult.fromJson(body);
    }
    final section = body['section'];
    if (section is Map && section['slots'] is List) {
      return SalesSopSlotsResult.fromJson(body);
    }
    final data = body['data'];
    if (data is Map && data['slots'] is List) {
      return SalesSopSlotsResult.fromJson(body);
    }
    return null;
  }

  dynamic _idPayload(String id) {
    return int.tryParse(id.trim()) ?? id.trim();
  }

  Future<String> _resolveSalesSopId(String? override, String apiToken) async {
    final sopId = await _tryResolveSalesSopId(override, apiToken);
    if (sopId.isEmpty) {
      throw const SalesSopSlotsException(
        'Could not resolve this project. Select the project again.',
        statusCode: 400,
      );
    }
    return sopId;
  }

  Future<String> _tryResolveSalesSopId(
    String? override,
    String apiToken,
  ) async {
    final explicit = override?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('sales_sop_id')?.trim() ?? '';
    final projectId = prefs.getString('project_id');
    final resolved = await DataProvider().resolveSalesSopId(
      projectId: projectId,
      apiToken: apiToken,
    );
    return (resolved ?? cached).trim();
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

  Future<Map<String, dynamic>> _postJson({
    required String explicitUrl,
    required List<String> fallbackPaths,
    required Map<String, dynamic> payload,
    required _AuthParams auth,
    required String errorFallback,
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
    final candidates = _postUris(explicitUrl, fallbackPaths, query);

    for (final uri in candidates) {
      try {
        final res = await ApiHttp.post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 30));
        lastStatus = res.statusCode;
        final decoded = _decodeMap(res.body);

        if (res.statusCode == 400) {
          throw SalesSopSlotsException(
            _messageFromBody(decoded) ?? errorFallback,
            statusCode: 400,
          );
        }
        if (res.statusCode == 401 || res.statusCode == 403) {
          lastMessage = _messageFromBody(decoded) ??
              (res.statusCode == 401
                  ? 'Invalid api token'
                  : 'You do not have permission');
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastMessage = _messageFromBody(decoded) ??
              '$errorFallback (${res.statusCode})';
          continue;
        }
        if (decoded != null &&
            decoded.containsKey('success') &&
            decoded['success'] == false) {
          lastMessage = _messageFromBody(decoded) ?? errorFallback;
          continue;
        }
        return decoded ?? <String, dynamic>{'success': true};
      } on SessionInvalidatedException {
        rethrow;
      } on SalesSopSlotsException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
      }
    }

    throw SalesSopSlotsException(
      lastMessage ?? errorFallback,
      statusCode: lastStatus,
    );
  }

  List<Uri> _postUris(
    String explicitUrl,
    List<String> fallbackPaths,
    Map<String, String> query,
  ) {
    final uris = <Uri>[];
    final trimmed = explicitUrl.trim();
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

    for (final fallbackPath in fallbackPaths) {
      final path = fallbackPath.trim();
      if (path.isEmpty) continue;
      for (final base in baseUrls) {
        for (final prefix in const ['API', 'api']) {
          uris.add(
            Uri.parse('$base/$prefix/$path').replace(queryParameters: query),
          );
        }
      }
    }
    return uris;
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
    final role = (prefs.getString('role') ?? '').trim().toLowerCase();
    return _AuthParams(
      token: token,
      userId: userId,
      isClient: role == 'client',
    );
  }
}

class _AuthParams {
  final String token;
  final String userId;
  final bool isClient;

  const _AuthParams({
    required this.token,
    required this.userId,
    required this.isClient,
  });
}
