import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_http.dart';
import 'mobile_more_menu.dart';
import 'session_manager.dart';

/// Fetches `GET /API/mobile/more-menu` once per surface, caches in
/// SharedPreferences, and exposes a stale-while-revalidate snapshot.
///
/// Cache:
/// * Created after a successful API parse (including `configured: false`
///   and intentional empty lists).
/// * Keyed by user id + role + surface so accounts cannot leak.
/// * Remains valid until logout / account switch; the drawer always renders
///   the cached snapshot immediately, then refreshes in the background.
/// * Never blocks drawer open on the network.
class MobileMoreMenuService {
  MobileMoreMenuService._();
  static final MobileMoreMenuService instance = MobileMoreMenuService._();
  factory MobileMoreMenuService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];
  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration minRefreshInterval = Duration(seconds: 20);

  /// Bumped when a surface snapshot changes so `NavMenuWidget` can `setState`.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String? _userId;
  String? _role;
  final Map<MobileMoreMenuSurface, MobileMoreMenuSnapshot> _memory = {};
  final Map<MobileMoreMenuSurface, Future<void>> _inFlight = {};
  final Map<MobileMoreMenuSurface, DateTime> _lastNetworkAt = {};

  MobileMoreMenuSnapshot? snapshot(MobileMoreMenuSurface surface) {
    return _memory[surface];
  }

  bool isBackendConfigured(MobileMoreMenuSurface surface) {
    return _memory[surface]?.configured == true;
  }

  /// Read cache (if needed) then refresh from the network without blocking UI.
  Future<void> ensureSurface(
    MobileMoreMenuSurface surface, {
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
    MobileMoreMenuSurface surface, {
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

  Future<bool> _hydrateFromPrefs(MobileMoreMenuSurface surface) async {
    if (_memory.containsKey(surface)) return false;
    final userId = _userId ?? '';
    if (userId.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        mobileMoreMenuCacheKey(
          userId: userId,
          role: _role ?? '',
          surface: surface,
        ),
      );
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final snapshot = MobileMoreMenuSnapshot.fromJson(
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
      print('[MobileMore] cache read failed for ${surface.apiName}: $e');
      return false;
    }
  }

  Future<void> _refreshFromNetwork(MobileMoreMenuSurface surface) async {
    try {
      final snapshot = await _fetchFromApi(surface);
      _lastNetworkAt[surface] = DateTime.now();
      if (snapshot == null) {
        print(
          '[MobileMore] ${surface.apiName} fetch failed; keeping '
          '${_memory.containsKey(surface) ? 'cache' : 'hardcoded fallback'}',
        );
        return;
      }
      final changed = _storeMemory(snapshot);
      await _persist(snapshot);
      if (changed) _emit();
      print(
        '[MobileMore] ${surface.apiName} configured=${snapshot.configured} '
        'keys=${snapshot.actionKeys}',
      );
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      _lastNetworkAt[surface] = DateTime.now();
      print('[MobileMore] ${surface.apiName} error: $e');
    }
  }

  Future<MobileMoreMenuSnapshot?> _fetchFromApi(
    MobileMoreMenuSurface surface,
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
        final uri = Uri.parse('$base/$prefix/mobile/more-menu')
            .replace(queryParameters: query);
        try {
          final response = await ApiHttp.get(uri, headers: headers)
              .timeout(requestTimeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          final decoded = jsonDecode(response.body);
          final snapshot = parseMobileMoreMenuPayload(
            decoded,
            surface: surface,
          );
          if (snapshot == null) {
            lastError = 'unexpected payload';
            continue;
          }
          return MobileMoreMenuSnapshot(
            surface: surface,
            configured: snapshot.configured,
            actionKeys: snapshot.actionKeys,
            role: _role,
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
    print('[MobileMore] ${surface.apiName} lastError=$lastError');
    return null;
  }

  bool _storeMemory(MobileMoreMenuSnapshot snapshot) {
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

  Future<void> _persist(MobileMoreMenuSnapshot snapshot) async {
    final userId = (snapshot.userId ?? _userId ?? '').trim();
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        mobileMoreMenuCacheKey(
          userId: userId,
          role: _role ?? '',
          surface: snapshot.surface,
        ),
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      print('[MobileMore] cache write failed: $e');
    }
  }

  void _emit() {
    revision.value++;
  }
}
