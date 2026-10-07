import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:buildAhome/services/notification_service.dart';
import 'package:buildAhome/services/push/alert_push.dart';
import 'package:buildAhome/services/push/chat_push_grouper.dart';
import 'package:buildAhome/services/push/fcm_token_client.dart';
import 'package:buildAhome/services/push/notification_permission_policy.dart';
import 'package:buildAhome/services/push/notification_target.dart';
import 'package:buildAhome/widgets/notification_permission_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FCM token registration', () {
    test('register sends the logged-in user and device token', () async {
      final calls = <_Posted>[];
      final client = FcmTokenClient(post: _record(calls));
      final ok = await client.register(
        const FcmTokenRegistration(
          userId: '42',
          apiToken: 'secret-token',
          fcmToken: 'device-token',
          platform: 'android',
          deviceId: 'device-1',
        ),
      );

      expect(ok, isTrue);
      expect(calls.single.uri.path, '/API/save_fcm_token');
      expect(calls.single.fields['user_id'], '42');
      expect(calls.single.fields['fcm_token'], 'device-token');
      expect(calls.single.fields['device_id'], 'device-1');
      expect(calls.single.fields['platform'], 'android');
      expect(calls.single.headers['X-Api-Token'], 'secret-token');
    });

    test('token refresh updates the same user', () async {
      final calls = <_Posted>[];
      final session = FcmSessionCoordinator(FcmTokenClient(post: _record(calls)));
      await session.bind(
        const FcmTokenRegistration(
          userId: '42',
          apiToken: 'secret-token',
          fcmToken: 'token-a',
          platform: 'android',
          deviceId: 'device-1',
        ),
      );
      final refreshed = await session.onTokenRefresh(
        fcmToken: 'token-b',
        apiToken: 'secret-token',
        platform: 'android',
      );

      expect(refreshed, isTrue);
      expect(session.fcmToken, 'token-b');
      expect(session.userId, '42');
      expect(calls.last.uri.path, '/API/save_fcm_token');
      expect(calls.last.fields['fcm_token'], 'token-b');
      expect(calls.last.fields['user_id'], '42');
    });

    test('logout unregisters the token and the next login binds the new user',
        () async {
      final calls = <_Posted>[];
      final session = FcmSessionCoordinator(FcmTokenClient(post: _record(calls)));
      await session.bind(
        const FcmTokenRegistration(
          userId: '42',
          apiToken: 'token-a',
          fcmToken: 'device-token',
          platform: 'ios',
          deviceId: 'device-1',
        ),
      );
      final loggedOut = await session.logout(apiToken: 'token-a');
      expect(loggedOut, isTrue);
      expect(session.userId, isNull);

      await session.bind(
        const FcmTokenRegistration(
          userId: '99',
          apiToken: 'token-b',
          fcmToken: 'device-token',
          platform: 'ios',
          deviceId: 'device-1',
        ),
      );

      expect(calls.map((call) => call.uri.path).toList(), [
        '/API/save_fcm_token',
        '/API/unregister_fcm_token',
        '/API/save_fcm_token',
      ]);
      expect(calls[1].fields['user_id'], '42');
      expect(calls[2].fields['user_id'], '99');
      expect(calls[2].fields['fcm_token'], 'device-token');
    });

    test('a failure response does not count as registered', () async {
      final client = FcmTokenClient(
        post: (_, __, ___) async => http.Response('failure', 200),
      );
      final ok = await client.register(
        const FcmTokenRegistration(
          userId: '42',
          apiToken: 'secret-token',
          fcmToken: 'device-token',
          platform: 'android',
          deviceId: 'device-1',
        ),
      );
      expect(ok, isFalse);
    });

    test('register is rejected without a user', () async {
      final client = FcmTokenClient(
        post: (_, __, ___) async => http.Response('{"success":true}', 200),
      );
      final ok = await client.register(
        const FcmTokenRegistration(
          userId: '',
          apiToken: 'secret-token',
          fcmToken: 'device-token',
          platform: 'android',
          deviceId: 'device-1',
        ),
      );
      expect(ok, isFalse);
    });
  });

  group('alert to push', () {
    test('keeps navigation fields and drops secrets', () {
      final data = AlertPushMapper.toData({
        'id': '9',
        'title': 'Task assigned',
        'body': 'Review the drawing',
        'type': 'task',
        'task_id': '77',
        'project_id': '3',
        'api_token': 'should-not-travel',
        'phone': '9999999999',
        'email': 'a@b.c',
      });

      expect(data['type'], 'task');
      expect(data['task_id'], '77');
      expect(data['project_id'], '3');
      expect(data.containsKey('api_token'), isFalse);
      expect(data.containsKey('phone'), isFalse);
      expect(data.containsKey('email'), isFalse);
    });

    test('only new unread alerts become pushes after a baseline sync', () {
      final previous = [
        {'id': '1', 'title': 'Old', 'body': 'Seen', 'unread': 0},
      ];
      final next = [
        {'id': '1', 'title': 'Old', 'body': 'Seen', 'unread': 0},
        {'id': '2', 'title': 'Payment', 'body': 'Bill due', 'unread': 1},
        {'id': '3', 'title': 'Read already', 'body': 'Done', 'unread': 0},
      ];

      final fresh = AlertPushMapper.selectNewAlerts(
        hadBaseline: true,
        previousFingerprints: previous.map(NotificationService.fingerprint).toSet(),
        next: next.map((item) => Map<String, dynamic>.from(item)).toList(),
        fingerprint: NotificationService.fingerprint,
        isUnread: (alert) => '${alert['unread']}' == '1',
      );

      expect(fresh.map((alert) => alert['id']), ['2']);
      expect(
        AlertPushMapper.selectNewAlerts(
          hadBaseline: false,
          previousFingerprints: const {},
          next: next.map((item) => Map<String, dynamic>.from(item)).toList(),
          fingerprint: NotificationService.fingerprint,
          isUnread: (_) => true,
        ),
        isEmpty,
      );
    });

    test('the same alert is shown once', () {
      final shown = ShownPushRegistry();
      expect(shown.claim('id:2'), isTrue);
      expect(shown.claim('id:2'), isFalse);
    });
  });

  group('chat grouping', () {
    test('several messages from one conversation update a single notification',
        () {
      final threads = <String, ChatPushThread>{};
      final first = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey', messageId: 'm1'),
      );
      final second = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Are you available?', messageId: 'm2'),
      );
      final third = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Please check the project', messageId: 'm3'),
      );

      expect(first!.notificationId, third!.notificationId);
      expect(second!.notificationId, third.notificationId);
      expect(third.title, 'Rahul');
      expect(third.body, '3 new messages');
      expect(third.count, 3);
      expect(third.lines, [
        'Rahul: Hey',
        'Rahul: Are you available?',
        'Rahul: Please check the project',
      ]);
      expect(threads.length, 1);
    });

    test('different conversations stay in separate notifications', () {
      final threads = <String, ChatPushThread>{};
      final rahul = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey', messageId: 'm1'),
      );
      final neha = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat(
          'c2',
          'Site update',
          messageId: 'm2',
          senderName: 'Neha',
          senderId: '8',
        ),
      );

      expect(rahul!.notificationId, isNot(neha!.notificationId));
      expect(rahul.title, 'Rahul');
      expect(neha.title, 'Neha');
      expect(threads.keys, containsAll(['c1', 'c2']));
    });

    test('the sender is not notified and an open chat is not pushed', () {
      final threads = <String, ChatPushThread>{};
      expect(
        ChatPushGrouper.record(
          threads: threads,
          incoming: _chat('c1', 'Hey', fromMe: true, senderId: '5'),
        ),
        isNull,
      );
      expect(
        ChatPushGrouper.record(
          threads: threads,
          incoming: _chat('c1', 'Hey', senderId: '5', currentUserId: '5'),
        ),
        isNull,
      );

      ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey', messageId: 'm1'),
      );
      final cleared = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Next', openConversationId: 'c1'),
      );
      expect(cleared!.clearExisting, isTrue);
      expect(threads.containsKey('c1'), isFalse);
    });

    test('socket and FCM copies of the same line are not counted twice', () {
      final threads = <String, ChatPushThread>{};
      ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey', messageId: 'm1'),
      );
      final again = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey'),
      );
      expect(again!.body, 'Hey');
      expect(threads['c1']!.count, 1);
    });

    test('a repeated delivery of the same message does not increase the count',
        () {
      final threads = <String, ChatPushThread>{};
      ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey', messageId: 'm1'),
      );
      final again = ChatPushGrouper.record(
        threads: threads,
        incoming: _chat('c1', 'Hey', messageId: 'm1'),
      );
      expect(again!.body, 'Hey');
      expect(threads['c1']!.count, 1);
    });
  });

  group('notification tap targets', () {
    test('project, task, payment, approval and chat resolve to their screens',
        () {
      expect(
        NotificationTarget.resolve({
          'type': 'project',
          'project_id': '15',
          'project_name': 'Villa',
        }).kind,
        NotificationKind.project,
      );
      expect(
        NotificationTarget.resolve({
          'type': 'task',
          'task_id': '88',
        }).taskId,
        '88',
      );
      expect(
        NotificationTarget.resolve({
          'type': 'bill',
          'bill_name': 'Foundation',
        }).kind,
        NotificationKind.payment,
      );
      expect(
        NotificationTarget.resolve({
          'type': 'approval',
          'indent_id': '4',
          'body': 'Review and approve the indent',
        }).kind,
        NotificationKind.indentApproval,
      );
      final chat = NotificationTarget.resolve({
        'type': 'chat',
        'conversation_id': 'c1',
        'title': 'Rahul',
      });
      expect(chat.kind, NotificationKind.chat);
      expect(chat.conversationId, 'c1');

      final approved = NotificationTarget.resolve({
        'title': 'Indent update',
        'body':
            '10 bags Cement Indent for project Villa has been approved by Ana',
        'indent_id': '4',
        'project_id': '15',
      });
      expect(approved.kind, NotificationKind.indent);
      expect(approved.myIndents, isTrue);
      expect(approved.indentId, '4');

      final po = NotificationTarget.resolve({
        'type': 'approved_po',
        'po_number': 'PO-9',
        'project_id': '15',
      });
      expect(po.kind, NotificationKind.approvedPo);
      expect(po.poQuery, 'PO-9');
      expect(po.projectId, '15');
    });

    test('a terminated launch waits until the app is ready, then opens once',
        () {
      final queue = PushLaunchQueue();
      queue.stage({
        'type': 'task',
        'task_id': '88',
        'title': 'Task assigned',
      });
      expect(queue.take(), isNull);

      queue.ready = true;
      expect(queue.take()?['task_id'], '88');
      expect(queue.take(), isNull);
    });

    test('invalid targets are rejected', () {
      expect(
        NotificationTarget.resolve({'type': 'chat'}).reason,
        'missing_conversation',
      );
      expect(
        NotificationTarget.resolve({'type': 'project'}).reason,
        'missing_project',
      );
      expect(
        NotificationTarget.resolve({'title': 'Hello'}).kind,
        NotificationKind.none,
      );
      expect(
        NotificationTarget.taskListContains(
          [
            {'id': '1'},
            {'task_id': '88'},
          ],
          '88',
        ),
        isTrue,
      );
      expect(
        NotificationTarget.taskListContains(
          [
            {'id': '1'},
          ],
          '88',
        ),
        isFalse,
      );
      expect(
        NotificationTarget.userIsParticipant(
          [
            {'user_id': '5'},
            {'id': '9'},
          ],
          '9',
        ),
        isTrue,
      );
      expect(
        NotificationTarget.userIsParticipant(
          [
            {'user_id': '5'},
          ],
          '9',
        ),
        isFalse,
      );
    });

    test('push data strips secrets nested in the payload', () {
      final data = normalizePushData({
        'type': 'task',
        'task_id': '88',
        'api_token': 'nope',
        'payload': '{"title":"Task","phone":"999"}',
      });
      expect(data.containsKey('api_token'), isFalse);
      expect(data['title'], 'Task');
      expect(data.containsKey('phone'), isFalse);
    });
  });

  group('notification permission banner', () {
    test('banner is hidden only while permission is enabled', () {
      expect(
        NotificationPermissionPolicy.bannerVisible(permissionEnabled: true),
        isFalse,
      );
      expect(
        NotificationPermissionPolicy.bannerVisible(permissionEnabled: false),
        isTrue,
      );
      expect(
        NotificationPermissionPolicy.enableAction(),
        NotificationEnableAction.openSettings,
      );
      expect(
        NotificationPermissionPolicy.isEnabledStatusName('granted'),
        isTrue,
      );
      expect(
        NotificationPermissionPolicy.isEnabledStatusName('permanentlyDenied'),
        isFalse,
      );
      expect(
        NotificationPermissionPolicy.shouldRequestSystemDialog(
          permissionStatusName: 'denied',
        ),
        isTrue,
      );
      expect(
        NotificationPermissionPolicy.shouldRequestSystemDialog(
          permissionStatusName: 'granted',
        ),
        isFalse,
      );
      expect(
        NotificationPermissionPolicy.shouldRequestSystemDialog(
          permissionStatusName: 'permanentlyDenied',
        ),
        isFalse,
      );
      expect(
        NotificationPermissionPolicy.systemDialogWasPresented(
          granted: false,
          elapsedMilliseconds: 20,
        ),
        isFalse,
      );
      expect(
        NotificationPermissionPolicy.systemDialogWasPresented(
          granted: true,
          elapsedMilliseconds: 20,
        ),
        isTrue,
      );
    });

    testWidgets('dashboard banner follows the permission flag', (tester) async {
      final visible = ValueNotifier<bool>(false);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationPermissionBanner(
              visible: visible,
              onEnable: () => taps += 1,
            ),
          ),
        ),
      );
      expect(find.textContaining('Notifications are disabled'), findsNothing);

      visible.value = true;
      await tester.pump();
      expect(find.textContaining('Notifications are disabled'), findsOneWidget);
      expect(find.text('Enable Notifications'), findsOneWidget);

      await tester.tap(find.text('Enable Notifications'));
      await tester.pump();
      expect(taps, 1);

      visible.value = false;
      await tester.pump();
      expect(find.textContaining('Notifications are disabled'), findsNothing);
    });
  });
}

ChatPushIncoming _chat(
  String conversationId,
  String preview, {
  String? messageId,
  String senderName = 'Rahul',
  String senderId = '7',
  String currentUserId = '5',
  String? openConversationId,
  bool fromMe = false,
}) {
  return ChatPushIncoming(
    conversationId: conversationId,
    senderName: senderName,
    preview: preview,
    senderId: senderId,
    currentUserId: currentUserId,
    openConversationId: openConversationId,
    messageId: messageId,
    fromMe: fromMe,
  );
}

class _Posted {
  final Uri uri;
  final Map<String, String> fields;
  final Map<String, String> headers;
  _Posted(this.uri, this.fields, this.headers);
}

FcmTokenPoster _record(List<_Posted> calls) {
  return (uri, fields, headers) async {
    calls.add(_Posted(uri, fields, headers));
    return http.Response('{"success":true}', 200);
  };
}
