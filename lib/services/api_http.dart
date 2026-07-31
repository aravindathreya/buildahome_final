import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

/// HTTP client that inspects every response for invalidated sessions.
class SessionAwareClient extends http.BaseClient {
  SessionAwareClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    final body = utf8.decode(bytes, allowMalformed: true);

    final loggedOut = await SessionManager.instance.handleStatusAndBody(
      statusCode: streamed.statusCode,
      body: body,
      requestUrl: request.url,
      requestHadCredentials: requestCarriesCredentials(request),
    );

    if (loggedOut) {
      throw SessionInvalidatedException();
    }

    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      streamed.statusCode,
      contentLength: bytes.length,
      request: streamed.request,
      headers: streamed.headers,
      reasonPhrase: streamed.reasonPhrase,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
    );
  }

  @override
  void close() => _inner.close();
}

/// True when the request actually sent an api token. Responses to requests
/// without one cannot tell us anything about the validity of the session.
bool requestCarriesCredentials(http.BaseRequest request) {
  final queryToken = request.url.queryParameters['api_token'];
  if (queryToken != null && queryToken.trim().isNotEmpty) return true;

  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == 'x-api-token' &&
        entry.value.trim().isNotEmpty) {
      return true;
    }
  }

  if (request is http.MultipartRequest) {
    final field = request.fields['api_token'];
    return field != null && field.trim().isNotEmpty;
  }

  if (request is http.Request) {
    try {
      return RegExp(r'api_token"?\s*[=:]\s*"?[^&",\s}]+').hasMatch(request.body);
    } catch (_) {
      return false;
    }
  }

  return false;
}

/// App-wide authenticated HTTP helpers. Prefer these over raw `http.*`
/// for any call that sends `api_token` / `X-Api-Token`.
class ApiHttp {
  ApiHttp._();

  static final SessionAwareClient client = SessionAwareClient();

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) {
    return client.get(url, headers: headers);
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return client.post(url, headers: headers, body: body, encoding: encoding);
  }

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return client.put(url, headers: headers, body: body, encoding: encoding);
  }

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return client.delete(url, headers: headers, body: body, encoding: encoding);
  }

  static Future<http.StreamedResponse> send(http.BaseRequest request) {
    return client.send(request);
  }
}
