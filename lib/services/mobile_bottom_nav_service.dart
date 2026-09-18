import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_http.dart';
import 'mobile_bottom_nav.dart';
import 'session_manager.dart';

/// Fetches `GET /API/mobile/bottom-nav` once per surface, caches in
/// SharedPreferences, and exposes a stale-while-revalidate snapshot.
///
/// Cache:
/// * Created after a successful API parse (including `configured: false`).
/// * Keyed by user id + role + surface so accounts cannot leak.
/// * Remains valid until logout / account switch; dashboards render the
///   cached snapshot immediately, then refresh in the background.
class MobileBottomNavService {
  MobileBottomNavService._();
  static final MobileBottomNavService instance = MobileBottomNavService._();
  factory MobileBottomNavService() => instance;

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
  final Map<MobileBottomNavSurface, MobileBottomNavSnapshot> _memory = {};
  final Map<MobileBottomNavSurface, Future<void>> _inFlight = {};
  final Map<MobileBottomNavSurface, DateTime> _lastNetworkAt = {};

  MobileBottomNavSnapshot? snapshot(MobileBottomNavSurface surface) {
    return _memory[surface];
  }

  bool isBackendConfigured(MobileBottomNavSurface surface) {
    return _memory[surface]?.configured == true;
  }

  /// Read cache (if needed) then refresh from the network without blocking UI.
  Future<void> ensureSurface(
    MobileBottomNavSurface surface, {
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
  void clearMemory() {
    _memory.clear();
    _inFlight.clear();
    _lastNetworkAt.clear();
    _userId = null;
    _role = null;
    revision.value++;
  }

  Future<void> _ensureSurfaceInternal(
    MobileBottomNavSurface surface, {
    required bool force,
  }) async {
    await _bindIdentity();
    final hydrated = await _hydrateFromPrefs(surface);
    if (hydrated) _emit();

    final cached = _memory[surface];
    // Stale "not configured" cache must not block a live web publish.
    final mustRefreshUnconfigured =
        cached != null && cached.configured != true;

    final last = _lastNetworkAt[surface];
    final recentlyFetched = last != null &&
        DateTime.now().difference(last) < minRefreshInterval;
    if (!force &&
        !mustRefreshUnconfigured &&
        recentlyFetched &&
        _memory.containsKey(surface)) {
      print(
        '[MobileBottomNav] ${surface.apiName} skip network '
        '(fresh cache configured=${cached?.configured})',
      );
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

  Future<bool> _hydrateFromPrefs(MobileBottomNavSurface surface) async {
    if (_memory.containsKey(surface)) return false;
    final userId = _userId ?? '';
    if (userId.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        mobileBottomNavCacheKey(
          userId: userId,
          role: _role ?? '',
          surface: surface,
        ),
      );
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final snapshot = MobileBottomNavSnapshot.fromJson(
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
      print('[MobileBottomNav] cache read failed for ${surface.apiName}: $e');
      return false;
    }
  }

  Future<void> _refreshFromNetwork(MobileBottomNavSurface surface) async {
    try {
      final snapshot = await _fetchFromApi(surface);
      if (snapshot == null) {
        // Do NOT stamp _lastNetworkAt on failure — otherwise a DNS blip
        // locks the UI on hardcoded fallback for 20s.
        print(
          '[MobileBottomNav] ${surface.apiName} fetch failed; keeping '
          '${_memory.containsKey(surface) ? 'cache' : 'hardcoded fallback'}',
        );
        return;
      }
      _lastNetworkAt[surface] = DateTime.now();
      final changed = _storeMemory(snapshot);
      await _persist(snapshot);
      // Always notify so dashboards rebuild even when the payload matches a
      // prior hydrate (first paint may have used the hardcoded fallback).
      _emit();
      print(
        '[MobileBottomNav] ${surface.apiName} configured=${snapshot.configured} '
        'keys=${snapshot.actionKeys} changed=$changed',
      );
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      print('[MobileBottomNav] ${surface.apiName} error: $e');
    }
  }

  Future<MobileBottomNavSnapshot?> _fetchFromApi(
    MobileBottomNavSurface surface,
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
        for (final path in const ['mobile/bottom-nav', 'mobile/bottom_nav']) {
          final uri = Uri.parse('$base/$prefix/$path')
              .replace(queryParameters: query);
          try {
            final response = await ApiHttp.get(uri, headers: headers)
                .timeout(requestTimeout);
            if (response.statusCode < 200 || response.statusCode >= 300) {
              lastError = 'HTTP ${response.statusCode}';
              continue;
            }
            final decoded = jsonDecode(response.body);
            final snapshot = parseMobileBottomNavPayload(
              decoded,
              surface: surface,
            );
            if (snapshot == null) {
              lastError = 'unexpected payload';
              continue;
            }
            return MobileBottomNavSnapshot(
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
    }
    print('[MobileBottomNav] ${surface.apiName} lastError=$lastError');
    return null;
  }

  bool _storeMemory(MobileBottomNavSnapshot snapshot) {
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

  Future<void> _persist(MobileBottomNavSnapshot snapshot) async {
    final userId = (snapshot.userId ?? _userId ?? '').trim();
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cache key must use the same role as hydrate (_role from prefs),
      // not the API echo — otherwise reads miss and the bar stays fallback.
      await prefs.setString(
        mobileBottomNavCacheKey(
          userId: userId,
          role: _role ?? '',
          surface: snapshot.surface,
        ),
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      print('[MobileBottomNav] cache write failed: $e');
    }
  }

  void _emit() {
    revision.value++;
  }
}
