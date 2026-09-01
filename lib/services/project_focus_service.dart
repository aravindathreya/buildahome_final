import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/project_focus.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// Fetches the Project Focus dashboard for a sales SOP.
///
/// `GET /api/projects/{sales_sop_id}/focus`
///
/// Does not compute blockers, phases, or next actions locally — the backend
/// payload is rendered as-is.
class ProjectFocusService {
  ProjectFocusService._();
  static final ProjectFocusService instance = ProjectFocusService._();
  factory ProjectFocusService() => instance;

  static const String baseUrl = 'https://office.buildahome.in';

  Future<ProjectFocus> fetchFocus(String salesSopId) async {
    final sopId = salesSopId.trim();
    if (sopId.isEmpty || sopId.toLowerCase() == 'null') {
      throw const ProjectFocusException('Select a project first.');
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim();
    if (token == null || token.isEmpty) {
      throw const ProjectFocusException('Not signed in');
    }

    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id'))?.trim() ?? '';
    final projectId = prefs.getString('project_id')?.trim() ?? '';

    final authHeaders = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };

    final attempts = <Uri>[
      Uri.parse('$baseUrl/api/projects/$sopId/focus').replace(
        queryParameters: {
          'api_token': token,
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
      Uri.parse('$baseUrl/API/projects/$sopId/focus').replace(
        queryParameters: {
          'api_token': token,
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
      Uri.parse('$baseUrl/api/projects/focus').replace(
        queryParameters: {
          'api_token': token,
          'sales_sop_id': sopId,
          if (projectId.isNotEmpty) 'project_id': projectId,
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
    ];

    int? lastStatus;
    String? lastMessage;

    for (final uri in attempts) {
      print('[ProjectFocus] GET $uri');
      try {
        final res = await ApiHttp.get(uri, headers: authHeaders)
            .timeout(const Duration(seconds: 20));
        lastStatus = res.statusCode;
        print('[ProjectFocus] status=${res.statusCode} body=${res.body}');

        Map<String, dynamic>? body;
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        } catch (_) {
          body = null;
        }

        if (res.statusCode == 401) {
          lastMessage = body?['message']?.toString() ?? 'Unauthorized';
          continue;
        }
        if (res.statusCode == 404) {
          lastMessage = body?['message']?.toString() ??
              'Project focus is not available for this project.';
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastMessage = body?['message']?.toString() ??
              'Could not load project focus (${res.statusCode})';
          continue;
        }
        if (body == null) {
          lastMessage = 'Unexpected response from server';
          continue;
        }
        if (body['success'] == false) {
          lastMessage =
              body['message']?.toString() ?? 'Could not load project focus';
          continue;
        }

        return ProjectFocus.fromJson(body);
      } on SessionInvalidatedException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
        print('[ProjectFocus] attempt failed: $e');
      }
    }

    throw ProjectFocusException(
      lastMessage ?? 'Could not load project focus',
      statusCode: lastStatus,
    );
  }
}
