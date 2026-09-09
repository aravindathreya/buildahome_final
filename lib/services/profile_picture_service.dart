import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePictureService {
  static const String baseUrl = 'https://office.buildahome.in';
  static const String _prefsKey = 'profile_picture';
  static const String skipPrefPrefix = 'profile_pic_skips_';
  static const int maxStartupSkips = 3;

  /// Prevents re-prompting within the same app session after dismiss/skip.
  static bool promptShownThisSession = false;

  /// Live path used by header/drawer avatars across the app.
  static final ValueNotifier<String?> picturePathNotifier =
      ValueNotifier<String?>(null);

  static bool isSkipPrefKey(String key) => key.startsWith(skipPrefPrefix);

  /// True when [path] is a real user-uploaded picture (not empty / defaults).
  static bool isValidPath(String? path) {
    if (path == null) return false;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower == 'null' ||
        lower == 'undefined' ||
        lower == 'none' ||
        lower == 'n/a' ||
        lower == '/') {
      return false;
    }
    // Server default placeholder used when the user has never uploaded a photo.
    // Login returns this for many staff accounts — treat as "no picture".
    final fileName = lower.split('/').last.split('?').first;
    if (fileName == 'profile_picture.png' ||
        fileName == 'profile_picture.jpg' ||
        fileName == 'default.png' ||
        fileName == 'default.jpg' ||
        fileName == 'avatar.png' ||
        fileName == 'avatar.jpg' ||
        lower.contains('/static/profile_picture')) {
      return false;
    }
    return true;
  }

  static String? resolveUrl(String? path) {
    if (!isValidPath(path)) return null;
    final trimmed = path!.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$baseUrl$trimmed';
    }
    return '$baseUrl/$trimmed';
  }

  static Future<String> _scopeId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();
    if (userId.isNotEmpty && userId.toLowerCase() != 'null') {
      return userId;
    }
    final phone = (prefs.getString('phone') ?? '').trim();
    if (phone.isNotEmpty) return 'phone_$phone';
    final username = (prefs.getString('username') ?? '').trim();
    if (username.isNotEmpty) return 'user_$username';
    return 'default';
  }

  static Future<String> _skipPrefKey([String? scopeId]) async {
    return '$skipPrefPrefix${scopeId ?? await _scopeId()}';
  }

  static Future<String?> getStoredPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    if (!isValidPath(value)) {
      if (value != null && value.trim().isNotEmpty) {
        // Clear stale placeholders like "null" so the login prompt can show.
        await prefs.remove(_prefsKey);
      }
      picturePathNotifier.value = null;
      return null;
    }
    final path = value!.trim();
    picturePathNotifier.value = path;
    return path;
  }

  static Future<bool> hasProfilePicture() async {
    final path = await getStoredPath();
    return path != null;
  }

  static Future<void> savePath(String path) async {
    if (!isValidPath(path)) {
      await clearStored();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    await prefs.setString(_prefsKey, trimmed);
    picturePathNotifier.value = trimmed;
    await clearSkipCount();
  }

  static Future<void> clearStored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    picturePathNotifier.value = null;
    promptShownThisSession = false;
  }

  /// How many times this user has tapped "Maybe later" on the startup prompt.
  static Future<int> getSkipCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(await _skipPrefKey()) ?? 0;
  }

  /// Skips still allowed before the prompt becomes mandatory.
  static Future<int> remainingSkips() async {
    final used = await getSkipCount();
    final left = maxStartupSkips - used;
    return left < 0 ? 0 : left;
  }

  static Future<bool> canSkipStartupPrompt() async {
    return await remainingSkips() > 0;
  }

  static Future<int> recordStartupSkip() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _skipPrefKey();
    final next = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, next > maxStartupSkips ? maxStartupSkips : next);
    return await remainingSkips();
  }

  static Future<void> clearSkipCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _skipPrefKey());
  }

  /// Restore skip counters after a full prefs wipe on logout.
  static Future<void> restorePreservedSkipCounts(
    Map<String, int> preserved,
  ) async {
    if (preserved.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in preserved.entries) {
      if (!isSkipPrefKey(entry.key)) continue;
      await prefs.setInt(entry.key, entry.value);
    }
  }

  /// Uploads [imageFile] and returns the server `profile_picture` path on success.
  static Future<String> upload(File imageFile) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? prefs.getString('user_id');
    final apiToken = prefs.getString('api_token');

    if (userId == null || userId.isEmpty) {
      throw Exception('User not logged in');
    }
    if (apiToken == null || apiToken.isEmpty) {
      throw Exception('Missing API token');
    }

    final uri = Uri.parse('$baseUrl/API/set_profile_picture');
    final request = http.MultipartRequest('POST', uri);
    request.fields['user_id'] = userId;
    request.fields['api_token'] = apiToken;
    request.headers['X-Api-Token'] = apiToken;

    final filename = imageFile.path.split(Platform.pathSeparator).last;
    request.files.add(
      await http.MultipartFile.fromPath(
        'profile_picture',
        imageFile.path,
        filename: filename,
      ),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        body = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 200 &&
        body != null &&
        (body['success'] == true || body['profile_picture'] != null)) {
      final path = body['profile_picture']?.toString().trim() ?? '';
      if (path.isEmpty) {
        throw Exception(body['message']?.toString() ??
            'Upload succeeded but no path returned');
      }
      await savePath(path);
      return path;
    }

    final message = body?['message']?.toString();
    throw Exception(
      message != null && message.isNotEmpty
          ? message
          : 'Failed to update profile picture (${response.statusCode})',
    );
  }
}
