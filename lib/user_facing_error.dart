/// Shown when a request cannot reach the server.
const String connectionErrorMessage =
    'No internet connection. Check your network and try again.';

/// Thrown by [ApiHttp] when the device cannot reach the server.
/// [toString] is the message shown on screen, with no request address.
class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException();

  @override
  String toString() => connectionErrorMessage;
}

/// True when [error] is a failed connection, DNS lookup, or request timeout.
///
/// A normal server message is not a connection failure, even if it mentions
/// the network. Otherwise an empty document list was shown as offline.
bool isConnectionError(Object? error) {
  if (error == null) return false;
  if (error is NetworkUnavailableException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('handshakeexception') ||
      text.contains('timeoutexception') ||
      text.contains('failed host lookup') ||
      text.contains('no address associated') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection abort') ||
      text.contains('connection timed out');
}

/// True when [message] is the offline sentence or a raw connection failure.
bool isOfflineUserMessage(String? message) {
  if (message == null || message.trim().isEmpty) return false;
  if (message.trim() == connectionErrorMessage) return true;
  return isConnectionError(message);
}

/// One sentence for a failed load.
///
/// No connection becomes [connectionErrorMessage]. Any other failure keeps a
/// short reason for that case, never a socket dump, URL, or token.
String situationError(
  Object? error, {
  required String fallback,
}) {
  if (error == null) return fallback;
  if (isConnectionError(error)) return connectionErrorMessage;
  final text = userFacingError(error, fallback: fallback);
  if (text == connectionErrorMessage) return connectionErrorMessage;
  return text;
}

/// Text safe to show for [error]. Connection failures never include the
/// request address or token.
String userFacingError(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error == null) return fallback;
  if (isConnectionError(error)) return connectionErrorMessage;
  var text = error.toString();
  text = text.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  text = text.replaceAll('Exception: ', '');
  text = text.trim();
  if (text.isEmpty || _looksTechnical(text)) return fallback;
  return text;
}

bool _looksTechnical(String text) {
  final lower = text.toLowerCase();
  return lower.contains('api_token') ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('errno') ||
      lower.contains('uri=') ||
      lower.contains('https://') ||
      lower.contains('http://') ||
      lower.contains('os error') ||
      lower.contains('stack trace');
}
