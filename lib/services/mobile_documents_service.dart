import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_document.dart';
import 'api_http.dart';
import 'mobile_documents.dart';
import 'session_manager.dart';

/// Fetches `GET /API/mobile/documents?project_id=` once per project, caches
/// in SharedPreferences, and exposes a stale-while-revalidate snapshot.
///
/// Cache:
/// * Keyed by user id + role + project_id so accounts and projects cannot leak.
/// * Shown immediately when valid, then refreshed in the background.
/// * On API failure, the current project's cache is kept. Another project's
///   documents are never displayed.
class MobileDocumentsService {
  MobileDocumentsService._();
  static final MobileDocumentsService instance = MobileDocumentsService._();
  factory MobileDocumentsService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];
  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration minRefreshInterval = Duration(seconds: 20);

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final MobileDocumentsInFlight inFlight = MobileDocumentsInFlight();

  String? _userId;
  String? _role;
  String? _projectId;
  MobileDocumentsSnapshot? _memory;
  DateTime? _lastNetworkAt;

  MobileDocumentsSnapshot? snapshotFor({String? projectId}) {
    final snap = _memory;
    if (snap == null) return null;
    final expected = (projectId ?? _projectId ?? '').trim();
    if (expected.isNotEmpty && snap.projectId != expected) return null;
    return snap;
  }

  bool isBackendConfigured({String? projectId}) {
    return snapshotFor(projectId: projectId)?.configured == true;
  }

  /// Read cache (if needed) then refresh from the network without inventing
  /// another project's tree.
  Future<void> ensureLibrary({
    String? projectId,
    bool force = false,
  }) async {
    await _bindIdentity(projectId: projectId);
    final resolved = (_projectId ?? '').trim();
    if (resolved.isEmpty) return;

    await inFlight.run(resolved, () async {
      await _ensureLibraryInternal(projectId: resolved, force: force);
    });
  }

  /// Instant in-memory wipe used on logout / account / project switch.
  void clearMemory() {
    _memory = null;
    inFlight.clear();
    _lastNetworkAt = null;
    _userId = null;
    _role = null;
    _projectId = null;
    revision.value++;
  }

  /// Drop the in-memory tree when staff select a different project.
  void onProjectChanged(String? projectId) {
    final next = (projectId ?? '').trim();
    if (next.isEmpty || next == (_projectId ?? '')) return;
    _memory = null;
    _lastNetworkAt = null;
    _projectId = next;
    revision.value++;
  }

  Future<void> _ensureLibraryInternal({
    required String projectId,
    required bool force,
  }) async {
    await _bindIdentity(projectId: projectId);
    if ((_projectId ?? '') != projectId) return;

    final hydrated = await _hydrateFromPrefs(projectId);
    if (hydrated) _emit();

    final last = _lastNetworkAt;
    final recentlyFetched = last != null &&
        DateTime.now().difference(last) < minRefreshInterval &&
        _memory?.projectId == projectId;
    if (!force && recentlyFetched && _memory != null) {
      return;
    }

    await _refreshFromNetwork(projectId);
  }

  Future<void> _bindIdentity({String? projectId}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();
    final role = (prefs.getString('role') ?? '').trim();
    final resolvedProject = (projectId ??
            prefs.getString('project_id') ??
            '')
        .trim();

    final identityChanged =
        userId != (_userId ?? '') || role != (_role ?? '');
    final projectChanged = resolvedProject != (_projectId ?? '');
    if (identityChanged || projectChanged) {
      if (_memory != null &&
          (identityChanged ||
              (_memory!.projectId != resolvedProject))) {
        _memory = null;
      }
      _lastNetworkAt = null;
      _userId = userId;
      _role = role;
      _projectId = resolvedProject;
    }
  }

  Future<bool> _hydrateFromPrefs(String projectId) async {
    if (_memory != null && _memory!.projectId == projectId) return false;
    final userId = _userId ?? '';
    if (userId.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        mobileDocumentsCacheKey(
          userId: userId,
          role: _role ?? '',
          projectId: projectId,
        ),
      );
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final snapshot = MobileDocumentsSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
        expectedProjectId: projectId,
        expectedUserId: userId,
      );
      if (snapshot == null) return false;
      if (snapshot.projectId != projectId) return false;
      _memory = snapshot;
      return true;
    } catch (e) {
      print('[MobileDocs] cache read failed for project=$projectId: $e');
      return false;
    }
  }

  Future<void> _refreshFromNetwork(String projectId) async {
    try {
      final snapshot = await _fetchFromApi(projectId);
      _lastNetworkAt = DateTime.now();
      if ((_projectId ?? '') != projectId) return;
      if (snapshot == null) {
        print(
          '[MobileDocs] project=$projectId fetch failed; keeping '
          '${_memory?.projectId == projectId ? 'cache' : 'legacy fallback'}',
        );
        return;
      }
      if (snapshot.projectId != projectId) {
        print('[MobileDocs] ignoring snapshot for ${snapshot.projectId}');
        return;
      }
      final changed = _storeMemory(snapshot);
      await _persist(snapshot);
      if (changed) _emit();
      print(
        '[MobileDocs] project=$projectId configured=${snapshot.configured} '
        'categories=${snapshot.library.libraryCategories.length}',
      );
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      _lastNetworkAt = DateTime.now();
      print('[MobileDocs] project=$projectId error: $e');
    }
  }

  Future<MobileDocumentsSnapshot?> _fetchFromApi(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('api_token') ?? '').trim();
    if (token.isEmpty || token.toLowerCase() == 'null') return null;
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();

    final query = <String, String>{
      'project_id': projectId,
      'api_token': token,
      if (userId.isNotEmpty) 'user_id': userId,
    };
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };

    Object? lastError;
    for (final base in baseUrls) {
      for (final prefix in const ['API', 'api']) {
        final uri = Uri.parse('$base/$prefix/mobile/documents')
            .replace(queryParameters: query);
        try {
          final response = await ApiHttp.get(uri, headers: headers)
              .timeout(requestTimeout);
          if (response.statusCode == 401 || response.statusCode == 403) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          final decoded = jsonDecode(response.body);
          final snapshot = parseMobileDocumentsPayload(
            decoded,
            expectedProjectId: projectId,
          );
          if (snapshot == null) {
            lastError = 'unexpected payload';
            continue;
          }
          return MobileDocumentsSnapshot(
            configured: snapshot.configured,
            projectId: projectId,
            library: snapshot.library,
            role: snapshot.role ?? _role,
            userId: userId,
            cachedAt: DateTime.now(),
            payload: snapshot.payload,
          );
        } on SessionInvalidatedException {
          rethrow;
        } catch (e) {
          lastError = e;
        }
      }
    }
    print('[MobileDocs] project=$projectId lastError=$lastError');
    return null;
  }

  bool _storeMemory(MobileDocumentsSnapshot snapshot) {
    if ((_projectId ?? '') != snapshot.projectId) return false;
    final previous = _memory;
    _memory = snapshot;
    if (previous == null) return true;
    if (previous.projectId != snapshot.projectId) return true;
    if (previous.configured != snapshot.configured) return true;
    return !_librariesEqual(previous.library, snapshot.library);
  }

  Future<void> _persist(MobileDocumentsSnapshot snapshot) async {
    final userId = (snapshot.userId ?? _userId ?? '').trim();
    if (userId.isEmpty) return;
    if (snapshot.projectId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        mobileDocumentsCacheKey(
          userId: userId,
          role: snapshot.role ?? _role ?? '',
          projectId: snapshot.projectId,
        ),
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      print('[MobileDocs] cache write failed: $e');
    }
  }

  void _emit() {
    revision.value++;
  }
}

bool _librariesEqual(WorkflowDocumentLibrary a, WorkflowDocumentLibrary b) {
  if (a.libraryCategories.length != b.libraryCategories.length) return false;
  for (var i = 0; i < a.libraryCategories.length; i++) {
    final ca = a.libraryCategories[i];
    final cb = b.libraryCategories[i];
    if (ca.id != cb.id || ca.label != cb.label) return false;
    if (ca.sections.length != cb.sections.length) return false;
    for (var s = 0; s < ca.sections.length; s++) {
      if (ca.sections[s].id != cb.sections[s].id) return false;
      if (ca.sections[s].documents.length != cb.sections[s].documents.length) {
        return false;
      }
    }
  }
  return true;
}
