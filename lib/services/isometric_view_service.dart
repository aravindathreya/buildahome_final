import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_base.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// `GET /API/mobile/isometric-view` on [kProductionApiBaseUrl].
const String kIsometricViewEndpoint = '/API/mobile/isometric-view';

/// JSON field that holds the isometric page URL.
const String kIsometricViewLinkKey = 'url';

class IsometricViewException implements Exception {
  final String message;

  const IsometricViewException(this.message);

  @override
  String toString() => message;
}

/// Asks the web API for the isometric view page URL for the open project.
class IsometricViewService {
  IsometricViewService._();

  static final IsometricViewService instance = IsometricViewService._();

  factory IsometricViewService() => instance;

  Future<Uri> fetchPageUri() async {
    final endpoint = kIsometricViewEndpoint.trim();
    final linkKey = kIsometricViewLinkKey.trim();
    if (endpoint.isEmpty || linkKey.isEmpty) {
      throw const IsometricViewException(
        'The 3D House Tour link is not connected yet.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim() ?? '';
    if (token.isEmpty || token.toLowerCase() == 'null') {
      throw const IsometricViewException('Not signed in');
    }

    final projectId = prefs.getString('project_id')?.trim() ?? '';
    if (projectId.isEmpty || projectId.toLowerCase() == 'null') {
      throw const IsometricViewException('Select a project first.');
    }

    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id'))?.trim() ??
            '';

    final uri = _requestUri(
      endpoint: endpoint,
      token: token,
      projectId: projectId,
      userId: userId,
    );

    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };

    print('[IsometricView] GET $uri');
    try {
      final response = await ApiHttp.get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      print(
        '[IsometricView] status=${response.statusCode} body=${response.body}',
      );

      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {
        body = null;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw IsometricViewException(
          body?['message']?.toString() ?? 'Not signed in',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw IsometricViewException(
          body?['message']?.toString() ??
              'Could not load the 3D House Tour (${response.statusCode})',
        );
      }
      if (body == null) {
        throw const IsometricViewException('Unexpected response from server');
      }
      // Cache human-facing project number whenever the API returns it.
      final projectCode = (body['project_code'] ?? body['project_number'])
          ?.toString()
          .trim();
      if (projectCode != null &&
          projectCode.isNotEmpty &&
          projectCode.toLowerCase() != 'null') {
        await prefs.setString('project_number', projectCode);
        await prefs.setString('project_code', projectCode);
      }
      if (body['success'] == false) {
        throw IsometricViewException(
          _messageOf(body) ?? 'Could not load the 3D House Tour',
        );
      }
      if (body['has_model'] == false) {
        throw IsometricViewException(
          _messageOf(body) ?? 'This project does not have a 3D model yet.',
        );
      }

      final link = _readLink(body, linkKey);
      if (link == null) {
        throw const IsometricViewException(
          'The 3D House Tour link was missing from the server response.',
        );
      }
      return link;
    } on IsometricViewException {
      rethrow;
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      throw IsometricViewException(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Uri _requestUri({
    required String endpoint,
    required String token,
    required String projectId,
    required String userId,
  }) {
    final Uri base;
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      base = Uri.parse(endpoint);
    } else {
      final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
      base = Uri.parse('$kProductionApiBaseUrl$path');
    }

    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'api_token': token,
        'project_id': projectId,
        if (userId.isNotEmpty) 'user_id': userId,
      },
    );
  }

  String? _messageOf(Map<String, dynamic> body) {
    final raw = body['message'];
    if (raw == null) return null;
    final message = raw.toString().trim();
    if (message.isEmpty || message.toLowerCase() == 'null') return null;
    return message;
  }

  Uri? _readLink(Map<String, dynamic> body, String key) {
    dynamic current = body;
    for (final part in key.split('.')) {
      final name = part.trim();
      if (name.isEmpty || current is! Map || !current.containsKey(name)) {
        return null;
      }
      current = current[name];
    }

    final raw = current?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    return uri;
  }
}
