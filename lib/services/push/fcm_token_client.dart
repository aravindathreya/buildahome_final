import 'dart:convert';

import 'package:http/http.dart' as http;

/// Registers this device's FCM token against the logged-in user.
///
/// The live API is `POST /API/save_fcm_token` (`user_id` + `fcm_token`).
/// It should upsert by [deviceId] + token, and move the token when the same
/// device signs in as someone else. There is no public delete route; logout
/// still calls [FcmTokenClient.unregister] so a future endpoint can drop it.
class FcmTokenRegistration {
  final String userId;
  final String apiToken;
  final String fcmToken;
  final String platform;
  final String deviceId;

  const FcmTokenRegistration({
    required this.userId,
    required this.apiToken,
    required this.fcmToken,
    required this.platform,
    required this.deviceId,
  });
}

typedef FcmTokenPoster = Future<http.Response> Function(
  Uri uri,
  Map<String, String> fields,
  Map<String, String> headers,
);

class FcmTokenClient {
  FcmTokenClient({
    FcmTokenPoster? post,
    this.baseUrl = 'https://office.buildahome.in',
  }) : _post = post ?? _defaultPost;

  final String baseUrl;
  final FcmTokenPoster _post;

  Future<bool> register(FcmTokenRegistration registration) {
    return _send('/API/save_fcm_token', registration);
  }

  Future<bool> unregister({
    required String userId,
    required String apiToken,
    required String fcmToken,
    required String deviceId,
  }) {
    return _send(
      '/API/unregister_fcm_token',
      FcmTokenRegistration(
        userId: userId,
        apiToken: apiToken,
        fcmToken: fcmToken,
        platform: '',
        deviceId: deviceId,
      ),
    );
  }

  Future<bool> _send(String path, FcmTokenRegistration registration) async {
    if (registration.userId.trim().isEmpty ||
        registration.apiToken.trim().isEmpty ||
        registration.fcmToken.trim().isEmpty) {
      return false;
    }
    try {
      final response = await _post(
        Uri.parse('$baseUrl$path'),
        {
          'user_id': registration.userId.trim(),
          'api_token': registration.apiToken.trim(),
          'fcm_token': registration.fcmToken.trim(),
          'device_id': registration.deviceId.trim(),
          if (registration.platform.trim().isNotEmpty)
            'platform': registration.platform.trim(),
        },
        {
          'Accept': 'application/json',
          'X-Api-Token': registration.apiToken.trim(),
        },
      );
      return _accepted(response);
    } catch (_) {
      return false;
    }
  }

  /// `save_fcm_token` answers with the plain text `success` or `failure`.
  static bool _accepted(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    final body = response.body.trim().toLowerCase();
    if (body == 'failure' || body == 'failed' || body == 'error') return false;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        if (decoded['success'] == false) return false;
        final status = decoded['status']?.toString().trim().toLowerCase();
        if (status == 'failure' || status == 'failed' || status == 'error') {
          return false;
        }
      }
    } catch (_) {}
    return true;
  }

  static Future<http.Response> _defaultPost(
    Uri uri,
    Map<String, String> fields,
    Map<String, String> headers,
  ) {
    return http
        .post(uri, headers: headers, body: fields)
        .timeout(const Duration(seconds: 20));
  }
}

/// Binds one device token to one user, including refresh and logout.
class FcmSessionCoordinator {
  FcmSessionCoordinator(this.client);

  final FcmTokenClient client;
  String? userId;
  String? fcmToken;
  String? deviceId;

  Future<bool> bind(FcmTokenRegistration registration) async {
    final previousUser = userId;
    final previousToken = fcmToken;
    final switchingUser =
        previousUser != null && previousUser != registration.userId;
    final tokenChanged =
        previousToken != null && previousToken != registration.fcmToken;
    if ((switchingUser || tokenChanged) &&
        previousUser != null &&
        previousToken != null) {
      await client.unregister(
        userId: previousUser,
        apiToken: registration.apiToken,
        fcmToken: previousToken,
        deviceId: registration.deviceId,
      );
    }
    final ok = await client.register(registration);
    if (!ok) return false;
    userId = registration.userId;
    fcmToken = registration.fcmToken;
    deviceId = registration.deviceId;
    return true;
  }

  Future<bool> onTokenRefresh({
    required String fcmToken,
    required String apiToken,
    required String platform,
  }) {
    final uid = userId;
    final device = deviceId;
    if (uid == null || device == null) return Future.value(false);
    return bind(
      FcmTokenRegistration(
        userId: uid,
        apiToken: apiToken,
        fcmToken: fcmToken,
        platform: platform,
        deviceId: device,
      ),
    );
  }

  Future<bool> logout({required String apiToken}) async {
    final uid = userId;
    final token = fcmToken;
    final device = deviceId ?? '';
    userId = null;
    fcmToken = null;
    if (uid == null || token == null) return true;
    return client.unregister(
      userId: uid,
      apiToken: apiToken,
      fcmToken: token,
      deviceId: device,
    );
  }
}
