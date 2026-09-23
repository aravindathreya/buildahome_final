import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/multi_material_site_proof.dart';
import 'api_base.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// Client for the multi-material site-proof APIs.
class MultiMaterialSiteProofService {
  MultiMaterialSiteProofService._();
  static final MultiMaterialSiteProofService instance =
      MultiMaterialSiteProofService._();
  factory MultiMaterialSiteProofService() => instance;

  /// Same production host as single-material site-proof / workflow APIs.
  static const String baseUrl = kProductionApiBaseUrl;

  Future<MultiMaterialSiteProofSession> fetchSession({
    required String indentId,
    String? itemRunId,
  }) async {
    final auth = await _authParams();
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
      if ((itemRunId ?? '').trim().isNotEmpty)
        'item_run_id': itemRunId!.trim(),
    };

    final body = await _getJson(
      pathSuffix: 'site_proof/multi_material/${indentId.trim()}',
      query: query,
      auth: auth,
    );

    final payload = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    if (!payload.containsKey('indent_id') && indentId.trim().isNotEmpty) {
      payload['indent_id'] = int.tryParse(indentId.trim()) ?? indentId.trim();
    }
    if (!payload.containsKey('item_run_id') &&
        (itemRunId ?? '').trim().isNotEmpty) {
      payload['item_run_id'] =
          int.tryParse(itemRunId!.trim()) ?? itemRunId.trim();
    }
    return MultiMaterialSiteProofSession.fromJson(payload);
  }

  Future<Map<String, dynamic>> saveMaterial({
    required String itemRunId,
    required String materialKey,
    required String quantityReceivedToday,
    String comment = '',
  }) async {
    return _postJson(
      pathSuffix: 'site_proof/multi_material/${itemRunId.trim()}/material',
      body: {
        'material_key': materialKey,
        'quantity_received_today': quantityReceivedToday,
        if (comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> uploadMaterialFiles({
    required String itemRunId,
    required String materialKey,
    required List<File> files,
  }) async {
    if (files.isEmpty) {
      return const {'success': true, 'message': 'No files to upload'};
    }
    return _postMultipart(
      pathSuffix:
          'site_proof/multi_material/${itemRunId.trim()}/material/upload',
      fields: {
        'material_key': materialKey,
      },
      files: files,
    );
  }

  Future<Map<String, dynamic>> saveCommon({
    required String itemRunId,
    required MultiMaterialCommonFields fields,
  }) async {
    return _postJson(
      pathSuffix: 'site_proof/multi_material/${itemRunId.trim()}/common',
      body: fields.toRequestBody(),
    );
  }

  Future<Map<String, dynamic>> uploadVehicleFiles({
    required String itemRunId,
    required List<File> files,
  }) async {
    if (files.isEmpty) {
      return const {'success': true, 'message': 'No files to upload'};
    }
    return _postMultipart(
      pathSuffix:
          'site_proof/multi_material/${itemRunId.trim()}/vehicle/upload',
      fields: const {},
      files: files,
    );
  }

  Future<MultiMaterialSubmitResult> submit({
    required String itemRunId,
  }) async {
    final body = await _postJson(
      pathSuffix: 'site_proof/multi_material/${itemRunId.trim()}/submit',
      body: const {},
    );
    return MultiMaterialSubmitResult.fromJson(body);
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

    for (final prefix in const ['API', 'api']) {
      final uri = Uri.parse('$baseUrl/$prefix/$pathSuffix')
          .replace(queryParameters: query);
      try {
        final res = await ApiHttp.get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
        lastStatus = res.statusCode;
        final decoded = _tryDecodeMap(res.body);

        if (res.statusCode == 401 || res.statusCode == 403) {
          lastMessage = _messageFromBody(decoded) ??
              (res.statusCode == 401
                  ? 'Invalid api token'
                  : 'You do not have permission');
          continue;
        }

        if (res.statusCode == 404) {
          throw MultiMaterialSiteProofException(
            _messageFromBody(decoded) ??
                'Multi-material site proof not found',
            statusCode: 404,
          );
        }

        if (res.statusCode < 200 ||
            res.statusCode >= 300 ||
            decoded == null) {
          lastMessage = _messageFromBody(decoded) ??
              'Could not load multi-material site proof (${res.statusCode})';
          continue;
        }

        if (_truthy(decoded['success']) == false) {
          lastMessage = _messageFromBody(decoded) ??
              'Could not load multi-material site proof';
          continue;
        }

        return decoded;
      } on SessionInvalidatedException {
        rethrow;
      } on MultiMaterialSiteProofException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
      }
    }

    throw MultiMaterialSiteProofException(
      lastMessage ?? 'Could not load multi-material site proof',
      statusCode: lastStatus,
    );
  }

  Future<Map<String, dynamic>> _postJson({
    required String pathSuffix,
    required Map<String, dynamic> body,
  }) async {
    final auth = await _authParams();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Api-Token': auth.token,
      'Authorization': 'Bearer ${auth.token}',
    };
    final payload = <String, dynamic>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
      ...body,
    };

    int? lastStatus;
    String? lastMessage;

    for (final prefix in const ['API', 'api']) {
      final uri = Uri.parse('$baseUrl/$prefix/$pathSuffix');
      try {
        final res = await ApiHttp.post(
          uri,
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 45));
        lastStatus = res.statusCode;
        final decoded = _tryDecodeMap(res.body);

        if (res.statusCode == 401 || res.statusCode == 403) {
          lastMessage = _messageFromBody(decoded) ??
              (res.statusCode == 401
                  ? 'Invalid api token'
                  : 'You do not have permission');
          continue;
        }

        if (res.statusCode < 200 ||
            res.statusCode >= 300 ||
            decoded == null) {
          lastMessage = _messageFromBody(decoded) ??
              'Request failed (${res.statusCode})';
          continue;
        }

        if (_truthy(decoded['success']) == false) {
          lastMessage = _messageFromBody(decoded) ?? 'Request failed';
          continue;
        }

        return decoded;
      } on SessionInvalidatedException {
        rethrow;
      } on MultiMaterialSiteProofException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
      }
    }

    throw MultiMaterialSiteProofException(
      lastMessage ?? 'Request failed',
      statusCode: lastStatus,
    );
  }

  Future<Map<String, dynamic>> _postMultipart({
    required String pathSuffix,
    required Map<String, String> fields,
    required List<File> files,
  }) async {
    final auth = await _authParams();
    int? lastStatus;
    String? lastMessage;

    for (final prefix in const ['API', 'api']) {
      final uri = Uri.parse('$baseUrl/$prefix/$pathSuffix');
      try {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Accept'] = 'application/json';
        request.headers['X-Api-Token'] = auth.token;
        request.headers['Authorization'] = 'Bearer ${auth.token}';
        request.fields['api_token'] = auth.token;
        if (auth.userId.isNotEmpty) {
          request.fields['user_id'] = auth.userId;
        }
        request.fields.addAll(fields);

          for (final file in files) {
            if (!await file.exists()) {
              throw MultiMaterialSiteProofException(
                'Selected file is missing on device: ${file.path}',
              );
            }
            final name = file.path.split(Platform.pathSeparator).last;
            // Match single-material workflow uploads (field name `files`).
            // `files[]` is not seen by Flask as `files`, which caused
            // "at least one file is required".
            request.files.add(
              await http.MultipartFile.fromPath(
                'files',
                file.path,
                filename: name,
                contentType: _guessMediaType(name),
              ),
            );
          }

          if (request.files.isEmpty) {
            throw const MultiMaterialSiteProofException(
              'At least one file is required.',
            );
          }

          print(
            '[MultiMaterialSiteProof] upload '
            'path=$pathSuffix files=${request.files.length} '
            'fields=${request.fields.keys.toList()}',
          );

        final streamed =
            await ApiHttp.send(request).timeout(const Duration(seconds: 90));
        final res = await http.Response.fromStream(streamed);
        lastStatus = res.statusCode;
        final decoded = _tryDecodeMap(res.body);

        if (res.statusCode == 401 || res.statusCode == 403) {
          lastMessage = _messageFromBody(decoded) ??
              (res.statusCode == 401
                  ? 'Invalid api token'
                  : 'You do not have permission');
          continue;
        }

        if (res.statusCode < 200 ||
            res.statusCode >= 300 ||
            decoded == null) {
          lastMessage = _messageFromBody(decoded) ??
              'Upload failed (${res.statusCode})';
          continue;
        }

        if (_truthy(decoded['success']) == false) {
          lastMessage = _messageFromBody(decoded) ?? 'Upload failed';
          continue;
        }

        return decoded;
      } on SessionInvalidatedException {
        rethrow;
      } on MultiMaterialSiteProofException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
      }
    }

    throw MultiMaterialSiteProofException(
      lastMessage ?? 'Upload failed',
      statusCode: lastStatus,
    );
  }

  Future<_AuthParams> _authParams() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim() ?? '';
    if (token.isEmpty) {
      throw const MultiMaterialSiteProofException(
        'Not signed in',
        statusCode: 401,
      );
    }
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id'))?.trim() ??
            '';
    return _AuthParams(token: token, userId: userId);
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
    try {
      final raw = jsonDecode(body);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  String? _messageFromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    for (final key in const ['message', 'error', 'detail']) {
      final msg = body[key]?.toString().trim() ?? '';
      if (msg.isNotEmpty && msg.toLowerCase() != 'null') return msg;
    }
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) {
        return first.first.toString();
      }
      return first.toString();
    }
    return null;
  }

  MediaType? _guessMediaType(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'webm':
        return MediaType('video', 'webm');
      case 'm4v':
        return MediaType('video', 'x-m4v');
      default:
        return null;
    }
  }
}

class _AuthParams {
  final String token;
  final String userId;

  const _AuthParams({required this.token, required this.userId});
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
