import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the current client/project should use the pre-redesign feature set.
enum ClientGeneration {
  /// Projects not created from Sales SOP.
  legacy,

  /// Projects created from Sales SOP (`created_from_sales_sop: true`).
  current,
}

/// Resolves old vs new client UI from
/// `GET /API/project_created_from_sales_sop/{id}`
/// or `GET /API/project_created_from_sales_sop?project_id=`.
///
/// `created_from_sales_sop: false` (or unknown) → older client view.
/// `created_from_sales_sop: true` → full current client experience.
class ClientGenerationService {
  ClientGenerationService._();
  static final ClientGenerationService instance = ClientGenerationService._();

  static const String baseUrl = 'https://office.buildahome.in';
  static const String endpointPath = '/API/project_created_from_sales_sop';

  static const String _prefGeneration = 'client_generation';
  static const String _prefProjectId = 'client_generation_project_id';

  final ValueNotifier<ClientGeneration> generation =
      ValueNotifier<ClientGeneration>(ClientGeneration.legacy);

  bool _hydrated = false;
  bool _hasPersistedGeneration = false;
  String? _hydratedProjectId;
  String? _refreshingProjectId;
  Future<void>? _refreshInFlight;

  bool get isLegacy => generation.value == ClientGeneration.legacy;

  /// Older project UI for Client login and for staff opening that project.
  bool get shouldUseLegacyProjectUi => isLegacy;

  /// Legacy feature gating for Client-role menus (coming-soon tiles, etc.).
  bool restrictsClientFeatures(String? role) {
    return (role ?? '').trim().toLowerCase() == 'client' && isLegacy;
  }

  /// Cache-first: hydrate prefs, paint immediately when a value exists for
  /// this project, then refresh in the background. Awaits the network only
  /// when there is no persisted generation for the current project.
  Future<void> ensureLoaded({String? projectId, bool force = false}) async {
    final pid = projectId?.trim();
    if (!_hydrated ||
        (pid != null &&
            pid.isNotEmpty &&
            _hydratedProjectId != null &&
            _hydratedProjectId != pid)) {
      await _hydrateFromPrefs();
    } else if (!_hydrated) {
      await _hydrateFromPrefs();
    }

    final hasCacheForProject = _hasPersistedGeneration &&
        (pid == null ||
            pid.isEmpty ||
            _hydratedProjectId == null ||
            _hydratedProjectId == pid);

    if (hasCacheForProject && !force) {
      unawaited(refresh(projectId: projectId));
      return;
    }
    await refresh(projectId: projectId);
  }

  Future<void> applyFromPayload(
    Map<String, dynamic>? payload, {
    String? projectId,
  }) async {
    final parsed = parseGeneration(payload);
    if (parsed == null) return;
    await _persist(parsed, projectId: projectId);
  }

  Future<void> refresh({
    String? projectId,
    String? userId,
    Map<String, dynamic>? extraPayload,
  }) async {
    if (extraPayload != null) {
      await applyFromPayload(extraPayload, projectId: projectId);
    }

    final prefs = await SharedPreferences.getInstance();
    final pid = (projectId ?? prefs.getString('project_id'))?.trim();

    if (_refreshInFlight != null && _refreshingProjectId == pid) {
      await _refreshInFlight;
      return;
    }

    final future = _refreshFromApi(projectId: pid);
    _refreshInFlight = future;
    _refreshingProjectId = pid;
    try {
      await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
        _refreshingProjectId = null;
      }
    }
  }

  void clearMemory() {
    generation.value = ClientGeneration.legacy;
    _hydrated = false;
    _hasPersistedGeneration = false;
    _hydratedProjectId = null;
  }

  Future<void> clear() async {
    clearMemory();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefGeneration);
      await prefs.remove(_prefProjectId);
    } catch (_) {}
  }

  static ClientGeneration? parseGeneration(dynamic source) {
    if (source is! Map) return null;
    final map = Map<String, dynamic>.from(source);

    final salesSopOrigin = _asBool(map['created_from_sales_sop']);
    if (salesSopOrigin != null) {
      return salesSopOrigin
          ? ClientGeneration.current
          : ClientGeneration.legacy;
    }

    ClientGeneration? fromBool(dynamic value, {required bool trueMeansLegacy}) {
      final parsed = _asBool(value);
      if (parsed == null) return null;
      if (trueMeansLegacy) {
        return parsed ? ClientGeneration.legacy : ClientGeneration.current;
      }
      return parsed ? ClientGeneration.current : ClientGeneration.legacy;
    }

    for (final key in ['is_new_client', 'is_new', 'new_client']) {
      final parsed = fromBool(map[key], trueMeansLegacy: false);
      if (parsed != null) return parsed;
    }
    for (final key in [
      'is_old_client',
      'is_legacy_client',
      'is_legacy',
      'is_old',
      'old_client',
    ]) {
      final parsed = fromBool(map[key], trueMeansLegacy: true);
      if (parsed != null) return parsed;
    }

    final nested = map['data'] ?? map['client'] ?? map['project'];
    if (nested is Map && !identical(nested, source)) {
      return parseGeneration(nested);
    }
    return null;
  }

  Future<void> _hydrateFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentProjectId = prefs.getString('project_id')?.trim();
      final storedProjectId = prefs.getString(_prefProjectId)?.trim();
      final stored = prefs.getString(_prefGeneration);

      // Cached generation only applies to the same project.
      if (currentProjectId != null &&
          currentProjectId.isNotEmpty &&
          storedProjectId == currentProjectId &&
          (stored == 'current' || stored == 'legacy')) {
        generation.value = stored == 'current'
            ? ClientGeneration.current
            : ClientGeneration.legacy;
        _hydratedProjectId = currentProjectId;
        _hasPersistedGeneration = true;
      } else {
        generation.value = ClientGeneration.legacy;
        _hydratedProjectId = currentProjectId;
        _hasPersistedGeneration = false;
      }
    } catch (_) {}
    _hydrated = true;
  }

  Future<void> _refreshFromApi({String? projectId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('api_token')?.trim();
      final pid = (projectId ?? prefs.getString('project_id'))?.trim();
      if (pid == null || pid.isEmpty) return;

      // Switching projects: don't keep the previous project's generation.
      if (_hydratedProjectId != pid &&
          prefs.getString(_prefProjectId) != pid) {
        generation.value = ClientGeneration.legacy;
      }

      final response = await _getOriginResponse(projectId: pid, token: token);
      if (response == null || response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final parsed = parseGeneration(decoded);
      if (parsed == null) return;

      await _persist(parsed, projectId: pid);
      await _cacheSalesSopFromPayload(decoded, pid);
    } catch (e) {
      debugPrint('[ClientGeneration] refresh failed: $e');
    }
  }

  Future<http.Response?> _getOriginResponse({
    required String projectId,
    String? token,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'X-Api-Token': token,
    };
    final query = <String, String>{
      if (token != null && token.isNotEmpty) 'api_token': token,
    };

    final encodedId = Uri.encodeComponent(projectId);
    final candidates = <Uri>[
      Uri.parse('$baseUrl$endpointPath/$encodedId').replace(
        queryParameters: query.isEmpty ? null : query,
      ),
      Uri.parse('$baseUrl$endpointPath').replace(
        queryParameters: {
          'project_id': projectId,
          ...query,
        },
      ),
      Uri.parse(
        '$baseUrl${endpointPath.replaceFirst('/API/', '/api/')}/$encodedId',
      ).replace(queryParameters: query.isEmpty ? null : query),
      Uri.parse(
        '$baseUrl${endpointPath.replaceFirst('/API/', '/api/')}',
      ).replace(
        queryParameters: {
          'project_id': projectId,
          ...query,
        },
      ),
    ];

    http.Response? last;
    for (final uri in candidates) {
      try {
        final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
        last = response;
        if (response.statusCode == 200) return response;
      } catch (e) {
        debugPrint('[ClientGeneration] $uri failed: $e');
      }
    }
    return last;
  }

  Future<void> _cacheSalesSopFromPayload(
    dynamic decoded,
    String projectId,
  ) async {
    if (decoded is! Map) return;
    final sopId = decoded['sales_sop_id']?.toString().trim();
    if (sopId == null || sopId.isEmpty || sopId.toLowerCase() == 'null') {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sales_sop_id', sopId);
      await prefs.setString('sales_sop_erp_project_id', projectId);
    } catch (_) {}
  }

  Future<void> _persist(
    ClientGeneration next, {
    String? projectId,
  }) async {
    if (generation.value != next) {
      generation.value = next;
    }
    _hydrated = true;
    _hasPersistedGeneration = true;
    if (projectId != null && projectId.trim().isNotEmpty) {
      _hydratedProjectId = projectId.trim();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefGeneration,
        next == ClientGeneration.current ? 'current' : 'legacy',
      );
      if (projectId != null && projectId.trim().isNotEmpty) {
        await prefs.setString(_prefProjectId, projectId.trim());
      }
    } catch (_) {}
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no' ||
          normalized == 'null') {
        return false;
      }
    }
    return null;
  }
}
