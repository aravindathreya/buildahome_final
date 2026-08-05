import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePictureService {
  static const String baseUrl = 'https://office.buildahome.in';
  static const String _prefsKey = 'profile_picture';

  /// Prevents re-prompting within the same app session after dismiss/skip.
  static bool promptShownThisSession = false;

  /// Live path used by header/drawer avatars across the app.
  static final ValueNotifier<String?> picturePathNotifier =
      ValueNotifier<String?>(null);

  static String? resolveUrl(String? path) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$baseUrl$trimmed';
    }
    return '$baseUrl/$trimmed';
  }

  static Future<String?> getStoredPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    if (value == null || value.trim().isEmpty) {
      picturePathNotifier.value = null;
      return null;
    }
    final path = value.trim();
    picturePathNotifier.value = path;
    return path;
  }

  static Future<bool> hasProfilePicture() async {
    final path = await getStoredPath();
    return path != null;
  }

  static Future<void> savePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    await prefs.setString(_prefsKey, trimmed);
    picturePathNotifier.value = trimmed;
  }

  static Future<void> clearStored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    picturePathNotifier.value = null;
    promptShownThisSession = false;
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
        throw Exception(body['message']?.toString() ?? 'Upload succeeded but no path returned');
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
