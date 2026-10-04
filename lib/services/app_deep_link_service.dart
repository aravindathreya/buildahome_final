import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../UploadPaymentProofScreen.dart';
import '../app_navigator.dart';

/// Handles `buildahome://open…` / `/app/open…` links and routes into native screens.
///
/// Upload proof examples:
/// - buildahome://open?native_screen=payment_proof
/// - buildahome://open?native_screen=upload_proof
/// - buildahome://open/payment_proof
/// - https://office.buildahome.in/app/open?native_screen=payment_proof
///   (HTTPS works only if the web bridge forwards the query string into the scheme)
class AppDeepLinkService {
  AppDeepLinkService._();
  static final AppDeepLinkService instance = AppDeepLinkService._();

  static const String _pendingPrefsKey = 'pending_deep_link_screen';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _pendingScreen;
  bool _ready = false;
  bool _navigating = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleUri(initial);
      }
    } catch (e) {
      print('[AppDeepLink] getInitialLink failed: $e');
    }

    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        unawaited(_handleUri(uri));
      },
      onError: (Object e) {
        print('[AppDeepLink] uriLinkStream error: $e');
      },
    );

    // Restore a pending target from a previous cold-start / pre-login open.
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_pendingPrefsKey)?.trim();
      if (stored != null && stored.isNotEmpty) {
        _pendingScreen ??= stored;
      }
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  /// Call once the user has reached Home / AdminDashboard after auth.
  Future<void> onAppReady() async {
    _ready = true;
    await flushPending();
  }

  /// Call on logout so links wait for the next login.
  void onLoggedOut() {
    _ready = false;
  }

  Future<void> flushPending() async {
    final screen = _pendingScreen;
    if (screen == null || screen.isEmpty) return;
    await _openScreen(screen);
  }

  Future<void> _handleUri(Uri uri) async {
    final screen = resolveScreen(uri);
    if (screen == null) return;

    if (_ready) {
      await _openScreen(screen);
    } else {
      _pendingScreen = screen;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_pendingPrefsKey, screen);
      } catch (_) {}
    }
  }

  /// Public for tests / callers that already have a URI string.
  static String? resolveScreen(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    final isCustomOpen = scheme == 'buildahome' &&
        (host == 'open' || path.contains('open'));
    final isHttpsOpen = (scheme == 'http' || scheme == 'https') &&
        host.contains('buildahome.in') &&
        path.contains('/app/open');

    if (!isCustomOpen && !isHttpsOpen) return null;

    for (final key in const [
      'native_screen',
      'open_tab',
      'screen',
      'page',
      'route',
    ]) {
      final value = uri.queryParameters[key]?.trim().toLowerCase() ?? '';
      final mapped = _mapScreenToken(value);
      if (mapped != null) return mapped;
    }

    // Path segments: buildahome://open/payment_proof or …/app/open/upload_proof
    final segments = uri.pathSegments
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty && s != 'app' && s != 'open')
        .toList();
    for (final segment in segments) {
      final mapped = _mapScreenToken(segment);
      if (mapped != null) return mapped;
    }

    return null;
  }

  static String? _mapScreenToken(String raw) {
    final value = raw.replaceAll('-', '_').replaceAll(' ', '_');
    if (value.isEmpty) return null;
    if (value == 'payment_proof' ||
        value == 'upload_proof' ||
        value == 'upload_payment_proof' ||
        value == 'uploadproof') {
      return 'payment_proof';
    }
    return null;
  }

  Future<void> _openScreen(String screen) async {
    if (_navigating) return;
    _navigating = true;
    try {
      if (screen != 'payment_proof') return;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('api_token')?.trim() ?? '';
      if (token.isEmpty) {
        _pendingScreen = screen;
        await prefs.setString(_pendingPrefsKey, screen);
        return;
      }

      // Upload proof is a client portal screen.
      final role = (prefs.getString('role') ?? '').trim().toLowerCase();
      if (role.isNotEmpty && role != 'client') {
        _pendingScreen = null;
        await prefs.remove(_pendingPrefsKey);
        return;
      }

      final nav = globalNavigatorKey.currentState;
      if (nav == null || !_ready) {
        _pendingScreen = screen;
        await prefs.setString(_pendingPrefsKey, screen);
        return;
      }

      _pendingScreen = null;
      await prefs.remove(_pendingPrefsKey);

      // Let the current route finish painting (e.g. right after login).
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (globalNavigatorKey.currentState == null) return;

      await globalNavigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const UploadPaymentProofScreen(),
        ),
      );
    } finally {
      _navigating = false;
    }
  }
}
