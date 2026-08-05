import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// JSON Client Portal API (`/api/client_portal/*`).
///
/// Auth: session cookie (role=Client) **or** `api_token` via query /
/// `X-Api-Token` / `Authorization: Bearer` / JSON body.
/// Aliases under `/API/client_portal/*` are tried as fallbacks.
class ClientPortalService {
  static const String baseUrl = 'https://office.buildahome.in';
  static const String _cookiePrefsKey = 'client_portal_session_cookie';

  static const List<String> sectionKeys = [
    'project',
    'documents',
    'floor_plan_elevation',
    'design_element',
    'site_preparation',
    'demolition',
    'site_inspection',
    'all_documents',
  ];

  static final ClientPortalService _instance = ClientPortalService._();
  factory ClientPortalService() => _instance;
  ClientPortalService._();

  String? _sessionCookie;

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<String?> _apiToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim();
    if (token == null || token.isEmpty || token.toLowerCase() == 'null') {
      return null;
    }
    return token;
  }

  Future<void> _ensureCookieLoaded() async {
    if (_sessionCookie != null) return;
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString(_cookiePrefsKey);
  }

  Future<void> _persistCookieFrom(http.BaseResponse response) async {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final parts = raw.split(',');
    final kept = <String>[];
    for (final part in parts) {
      final first = part.split(';').first.trim();
      if (first.toLowerCase().startsWith('buildahome_session=')) {
        kept.add(first);
      }
    }
    if (kept.isEmpty) return;
    _sessionCookie = kept.join('; ');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiePrefsKey, _sessionCookie!);
  }

  Future<Map<String, String>> _headers({
    required String apiToken,
    bool jsonBody = false,
    bool multipart = false,
  }) async {
    await _ensureCookieLoaded();
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': apiToken,
      'Authorization': 'Bearer $apiToken',
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (jsonBody) headers['Content-Type'] = 'application/json';
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  List<String> _pathAliases(String path) {
    // Prefer /api/, fall back to /API/
    if (path.startsWith('/api/')) {
      return [path, path.replaceFirst('/api/', '/API/')];
    }
    if (path.startsWith('/API/')) {
      return [path, path.replaceFirst('/API/', '/api/')];
    }
    return [path];
  }

  Uri _uri(String path, {Map<String, String>? query, String? apiToken}) {
    final q = <String, String>{
      if (query != null) ...query,
      if (apiToken != null) 'api_token': apiToken,
    };
    return Uri.parse('$baseUrl$path')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, dynamic> _decodeOrThrow(http.Response response) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode == 401) {
      throw Exception(json?['message']?.toString() ?? 'Unauthorized');
    }
    if (response.statusCode == 404) {
      throw Exception(
        json?['message']?.toString() ?? 'No project linked to this client',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        json?['message']?.toString() ??
            'Request failed (${response.statusCode})',
      );
    }
    if (json == null) {
      throw Exception('Invalid response from server');
    }
    if (json['success'] == false) {
      throw Exception(json['message']?.toString() ?? 'Request failed');
    }
    return json;
  }

  Future<void> _cacheIdsFromPayload(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final sopId = payload['sales_sop_id']?.toString();
    final convertedId = payload['converted_project_id']?.toString();
    if (sopId != null && sopId.isNotEmpty) {
      await prefs.setString('sales_sop_id', sopId);
    }
    if (convertedId != null && convertedId.isNotEmpty) {
      await prefs.setString('project_id', convertedId);
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final token = await _apiToken();
    if (token == null) {
      throw Exception('Not authenticated. Please log in again.');
    }

    Object? lastError;
    for (final alias in _pathAliases(path)) {
      try {
        final response = await http
            .get(
              _uri(alias, query: query, apiToken: token),
              headers: await _headers(apiToken: token),
            )
            .timeout(const Duration(seconds: 25));
        await _persistCookieFrom(response);
        final json = _decodeOrThrow(response);
        await _cacheIdsFromPayload(json);
        return json;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Unable to load client portal data',
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _apiToken();
    if (token == null) {
      throw Exception('Not authenticated. Please log in again.');
    }
    final payload = <String, dynamic>{...body, 'api_token': token};

    Object? lastError;
    for (final alias in _pathAliases(path)) {
      try {
        final response = await http
            .post(
              _uri(alias, apiToken: token),
              headers: await _headers(apiToken: token, jsonBody: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 30));
        await _persistCookieFrom(response);
        // tutorial_complete may return 204
        if (response.statusCode == 204) {
          return {'success': true};
        }
        final json = _decodeOrThrow(response);
        await _cacheIdsFromPayload(json);
        return json;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Request failed',
    );
  }

  Future<Map<String, dynamic>> _postMultipart(
    String path,
    Map<String, String> fields, {
    required String fileField,
    required File file,
    String? filename,
  }) async {
    final token = await _apiToken();
    if (token == null) {
      throw Exception('Not authenticated. Please log in again.');
    }

    Object? lastError;
    for (final alias in _pathAliases(path)) {
      try {
        final request = http.MultipartRequest(
          'POST',
          _uri(alias, apiToken: token),
        );
        request.headers.addAll(
          await _headers(apiToken: token, multipart: true),
        );
        request.fields.addAll({...fields, 'api_token': token});
        request.files.add(
          await http.MultipartFile.fromPath(
            fileField,
            file.path,
            filename: filename ?? file.path.split('/').last,
          ),
        );
        final streamed =
            await request.send().timeout(const Duration(seconds: 60));
        final response = await http.Response.fromStream(streamed);
        await _persistCookieFrom(response);
        final json = _decodeOrThrow(response);
        await _cacheIdsFromPayload(json);
        return json;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Upload failed',
    );
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// GET /api/client_portal  (optional `?sections=a,b`)
  Future<Map<String, dynamic>> getPortal({List<String>? sections}) {
    return _get(
      '/api/client_portal',
      query: sections == null || sections.isEmpty
          ? null
          : {'sections': sections.join(',')},
    );
  }

  /// GET /api/client_portal/sections
  Future<Map<String, dynamic>> getAllSections() {
    return _get('/api/client_portal/sections');
  }

  /// GET /api/client_portal/sections/<key>
  Future<Map<String, dynamic>> getSection(String key) {
    return _get('/api/client_portal/sections/$key');
  }

  Future<Map<String, dynamic>> getDocuments() => getSection('documents');
  Future<Map<String, dynamic>> getFloorPlanElevation() =>
      getSection('floor_plan_elevation');
  Future<Map<String, dynamic>> getDesignElement() =>
      getSection('design_element');
  Future<Map<String, dynamic>> getSitePreparation() =>
      getSection('site_preparation');
  Future<Map<String, dynamic>> getDemolition() => getSection('demolition');
  Future<Map<String, dynamic>> getSiteInspection() =>
      getSection('site_inspection');
  Future<Map<String, dynamic>> getAllDocuments() =>
      getSection('all_documents');
  Future<Map<String, dynamic>> getProject() => getSection('project');

  Map<String, dynamic> sectionOf(Map<String, dynamic> payload) {
    if (payload['section'] is Map) {
      return Map<String, dynamic>.from(payload['section'] as Map);
    }
    return <String, dynamic>{};
  }

  List<String> availableSectionsOf(Map<String, dynamic> payload) {
    final raw = payload['available_sections'];
    if (raw is! List) return List<String>.from(sectionKeys);
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// POST /api/client_portal/documents/upload
  /// multipart: `doc_key=aadhar` + field named after doc_key, or
  /// `custom_doc_name` + `custom_doc_files`.
  Future<Map<String, dynamic>> uploadDocument({
    required String docKey,
    required File file,
    String? customDocName,
  }) async {
    final isCustom = docKey == 'custom' ||
        (customDocName != null && customDocName.trim().isNotEmpty);
    if (isCustom) {
      return _postMultipart(
        '/api/client_portal/documents/upload',
        {
          'doc_key': 'custom',
          'custom_doc_name': customDocName?.trim().isNotEmpty == true
              ? customDocName!.trim()
              : 'custom',
        },
        fileField: 'custom_doc_files',
        file: file,
      );
    }
    return _postMultipart(
      '/api/client_portal/documents/upload',
      {'doc_key': docKey},
      fileField: docKey,
      file: file,
    );
  }

  /// POST /api/client_portal/documents/comment
  Future<Map<String, dynamic>> saveComment(String comment) {
    return _postJson('/api/client_portal/documents/comment', {
      'client_kyc_comment': comment,
    });
  }

  /// POST /api/client_portal/site-preparation
  /// Body: `{ "demolition_required": "yes"|"no", "borewell_required": "yes"|"no" }`
  Future<Map<String, dynamic>> saveSitePreparation({
    required bool demolitionRequired,
    required bool borewellRequired,
  }) {
    return _postJson('/api/client_portal/site-preparation', {
      'demolition_required': demolitionRequired ? 'yes' : 'no',
      'borewell_required': borewellRequired ? 'yes' : 'no',
    });
  }

  /// POST /api/client_portal/site-preparation/defer
  Future<Map<String, dynamic>> deferSitePreparation() {
    return _postJson('/api/client_portal/site-preparation/defer', {});
  }

  /// POST /api/client_portal/demolition
  Future<Map<String, dynamic>> saveDemolition({
    required bool demolitionRequired,
    String? completionDate,
    String? comment,
  }) {
    return _postJson('/api/client_portal/demolition', {
      'demolition_required': demolitionRequired ? 'yes' : 'no',
      if (completionDate != null) 'demolition_completion_date': completionDate,
      if (comment != null) 'demolition_comment': comment,
    });
  }

  /// POST /api/client_portal/site-inspection
  Future<Map<String, dynamic>> submitSiteInspection({
    required String presenceType,
    String? virtualConnectionDetails,
    required String slot1Date,
    required String slot1Period,
    required String slot2Date,
    required String slot2Period,
    required String slot3Date,
    required String slot3Period,
    required bool siteCleanedConfirmed,
    File? siteCleanedProof,
  }) async {
    final fields = <String, dynamic>{
      'presence_type': presenceType,
      if (virtualConnectionDetails != null &&
          virtualConnectionDetails.trim().isNotEmpty)
        'virtual_connection_details': virtualConnectionDetails.trim(),
      'slot1_date': slot1Date,
      'slot1_period': slot1Period,
      'slot2_date': slot2Date,
      'slot2_period': slot2Period,
      'slot3_date': slot3Date,
      'slot3_period': slot3Period,
      'site_cleaned_confirmed': siteCleanedConfirmed,
    };

    if (siteCleanedProof == null) {
      return _postJson('/api/client_portal/site-inspection', fields);
    }

    // Multipart when attaching proof.
    final token = await _apiToken();
    if (token == null) {
      throw Exception('Not authenticated. Please log in again.');
    }
    Object? lastError;
    for (final alias in _pathAliases('/api/client_portal/site-inspection')) {
      try {
        final request = http.MultipartRequest(
          'POST',
          _uri(alias, apiToken: token),
        );
        request.headers.addAll(
          await _headers(apiToken: token, multipart: true),
        );
        fields.forEach((k, v) {
          request.fields[k] = v.toString();
        });
        request.fields['api_token'] = token;
        request.files.add(
          await http.MultipartFile.fromPath(
            'site_cleaned_proof',
            siteCleanedProof.path,
          ),
        );
        final streamed =
            await request.send().timeout(const Duration(seconds: 60));
        final response = await http.Response.fromStream(streamed);
        await _persistCookieFrom(response);
        final json = _decodeOrThrow(response);
        await _cacheIdsFromPayload(json);
        return json;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Could not submit site inspection',
    );
  }

  /// POST /api/client_portal/tutorial_complete
  Future<void> completeTutorial() async {
    await _postJson('/api/client_portal/tutorial_complete', {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('client_portal_tutorial_done', true);
  }

  String serveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) return '$baseUrl$path';
    return '$baseUrl/$path';
  }

  Future<void> clearSession() async {
    _sessionCookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookiePrefsKey);
  }
}
