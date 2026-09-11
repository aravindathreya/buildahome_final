import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_http.dart';
import 'mobile_quick_actions.dart';
import 'session_manager.dart';

/// Fetches `GET /API/mobile/actions` once per surface, caches in
/// SharedPreferences, and exposes a stale-while-revalidate snapshot.
///
/// Cache:
/// * Created after a successful API parse (including `configured: false`
///   and intentional empty lists).
/// * Keyed by user id + role + surface so accounts cannot leak.
/// * Remains valid until logout / account switch; dashboards always render
///   the cached snapshot immediately, then refresh in the background.
/// * Pull-to-refresh and `force: true` bypass the 20s network debounce.
class MobileQuickActionsService {
  MobileQuickActionsService._();
  static final MobileQuickActionsService instance =
      MobileQuickActionsService._();
  factory MobileQuickActionsService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];
  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration minRefreshInterval = Duration(seconds: 20);

  /// Bumped when a surface snapshot changes so dashboards can `setState`.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String? _userId;
  String? _role;
  final Map<MobileQuickActionSurface, MobileQuickActionsSnapshot> _memory = {};
  final Map<MobileQuickActionSurface, Future<void>> _inFlight = {};
  final Map<MobileQuickActionSurface, DateTime> _lastNetworkAt = {};

  MobileQuickActionsSnapshot? snapshot(MobileQuickActionSurface surface) {
    return _memory[surface];
  }

  bool isBackendConfigured(MobileQuickActionSurface surface) {
    return _memory[surface]?.configured == true;
  }

  /// Read cache (if needed) then refresh from the network without blocking UI.
  Future<void> ensureSurface(
    MobileQuickActionSurface surface, {
    bool force = false,
  }) async {
    final existing = _inFlight[surface];
    if (existing != null && !force) {
      await existing;
      return;
    }

    final future = _ensureSurfaceInternal(surface, force: force);
    _inFlight[surface] = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight[surface], future)) {
        _inFlight.remove(surface);
      }
    }
  }

  /// Instant in-memory wipe used on logout / account switch.
  /// SharedPreferences entries are removed by `AppLogout.clearLocalSession`.
  void clearMemory() {
    _memory.clear();
    _inFlight.clear();
    _lastNetworkAt.clear();
    _userId = null;
    _role = null;
    revision.value++;
  }

  Future<void> _ensureSurfaceInternal(
    MobileQuickActionSurface surface, {
    required bool force,
  }) async {
    await _bindIdentity();
    final hydrated = await _hydrateFromPrefs(surface);
    if (hydrated) _emit();

    final last = _lastNetworkAt[surface];
    final recentlyFetched = last != null &&
        DateTime.now().difference(last) < minRefreshInterval;
    if (!force && recentlyFetched && _memory.containsKey(surface)) {
      return;
    }

    await _refreshFromNetwork(surface);
  }

  Future<void> _bindIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();
    final role = (prefs.getString('role') ?? '').trim();
    if (userId != (_userId ?? '') || role != (_role ?? '')) {
      _memory.clear();
      _lastNetworkAt.clear();
      _userId = userId;
      _role = role;
    }
  }

  Future<bool> _hydrateFromPrefs(MobileQuickActionSurface surface) async {
    if (_memory.containsKey(surface)) return false;
    final userId = _userId ?? '';
    if (userId.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        mobileQuickActionsCacheKey(
          userId: userId,
          role: _role ?? '',
          surface: surface,
        ),
      );
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final snapshot = MobileQuickActionsSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
        expectedSurface: surface,
      );
      if (snapshot == null) return false;
      if ((snapshot.userId ?? '').isNotEmpty && snapshot.userId != userId) {
        return false;
      }
      _memory[surface] = snapshot;
      return true;
    } catch (e) {
      print('[MobileQA] cache read failed for ${surface.apiName}: $e');
      return false;
    }
  }

  Future<void> _refreshFromNetwork(MobileQuickActionSurface surface) async {
    try {
      final snapshot = await _fetchFromApi(surface);
      _lastNetworkAt[surface] = DateTime.now();
      if (snapshot == null) {
        print(
          '[MobileQA] ${surface.apiName} fetch failed; keeping '
          '${_memory.containsKey(surface) ? 'cache' : 'hardcoded fallback'}',
        );
        return;
      }
      final changed = _storeMemory(snapshot);
      await _persist(snapshot);
      if (changed) _emit();
      print(
        '[MobileQA] ${surface.apiName} configured=${snapshot.configured} '
        'keys=${snapshot.actionKeys}',
      );
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      _lastNetworkAt[surface] = DateTime.now();
      print('[MobileQA] ${surface.apiName} error: $e');
    }
  }

  Future<MobileQuickActionsSnapshot?> _fetchFromApi(
    MobileQuickActionSurface surface,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('api_token') ?? '').trim();
    if (token.isEmpty || token.toLowerCase() == 'null') return null;
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();

    final query = <String, String>{
      'surface': surface.apiName,
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
        final uri = Uri.parse('$base/$prefix/mobile/actions')
            .replace(queryParameters: query);
        try {
          final response = await ApiHttp.get(uri, headers: headers)
              .timeout(requestTimeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          final decoded = jsonDecode(response.body);
          final snapshot = parseMobileQuickActionsPayload(
            decoded,
            surface: surface,
          );
          if (snapshot == null) {
            lastError = 'unexpected payload';
            continue;
          }
          return MobileQuickActionsSnapshot(
            surface: surface,
            configured: snapshot.configured,
            actionKeys: snapshot.actionKeys,
            role: snapshot.role ?? _role,
            userId: userId,
            cachedAt: DateTime.now(),
          );
        } on SessionInvalidatedException {
          rethrow;
        } catch (e) {
          lastError = e;
        }
      }
    }
    print('[MobileQA] ${surface.apiName} lastError=$lastError');
    return null;
  }

  bool _storeMemory(MobileQuickActionsSnapshot snapshot) {
    final previous = _memory[snapshot.surface];
    _memory[snapshot.surface] = snapshot;
    if (previous == null) return true;
    if (previous.configured != snapshot.configured) return true;
    if (previous.actionKeys.length != snapshot.actionKeys.length) return true;
    for (var i = 0; i < snapshot.actionKeys.length; i++) {
      if (previous.actionKeys[i] != snapshot.actionKeys[i]) return true;
    }
    return false;
  }

  Future<void> _persist(MobileQuickActionsSnapshot snapshot) async {
    final userId = (snapshot.userId ?? _userId ?? '').trim();
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        mobileQuickActionsCacheKey(
          userId: userId,
          role: snapshot.role ?? _role ?? '',
          surface: snapshot.surface,
        ),
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      print('[MobileQA] cache write failed: $e');
    }
  }

  void _emit() {
    revision.value++;
  }
}
