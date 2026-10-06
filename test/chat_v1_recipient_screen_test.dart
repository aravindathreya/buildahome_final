import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_api.dart';
import 'package:buildAhome/chat_v1/chat_v1_controller.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';
import 'package:buildAhome/chat_v1/chat_v1_socket.dart';
import 'package:buildAhome/chat_v1/chat_v1_theme.dart';
import 'package:buildAhome/chat_v1/screens/chat_v1_conversation_screen.dart';

import 'chat_v1_socket_recovery_test.dart' show FakeSocket;

class _OfflineApi extends ChatV1Api {
  final List<Map<String, dynamic>> history;
  final Completer<Map<String, dynamic>>? detailGate;
  final List<String> unexpectedRequests = [];
  int historyRequests = 0;
  int reads = 0;

  _OfflineApi({this.history = const [], this.detailGate}) : super.forTesting();

  @override
  Future<List<Map<String, dynamic>>> listMessages(
    String conversationId, {
    int pageSize = 50,
    String? beforeId,
    String? afterId,
    bool includeExtras = true,
  }) async {
    if (beforeId != null || afterId != null) return [];
    historyRequests++;
    return history;
  }

  @override
  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    if (detailGate != null) return await detailGate!.future;
    return {'id': 1};
  }

  @override
  Future<List<Map<String, dynamic>>> listMentionParticipants(
          String conversationId) async =>
      [];

  @override
  Future<void> markConversationRead(String conversationId,
      {String? upToMessageId}) async {
    reads++;
  }

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    unexpectedRequests.add('GET $path');
    throw StateError('Unexpected request in offline screen test: $path');
  }

  @override
  Future<dynamic> post(String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    unexpectedRequests.add('POST $path');
    throw StateError('Unexpected request in offline screen test: $path');
  }
}

Map<String, dynamic> _row({int id = 12, int sender = 2}) => {
      'id': id,
      'conversation_id': 1,
      'sender_id': sender,
      'sender_name': sender == 7 ? 'Priya Rao' : 'Aravind',
      'body': '@Priya Please check the site photos.',
      'created_at': DateTime.utc(2026, 10, 5, 6, 30)
          .add(Duration(seconds: id))
          .toIso8601String(),
      // A lightweight event has no extras. Its separate personal event is the
      // authoritative evidence that this recipient was mentioned.
    };

Map<String, dynamic> _mention({
  int message = 12,
  int recipient = 7,
  int conversation = 1,
}) =>
    {
      'mention': {
        'mentioned_user_id': recipient,
        'conversation_id': conversation,
        'message_id': message,
      },
    };

class _ScreenHarness {
  final _OfflineApi api;
  final raw = FakeSocket();
  late final socket = ChatV1Socket.forTesting(
      socket: raw, tokenProvider: () async => 'offline-test-token');

  _ScreenHarness(this.api);

  Future<void> mount(WidgetTester tester) async {
    final ctrl = ChatV1Controller.instance;
    final oldId = ctrl.currentUserId;
    final oldName = ctrl.currentUserName;
    final oldCache = ctrl.cachedMessages('1');
    ctrl.currentUserId = '7';
    ctrl.currentUserName = 'Priya Rao';
    ctrl.putCachedMessages('1', []);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      socket.disconnect();
      ctrl.currentUserId = oldId;
      ctrl.currentUserName = oldName;
      ctrl.putCachedMessages('1', oldCache ?? []);
    });
    await tester.pumpWidget(MaterialApp(
      theme: ChatV1Theme.data(dark: true),
      home: ChatV1ConversationScreen.forTesting(
        meta: const ChatV1ConvMeta(
          id: '1',
          title: 'General',
          subtitle: 'Project channel',
          icon: Icons.tag,
          accent: ChatV1Theme.accent,
          members: [],
          description: 'General project discussion',
        ),
        onOpenInfo: () {},
        api: api,
        socket: socket,
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(socket.isConnected, isTrue);
    expect(socket.joinedConversationId, '1');
  }

  void emit(String event, Map<String, dynamic> payload) {
    raw.onevent({
      'data': [event, payload]
    });
  }

  void message({int id = 12, int sender = 2}) => emit('message_created', {
        'conversation_id': 1,
        'message': _row(id: id, sender: sender),
      });
}

void _expectPersonalState(WidgetTester tester) {
  expect(find.text('@You'), findsOneWidget);
  expect(find.text('You were tagged here'), findsOneWidget);
  expect(find.text('You were tagged'), findsOneWidget);
  expect(find.text('View message'), findsOneWidget);
  final bubble = tester.widget<Container>(find
      .ancestor(
          of: find.byKey(const ValueKey('personal-mention-chip')),
          matching: find.byType(Container))
      .first);
  expect(((bubble.decoration! as BoxDecoration).border! as Border).left.color,
      ChatV1Theme.unread);
}

void main() {
  for (final eventFirst in [true, false]) {
    testWidgets(
        'real recipient screen shows green state for mention event first=$eventFirst',
        (tester) async {
      final api = _OfflineApi();
      final harness = _ScreenHarness(api);
      await harness.mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('@You'), findsNothing);
      if (eventFirst) {
        harness.emit('mention_received', _mention());
        await tester.pump();
        expect(find.text('@You'), findsNothing);
        harness.message();
      } else {
        harness.message();
        await tester.pumpAndSettle();
        expect(find.text('@You'), findsNothing);
        harness.emit('mention_received', _mention());
      }
      await tester.pumpAndSettle();
      _expectPersonalState(tester);
      expect(api.historyRequests, 1);
      expect(api.unexpectedRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'foreign recipient/channel and own tags do not mark the recipient',
      (tester) async {
    final api = _OfflineApi();
    final harness = _ScreenHarness(api);
    await harness.mount(tester);
    await tester.pumpAndSettle();
    harness.emit('mention_received', _mention(recipient: 8));
    harness.message();
    harness.emit('mention_received', _mention(message: 13, conversation: 2));
    harness.message(id: 13);
    harness.emit('mention_received', _mention(message: 14));
    harness.message(id: 14, sender: 7);
    await tester.pumpAndSettle();
    expect(find.text('@You'), findsNothing);
    expect(find.text('You were tagged here'), findsNothing);
    expect(find.text('You were tagged'), findsNothing);
    expect(api.unexpectedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late initial history completion keeps live recipient tag visible',
      (tester) async {
    final detail = Completer<Map<String, dynamic>>();
    final api = _OfflineApi(history: [_row()], detailGate: detail);
    final harness = _ScreenHarness(api);
    await harness.mount(tester);
    expect(api.historyRequests, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    harness.emit('mention_received', _mention());
    harness.message();
    await tester.pump();
    detail.complete({'id': 1});
    await tester.pumpAndSettle();
    _expectPersonalState(tester);
    final cached = ChatV1Controller.instance.cachedMessages('1')!;
    expect(cached.single.mentions.single.userId, '7');
    expect(api.unexpectedRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
