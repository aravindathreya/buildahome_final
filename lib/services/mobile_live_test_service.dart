import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mobile_live_test.dart';
import 'mobile_live_test_access.dart';
import 'mobile_live_test_storage.dart';
import 'session_manager.dart';

class MobileLiveTestAuthParams {
  final String userId;
  final String apiToken;
  final String role;

  const MobileLiveTestAuthParams({
    required this.userId,
    required this.apiToken,
    this.role = '',
  });

  bool get isSignedIn => userId.isNotEmpty && apiToken.isNotEmpty;
}

class MobileLiveTestException implements Exception {
  final String message;
  final int? statusCode;
  final bool isPermissionDenied;
  final bool isDeviceAuthFailure;
  final bool isTaskUnavailable;

  const MobileLiveTestException(
    this.message, {
    this.statusCode,
    this.isPermissionDenied = false,
    this.isDeviceAuthFailure = false,
    this.isTaskUnavailable = false,
  });

  @override
  String toString() => message;
}

/// Dedicated Mobile Live Test client. Never calls production `/API/get_tasks`.
class MobileLiveTestService {
  MobileLiveTestService({
    http.Client? client,
    MobileLiveTestStore? store,
    Future<MobileLiveTestAuthParams> Function()? authParams,
    this.baseUrl = 'https://office.buildahome.in',
  })  : _client = client ?? http.Client(),
        _store = store ?? MobileLiveTestCredentials.store,
        _authParams = authParams ?? _defaultAuthParams;

  static final MobileLiveTestService instance = MobileLiveTestService();

  static const Duration requestTimeout = Duration(seconds: 20);
  static const Duration multipartTimeout = Duration(seconds: 90);

  final http.Client _client;
  final MobileLiveTestStore _store;
  final Future<MobileLiveTestAuthParams> Function() _authParams;
  final String baseUrl;
  final Map<int, _OpenTaskCacheEntry> _openTaskCache = {};

  static const Duration openTaskCacheTtl = Duration(seconds: 45);

  MobileLiveTestStore get store => _store;
  http.Client get httpClient => _client;

  void invalidateOpenTaskCache([int? itemRunId]) {
    if (itemRunId != null) {
      _openTaskCache.remove(itemRunId);
      return;
    }
    _openTaskCache.clear();
  }

  static Future<MobileLiveTestAuthParams> _defaultAuthParams() async {
    final prefs = await SharedPreferences.getInstance();
    return MobileLiveTestAuthParams(
      userId: (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
          .trim(),
      apiToken: (prefs.getString('api_token') ?? '').trim(),
      role: (prefs.getString('role') ?? '').trim(),
    );
  }

  static String defaultDeviceName() {
    try {
      final os = Platform.operatingSystem;
      if (os.isEmpty) return 'Mobile Test Device';
      return '${os[0].toUpperCase()}${os.substring(1)} Test Device';
    } catch (_) {
      return 'Mobile Test Device';
    }
  }

  Future<bool> isEnabled() => _store.hasCredentials();

  Future<bool> canEnableForCurrentUser() async {
    final auth = await _authParams();
    return MobileLiveTestAccess.canEnable(auth.role);
  }

  /// Register this phone as a Test Device using the logged-in Super Admin.
  Future<MobileLiveTestDevice> enable({String? displayName}) async {
    final auth = await _authParams();
    if (!auth.isSignedIn) {
      throw const MobileLiveTestException(
        'Sign in before enabling Test Mode.',
        statusCode: 401,
      );
    }
    if (!MobileLiveTestAccess.canEnable(auth.role)) {
      throw const MobileLiveTestException(
        'Only Super Admin can enable Mobile Test Mode.',
        statusCode: 403,
        isPermissionDenied: true,
      );
    }

    final name = (displayName ?? '').trim().isEmpty
        ? defaultDeviceName()
        : displayName!.trim();
    final uri = _uri(MobileLiveTestAccess.registerPath, auth);
    final response = await _send(
      () => _client.post(
        uri,
        headers: _headers(auth),
        body: jsonEncode({
          'user_id': auth.userId,
          'api_token': auth.apiToken,
          'display_name': name,
        }),
      ),
    );
    final body = _decode(response.body);
    await _maybeInvalidateUserSession(response.statusCode, body);

    if (response.statusCode == 403) {
      throw MobileLiveTestException(
        _message(body, 'Only Super Admin can register or manage Test Devices.'),
        statusCode: 403,
        isPermissionDenied: true,
      );
    }
    if (response.statusCode == 401) {
      throw MobileLiveTestException(
        _message(body, 'Invalid user_id or api_token.'),
        statusCode: 401,
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      throw MobileLiveTestException(
        _message(body, 'Could not register this Test Device.'),
        statusCode: response.statusCode,
      );
    }

    final deviceRaw = body['device'];
    final device = MobileLiveTestDevice.fromJson(
      deviceRaw is Map ? Map<String, dynamic>.from(deviceRaw) : null,
    );
    final token = device.deviceToken?.trim() ?? '';
    if (token.isEmpty || device.publicId.isEmpty) {
      throw const MobileLiveTestException(
        'Registration succeeded but no device_token was returned.',
        statusCode: 500,
      );
    }
    await _store.saveCredentials(
      deviceToken: token,
      publicId: device.publicId,
      displayName: device.displayName,
      registeredBy: auth.userId,
    );
    return device;
  }

  /// Disconnect this device from Test Mode. Does not cancel the backend run.
  Future<void> disable() async {
    await _store.clear();
  }

  Future<MobileLiveTestDevice> heartbeat() async {
    final body = await _deviceRequest(
      method: 'POST',
      path: MobileLiveTestAccess.heartbeatPath,
    );
    final deviceRaw = body['device'];
    return MobileLiveTestDevice.fromJson(
      deviceRaw is Map ? Map<String, dynamic>.from(deviceRaw) : null,
    );
  }

  Future<MobileLiveTestSession> fetchSession() async {
    final body = await _deviceRequest(
      method: 'GET',
      path: MobileLiveTestAccess.sessionPath,
    );
    return MobileLiveTestSession.fromJson(body);
  }

  Future<MobileLiveTestSession> fetchTasks() async {
    final body = await _deviceRequest(
      method: 'GET',
      path: MobileLiveTestAccess.tasksPath,
    );
    return MobileLiveTestSession.fromJson(body);
  }

  Future<MobileLiveTestExecutionContext> openTask(
    int itemRunId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _openTaskCache[itemRunId];
      if (cached != null && !cached.isExpired) {
        return cached.context;
      }
    }
    final body = await _deviceRequest(
      method: 'GET',
      path: MobileLiveTestAccess.taskOpenPath(itemRunId),
    );
    final context = MobileLiveTestExecutionContext.fromJson(body);
    _openTaskCache[itemRunId] = _OpenTaskCacheEntry(context);
    return context;
  }

  Future<MobileLiveTestCompletionResult> completeTask(
    int itemRunId, {
    String? decision,
    String? comment,
    String? actionId,
  }) async {
    final payload = <String, dynamic>{};
    final normalizedDecision = (decision ?? '').trim();
    final normalizedComment = (comment ?? '').trim();
    final normalizedActionId = (actionId ?? '').trim();
    if (normalizedDecision.isNotEmpty) {
      payload['decision'] = normalizedDecision;
    }
    if (normalizedComment.isNotEmpty) {
      payload['comments'] = normalizedComment;
    }
    if (normalizedActionId.isNotEmpty) {
      payload['action_id'] = normalizedActionId;
    }

    final body = await _deviceRequest(
      method: 'POST',
      path: MobileLiveTestAccess.taskCompletePath(itemRunId),
      jsonBody: payload,
    );
    invalidateOpenTaskCache(itemRunId);
    return MobileLiveTestCompletionResult.fromJson(body);
  }

  Future<MobileLiveTestExecutionContext> refreshTask(int itemRunId) =>
      openTask(itemRunId, forceRefresh: true);

  Future<List<MobileLiveTestComment>> fetchComments(int itemRunId) async {
    final body = await _deviceRequest(
      method: 'GET',
      path: MobileLiveTestAccess.taskActionPath(itemRunId, 'comments'),
    );
    final raw = body['comments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => MobileLiveTestComment.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<MobileLiveTestComment> addTaskComment(
    int itemRunId,
    String bodyText,
  ) async {
    final trimmed = bodyText.trim();
    if (trimmed.isEmpty) {
      throw const MobileLiveTestException('Comment is required.');
    }
    final body = await _deviceRequest(
      method: 'POST',
      path: MobileLiveTestAccess.taskActionPath(itemRunId, 'comments'),
      jsonBody: {'body': trimmed},
    );
    final commentRaw = body['comment'];
    if (commentRaw is Map) {
      return MobileLiveTestComment.fromJson(
        Map<String, dynamic>.from(commentRaw),
      );
    }
    return MobileLiveTestComment(
      id: _asIntFromDynamic(body['comment_id']),
      body: trimmed,
    );
  }

  Future<MobileLiveTestActionResult> submitJsonAction(
    int itemRunId,
    String pathOrSlug, {
    Map<String, dynamic>? payload,
  }) async {
    final path = _resolveTaskActionPath(itemRunId, pathOrSlug);
    _rejectForbiddenActorFields(payload ?? {});
    final body = await _deviceRequest(
      method: 'POST',
      path: path,
      jsonBody: payload ?? {},
    );
    return MobileLiveTestActionResult.fromJson(body);
  }

  Future<MobileLiveTestActionResult> submitMultipartAction(
    int itemRunId,
    String pathOrSlug, {
    Map<String, String> fields = const {},
    List<MobileLiveTestUploadPart> files = const [],
  }) async {
    final path = _resolveTaskActionPath(itemRunId, pathOrSlug);
    _rejectForbiddenActorFields(fields);
    final body = await _deviceMultipartRequest(
      path: path,
      fields: fields,
      files: files,
    );
    return MobileLiveTestActionResult.fromJson(body);
  }

  Future<MobileLiveTestActionResult> submitWorkflowAction(
    int itemRunId,
    MobileLiveTestWorkflowAction action, {
    Map<String, dynamic>? jsonPayload,
    Map<String, String>? fields,
    List<MobileLiveTestUploadPart>? files,
  }) async {
    final path = MobileLiveTestAccess.resolveActionSubmitPath(itemRunId, action.raw);
    if (path.isEmpty) {
      throw MobileLiveTestException(
        'No live-test API is configured for action type "${action.type}".',
      );
    }
    if (!MobileLiveTestAccess.isLiveTestPath(path)) {
      throw MobileLiveTestException(
        'Refusing to call production workflow API for live-test task.',
      );
    }
    if (action.usesMultipart) {
      return submitMultipartAction(
        itemRunId,
        path,
        fields: fields ?? {},
        files: files ?? const [],
      );
    }
    return submitJsonAction(itemRunId, path, payload: jsonPayload);
  }

  String _resolveTaskActionPath(int itemRunId, String pathOrSlug) {
    final value = pathOrSlug.trim();
    if (value.startsWith('/API/')) return value;
    if (value.contains('/mobile-live-test/')) return value;
    final slug = value.contains('/') ? value.split('/').last : value;
    return MobileLiveTestAccess.taskActionPath(itemRunId, slug);
  }

  void _rejectForbiddenActorFields(Map<String, dynamic> payload) {
    const forbidden = {
      'acting_user',
      'acting_user_id',
      'mapped_user_id',
      'test_user_id',
      'author_id',
      'submitted_by',
      'requested_by',
      'added_by',
    };
    for (final key in forbidden) {
      if (payload.containsKey(key) &&
          payload[key] != null &&
          payload[key].toString().trim().isNotEmpty) {
        throw MobileLiveTestException(
          'Mobile cannot send $key for live-test actions.',
        );
      }
    }
  }

  int? _asIntFromDynamic(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<Map<String, dynamic>> _deviceMultipartRequest({
    required String path,
    Map<String, String> fields = const {},
    List<MobileLiveTestUploadPart> files = const [],
  }) async {
    final auth = await _authParams();
    if (!auth.isSignedIn) {
      throw const MobileLiveTestException(
        'Sign in before using Test Mode.',
        statusCode: 401,
      );
    }
    final token = (await _store.readDeviceToken() ?? '').trim();
    if (token.isEmpty) {
      throw const MobileLiveTestException(
        'Test Mode is not enabled on this device.',
        statusCode: 401,
        isDeviceAuthFailure: true,
      );
    }

    final uri = _uri(path, auth, deviceToken: token);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_multipartHeaders(auth, deviceToken: token));
    request.fields['user_id'] = auth.userId;
    request.fields['api_token'] = auth.apiToken;
    request.fields['device_token'] = token;
    for (final entry in fields.entries) {
      request.fields[entry.key] = entry.value;
    }
    var filesAttached = 0;
    for (final part in files) {
      final file = File(part.filePath);
      if (!await file.exists()) {
        throw MobileLiveTestException(
          'Could not read the selected file. Please pick the file again.',
        );
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          part.fieldName,
          part.filePath,
          filename: part.filename,
        ),
      );
      filesAttached++;
    }
    if (files.isNotEmpty && filesAttached == 0) {
      throw MobileLiveTestException(
        'Could not read the selected file. Please pick the file again.',
      );
    }

    final streamed = await _sendMultipart(() => _client.send(request));
    final response = await http.Response.fromStream(streamed);
    final body = _decode(response.body);
    await _maybeInvalidateUserSession(response.statusCode, body);

    if (response.statusCode == 401) {
      final deviceFailure = _isDeviceAuthFailure(body);
      if (deviceFailure) await _store.clear();
      throw MobileLiveTestException(
        _message(body, 'Test Device authentication failed.'),
        statusCode: 401,
        isDeviceAuthFailure: deviceFailure,
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      throw MobileLiveTestException(
        _message(body, 'Could not submit this live-test action.'),
        statusCode: response.statusCode,
        isTaskUnavailable: response.statusCode == 409,
        isPermissionDenied: response.statusCode == 403,
      );
    }
    return body;
  }

  Uri _uri(String path, MobileLiveTestAuthParams auth, {String? deviceToken}) {
    final query = <String, String>{
      'user_id': auth.userId,
      'api_token': auth.apiToken,
    };
    if (deviceToken != null && deviceToken.isNotEmpty) {
      query['device_token'] = deviceToken;
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Map<String, String> _headers(
    MobileLiveTestAuthParams auth, {
    String? deviceToken,
  }) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Api-Token': auth.apiToken,
      'Authorization': 'Bearer ${auth.apiToken}',
      if (deviceToken != null && deviceToken.isNotEmpty)
        'X-Live-Test-Device-Token': deviceToken,
    };
  }

  /// Multipart uploads must not set Content-Type — the client sets boundary.
  Map<String, String> _multipartHeaders(
    MobileLiveTestAuthParams auth, {
    String? deviceToken,
  }) {
    return {
      'Accept': 'application/json',
      'X-Api-Token': auth.apiToken,
      'Authorization': 'Bearer ${auth.apiToken}',
      if (deviceToken != null && deviceToken.isNotEmpty)
        'X-Live-Test-Device-Token': deviceToken,
    };
  }

  Future<Map<String, dynamic>> _deviceRequest({
    required String method,
    required String path,
    Map<String, dynamic>? jsonBody,
  }) async {
    final auth = await _authParams();
    if (!auth.isSignedIn) {
      throw const MobileLiveTestException(
        'Sign in before using Test Mode.',
        statusCode: 401,
      );
    }
    final token = (await _store.readDeviceToken() ?? '').trim();
    if (token.isEmpty) {
      throw const MobileLiveTestException(
        'Test Mode is not enabled on this device.',
        statusCode: 401,
        isDeviceAuthFailure: true,
      );
    }

    final uri = _uri(path, auth, deviceToken: token);
    final headers = _headers(auth, deviceToken: token);
    final encodedBody =
        jsonBody == null ? null : jsonEncode(jsonBody);
    final response = await _send(() {
      if (method == 'POST') {
        return _client.post(uri, headers: headers, body: encodedBody ?? '{}');
      }
      return _client.get(uri, headers: headers);
    });
    final body = _decode(response.body);
    await _maybeInvalidateUserSession(response.statusCode, body);

    if (response.statusCode == 401) {
      final deviceFailure = _isDeviceAuthFailure(body);
      if (deviceFailure) {
        await _store.clear();
      }
      throw MobileLiveTestException(
        _message(body, 'Test Device authentication failed.'),
        statusCode: 401,
        isDeviceAuthFailure: deviceFailure,
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      final message = _message(body, 'Could not load Mobile Live Test.');
      throw MobileLiveTestException(
        message,
        statusCode: response.statusCode,
        isTaskUnavailable: response.statusCode == 409,
        isPermissionDenied: response.statusCode == 403,
      );
    }
    return body;
  }

  Future<http.Response> _send(Future<http.Response> Function() send) {
    return send().timeout(requestTimeout);
  }

  Future<http.StreamedResponse> _sendStream(
    Future<http.StreamedResponse> Function() send,
  ) {
    return send().timeout(requestTimeout);
  }

  Future<http.StreamedResponse> _sendMultipart(
    Future<http.StreamedResponse> Function() send,
  ) {
    return send().timeout(multipartTimeout);
  }

  Map<String, dynamic> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  String _message(Map<String, dynamic> body, String fallback) {
    final message = body['message']?.toString().trim() ?? '';
    return message.isEmpty ? fallback : message;
  }

  bool _isUserSessionInvalid(int statusCode, Map<String, dynamic> body) {
    final message = _message(body, '').toLowerCase();
    if (message.contains('invalid api token')) return true;
    if (statusCode != 401) return false;
    return message.contains('invalid user_id or api_token');
  }

  bool _isDeviceAuthFailure(Map<String, dynamic> body) {
    final message = _message(body, '').toLowerCase();
    return message.contains('device_token') ||
        message.contains('test device') ||
        message.contains('unknown or disabled');
  }

  Future<void> _maybeInvalidateUserSession(
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    if (!_isUserSessionInvalid(statusCode, body)) return;
    try {
      await SessionManager.instance.handleStatusAndBody(
        statusCode: statusCode,
        body: jsonEncode(body),
        requestHadCredentials: true,
      );
    } catch (_) {}
  }
}

class _OpenTaskCacheEntry {
  final MobileLiveTestExecutionContext context;
  final DateTime fetchedAt;

  _OpenTaskCacheEntry(this.context) : fetchedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) >
      MobileLiveTestService.openTaskCacheTtl;
}
