import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'chat_v1_api.dart';

typedef ChatV1SocketHandler = void Function(dynamic data);

class _QueuedEmit {
  final String event;
  final Map<String, dynamic> data;
  _QueuedEmit(this.event, this.data);
}

/// Socket.IO client for Chat V1 (`/socket.io`, websocket-only).
///
/// Lifecycle: create once → bind listeners → connect() once;
/// never call connect() while Manager is already opening.
class ChatV1Socket {
  ChatV1Socket._();
  static final ChatV1Socket instance = ChatV1Socket._();

  static const String _path = '/socket.io';
  static const List<String> _transports = ['websocket'];
  static const int _timeoutMs = 20000;
  static const int _reconnectAttempts = 999;
  static const int _reconnectDelayMs = 1000;
  static const int _reconnectDelayMaxMs = 10000;

  io.Socket? _socket;
  String? _joinedConversationId;
  Completer<void>? _connecting;
  bool _handlersBound = false;
  String? _boundToken;

  final Map<String, List<ChatV1SocketHandler>> _listeners = {};
  final List<_QueuedEmit> _outboundQueue = [];

  bool get isConnected => _socket?.connected == true;
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

  String _managerReadyState() {
    try {
      return (_socket?.io.readyState ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  bool _managerIsOpening() => _managerReadyState().contains('opening');

  bool _managerIsOpen() => _managerReadyState() == 'open';

  bool _managerIsClosedOrIdle() {
    final rs = _managerReadyState();
    return rs.isEmpty || rs.contains('closed');
  }

  void _completeConnecting() {
    final c = _connecting;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// Ensure a live connection without overlapping Engine.IO opens.
  Future<void> connect() async {
    if (_socket?.connected == true) return;
    if (_connecting != null) return _connecting!.future;

    final completer = Completer<void>();
    _connecting = completer;

    try {
      final token = await ChatV1Api.instance.getApiToken();
      final query = <String, dynamic>{
        if (token != null) 'api_token': token,
      };
      final auth = <String, dynamic>{
        if (token != null) 'api_token': token,
      };

      // Recreate only when api_token changes (session lifetime otherwise).
      if (_socket != null && _boundToken != token) {
        _handlersBound = false;
        _socket!.dispose();
        _socket = null;
      }

      if (_socket == null) {
        final options = io.OptionBuilder()
            .setPath(_path)
            .setTransports(List<String>.from(_transports))
            .setAuth(auth)
            .setQuery(query)
            .enableForceNew()
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(_reconnectAttempts)
            .setReconnectionDelay(_reconnectDelayMs)
            .setReconnectionDelayMax(_reconnectDelayMaxMs)
            .setTimeout(_timeoutMs)
            .build();

        _boundToken = token;
        _handlersBound = false;
        _socket = io.io(ChatV1Api.baseUrl, options);

        // Bind ALL listeners BEFORE the single connect().
        _bindSocketHandlers();
        _socket!.connect();
      } else if (_socket?.connected != true) {
        if (_managerIsOpening()) {
          // Manager already opening — wait; do not call connect().
        } else if (_managerIsOpen()) {
          // Transport open but namespace not connected — attach namespace.
          _socket!.connect();
        } else if (_managerIsClosedOrIdle()) {
          _socket!.connect();
        }
      }

      if (_socket?.connected == true) {
        _completeConnecting();
      } else {
        await Future.any([
          completer.future,
          Future<void>.delayed(const Duration(seconds: 20)),
        ]);
      }
    } catch (_) {
      _completeConnecting();
    } finally {
      _completeConnecting();
      if (_connecting == completer) _connecting = null;
    }
  }

  void _bindSocketHandlers() {
    if (_handlersBound || _socket == null) return;
    _handlersBound = true;
    final s = _socket!;

    s
      ..onConnect((_) {
        _flushOutboundQueue();
        final id = _joinedConversationId;
        if (id != null) _emitJoin(id);
        _completeConnecting();
      })
      ..onConnectError((_) {
        _completeConnecting();
      })
      ..onConnectTimeout((_) {
        _completeConnecting();
      })
      ..onReconnect((_) {
        _flushOutboundQueue();
        final id = _joinedConversationId;
        if (id != null) _emitJoin(id);
      })
      // App events
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
  }

  void on(String event, ChatV1SocketHandler handler) {
    _listeners.putIfAbsent(event, () => []).add(handler);
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

  void _emitOrQueue(String event, Map<String, dynamic> data) {
    if (_socket?.connected == true) {
      _socket!.emit(event, data);
      return;
    }
    // Do NOT start another connection attempt — queue until onConnect flush.
    _outboundQueue.add(_QueuedEmit(event, data));
  }

  void _flushOutboundQueue() {
    if (_socket?.connected != true || _outboundQueue.isEmpty) return;
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
    if (_socket?.connected == true) {
      _socket!.emit('join_conversation', payload);
    } else {
      _emitOrQueue('join_conversation', payload);
    }
  }

  /// Ensure connection exists (wait if opening), then join room.
  /// Does not force a reconnect when already connected.
  Future<void> joinConversation(String conversationId) async {
    _joinedConversationId = conversationId;
    if (_socket?.connected != true) {
      await connect();
    }
    _emitJoin(conversationId);
  }

  void leaveConversation(String conversationId) {
    if (_joinedConversationId == conversationId) {
      _joinedConversationId = null;
    }
    final payload = <String, dynamic>{
      'conversation_id': convId(conversationId),
    };
    if (_socket?.connected == true) {
      _socket!.emit('leave_conversation', payload);
    }
  }

  Future<Map<String, dynamic>?> sendMessage({
    required String conversationId,
    required String body,
    String contentType = 'text',
    int? parentMessageId,
  }) async {
    // Wait for existing connect if opening; do not force a new Engine open.
    if (_socket?.connected != true) {
      await connect();
    }
    final socket = _socket;
    if (socket == null || !socket.connected) return null;

    final payload = <String, dynamic>{
      'conversation_id': convId(conversationId),
      'body': body,
      'content_type': contentType,
      'parent_message_id': parentMessageId,
    };

    final completer = Completer<Map<String, dynamic>?>();
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

    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
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

  void disconnect() {
    _joinedConversationId = null;
    _outboundQueue.clear();
    _handlersBound = false;
    _boundToken = null;
    _socket?.dispose();
    _socket = null;
    _completeConnecting();
    _connecting = null;
  }
}
