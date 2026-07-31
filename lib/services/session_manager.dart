import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../Skin2/loginPage.dart';
import '../app_navigator.dart';
import 'data_provider.dart';

/// Handles single-device session invalidation.
///
/// Backend keeps one active [api_token] per user. When that token is replaced
/// (login on another device), authenticated APIs return 401 / invalid-token
/// payloads. This manager clears local session and returns the user to Login.
class SessionManager {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  static const String logoutMessage =
      'You cannot stay logged in on two devices at the same time. '
      'This account was signed in on another device, so you have been logged out here.';

  static const String logoutDialogTitle = 'Signed in on another device';

  bool _isLoggingOut = false;
  DateTime? _lastValidateAt;
  Future<bool>? _confirmInFlight;

  bool get isLoggingOut => _isLoggingOut;

  /// Returns true when the response means the local session is no longer valid.
  bool isSessionInvalidResponse(
    http.Response response, {
    Uri? requestUrl,
    bool requestHadCredentials = true,
  }) {
    if (_isLoginRequest(requestUrl ?? response.request?.url)) {
      return false;
    }
    return isSessionInvalid(
      statusCode: response.statusCode,
      body: response.body,
      requestHadCredentials: requestHadCredentials,
    );
  }

  bool isSessionInvalid({
    required int statusCode,
    String? body,
    dynamic decoded,
    bool requestHadCredentials = true,
  }) {
    // A response can only mean "token revoked" if we actually sent a token.
    if (!requestHadCredentials) return false;

    // Only auth failures — not normal business 400/403/500 errors.
    final parsed = decoded ?? _tryDecode(body);
    final message = _extractMessage(parsed)?.toLowerCase().trim() ?? '';

    // The backend says the call was missing credentials: that is a request
    // built without a token, not a session replaced on another device.
    if (_isMissingCredentialsMessage(message)) return false;

    if (statusCode == 401) {
      return true;
    }

    if (_isInvalidTokenMessage(message)) {
      // Explicit invalid-token wording is authoritative when we sent credentials.
      // Covers 200/success:false, bare 4xx, and odd payloads without success.
      return true;
    }

    return false;
  }

  /// Inspect an HTTP response. If the session is invalid, triggers logout.
  /// Returns true when logout was triggered.
  Future<bool> handleResponse(
    http.Response response, {
    Uri? requestUrl,
    bool requestHadCredentials = true,
    bool confirmBeforeLogout = true,
  }) async {
    if (!isSessionInvalidResponse(
      response,
      requestUrl: requestUrl,
      requestHadCredentials: requestHadCredentials,
    )) {
      return false;
    }
    if (confirmBeforeLogout &&
        !_isExplicitInvalidTokenBody(response.body) &&
        !await _storedTokenIsRejected()) {
      return false;
    }
    await forceLogoutDueToInvalidSession();
    return true;
  }

  /// Same as [handleResponse] but for already-decoded bodies / status codes.
  Future<bool> handleStatusAndBody({
    required int statusCode,
    String? body,
    Uri? requestUrl,
    bool requestHadCredentials = true,
    bool confirmBeforeLogout = true,
  }) async {
    if (_isLoginRequest(requestUrl)) return false;
    if (!isSessionInvalid(
      statusCode: statusCode,
      body: body,
      requestHadCredentials: requestHadCredentials,
    )) {
      return false;
    }
    // Explicit "Invalid api token" from the API is authoritative (e.g. while
    // completing a task). Do not wait on a second probe that can soft-fail and
    // leave the user staring at the raw error.
    if (confirmBeforeLogout &&
        !_isExplicitInvalidTokenBody(body) &&
        !await _storedTokenIsRejected()) {
      return false;
    }
    await forceLogoutDueToInvalidSession();
    return true;
  }

  /// Second opinion before logging anybody out: ask a known authenticated
  /// endpoint with the stored token. Individual endpoints can answer 401 for
  /// reasons unrelated to the session (missing resource, probe URLs, endpoints
  /// that expect different params), so a single failure is not enough.
  Future<bool> _storedTokenIsRejected() {
    return _confirmInFlight ??= () async {
      try {
        final response = await _probeSession();
        if (response == null) return false;
        return isSessionInvalid(
          statusCode: response.statusCode,
          body: response.body,
        );
      } finally {
        _confirmInFlight = null;
      }
    }();
  }

  /// Raw (non-intercepted) call to a stable authenticated endpoint.
  /// Returns null when credentials are missing locally or the network failed.
  Future<http.Response?> _probeSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId =
          (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
      final apiToken = (prefs.getString('api_token') ?? '').trim();
      if (userId.isEmpty || apiToken.isEmpty) return null;

      final uri = Uri.parse('https://office.buildahome.in/API/get_tasks')
          .replace(queryParameters: {
        'user_id': userId,
        'assigned_to': userId,
        'api_token': apiToken,
      });

      return await http
          .get(uri, headers: {'X-Api-Token': apiToken})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      print('[SessionManager] Session probe failed: $e');
      return null;
    }
  }

  Future<void> forceLogoutDueToInvalidSession() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    try {
      DataProvider().clearData();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('api_token');
        await prefs.remove('userId');
        await prefs.remove('user_id');
        await prefs.remove('username');
        await prefs.remove('role');
        await prefs.remove('project_id');
        await prefs.remove('project_value');
        await prefs.remove('completed');
        await prefs.remove('location');
        await prefs.clear();
      } catch (e) {
        print('[SessionManager] Failed clearing prefs: $e');
      }

      final navigator = globalNavigatorKey.currentState;
      final context = globalNavigatorKey.currentContext;
      final messenger = globalScaffoldMessengerKey.currentState;
      messenger?.clearSnackBars();

      if (context != null && context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text(logoutDialogTitle),
              content: const Text(logoutMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(logoutMessage),
            duration: Duration(seconds: 5),
            backgroundColor: Color(0xFFB45309),
          ),
        );
      }

      if (navigator != null) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreenNew()),
          (route) => false,
        );
      }
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _isLoggingOut = false;
      });
    }
  }

  /// Lightweight check used on cold start / app resume.
  Future<void> validateSessionIfLoggedIn({bool force = false}) async {
    if (_isLoggingOut) return;

    final now = DateTime.now();
    if (!force &&
        _lastValidateAt != null &&
        now.difference(_lastValidateAt!) < const Duration(seconds: 8)) {
      return;
    }
    _lastValidateAt = now;

    // Raw http to avoid recursive interceptor while logging out.
    final response = await _probeSession();
    if (response == null) return;

    // The probe is already the authoritative check, so no second call.
    await handleResponse(
      response,
      requestUrl: response.request?.url,
      confirmBeforeLogout: false,
    );
  }

  bool _isLoginRequest(Uri? url) {
    if (url == null) return false;
    final path = url.path.toLowerCase();
    return path.endsWith('/api/login') || path.endsWith('/login');
  }

  bool _isInvalidTokenMessage(String message) {
    if (message.isEmpty) return false;
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.contains('invalid api token');
  }

  bool _isExplicitInvalidTokenBody(String? body) {
    final message = _extractMessage(_tryDecode(body))?.toLowerCase().trim() ?? '';
    return _isInvalidTokenMessage(message);
  }

  bool _isMissingCredentialsMessage(String message) {
    if (message.isEmpty) return false;
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.contains('are required') &&
        (normalized.contains('api_token') || normalized.contains('user_id'));
  }

  dynamic _tryDecode(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _extractMessage(dynamic decoded) {
    if (decoded is Map) {
      final message = decoded['message'] ?? decoded['error'] ?? decoded['detail'];
      return message?.toString();
    }
    return null;
  }
}

/// Thrown after session logout so callers stop work without showing the raw
/// backend "Invalid api token" string.
class SessionInvalidatedException implements Exception {
  @override
  String toString() => SessionManager.logoutMessage;
}
