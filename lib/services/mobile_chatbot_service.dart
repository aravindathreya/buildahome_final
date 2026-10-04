import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mobile_chatbot.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// Client project Q&A bot — `/API/mobile/chatbot` and `/ask`.
///
/// Same handlers as `/api/client_portal/chatbot*`. Not staff Chat V1.
class MobileChatbotService {
  MobileChatbotService._();
  static final MobileChatbotService instance = MobileChatbotService._();
  factory MobileChatbotService() => instance;

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];
  static const Duration greetingTimeout = Duration(seconds: 15);
  static const Duration askTimeout = Duration(seconds: 45);

  Future<MobileChatbotGreeting> fetchGreeting() async {
    try {
      final auth = await _auth();
      if (auth == null) return MobileChatbotGreeting.fallback;

      final headers = _headers(auth.token);
      final query = <String, String>{
        'api_token': auth.token,
        if (auth.userId.isNotEmpty) 'user_id': auth.userId,
      };

      for (final uri in _uris('mobile/chatbot', query)) {
        try {
          final res = await ApiHttp.get(uri, headers: headers)
              .timeout(greetingTimeout);
          final body = _decodeMap(res.body);
          if (body == null) continue;
          if (body['success'] == false) {
            final failed = MobileChatbotAskResult.fromJson(
              body,
              statusCode: res.statusCode,
            );
            if (failed.text.trim().isEmpty) continue;
            return MobileChatbotGreeting(greeting: failed.text);
          }
          if (res.statusCode < 200 || res.statusCode >= 300) continue;
          final greeting = MobileChatbotGreeting.fromJson(body);
          if (greeting.greeting.trim().isEmpty) continue;
          return greeting;
        } on SessionInvalidatedException {
          rethrow;
        } catch (e) {
          print('[MobileChatbot] greeting $uri failed: $e');
        }
      }
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      print('[MobileChatbot] greeting error: $e');
    }
    return MobileChatbotGreeting.fallback;
  }

  Future<MobileChatbotAskResult> ask({
    required String question,
    Map<String, dynamic>? conversation,
  }) async {
    final text = question.trim();
    if (text.isEmpty) {
      return MobileChatbotAskResult.failure('Please type a question.');
    }

    final auth = await _auth();
    if (auth == null) {
      return MobileChatbotAskResult.failure('Please sign in again.');
    }

    final headers = {
      ..._headers(auth.token),
      'Content-Type': 'application/json',
    };
    final query = <String, String>{
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
    };
    final payload = <String, dynamic>{
      'question': text,
      'conversation': conversation,
      'api_token': auth.token,
      if (auth.userId.isNotEmpty) 'user_id': auth.userId,
    };
    final encoded = jsonEncode(payload);

    String? lastMessage;
    for (final uri in _uris('mobile/chatbot/ask', query)) {
      try {
        final res = await ApiHttp.post(uri, headers: headers, body: encoded)
            .timeout(askTimeout);
        final body = _decodeMap(res.body);

        if (body != null) {
          final parsed = MobileChatbotAskResult.fromJson(
            body,
            statusCode: res.statusCode,
          );
          if (res.statusCode >= 200 && res.statusCode < 300) {
            return parsed;
          }
          if (body.containsKey('success') ||
              body.containsKey('ok') ||
              body.containsKey('answer') ||
              body.containsKey('message')) {
            return parsed;
          }
        }

        if (res.statusCode >= 200 && res.statusCode < 300) {
          return MobileChatbotAskResult.failure(
            'Unexpected response from the assistant.',
          );
        }
        lastMessage = _messageFrom(body) ??
            'Could not reach the assistant (${res.statusCode})';
      } on SessionInvalidatedException {
        rethrow;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
        print('[MobileChatbot] ask $uri failed: $e');
      }
    }

    return MobileChatbotAskResult.failure(
      lastMessage?.trim().isNotEmpty == true
          ? lastMessage!
          : 'Could not reach the assistant. Try again.',
    );
  }

  List<Uri> _uris(String pathSuffix, Map<String, String> query) {
    final uris = <Uri>[];
    for (final base in baseUrls) {
      for (final prefix in const ['API', 'api']) {
        uris.add(
          Uri.parse('$base/$prefix/$pathSuffix')
              .replace(queryParameters: query),
        );
      }
    }
    return uris;
  }

  Map<String, String> _headers(String token) {
    return {
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };
  }

  Future<_ChatbotAuth?> _auth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('api_token') ?? '').trim();
    if (token.isEmpty || token.toLowerCase() == 'null') return null;
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '')
            .trim();
    return _ChatbotAuth(token: token, userId: userId);
  }

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final raw = jsonDecode(body);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  String? _messageFrom(Map<String, dynamic>? body) {
    if (body == null) return null;
    for (final key in const ['message', 'error', 'detail', 'answer']) {
      final text = body[key]?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }
}

class _ChatbotAuth {
  const _ChatbotAuth({required this.token, required this.userId});
  final String token;
  final String userId;
}
