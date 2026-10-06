import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'client_portal_service.dart';
import 'document_byte_cache.dart';

/// How a document URL should be fetched.
enum DocumentUrlProfile {
  buildahomePrivate,
  publicDirect,
}

enum DocumentPayloadKind {
  pdf,
  image,
  unsupported,
  loginHtml,
  missing,
  sessionExpired,
  networkError,
}

class DocumentFetchResult {
  final DocumentPayloadKind kind;
  final Uint8List? bytes;
  final String userMessage;
  final int statusCode;
  final String contentType;
  final String detectedSignature;
  final String finalUrl;
  final DocumentUrlProfile profile;
  final String authMethod;

  const DocumentFetchResult({
    required this.kind,
    this.bytes,
    required this.userMessage,
    this.statusCode = 0,
    this.contentType = '',
    this.detectedSignature = '',
    this.finalUrl = '',
    this.profile = DocumentUrlProfile.publicDirect,
    this.authMethod = 'none',
  });

  bool get isSuccess =>
      kind == DocumentPayloadKind.pdf || kind == DocumentPayloadKind.image;
}

/// URL plus headers for a viewer that can load the file itself.
class PreparedDocumentRequest {
  final Uri uri;
  final Map<String, String> headers;
  final String cacheKey;

  const PreparedDocumentRequest({
    required this.uri,
    required this.headers,
    required this.cacheKey,
  });
}

/// A few bytes of a document, used to decide if the browser can stream it.
class DocumentProbe {
  final bool canStream;
  final bool blockNative;
  final bool downloadInstead;
  final String message;

  const DocumentProbe({
    required this.canStream,
    required this.blockNative,
    required this.downloadInstead,
    this.message = '',
  });

  const DocumentProbe.allow()
      : canStream = true,
        blockNative = false,
        downloadInstead = false,
        message = '';

  const DocumentProbe.keepNative()
      : canStream = false,
        blockNative = false,
        downloadInstead = false,
        message = '';
}

/// Downloads workflow / portal documents with auth and validates bytes.
class AuthenticatedDocumentFetcher {
  AuthenticatedDocumentFetcher._();
  static final AuthenticatedDocumentFetcher instance =
      AuthenticatedDocumentFetcher._();

  static const String baseUrl = 'https://office.buildahome.in';
  static const int _maxRedirects = 8;
  static const int _maxBytes = 80 * 1024 * 1024; // 80 MB

  final http.Client _client = http.Client();
  final Map<String, Future<DocumentFetchResult>> _inflight = {};
  _AuthBundle? _authCache;
  DateTime? _authCacheAt;
  String? _authCacheKey;

  /// Start a download so a later open can use the saved bytes.
  Future<void> prefetch({
    required String url,
    String? documentId,
    String? contentTypeHint,
    bool? isPdfHint,
    bool? isImageHint,
  }) {
    return fetch(
      url: url,
      documentId: documentId,
      contentTypeHint: contentTypeHint,
      isPdfHint: isPdfHint,
      isImageHint: isImageHint,
    );
  }

  Future<PreparedDocumentRequest> prepareRequest(String url) async {
    final normalizedUrl = _normalizeUrl(url);
    final profile = classifyUrl(normalizedUrl);
    final auth = await _buildAuth(profile, normalizedUrl);
    return PreparedDocumentRequest(
      uri: _uriWithToken(Uri.parse(normalizedUrl), auth.apiToken),
      headers: auth.headers,
      cacheKey: documentCacheKey(normalizedUrl),
    );
  }

  /// Reads only the start of the file, then stops.
  Future<DocumentProbe> probe(
    PreparedDocumentRequest prepared, {
    required bool allowHeaders,
  }) async {
    if (DocumentByteCache.instance.isStreamable(prepared.cacheKey)) {
      return const DocumentProbe.allow();
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', prepared.uri);
      request.headers['Accept'] = '*/*';
      request.headers['Range'] = 'bytes=0-2047';
      if (allowHeaders) {
        request.headers.addAll(prepared.headers);
      }
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 6));
      final buf = BytesBuilder(copy: false);
      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = streamed.stream.listen(
        (chunk) {
          if (buf.length < 4096) buf.add(chunk);
          if (buf.length >= 16 && !done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
      await sub.cancel();
      final bytes = buf.takeBytes();
      final status = streamed.statusCode;
      final contentType =
          streamed.headers['content-type']?.split(';').first.trim() ?? '';
      final disposition =
          (streamed.headers['content-disposition'] ?? '').toLowerCase();
      if (status == 401 || status == 403) {
        return const DocumentProbe(
          canStream: false,
          blockNative: true,
          downloadInstead: false,
          message: 'Your session has expired. Please refresh and try again.',
        );
      }
      if (_isLoginHtml(bytes) || _isHtml(bytes)) {
        return DocumentProbe(
          canStream: false,
          blockNative: true,
          downloadInstead: false,
          message: _isLoginHtml(bytes)
              ? 'Your session has expired. Please refresh and try again.'
              : 'Unable to open this document right now.',
        );
      }
      final isPdf = _isPdf(bytes, contentType) ||
          contentType.toLowerCase().contains('pdf');
      if (!isPdf || status < 200 || status >= 300) {
        return const DocumentProbe.keepNative();
      }
      if (disposition.contains('attachment')) {
        return const DocumentProbe(
          canStream: false,
          blockNative: false,
          downloadInstead: true,
        );
      }
      DocumentByteCache.instance.markStreamable(prepared.cacheKey);
      return const DocumentProbe.allow();
    } catch (_) {
      return const DocumentProbe.keepNative();
    } finally {
      client.close();
    }
  }

  Future<DocumentFetchResult> fetch({
    required String url,
    String? documentId,
    String? contentTypeHint,
    bool? isPdfHint,
    bool? isImageHint,
  }) {
    final normalizedUrl = _normalizeUrl(url);
    final cacheKey = documentCacheKey(normalizedUrl);
    final pending = _inflight[cacheKey];
    if (pending != null) return pending;
    final future = _fetch(
      url: url,
      documentId: documentId,
      contentTypeHint: contentTypeHint,
      isPdfHint: isPdfHint,
      isImageHint: isImageHint,
    );
    _inflight[cacheKey] = future;
    future.whenComplete(() {
      if (identical(_inflight[cacheKey], future)) {
        _inflight.remove(cacheKey);
      }
    });
    return future;
  }

  Future<DocumentFetchResult> _fetch({
    required String url,
    String? documentId,
    String? contentTypeHint,
    bool? isPdfHint,
    bool? isImageHint,
  }) async {
    final normalizedUrl = _normalizeUrl(url);
    final cacheKey = documentCacheKey(normalizedUrl);
    final cachedBytes = await DocumentByteCache.instance.read(cacheKey);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      final detected = _detectPayload(
        bytes: cachedBytes,
        contentType: contentTypeHint ?? '',
        contentTypeHint: contentTypeHint,
        isPdfHint: isPdfHint,
        isImageHint: isImageHint,
      );
      if (detected == 'PDF' || detected.startsWith('IMAGE')) {
        return DocumentFetchResult(
          kind: detected == 'PDF'
              ? DocumentPayloadKind.pdf
              : DocumentPayloadKind.image,
          bytes: cachedBytes,
          userMessage: '',
          statusCode: 200,
          contentType: detected == 'PDF'
              ? (contentTypeHint ?? 'application/pdf')
              : (contentTypeHint ?? 'image/*'),
          finalUrl: normalizedUrl,
          authMethod: 'cache',
        );
      }
    }

    final profile = classifyUrl(normalizedUrl);
    final auth = await _buildAuth(profile, normalizedUrl);

    _debugLog(
      'URL: $normalizedUrl\n'
      'DocumentId: ${documentId ?? 'n/a'}\n'
      'Profile: ${profile.name}\n'
      'Auth: ${auth.methodLabel}',
    );

    try {
      final response = await _getFollowingRedirects(
        normalizedUrl,
        headers: auth.headers,
        apiToken: auth.apiToken,
        profile: profile,
      );

      final status = response.statusCode;
      final finalUrl = response.request?.url.toString() ?? normalizedUrl;
      final contentType =
          response.headers['content-type']?.split(';').first.trim() ?? '';
      final bytes = response.bodyBytes;
      final length = bytes.length;
      final signature = _signaturePreview(bytes);
      final detected = _detectPayload(
        bytes: bytes,
        contentType: contentType,
        contentTypeHint: contentTypeHint,
        isPdfHint: isPdfHint,
        isImageHint: isImageHint,
      );

      _debugLog(
        'FinalURL: $finalUrl\n'
        'Status: $status\n'
        'Content-Type: $contentType\n'
        'Content-Length: $length\n'
        'Signature: $signature\n'
        'Detected: $detected\n'
        'Auth: ${auth.methodLabel}',
      );

      if (status == 401 || status == 403) {
        return DocumentFetchResult(
          kind: DocumentPayloadKind.sessionExpired,
          userMessage:
              'Your session has expired. Please refresh and try again.',
          statusCode: status,
          contentType: contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      if (status == 404) {
        return DocumentFetchResult(
          kind: DocumentPayloadKind.missing,
          userMessage: 'Document is no longer available.',
          statusCode: status,
          contentType: contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      if (status < 200 || status >= 300) {
        return DocumentFetchResult(
          kind: DocumentPayloadKind.networkError,
          userMessage: 'Unable to open this document right now.',
          statusCode: status,
          contentType: contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      if (length == 0) {
        return DocumentFetchResult(
          kind: DocumentPayloadKind.missing,
          userMessage: 'Document is no longer available.',
          statusCode: status,
          contentType: contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      if (detected == 'LOGIN_HTML' || detected == 'HTML') {
        _debugLog('Action: reject response (HTML/login)');
        return DocumentFetchResult(
          kind: DocumentPayloadKind.loginHtml,
          userMessage: detected == 'LOGIN_HTML'
              ? 'Your session has expired. Please refresh and try again.'
              : 'Unable to open this document right now.',
          statusCode: status,
          contentType: contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      if (detected == 'PDF') {
        _debugLog('Action: open native PDF viewer');
        DocumentByteCache.instance.remember(cacheKey, bytes);
        return DocumentFetchResult(
          kind: DocumentPayloadKind.pdf,
          bytes: bytes,
          userMessage: '',
          statusCode: status,
          contentType: contentType.isEmpty ? 'application/pdf' : contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      if (detected.startsWith('IMAGE')) {
        _debugLog('Action: open native image viewer');
        DocumentByteCache.instance.remember(cacheKey, bytes);
        return DocumentFetchResult(
          kind: DocumentPayloadKind.image,
          bytes: bytes,
          userMessage: '',
          statusCode: status,
          contentType: contentType,
          detectedSignature: signature,
          finalUrl: finalUrl,
          profile: profile,
          authMethod: auth.methodLabel,
        );
      }

      _debugLog('Action: reject unsupported format');
      return DocumentFetchResult(
        kind: DocumentPayloadKind.unsupported,
        userMessage: 'This document format cannot be previewed.',
        statusCode: status,
        contentType: contentType,
        detectedSignature: signature,
        finalUrl: finalUrl,
        profile: profile,
        authMethod: auth.methodLabel,
      );
    } catch (e, st) {
      _debugLog('Fetch error: $e\n$st');
      return DocumentFetchResult(
        kind: DocumentPayloadKind.networkError,
        userMessage: 'Unable to open this document right now.',
        profile: profile,
        authMethod: auth.methodLabel,
      );
    }
  }

  static DocumentUrlProfile classifyUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('serve_sales_sop') ||
        lower.contains('serve_global_reference') ||
        lower.contains('serve_client') ||
        lower.contains('serve_kyc') ||
        lower.contains('costing_sheet') ||
        lower.contains('area_statement') ||
        lower.contains('final_cost_sheet')) {
      return DocumentUrlProfile.buildahomePrivate;
    }
    if (lower.contains('buildahome.in') &&
        (lower.contains('/files/') ||
            lower.contains('/serve') ||
            lower.contains('/api/'))) {
      return DocumentUrlProfile.buildahomePrivate;
    }
    return DocumentUrlProfile.publicDirect;
  }

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) return '$baseUrl$trimmed';
    return '$baseUrl/$trimmed';
  }

  Future<_AuthBundle> _buildAuth(
    DocumentUrlProfile profile,
    String url,
  ) async {
    final cacheKey = profile.name;
    final cachedAt = _authCacheAt;
    if (_authCache != null &&
        _authCacheKey == cacheKey &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 45)) {
      return _authCache!;
    }
    final auth = await _loadAuth(profile, url);
    _authCache = auth;
    _authCacheKey = cacheKey;
    _authCacheAt = DateTime.now();
    return auth;
  }

  Future<_AuthBundle> _loadAuth(
    DocumentUrlProfile profile,
    String url,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken = prefs.getString('api_token')?.trim();
    final hasToken = apiToken != null &&
        apiToken.isNotEmpty &&
        apiToken.toLowerCase() != 'null';

    final headers = <String, String>{
      'Accept': '*/*',
    };

    final methods = <String>[];

    if (hasToken) {
      headers['X-Api-Token'] = apiToken;
      headers['Authorization'] = 'Bearer $apiToken';
      methods.add('X-Api-Token');
    }

    final needsCookie = profile == DocumentUrlProfile.buildahomePrivate ||
        url.contains('buildahome.in');
    if (needsCookie) {
      final cookie = await ClientPortalService().sessionCookieHeader();
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
        methods.add('session-cookie');
      }
    }

    if (methods.isEmpty) methods.add('none');

    return _AuthBundle(
      headers: headers,
      apiToken: hasToken ? apiToken : null,
      methodLabel: methods.join(' + '),
    );
  }

  Future<http.Response> _getFollowingRedirects(
    String url, {
    required Map<String, String> headers,
    required String? apiToken,
    required DocumentUrlProfile profile,
  }) async {
    var uri = _uriWithToken(Uri.parse(url), apiToken);

    http.Response? lastResponse;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('GET', uri)..headers.addAll(headers);
      final streamed = await _client.send(request);
      final bytes = <int>[];
      var total = 0;
      await for (final chunk in streamed.stream) {
        total += chunk.length;
        if (total > _maxBytes) {
          throw Exception('Document exceeds maximum preview size');
        }
        bytes.addAll(chunk);
      }

      lastResponse = http.Response.bytes(
        bytes,
        streamed.statusCode,
        request: request,
        headers: streamed.headers,
        isRedirect: streamed.isRedirect,
      );

      final redirect = _redirectLocation(lastResponse);
      if (redirect == null) {
        return lastResponse;
      }

      uri = uri.resolve(redirect);
      _debugLog('Redirect ${lastResponse.statusCode} -> $uri');

      // Signed S3 URLs typically should not carry BuildAhome auth headers.
      if (!_isBuildahomeHost(uri)) {
        headers = Map<String, String>.from(headers)
          ..remove('Cookie')
          ..remove('X-Api-Token')
          ..remove('Authorization');
      }
    }

    return lastResponse ??
        http.Response('Too many redirects', 310, request: http.Request('GET', uri));
  }

  String? _redirectLocation(http.Response response) {
    final code = response.statusCode;
    if (code != 301 &&
        code != 302 &&
        code != 303 &&
        code != 307 &&
        code != 308) {
      return null;
    }
    return response.headers['location'];
  }

  Uri _uriWithToken(Uri uri, String? apiToken) {
    final isBuildahome = uri.host.toLowerCase().contains('buildahome.in');
    if (!isBuildahome ||
        apiToken == null ||
        apiToken.isEmpty ||
        uri.queryParameters.containsKey('api_token')) {
      return uri;
    }
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'api_token': apiToken},
    );
  }

  bool _isBuildahomeHost(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('buildahome.in');
  }

  String _detectPayload({
    required List<int> bytes,
    required String contentType,
    String? contentTypeHint,
    bool? isPdfHint,
    bool? isImageHint,
  }) {
    if (_isLoginHtml(bytes)) return 'LOGIN_HTML';
    if (_isHtml(bytes)) return 'HTML';
    if (_isPdf(bytes, contentType)) return 'PDF';
    if (_isImage(bytes, contentType)) {
      return 'IMAGE:${contentType.split('/').last}';
    }

    final lowerType = contentType.toLowerCase();
    if (lowerType.contains('pdf') || isPdfHint == true) {
      if (_isPdf(bytes, contentType)) return 'PDF';
    }
    if (lowerType.startsWith('image/') || isImageHint == true) {
      if (_isImage(bytes, contentType)) {
        return 'IMAGE:${contentType.split('/').last}';
      }
    }

    final hint = contentTypeHint?.toLowerCase() ?? '';
    if (hint.contains('pdf') && _isPdf(bytes, contentType)) return 'PDF';
    if (hint.startsWith('image/') && _isImage(bytes, contentType)) {
      return 'IMAGE:$hint';
    }

    return 'UNKNOWN';
  }

  bool _isPdf(List<int> bytes, String contentType) {
    if (contentType.toLowerCase().contains('application/pdf')) {
      return bytes.length >= 4 &&
          String.fromCharCodes(bytes.take(4)) == '%PDF';
    }
    return bytes.length >= 4 &&
        String.fromCharCodes(bytes.take(4)) == '%PDF';
  }

  bool _isImage(List<int> bytes, String contentType) {
    if (bytes.length < 4) return false;
    final lower = contentType.toLowerCase();
    if (lower.startsWith('image/')) {
      return _hasImageMagic(bytes);
    }
    return _hasImageMagic(bytes);
  }

  bool _hasImageMagic(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true; // PNG
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return true;
    }
    if (bytes.length >= 6) {
      final head = String.fromCharCodes(bytes.take(6)).toUpperCase();
      if (head == 'GIF87A' || head == 'GIF89A') return true;
    }
    return false;
  }

  bool _isHtml(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final sample =
        String.fromCharCodes(bytes.take(512)).trimLeft().toLowerCase();
    return sample.startsWith('<!doctype html') ||
        sample.startsWith('<html') ||
        sample.startsWith('<head');
  }

  bool _isLoginHtml(List<int> bytes) {
    if (!_isHtml(bytes)) return false;
    final sample =
        String.fromCharCodes(bytes.take(4096)).toLowerCase();
    return sample.contains('login') ||
        sample.contains('sign in') ||
        sample.contains('password') ||
        sample.contains('buildahome_session') ||
        sample.contains('api_token');
  }

  String _signaturePreview(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    if (bytes.length >= 4 &&
        String.fromCharCodes(bytes.take(4)) == '%PDF') {
      return '%PDF-';
    }
    return String.fromCharCodes(bytes.take(16))
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '.');
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[DocumentViewer]\n$message');
    }
  }
}

class _AuthBundle {
  final Map<String, String> headers;
  final String? apiToken;
  final String methodLabel;

  const _AuthBundle({
    required this.headers,
    required this.apiToken,
    required this.methodLabel,
  });
}
