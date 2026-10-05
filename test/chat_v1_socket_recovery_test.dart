import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';
import 'package:socket_io_client/src/engine/socket.dart' as engine;

import 'package:buildAhome/chat_v1/chat_v1_socket.dart';
import 'package:buildAhome/chat_v1/chat_v1_controller.dart';
import 'package:buildAhome/chat_v1/chat_v1_mapper.dart';

class FakeEngine extends engine.Socket {
  final void Function() closed;
  int closeCalls = 0;
  FakeEngine(this.closed)
      : super('https://chat.invalid', {
          'transports': ['websocket']
        });
  @override
  void open() {
    readyState = 'open';
  }

  @override
  engine.Socket close() {
    closeCalls++;
    readyState = 'closed';
    closed();
    return this;
  }
}

class FakeManager extends Manager {
  final Map<String, int> registrations = {};
  int disconnectCalls = 0;
  FakeManager()
      : super(uri: 'https://chat.invalid', options: {'autoConnect': false});
  @override
  void on(String event, dynamic Function(dynamic) handler) {
    registrations.update(event, (count) => count + 1, ifAbsent: () => 1);
    super.on(event, handler);
  }

  @override
  void disconnect() {
    disconnectCalls++;
    readyState = 'closed';
    reconnecting = false;
    skipReconnect = true;
  }
}

class FakeSocket extends io.Socket {
  int connectCalls = 0;
  final List<Map<String, dynamic>> sent = [];
  bool acknowledgeHealth = true;
  bool autoConnect = true;
  FakeManager get manager => this.io as FakeManager;
  FakeEngine get engineSocket => this.io.engine as FakeEngine;
  FakeSocket() : super(FakeManager(), '/', {'autoConnect': false}) {
    this.io.engine = FakeEngine(() {
      manager.readyState = 'closed';
      drop('transport close');
    });
  }
  @override
  io.Socket connect() {
    connectCalls++;
    if (autoConnect) connectedNow();
    return this;
  }

  void connectedNow() {
    manager.readyState = 'open';
    manager.skipReconnect = false;
    onconnect('test-$connectCalls', null);
  }

  void drop(String reason) {
    connected = false;
    disconnected = true;
    super.emit('disconnect', reason);
  }

  void namespaceError(dynamic error) {
    super.emit('error', error);
  }

  @override
  io.Socket disconnect() {
    connected = false;
    disconnected = true;
    manager.disconnect();
    return this;
  }

  @override
  void emitWithAck(String event, dynamic data,
      {Function? ack, bool binary = false}) {
    if (io.events.contains(event)) {
      super.emitWithAck(event, data, ack: ack, binary: binary);
      return;
    }
    sent.add({'event': event, 'data': data});
    if (ack != null) {
      final ackId = (ids++).toString();
      acks[ackId] = ack;
      if (event == 'chat_ping' && acknowledgeHealth) {
        acks.remove(ackId);
        ack({'ok': true});
      }
    }
  }

  int count(String event) => sent.where((row) => row['event'] == event).length;
}

Map<String, dynamic> row(int id, {int conversation = 1}) => {
      'id': id,
      'conversation_id': conversation,
      'body': 'Message $id',
      'sender_id': 7,
      'sender_name': 'Aravind',
      'created_at': DateTime.utc(2026, 10, 5)
          .add(Duration(seconds: id))
          .toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('concurrent callers share one connection and one room join',
      (tester) async {
    final raw = FakeSocket();
    final token = Completer<String?>();
    final socket =
        ChatV1Socket.forTesting(socket: raw, tokenProvider: () => token.future);
    addTearDown(socket.disconnect);
    final joins = List.generate(20, (_) => socket.joinConversation('1'));
    expect(raw.connectCalls, 0);
    token.complete('token');
    await Future.wait(joins);
    expect(raw.connectCalls, 1);
    expect(raw.count('join_conversation'), 1);
    expect(raw.manager.options!.containsKey('query'), false);
  });

  testWidgets('healthy app resume probes without closing or reconnecting',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    await socket.joinConversation('1');
    final recovered = <dynamic>[];
    socket.on('connected', recovered.add);
    socket.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(socket.isConnected, false);
    socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(socket.isConnected, true);
    expect(raw.count('chat_ping'), 1);
    expect(raw.connectCalls, 1);
    expect(raw.engineSocket.closeCalls, 0);
    expect(recovered.single['recovered'], true);
  });

  testWidgets('background reconnect rejoins active room after healthy resume',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    await socket.joinConversation('1');
    socket.didChangeAppLifecycleState(AppLifecycleState.paused);
    raw.drop('transport close');
    raw.connect();
    socket.conversationRead('1');
    expect(raw.count('join_conversation'), 1);
    expect(raw.count('conversation_read'), 0);
    socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(socket.isConnected, true);
    expect(raw.count('join_conversation'), 2);
    expect(raw.count('conversation_read'), 1);
    expect(raw.engineSocket.closeCalls, 0);
  });

  testWidgets('stale resume transport closes only after failed probe',
      (tester) async {
    final raw = FakeSocket()..acknowledgeHealth = false;
    final socket = ChatV1Socket.forTesting(
        socket: raw,
        tokenProvider: () async => 'token',
        healthTimeout: const Duration(seconds: 2));
    addTearDown(socket.disconnect);
    await socket.joinConversation('1');
    socket.didChangeAppLifecycleState(AppLifecycleState.paused);
    socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(raw.engineSocket.closeCalls, 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(raw.engineSocket.closeCalls, 1);
    expect(raw.connectCalls, 2);
    expect(raw.count('join_conversation'), 2);
    expect(raw.acks, isEmpty);
  });

  testWidgets('late failed probe cannot close a replacement connection',
      (tester) async {
    final raw = FakeSocket()..acknowledgeHealth = false;
    final socket = ChatV1Socket.forTesting(
        socket: raw,
        tokenProvider: () async => 'token',
        healthTimeout: const Duration(seconds: 2));
    addTearDown(socket.disconnect);
    await socket.connect();
    socket.didChangeAppLifecycleState(AppLifecycleState.paused);
    socket.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    raw.drop('ping timeout');
    raw.connect();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(raw.connectCalls, 2);
    expect(raw.engineSocket.closeCalls, 0);
    expect(socket.isConnected, true);
  });

  testWidgets('each namespace handshake reads the latest stored token',
      (tester) async {
    final raw = FakeSocket();
    var token = 'first-token';
    final socket =
        ChatV1Socket.forTesting(socket: raw, tokenProvider: () async => token);
    addTearDown(socket.disconnect);
    await socket.connect();
    final credentials = <dynamic>[];
    final auth = raw.auth as Function;
    auth(credentials.add);
    await tester.pump();
    token = 'updated-token';
    auth(credentials.add);
    await tester.pump();
    expect(credentials, [
      {'api_token': 'first-token'},
      {'api_token': 'updated-token'}
    ]);
  });

  testWidgets('disposed screen cannot join after its connection finishes',
      (tester) async {
    final raw = FakeSocket();
    final token = Completer<String?>();
    final socket =
        ChatV1Socket.forTesting(socket: raw, tokenProvider: () => token.future);
    addTearDown(socket.disconnect);
    final opening = socket.joinConversation('1');
    socket.leaveConversation('1');
    token.complete('token');
    await opening;
    expect(raw.count('join_conversation'), 0);
    expect(socket.joinedConversationId, null);
  });

  testWidgets('rapid screen switch joins only the current conversation',
      (tester) async {
    final raw = FakeSocket();
    final token = Completer<String?>();
    final socket =
        ChatV1Socket.forTesting(socket: raw, tokenProvider: () => token.future);
    addTearDown(socket.disconnect);
    final old = socket.joinConversation('1');
    final current = socket.joinConversation('2');
    token.complete('token');
    await Future.wait([old, current]);
    final joins = raw.sent.where((row) => row['event'] == 'join_conversation');
    expect(joins.single['data']['conversation_id'], 2);
  });

  testWidgets('logout cancels pending connection and does not resurrect it',
      (tester) async {
    final raw = FakeSocket();
    final token = Completer<String?>();
    final socket =
        ChatV1Socket.forTesting(socket: raw, tokenProvider: () => token.future);
    final opening = socket.joinConversation('1');
    socket.disconnect();
    token.complete('token');
    await opening;
    expect(raw.connectCalls, 0);
    expect(socket.state, ChatV1SocketState.loggedOut);
  });

  testWidgets('logout prevents stale queued events reaching the next login',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    await socket.connect();
    socket.disconnect();
    socket.conversationRead('1');
    socket.addReaction(messageId: '10', emoji: 'thumbs_up');
    await socket.connect();
    expect(raw.count('conversation_read'), 0);
    expect(raw.count('add_reaction'), 0);
    socket.disconnect();
  });

  testWidgets('server disconnect retries with delay and logout cancels retry',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    await socket.connect();
    raw.drop('io server disconnect');
    await tester.pump();
    expect(raw.connectCalls, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(raw.connectCalls, 2);
    raw.drop('io server disconnect');
    socket.disconnect();
    await tester.pump(const Duration(seconds: 40));
    expect(raw.connectCalls, 2);
  });

  testWidgets('rejected token pauses retries until credentials change',
      (tester) async {
    final raw = FakeSocket()..autoConnect = false;
    var token = 'revoked';
    final socket =
        ChatV1Socket.forTesting(socket: raw, tokenProvider: () async => token);
    addTearDown(socket.disconnect);
    final attempt = socket.connect();
    await tester.pump();
    raw.namespaceError({'message': 'Invalid api token'});
    await attempt;
    await tester.pump(const Duration(seconds: 40));
    await socket.connect();
    expect(raw.connectCalls, 1);
    expect(socket.state, ChatV1SocketState.disconnected);
    token = 'new-token';
    raw.autoConnect = true;
    await socket.connect();
    expect(raw.connectCalls, 2);
    expect(socket.isConnected, true);
  });

  testWidgets(
      'generic namespace rejection retries after temporary server outage',
      (tester) async {
    final raw = FakeSocket()..autoConnect = false;
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    final attempt = socket.connect();
    await tester.pump();
    raw.manager.readyState = 'open';
    raw.namespaceError({'message': 'Connection rejected by server'});
    await attempt;
    expect(raw.connectCalls, 1);
    raw.autoConnect = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(raw.connectCalls, 2);
    expect(socket.isConnected, true);
  });

  testWidgets('manager callbacks are bound once across repeated logins',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    for (var i = 0; i < 5; i++) {
      await socket.connect();
      socket.disconnect();
    }
    expect(raw.manager.registrations['reconnect_attempt'], 1);
    expect(raw.manager.registrations['reconnect_error'], 1);
    expect(raw.manager.registrations['reconnect_failed'], 1);
  });

  testWidgets(
      'offline read queue coalesces room reads without losing individual reads',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    await socket.connect();
    raw.drop('transport close');
    socket.messageRead(conversationId: '1', messageId: '10');
    socket.messageRead(conversationId: '1', messageId: '11');
    socket.messageRead(conversationId: '1', messageId: '10');
    socket.messageRead(conversationId: '2', messageId: '12');
    socket.conversationRead('2');
    socket.conversationRead('2');
    raw.connect();
    expect(raw.count('message_read'), 2);
    expect(raw.count('conversation_read'), 1);
  });

  test('retry backoff spreads clients and remains capped', () {
    expect(ChatV1Socket.retryDelay(0, 0).inMilliseconds, 500);
    expect(ChatV1Socket.retryDelay(0, 1).inMilliseconds, 1500);
    expect(ChatV1Socket.retryDelay(99, .9).inMilliseconds, 28000);
    for (var attempt = 0; attempt < 100; attempt++) {
      expect(ChatV1Socket.retryDelay(attempt, .9).inSeconds,
          lessThanOrEqualTo(30));
    }
  });

  testWidgets('recovery fetches only active chat and delivers missed messages',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    await socket.joinConversation('1');
    final fetched = <String>[];
    final controller = ChatV1Controller.forTesting(
        socket: socket,
        messageLoader: (id, afterId, pageSize) async {
          fetched.add(id);
          expect(afterId, '1');
          return [row(2), row(3)];
        },
        conversationLoader: (_) async => [
              {
                'id': 1,
                'title': 'General',
                'conversation_type': 'channel',
                'unread_count': 0,
                'unread_mention_count': 0,
                'last_message': {'body': 'Message 3', 'sender_name': 'Aravind'},
              }
            ]);
    addTearDown(controller.dispose);
    controller.salesSopId = '2553';
    controller.currentUserId = '9';
    controller.putCachedMessages(
        '1', [ChatV1Mapper.messageFromJson(row(1), currentUserId: '9')]);
    controller.putCachedMessages('2', [
      ChatV1Mapper.messageFromJson(row(1, conversation: 2), currentUserId: '9')
    ]);
    final delivered = <dynamic>[];
    socket.on('message_created', delivered.add);
    await controller.recoverAfterReconnectForTesting();
    expect(fetched, ['1']);
    expect(controller.cachedMessages('2'), null);
    expect(controller.cachedMessages('1')!.map((m) => m.id), ['1', '2', '3']);
    expect(delivered.map((data) => data['message']['id']), [2, 3]);
    expect(controller.channels.single.unread, 0);
  });

  testWidgets('long recovery gap is bounded and includes the newest page',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    await socket.joinConversation('1');
    var requests = 0;
    final controller = ChatV1Controller.forTesting(
        socket: socket,
        messageLoader: (_, afterId, __) async {
          requests++;
          final start = afterId == null ? 999 : int.parse(afterId) + 1;
          return List.generate(100, (i) => row(start + i));
        },
        conversationLoader: (_) async => []);
    addTearDown(controller.dispose);
    controller.putCachedMessages(
        '1', [ChatV1Mapper.messageFromJson(row(1), currentUserId: '9')]);
    await controller.recoverAfterReconnectForTesting();
    expect(requests, ChatV1Controller.maxRecoveryPages + 1);
    expect(controller.cachedMessages('1')!.last.id, '1098');
    expect(controller.cachedMessages('1')!.length, lessThanOrEqualTo(300));
  });

  testWidgets('reconnect burst coalesces recovery with a cooldown',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    addTearDown(socket.disconnect);
    await socket.joinConversation('1');
    final pending = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    final controller = ChatV1Controller.forTesting(
        socket: socket,
        messageLoader: (_, __, ___) {
          calls++;
          return calls == 1 ? pending.future : Future.value([]);
        },
        conversationLoader: (_) async => []);
    addTearDown(controller.dispose);
    controller.putCachedMessages(
        '1', [ChatV1Mapper.messageFromJson(row(1), currentUserId: '9')]);
    final recovery = controller.recoverAfterReconnectForTesting();
    for (var index = 0; index < 20; index++) {
      raw.connectedNow();
    }
    pending.complete([]);
    await recovery;
    await tester.pump(const Duration(seconds: 14));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('logout during recovery discards late response and clears cache',
      (tester) async {
    final raw = FakeSocket();
    final socket = ChatV1Socket.forTesting(
        socket: raw, tokenProvider: () async => 'token');
    await socket.joinConversation('1');
    final response = Completer<List<Map<String, dynamic>>>();
    var summaryCalls = 0;
    final controller = ChatV1Controller.forTesting(
        socket: socket,
        messageLoader: (_, __, ___) => response.future,
        conversationLoader: (_) async {
          summaryCalls++;
          return [];
        });
    addTearDown(controller.dispose);
    controller.salesSopId = '2553';
    controller.putCachedMessages(
        '1', [ChatV1Mapper.messageFromJson(row(1), currentUserId: '9')]);
    final recovering = controller.recoverAfterReconnectForTesting();
    socket.disconnect();
    response.complete([row(2)]);
    await recovering;
    expect(controller.cachedMessages('1'), null);
    expect(summaryCalls, 0);
    expect(controller.currentUserId, null);
  });
}
