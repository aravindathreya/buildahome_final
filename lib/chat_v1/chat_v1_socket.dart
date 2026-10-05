import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'chat_v1_api.dart';

typedef ChatV1SocketHandler = void Function(dynamic data);

/// Distinguishes a network drop from logout so reconnect never runs after logout.
enum ChatV1SocketState {
  loggedOut,
  connecting,
  connected,
  disconnected,
  reconnecting,
}

class _QueuedEmit {
  final String event;
  final Map<String, dynamic> data;
  _QueuedEmit(this.event, this.data);
}

/// Socket.IO client for Chat V1 (`/socket.io`, websocket-only).
///
/// One Manager per process. Reconnect reuses it. [disconnect] is logout only
/// and stops reconnection. The server authenticates and joins the user's
/// rooms on each new Engine.IO session; the open conversation is joined again
/// from here because that room does not survive the previous WebSocket.
class ChatV1Socket with WidgetsBindingObserver {
  ChatV1Socket._()
      : _tokenProvider = ChatV1Api.instance.getApiToken,
        _healthTimeout = const Duration(seconds: 5);

  @visibleForTesting
  ChatV1Socket.forTesting({
    required io.Socket socket,
    required Future<String?> Function() tokenProvider,
    Duration healthTimeout = const Duration(seconds: 5),
  })  : _socket = socket,
        _tokenProvider = tokenProvider,
        _healthTimeout = healthTimeout;
  static final ChatV1Socket instance = ChatV1Socket._();

  static const String _path = '/socket.io';
  static const List<String> _transports = ['websocket'];
  static const int _timeoutMs = 20000;
  static const num _reconnectAttempts = double.infinity;
  static const int _reconnectDelayMs = 1000;
  static const int _reconnectDelayMaxMs = 30000;

  io.Socket? _socket;
  String? _joinedConversationId;
  Completer<void>? _connecting;
  bool _handlersBound = false;
  bool _managerHandlersBound = false;
  final Future<String?> Function() _tokenProvider;
  final Duration _healthTimeout;
  final Random _random = Random();
  Timer? _namespaceRetry;
  int _namespaceRetryAttempt = 0;
  String? _rejectedToken;
  bool _resumeProbeNeeded = false;
  String? _roomJoinedForConnection;
  String? _boundToken;
  bool _loggedOut = true;
  bool _backgrounded = false;
  bool _everConnected = false;
  bool _observingLifecycle = false;
  int _generation = 0;
  ChatV1SocketState _state = ChatV1SocketState.loggedOut;

  final Map<String, List<ChatV1SocketHandler>> _listeners = {};
  final List<_QueuedEmit> _outboundQueue = [];

  ChatV1SocketState get state => _state;

  /// Bumps on logout. In-flight chat loads compare this so they do not connect
  /// again after the session was destroyed.
  int get sessionGeneration => _generation;

  /// Backgrounded apps do not send events. On resume, a cheap acknowledged
  /// probe distinguishes a healthy connection from a stale mobile transport.
  bool get isConnected =>
      !_loggedOut &&
      !_backgrounded &&
      _state == ChatV1SocketState.connected &&
      _socket?.connected == true;

  String? get joinedConversationId => _joinedConversationId;

  /// Coerce conversation id to int when numeric (server expects number).
  static dynamic convId(String id) => int.tryParse(id) ?? id;

  /// Unwrap socket payloads: List → first map, nested `message`, etc.
  static Map<String, dynamic>? asMap(dynamic data) {
    dynamic cur = data;
    if (cur is List && cur.isNotEmpty) cur = cur.first;
    if (cur is! Map) return null;
    return Map<String, dynamic>.from(cur);
  }

  /// Normalize message_created / similar envelopes.
  /// Returns null if unusable; otherwise `{conversationId, message}`.
  static Map<String, dynamic>? unwrapMessageEvent(dynamic data) {
    final map = asMap(data);
    if (map == null) return null;

    Map<String, dynamic> message;
    if (map['message'] is Map) {
      message = Map<String, dynamic>.from(map['message'] as Map);
    } else if (map['data'] is Map && (map['data'] as Map)['message'] is Map) {
      message = Map<String, dynamic>.from(
        (map['data'] as Map)['message'] as Map,
      );
    } else {
      message = map;
    }

    final conversationId = (map['conversation_id'] ??
            map['conversationId'] ??
            message['conversation_id'] ??
            message['conversationId'] ??
            '')
        .toString();
    return {
      'conversationId': conversationId,
      'message': message,
    };
  }

  void _log(String message) => print(message);

  bool _stillCurrent(int generation) =>
      !_loggedOut && generation == _generation;

  String _managerReadyState() {
    try {
      return (_socket?.io.readyState ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  bool _managerIsOpening() => _managerReadyState().contains('opening');

  bool _managerIsOpen() => _managerReadyState() == 'open';

  void _completeConnecting() {
    final c = _connecting;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  void _ensureLifecycleObserver() {
    if (_observingLifecycle) return;
    _observingLifecycle = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _removeLifecycleObserver() {
    if (!_observingLifecycle) return;
    _observingLifecycle = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_backgrounded || _loggedOut) return;
      _backgrounded = true;
      _log('CHAT SOCKET app paused');
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    _log('CHAT SOCKET app resumed');
    if (_loggedOut) return;
    final wasBackgrounded = _backgrounded;
    _backgrounded = false;
    _resumeProbeNeeded = wasBackgrounded && _socket?.connected == true;
    if (!wasBackgrounded && isConnected) return;
    unawaited(connect());
  }

  Map<String, dynamic> _authFor(String? token) {
    if (token == null || token.isEmpty) return <String, dynamic>{};
    return <String, dynamic>{'api_token': token};
  }

  void _applyCredentials(String? token) {
    final socket = _socket;
    if (socket == null) return;
    // Refresh auth for every namespace handshake, including automatic
    // reconnects. Credentials belong in the CONNECT payload, not the URL.
    socket.auth = _supplyAuth;
    final options = socket.io.options;
    if (options != null) {
      options['auth'] = _supplyAuth;
      options.remove('query');
    }
    _boundToken = token;
  }

  void _supplyAuth(Function callback) async {
    final generation = _generation;
    final socket = _socket;
    final engine = socket?.io.engine;
    try {
      final token = await _tokenProvider();
      if (!_stillCurrent(generation) ||
          socket != _socket ||
          socket?.io.readyState != 'open' ||
          socket?.io.engine != engine) {
        return;
      }
      if (token == null || token.isEmpty) {
        socket?.io.disconnect();
        _state = ChatV1SocketState.disconnected;
        _completeConnecting();
        return;
      }
      _boundToken = token;
      callback(_authFor(token));
    } catch (error) {
      _log('CHAT SOCKET credential lookup failed: $error');
      if (!_stillCurrent(generation)) return;
      socket?.io.disconnect();
      _completeConnecting();
      _scheduleNamespaceRetry();
    }
  }

  @visibleForTesting
  static Duration retryDelay(int attempt, double randomValue) {
    // Keep the whole jitter range below the cap, so exhausted clients do not
    // all clamp onto the same 30-second retry boundary.
    final base = min(_reconnectDelayMaxMs ~/ 1.5,
        _reconnectDelayMs * pow(2, min(max(attempt, 0), 6)));
    return Duration(
        milliseconds:
            min(_reconnectDelayMaxMs, (base * (0.5 + randomValue)).round()));
  }

  void _scheduleNamespaceRetry() {
    if (_loggedOut || _backgrounded || _namespaceRetry != null) return;
    final generation = _generation;
    final delay = retryDelay(_namespaceRetryAttempt++, _random.nextDouble());
    _state = ChatV1SocketState.reconnecting;
    _namespaceRetry = Timer(delay, () {
      _namespaceRetry = null;
      if (!_stillCurrent(generation) || _backgrounded) return;
      unawaited(connect());
    });
  }

  void _onConnectError(dynamic error) {
    if (_loggedOut || _socket?.connected == true) return;
    final map = asMap(error);
    final message = (map?['message'] ?? error ?? '').toString().toLowerCase();
    _log('CHAT SOCKET connection rejected or unavailable');
    if (message.contains('unauthorized') ||
        message.contains('invalid api token') ||
        message.contains('unauthenticated')) {
      // Retry a rejected login only after its token changes. A retry loop
      // cannot repair revoked credentials and repeatedly hits server auth.
      _rejectedToken = _boundToken;
      _namespaceRetry?.cancel();
      _namespaceRetry = null;
      _socket?.io.disconnect();
      _state = ChatV1SocketState.disconnected;
      _completeConnecting();
      return;
    }
    _state = ChatV1SocketState.reconnecting;
    // Transport failures already have a jittered Manager retry. Namespace
    // errors can leave the transport open and need a separate paced retry.
    _completeConnecting();
    if (_managerIsOpen()) _scheduleNamespaceRetry();
  }

  Future<bool> _probeHealth(int generation) async {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    final reply = Completer<bool>();
    final ackId = socket.ids.toString();
    try {
      socket.emitWithAck('chat_ping', <String, dynamic>{}, ack: (dynamic data) {
        if (!reply.isCompleted) {
          reply.complete(
              _stillCurrent(generation) && asMap(data)?['ok'] == true);
        }
      });
      return await reply.future.timeout(_healthTimeout, onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      // This client version keeps timed-out ACKs until an answer arrives.
      socket.acks.remove(ackId);
    }
  }

  void _createSocket(String? token) {
    final auth = _authFor(token);
    // Do not call enableForceNew(). socket_io_client already opens a second
    // Manager when this namespace is cached, and forceNew does that on every
    // io() call. This socket is created once and reused for reconnect.
    // WebSocket-only stays: the browser client uses the same transport against
    // this Nginx/Socket.IO server, and the Dart VM client cannot fall back to
    // XHR polling.
    final options = io.OptionBuilder()
        .setPath(_path)
        .setTransports(List<String>.from(_transports))
        .setAuth(auth)
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(_reconnectAttempts)
        .setReconnectionDelay(_reconnectDelayMs)
        .setReconnectionDelayMax(_reconnectDelayMaxMs)
        .setRandomizationFactor(0.5)
        .setTimeout(_timeoutMs)
        .build();

    _boundToken = token;
    _handlersBound = false;
    _socket = io.io(ChatV1Api.baseUrl, options);
    _applyCredentials(token);
    _log(
      'CHAT SOCKET created url=${ChatV1Api.baseUrl} path=$_path transport=websocket',
    );
    _bindSocketHandlers();
  }

  /// Ensure a live connection on the existing Manager.
  ///
  /// Concurrent callers share a single attempt. Resume probes the transport
  /// before closing it, and Socket.IO owns transport reconnect backoff.
  Future<void> connect() async {
    if (_loggedOut) _loggedOut = false;
    if (_connecting != null) return _connecting!.future;

    if (!_backgrounded &&
        !_resumeProbeNeeded &&
        _state == ChatV1SocketState.connected &&
        _socket?.connected == true) {
      return;
    }

    final generation = _generation;
    _ensureLifecycleObserver();

    final completer = Completer<void>();
    _connecting = completer;

    try {
      final token = await _tokenProvider();
      if (!_stillCurrent(generation)) return;
      if (token == null ||
          token.isEmpty ||
          (_rejectedToken != null && _rejectedToken == token)) {
        _state = ChatV1SocketState.disconnected;
        _completeConnecting();
        return;
      }
      _rejectedToken = null;

      if (_socket == null) {
        _createSocket(token);
      } else {
        _applyCredentials(token);
        if (!_handlersBound) _bindSocketHandlers();
      }
      if (!_stillCurrent(generation)) return;

      if (_resumeProbeNeeded && _socket?.connected == true) {
        _resumeProbeNeeded = false;
        final probedId = _socket?.id;
        final probedEngine = _socket?.io.engine;
        final healthy = await _probeHealth(generation);
        if (!_stillCurrent(generation) || _backgrounded) return;
        if ((_socket?.id != probedId || _socket?.io.engine != probedEngine) &&
            _socket?.connected == true) {
          // An automatic reconnect completed while the old probe was waiting.
          // Its connect handler already recovered this replacement transport.
          _completeConnecting();
          return;
        }
        if (healthy && _socket?.connected == true) {
          _state = ChatV1SocketState.connected;
          _flushOutboundQueue();
          _rejoinOpenConversation();
          _completeConnecting();
          _emitLocal('connected', {'recovered': true});
          return;
        }
        // Only close a transport that failed the resume probe. The Manager
        // owns its retry, so this cannot create a competing connection loop.
        if (_socket?.connected == true && _socket?.io.engine == probedEngine) {
          _socket?.io.engine?.close();
        }
      }
      _resumeProbeNeeded = false;
      if (_backgrounded) return;
      _openOrRecover(generation, 'ensure');

      if (_socket?.connected == true &&
          _state == ChatV1SocketState.connected &&
          !_backgrounded) {
        _completeConnecting();
      } else {
        await completer.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () {},
        );
      }
    } catch (e) {
      _log('CHAT SOCKET connect error: $e');
    } finally {
      if (!completer.isCompleted) completer.complete();
      if (_connecting == completer) _connecting = null;
    }
  }

  void _openOrRecover(int generation, String reason) {
    final socket = _socket;
    if (socket == null || !_stillCurrent(generation)) return;
    final manager = socket.io;
    if (manager.reconnecting || _managerIsOpening()) {
      _state = ChatV1SocketState.reconnecting;
      _log('CHAT SOCKET reconnect already in progress ($reason)');
      return;
    }

    if (socket.connected == true && !_backgrounded) {
      _state = ChatV1SocketState.connected;
      _completeConnecting();
      return;
    }

    _state = _everConnected
        ? ChatV1SocketState.reconnecting
        : ChatV1SocketState.connecting;
    _log(
      _everConnected
          ? 'CHAT SOCKET reconnect existing manager ($reason)'
          : 'CHAT SOCKET connecting',
    );
    socket.connect();
  }

  void _bindSocketHandlers() {
    if (_handlersBound || _socket == null) return;
    _handlersBound = true;
    final s = _socket!;

    s
      ..onConnect((_) {
        if (_loggedOut) return;
        final recovered = _everConnected;
        _everConnected = true;
        _namespaceRetry?.cancel();
        _namespaceRetry = null;
        _namespaceRetryAttempt = 0;
        _rejectedToken = null;
        _roomJoinedForConnection = null;
        _state = ChatV1SocketState.connected;
        _log(recovered
            ? 'CHAT SOCKET reconnect success'
            : 'CHAT SOCKET connected');
        _flushOutboundQueue();
        _rejoinOpenConversation();
        _completeConnecting();
        _emitLocal('connected', {'recovered': recovered});
      })
      ..onDisconnect((dynamic reason) {
        final why = (reason ?? 'unknown').toString();
        _log('CHAT SOCKET DISCONNECTED: $why');
        if (_loggedOut) return;
        _roomJoinedForConnection = null;
        _completeConnecting();
        _state = ChatV1SocketState.reconnecting;
        // Engine close (transport close, ping timeout, forced close) is
        // retried by the Manager. An explicit server disconnect sets
        // skipReconnect, so reuse this same socket once.
        if (why == 'io server disconnect') _scheduleNamespaceRetry();
        _emitLocal('disconnected', {'reason': why});
      })
      ..onConnectError(_onConnectError)
      // 2.0.3+1 emits namespace CONNECT_ERROR as `error` on the Socket.
      ..on('error', _onConnectError)
      // App events. Bound once for this socket object; reconnect does not rebind.
      ..on('message_created', (data) => _emitLocal('message_created', data))
      ..on('typing_started', (data) => _emitLocal('typing_started', data))
      ..on('typing_stopped', (data) => _emitLocal('typing_stopped', data))
      ..on('typing_snapshot', (data) => _emitLocal('typing_snapshot', data))
      ..on('reaction_added', (data) => _emitLocal('reaction_added', data))
      ..on('reaction_removed', (data) => _emitLocal('reaction_removed', data))
      ..on('presence_snapshot', (data) => _emitLocal('presence', data))
      ..on('user_online', (data) => _emitLocal('presence', data))
      ..on('user_offline', (data) => _emitLocal('presence', data))
      ..on('mention_received', (data) => _emitLocal('mention_received', data))
      ..on('conversation_read', (data) => _emitLocal('conversation_read', data))
      ..on('message_read', (data) => _emitLocal('message_read', data))
      ..on('attachment_uploaded',
          (data) => _emitLocal('attachment_uploaded', data));

    // These callbacks live on Manager, and Socket.dispose does not remove
    // them. Bind once across logout/login when reusing the Manager.
    if (_managerHandlersBound) return;
    _managerHandlersBound = true;
    s.io
      ..on('reconnect_attempt', (dynamic attempt) {
        if (_loggedOut) return;
        _state = ChatV1SocketState.reconnecting;
        _log('CHAT SOCKET reconnect attempt $attempt');
      })
      ..on('reconnect_error', (dynamic error) {
        if (_loggedOut) return;
        _log('CHAT SOCKET transport reconnect failed');
      })
      ..on('reconnect_failed', (_) {
        if (_loggedOut) return;
        _state = ChatV1SocketState.disconnected;
      });
  }

  void _rejoinOpenConversation() {
    final id = _joinedConversationId;
    if (id == null) {
      _log(
        'CHAT SOCKET room rejoin skipped (server restores user rooms on connect)',
      );
      return;
    }
    _log('CHAT SOCKET room rejoin conversation=$id');
    _emitJoin(id);
  }

  void on(String event, ChatV1SocketHandler handler) {
    final list = _listeners.putIfAbsent(event, () => []);
    if (list.contains(handler)) return;
    list.add(handler);
  }

  void off(String event, [ChatV1SocketHandler? handler]) {
    if (handler == null) {
      _listeners.remove(event);
      return;
    }
    _listeners[event]?.remove(handler);
  }

  void _emitLocal(String event, dynamic data) {
    final list = _listeners[event];
    if (list == null) return;
    for (final h in List<ChatV1SocketHandler>.from(list)) {
      h(data);
    }
  }

  /// Deliver REST catch-up through the same listeners as live messages.
  void deliverRecoveredMessage(
      String conversationId, Map<String, dynamic> message) {
    if (!isConnected || _joinedConversationId != conversationId) return;
    _emitLocal('message_created', {
      'conversation_id': convId(conversationId),
      'message': message,
      '_recovered': true,
    });
  }

  void _emitOrQueue(String event, Map<String, dynamic> data) {
    if (_loggedOut) return;
    if (isConnected) {
      _socket!.emit(event, data);
      return;
    }
    // Typing and room joins expire while offline; the current room is rejoined
    // on connect. Do not replay stale typing or old room subscriptions.
    if (event == 'typing_start' ||
        event == 'typing_stop' ||
        event == 'join_conversation') return;
    // Do NOT start another connection attempt — queue until onConnect flush.
    // A conversation read supersedes pending per-message reads in that room.
    // Individual message reads remain distinct; only exact duplicates collapse.
    if (event == 'conversation_read') {
      _outboundQueue.removeWhere((item) =>
          (item.event == 'conversation_read' || item.event == 'message_read') &&
          item.data['conversation_id'] == data['conversation_id']);
    } else if (event == 'message_read') {
      if (_outboundQueue.any((item) =>
          item.event == 'conversation_read' &&
          item.data['conversation_id'] == data['conversation_id'])) return;
      _outboundQueue.removeWhere((item) =>
          item.event == event && item.data['message_id'] == data['message_id']);
    }
    if (_outboundQueue.length >= 100) _outboundQueue.removeAt(0);
    _outboundQueue.add(_QueuedEmit(event, data));
  }

  void _flushOutboundQueue() {
    if (!isConnected || _outboundQueue.isEmpty) return;
    final pending = List<_QueuedEmit>.from(_outboundQueue);
    _outboundQueue.clear();
    for (final item in pending) {
      _socket!.emit(item.event, item.data);
    }
  }

  void _emitJoin(String conversationId) {
    final payload = <String, dynamic>{
      'conversation_id': convId(conversationId),
    };
    if (isConnected && _roomJoinedForConnection != conversationId) {
      _socket!.emit('join_conversation', payload);
      _roomJoinedForConnection = conversationId;
    }
  }

  /// Ensure connection exists (wait if opening), then join room.
  /// Does not force a second Manager when already connected.
  Future<void> joinConversation(String conversationId) async {
    final generation = _generation;
    final previous = _joinedConversationId;
    if (previous != null && previous != conversationId) {
      leaveConversation(previous);
    }
    _joinedConversationId = conversationId;
    if (!isConnected) await connect();
    if (!_stillCurrent(generation) || _joinedConversationId != conversationId)
      return;
    _emitJoin(conversationId);
  }

  void leaveConversation(String conversationId) {
    if (_joinedConversationId == conversationId) {
      _joinedConversationId = null;
    }
    if (_roomJoinedForConnection == conversationId) {
      _roomJoinedForConnection = null;
    }
    final payload = <String, dynamic>{
      'conversation_id': convId(conversationId),
    };
    if (_socket?.connected == true && !_loggedOut && !_backgrounded) {
      _socket!.emit('leave_conversation', payload);
    }
  }

  Future<Map<String, dynamic>?> sendMessage({
    required String conversationId,
    required String body,
    String contentType = 'text',
    int? parentMessageId,
  }) async {
    final generation = _generation;
    if (!isConnected) {
      await connect();
    }
    final socket = _socket;
    if (!_stillCurrent(generation) || socket == null || !isConnected)
      return null;

    final payload = <String, dynamic>{
      'conversation_id': convId(conversationId),
      'body': body,
      'content_type': contentType,
      'parent_message_id': parentMessageId,
    };

    final completer = Completer<Map<String, dynamic>?>();
    final ackId = socket.ids.toString();
    try {
      socket.emitWithAck('send_message', payload, ack: (dynamic resp) {
        if (completer.isCompleted) return;
        final map = asMap(resp);
        if (map == null) {
          completer.complete(null);
          return;
        }
        if (map['success'] == false) {
          completer.completeError(
            ChatV1ApiException(
              map['message']?.toString() ?? 'Send failed',
            ),
          );
          return;
        }
        if (map['message'] is Map) {
          completer.complete(
            Map<String, dynamic>.from(map['message'] as Map),
          );
        } else {
          completer.complete(map);
        }
      });
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }

    try {
      return await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => null,
      );
    } finally {
      socket.acks.remove(ackId);
    }
  }

  void typingStart(String conversationId) {
    _emitOrQueue('typing_start', {
      'conversation_id': convId(conversationId),
    });
  }

  void typingStop(String conversationId) {
    _emitOrQueue('typing_stop', {
      'conversation_id': convId(conversationId),
    });
  }

  void messageRead({
    required String conversationId,
    required String messageId,
  }) {
    _emitOrQueue('message_read', {
      'conversation_id': convId(conversationId),
      'message_id': int.tryParse(messageId) ?? messageId,
    });
  }

  void conversationRead(String conversationId) {
    _emitOrQueue('conversation_read', {
      'conversation_id': convId(conversationId),
    });
  }

  void addReaction({
    required String messageId,
    required String emoji,
  }) {
    _emitOrQueue('add_reaction', {
      'message_id': int.tryParse(messageId) ?? messageId,
      'reaction': emoji,
    });
  }

  void removeReaction({
    required String messageId,
    required String emoji,
  }) {
    _emitOrQueue('remove_reaction', {
      'message_id': int.tryParse(messageId) ?? messageId,
      'reaction': emoji,
    });
  }

  /// Logout only. Stops retry timers and clears transport buffers.
  void disconnect() {
    _loggedOut = true;
    _state = ChatV1SocketState.loggedOut;
    _backgrounded = false;
    _everConnected = false;
    _generation++;
    _namespaceRetry?.cancel();
    _namespaceRetry = null;
    _namespaceRetryAttempt = 0;
    _rejectedToken = null;
    _resumeProbeNeeded = false;
    _roomJoinedForConnection = null;
    _removeLifecycleObserver();
    _joinedConversationId = null;
    _outboundQueue.clear();
    _boundToken = null;
    _handlersBound = false;
    _completeConnecting();
    _connecting = null;
    _log('CHAT SOCKET logout disconnect');
    // dispose() sets the Manager's skipReconnect and clears socket listeners.
    // The same socket object is kept so the next login does not call io()
    // again and open a second Manager.
    _socket?.dispose();
    _socket?.sendBuffer.clear();
    _socket?.receiveBuffer.clear();
    _socket?.acks.clear();
    _emitLocal('logged_out', null);
  }
}
