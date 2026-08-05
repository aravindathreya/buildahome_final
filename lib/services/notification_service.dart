import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Caches notifications locally and syncs only the delta when possible.
///
/// The list API may return a full snapshot or (if supported) items newer than
/// [since]. Either way we merge into the local cache so the UI can render
/// instantly from cache and the unread badge stays in sync.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _baseUrl = 'https://office.buildahome.in';
  static const String _cacheKeyPrefix = 'notifications_cache_v1_';
  static const String _metaKeyPrefix = 'notifications_meta_v1_';
  static const Duration _minSyncInterval = Duration(seconds: 20);

  final ValueNotifier<List<Map<String, dynamic>>> notificationsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);

  String? _userId;
  DateTime? _lastSyncedAt;
  String? _newestTimestamp;
  Future<void>? _inFlightSync;

  List<Map<String, dynamic>> get notifications =>
      List<Map<String, dynamic>>.unmodifiable(notificationsNotifier.value);

  int get unreadCount => unreadCountNotifier.value;

  static String fingerprint(Map<String, dynamic> notification) {
    final id = notification['id']?.toString().trim();
    if (id != null && id.isNotEmpty && id != 'null') {
      return 'id:$id';
    }
    final title = (notification['title'] ?? '').toString().trim();
    final body = (notification['body'] ?? '').toString().trim();
    final timestamp = (notification['timestamp'] ??
            notification['created_at'] ??
            notification['createdAt'] ??
            notification['date'] ??
            notification['datetime'] ??
            notification['time'] ??
            '')
        .toString()
        .trim();
    return 't:$title|b:$body|ts:$timestamp';
  }

  Future<void> ensureHydrated() async {
    final userId = await _resolveUserId();
    if (userId == null) return;
    if (_userId == userId && notificationsNotifier.value.isNotEmpty) return;
    await _loadCacheForUser(userId);
  }

  /// Loads cache immediately (if needed) then fetches/merges remote updates.
  Future<void> sync({bool force = false, bool markRead = false}) async {
    if (_inFlightSync != null) {
      await _inFlightSync;
      if (!force && !markRead) return;
    }

    final future = _syncInternal(force: force, markRead: markRead);
    _inFlightSync = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightSync, future)) {
        _inFlightSync = null;
      }
    }
  }

  Future<void> markAllAsRead() async {
    await sync(force: true, markRead: true);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userId != null) {
      await prefs.remove(_cacheKey(_userId!));
      await prefs.remove(_metaKey(_userId!));
    }
    _userId = null;
    _lastSyncedAt = null;
    _newestTimestamp = null;
    notificationsNotifier.value = const [];
    unreadCountNotifier.value = 0;
    isSyncingNotifier.value = false;
  }

  Future<void> _syncInternal({
    required bool force,
    required bool markRead,
  }) async {
    final userId = await _resolveUserId();
    if (userId == null) return;

    if (_userId != userId ||
        (notificationsNotifier.value.isEmpty && _lastSyncedAt == null)) {
      await _loadCacheForUser(userId);
    }

    if (!force &&
        !markRead &&
        _lastSyncedAt != null &&
        DateTime.now().difference(_lastSyncedAt!) < _minSyncInterval) {
      return;
    }

    isSyncingNotifier.value = true;
    try {
      final uri = Uri.parse('$_baseUrl/API/get_notifications').replace(
        queryParameters: {
          'recipient': userId,
          if (_newestTimestamp != null && _newestTimestamp!.isNotEmpty)
            'since': _newestTimestamp!,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final remote = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();

          final merged = _mergeRemote(notificationsNotifier.value, remote);
          _applyLocalState(merged, userId: userId, syncedAt: DateTime.now());
          await _persist(userId, merged);
        }
      }
    } catch (_) {
      // Keep cached data on network/parse failures.
    } finally {
      if (markRead) {
        await _markRemoteAndLocalRead(userId);
      }
      isSyncingNotifier.value = false;
    }
  }

  Future<void> _markRemoteAndLocalRead(String userId) async {
    try {
      await http
          .get(Uri.parse(
              '$_baseUrl/API/mark_notifications_as_read?user_id=$userId'))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}

    final marked = notificationsNotifier.value
        .map((n) => Map<String, dynamic>.from(n)..['unread'] = 0)
        .toList(growable: false);
    _applyLocalState(marked, userId: userId, syncedAt: _lastSyncedAt);
    await _persist(userId, marked);
  }

  List<Map<String, dynamic>> _mergeRemote(
    List<Map<String, dynamic>> cached,
    List<Map<String, dynamic>> remote,
  ) {
    if (remote.isEmpty) return cached;

    final cachedByKey = <String, Map<String, dynamic>>{
      for (final item in cached) fingerprint(item): item,
    };
    final remoteByKey = <String, Map<String, dynamic>>{
      for (final item in remote) fingerprint(item): item,
    };

    final knownOverlap =
        remoteByKey.keys.any((key) => cachedByKey.containsKey(key));
    final treatAsFullSnapshot =
        cached.isEmpty || knownOverlap || remote.length >= cached.length;

    if (treatAsFullSnapshot) {
      // Prefer remote order/unread flags; keep any cached-only items at the end
      // in case the API ever returns a partial window.
      final merged = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final item in remote) {
        final key = fingerprint(item);
        seen.add(key);
        merged.add(Map<String, dynamic>.from(item));
      }
      for (final item in cached) {
        final key = fingerprint(item);
        if (seen.add(key)) {
          merged.add(Map<String, dynamic>.from(item));
        }
      }
      return merged;
    }

    // True delta response: prepend new items, keep existing cache.
    final merged = <Map<String, dynamic>>[
      for (final item in remote) Map<String, dynamic>.from(item),
      ...cached.map((item) => Map<String, dynamic>.from(item)),
    ];
    return merged;
  }

  Future<void> _loadCacheForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(userId));
    final metaRaw = prefs.getString(_metaKey(userId));

    List<Map<String, dynamic>> cached = const [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          cached = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
        }
      } catch (_) {
        cached = const [];
      }
    }

    DateTime? syncedAt;
    String? newest;
    if (metaRaw != null && metaRaw.isNotEmpty) {
      try {
        final meta = jsonDecode(metaRaw);
        if (meta is Map) {
          final synced = meta['lastSyncedAt']?.toString();
          if (synced != null && synced.isNotEmpty) {
            syncedAt = DateTime.tryParse(synced);
          }
          newest = meta['newestTimestamp']?.toString();
        }
      } catch (_) {}
    }

    _applyLocalState(cached, userId: userId, syncedAt: syncedAt);
    _newestTimestamp = (newest != null && newest.isNotEmpty)
        ? newest
        : _newestTimestampFrom(cached);
  }

  Future<void> _persist(
    String userId,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(userId), jsonEncode(items));
    await prefs.setString(
      _metaKey(userId),
      jsonEncode({
        'lastSyncedAt': _lastSyncedAt?.toIso8601String(),
        'newestTimestamp': _newestTimestamp,
      }),
    );
  }

  void _applyLocalState(
    List<Map<String, dynamic>> items, {
    required String userId,
    DateTime? syncedAt,
  }) {
    _userId = userId;
    _lastSyncedAt = syncedAt;
    _newestTimestamp = _newestTimestampFrom(items);
    notificationsNotifier.value = List<Map<String, dynamic>>.unmodifiable(
      items.map((item) => Map<String, dynamic>.from(item)),
    );
    unreadCountNotifier.value = items.where(_isUnread).length;
  }

  String? _newestTimestampFrom(List<Map<String, dynamic>> items) {
    // API samples return oldest-first, so the last timestamped item is newest.
    for (var i = items.length - 1; i >= 0; i--) {
      final ts = (items[i]['timestamp'] ??
              items[i]['created_at'] ??
              items[i]['createdAt'] ??
              items[i]['date'] ??
              items[i]['datetime'] ??
              items[i]['time'])
          ?.toString()
          .trim();
      if (ts != null && ts.isNotEmpty) return ts;
    }
    return null;
  }

  bool _isUnread(Map<String, dynamic> notification) {
    final value = notification['unread'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final asString = value?.toString().trim().toLowerCase();
    return asString == '1' || asString == 'true' || asString == 'yes';
  }

  Future<String?> _resolveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.get('user_id') ?? prefs.get('userId');
    if (userId == null) return null;
    final asString = userId.toString().trim();
    return asString.isEmpty ? null : asString;
  }

  String _cacheKey(String userId) => '$_cacheKeyPrefix$userId';
  String _metaKey(String userId) => '$_metaKeyPrefix$userId';
}
