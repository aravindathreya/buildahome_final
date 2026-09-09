import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buildAhome/mobile_live_test_screen.dart';
import 'package:buildAhome/mobile_live_test_task_screen.dart';
import 'package:buildAhome/models/mobile_live_test.dart';
import 'package:buildAhome/services/mobile_live_test_access.dart';
import 'package:buildAhome/services/mobile_live_test_controller.dart';
import 'package:buildAhome/services/mobile_live_test_service.dart';
import 'package:buildAhome/services/mobile_live_test_storage.dart';

void main() {
  const superAdmin = MobileLiveTestAuthParams(
    userId: '29',
    apiToken: 'user-token',
    role: 'Super Admin',
  );

  MobileLiveTestService buildService({
    required http.Client client,
    MobileLiveTestStore? store,
    MobileLiveTestAuthParams auth = superAdmin,
  }) {
    return MobileLiveTestService(
      client: client,
      store: store ?? MemoryMobileLiveTestStore(),
      authParams: () async => auth,
      baseUrl: 'https://office.buildahome.in',
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'userId': '29',
      'api_token': 'user-token',
      'role': 'Super Admin',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> waitForTextContaining(WidgetTester tester, String text) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.textContaining(text).evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for text containing "$text"');
  }

  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(text).evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for "$text"');
  }

  Map<String, dynamic> openPayload({
    int itemRunId = 456,
    String name = 'Approve BOQ',
    String requiredDecision = 'yes_no',
    bool canComplete = true,
    bool mandatoryUploadsPending = false,
    List<Map<String, dynamic>>? options,
    List<Map<String, dynamic>>? actions,
    List<Map<String, dynamic>>? comments,
    Map<String, dynamic>? actionResponses,
    String blockReason = '',
  }) {
    return {
      'success': true,
      'test_execution': true,
      'test_mode': true,
      'run_id': 123,
      'item_run_id': itemRunId,
      'authenticated_user': {
        'user_id': 29,
        'name': 'Super Admin',
        'role': 'Super Admin',
      },
      'acting_user': {
        'id': 88,
        'name': 'QS Test User',
        'role': 'QS Engineer',
      },
      'task': {
        'name': name,
        'description': 'Review and approve the BOQ.',
        'instructions': 'Review and approve the BOQ.',
        'status': 'ready',
        'status_label': 'Ready',
        'role': 'QS Engineer',
        'can_complete': canComplete,
        'block_reason': blockReason,
        'mandatory_uploads_pending': mandatoryUploadsPending,
        'required_decision': requiredDecision,
        'options': options ??
            [
              {'decision': 'yes', 'label': 'Yes', 'kind': 'yes'},
              {'decision': 'no', 'label': 'No', 'kind': 'no'},
            ],
        'requirements': mandatoryUploadsPending
            ? [
                {
                  'type': 'mandatory_upload',
                  'message': 'Upload required documents first.',
                  'satisfied': false,
                },
              ]
            : [],
        'actions': actions ?? [],
        'action_responses': actionResponses ?? {},
        'comments': comments ?? [],
      },
    };
  }

  group('execution service', () {
    test('openTask calls dedicated /open API only', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      String? openedPath;
      final client = MockClient((request) async {
        openedPath = request.url.path;
        expect(request.method, 'GET');
        expect(openedPath, MobileLiveTestAccess.taskOpenPath(456));
        expect(request.url.path.contains('item-runs'), isFalse);
        expect(request.url.path.contains('get_tasks'), isFalse);
        expect(request.headers['X-Live-Test-Device-Token'], 'device-secret');
        return http.Response(
          jsonEncode(openPayload()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      final context = await service.openTask(456);
      expect(context.actingUser?.name, 'QS Test User');
      expect(context.authenticatedUser?.name, 'Super Admin');
      expect(context.task.name, 'Approve BOQ');
      expect(openedPath, isNotNull);
    });

    test('completeTask sends only allowed fields', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, MobileLiveTestAccess.taskCompletePath(456));
        expect(body!.containsKey('acting_user'), isFalse);
        expect(body!.containsKey('acting_user_id'), isFalse);
        expect(body!.containsKey('user_id'), isFalse);
        expect(body!['decision'], 'yes');
        expect(body!['comments'], 'Looks good');
        return http.Response(
          jsonEncode({
            'success': true,
            'test_execution': true,
            'run_id': 123,
            'item_run_id': 456,
            'acting_user': {'id': 88, 'name': 'QS Test User', 'role': 'QS Engineer'},
            'engine': 'complete_item_run',
            'status': 'completed',
            'decision': 'yes',
            'task_completed': true,
            'new_ready': [],
            'remaining_parallel': [{'item_run_id': 457}],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      final result = await service.completeTask(
        456,
        decision: 'yes',
        comment: 'Looks good',
      );
      expect(result.taskCompleted, isTrue);
      expect(result.engine, 'complete_item_run');
      expect(body, isNotNull);
    });

    test('approve and reject decisions are forwarded', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final decisions = <String>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        decisions.add(body['decision'] as String);
        return http.Response(
          jsonEncode({
            'success': true,
            'test_execution': true,
            'task_completed': true,
            'status': 'completed',
            'decision': body['decision'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      await service.completeTask(456, decision: 'approve');
      await service.completeTask(456, decision: 'reject', comment: 'redo');
      expect(decisions, ['approve', 'reject']);
    });

    test('plain completion sends only optional comments', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'test_execution': true,
            'task_completed': true,
            'status': 'completed',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      await service.completeTask(456, comment: 'Done');
      expect(body!.containsKey('decision'), isFalse);
      expect(body!['comments'], 'Done');
    });
  });

  group('task detail model', () {
    test('mandatory upload requirement is supported, completion stays blocked',
        () {
      final task = MobileLiveTestTaskDetail.fromJson({
        'name': 'Upload docs',
        'can_complete': false,
        'mandatory_uploads_pending': true,
        'requirements': [
          {
            'type': 'mandatory_upload',
            'message': 'Upload required documents first.',
            'satisfied': false,
          },
        ],
        'actions': [
          {'id': 'u1', 'type': 'upload', 'label': 'Upload documents'},
        ],
      });
      expect(task.hasUnsupportedRequirements, isFalse);
      expect(task.interactiveActions.length, 1);
      expect(task.showPlainComplete, isFalse);
      expect(task.unsupportedMessage, contains('required uploads'));
    });

    test('percent upload action exposes min next percent validation', () {
      final action = MobileLiveTestWorkflowAction.fromJson({
        'id': 'u1',
        'type': 'upload',
        'add_percent_to_task': true,
        'current_percent': 40,
        'label': 'Add % progress',
      });
      expect(action.addPercentToTask, isTrue);
      expect(action.minNextPercent, 41);
      expect(action.validatePercentInput('50', 40), isNull);
      expect(action.validatePercentInput('', 40), isNotNull);
      expect(action.validatePercentInput('40', 40), isNotNull);
    });
  });

  group('Mobile Live Test task screen', () {
    testWidgets('live-test list shows inline task card with actions',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == MobileLiveTestAccess.sessionPath) {
          return http.Response(
            jsonEncode({
              'success': true,
              'test_mode': true,
              'device': {'connection_label': 'Connected'},
              'active_run': {'run_id': 123, 'workflow_name': 'TEST-001'},
              'tasks': [
                {
                  'item_run_id': 456,
                  'name': 'Approve BOQ',
                  'role': 'QS Engineer',
                  'assigned_user_name': 'QS Test User',
                  'status': 'ready',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(456)) {
          return http.Response(
            jsonEncode(openPayload()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
        heartbeatInterval: const Duration(hours: 1),
        pollInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      controller.stopSync();
      await waitForText(tester, 'Approve BOQ');
      await waitForTextContaining(tester, 'mapped test user');
      expect(find.textContaining('mapped test user'), findsOneWidget);
      expect(find.text('My tasks'), findsWidgets);
      expect(
        paths.any((path) => path.contains('/mobile-live-test/tasks/456/open')),
        isTrue,
      );
      expect(paths.any((path) => path.contains('item-runs')), isFalse);
      controller.dispose();
    });

    testWidgets('task detail screen still renders execution body', (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(456)) {
          return http.Response(
            jsonEncode(openPayload()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
        ),
      ));
      await waitForTextContaining(tester, 'Acting as');
      expect(find.text('MOBILE LIVE TEST'), findsOneWidget);
    });

    testWidgets('acting user is shown and cannot be changed', (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(openPayload()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
        ),
      ));
      await waitForTextContaining(tester, 'Acting as');
      expect(find.text('QS Test User'), findsWidgets);
      expect(find.textContaining('Super Admin'), findsWidgets);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.textContaining('Comment (optional)'), findsOneWidget);
    });

    testWidgets('yes button sends decision=yes and refreshes list',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      var completeCalls = 0;
      var sessionCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(456)) {
          return http.Response(
            jsonEncode(openPayload()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskCompletePath(456)) {
          completeCalls += 1;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['decision'], 'yes');
          return http.Response(
            jsonEncode({
              'success': true,
              'test_execution': true,
              'task_completed': true,
              'status': 'completed',
              'message': 'Task completed through the real workflow engine.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.sessionPath) {
          sessionCalls += 1;
          return http.Response(
            jsonEncode({
              'success': true,
              'test_mode': true,
              'active_run': {'run_id': 123},
              'tasks': [
                {
                  'item_run_id': 457,
                  'name': 'Approve Drawing',
                  'role': 'Site Engineer',
                  'assigned_user_name': 'Site Engineer Test User',
                  'status': 'ready',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
      )..enabled = true;

      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
          listController: controller,
        ),
      ));
      await waitForText(tester, 'Yes');
      await tester.tap(find.text('Yes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(completeCalls, 1);
      expect(sessionCalls, greaterThanOrEqualTo(1));
      controller.dispose();
      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('approve/reject buttons render from backend options',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(openPayload(
            requiredDecision: 'approve_reject',
            options: [
              {'decision': 'approve', 'label': 'Approve', 'kind': 'yes'},
              {'decision': 'reject', 'label': 'Reject', 'kind': 'no'},
            ],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
        ),
      ));
      await waitForText(tester, 'Approve');
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('mandatory upload shows upload UI and blocks completion',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(openPayload(
            canComplete: false,
            mandatoryUploadsPending: true,
            options: [],
            actions: [
              {'id': 'u1', 'type': 'upload', 'label': 'Upload documents'},
            ],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
        ),
      ));
      await waitForText(tester, 'Upload documents');
      await tester.tap(find.text('Upload documents'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await waitForText(tester, 'UPLOAD');
      expect(find.widgetWithText(ElevatedButton, 'Complete task'), findsNothing);
      expect(find.text('Yes'), findsNothing);
    });

    testWidgets('starter kit task shows both options until one is submitted',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(openPayload(
            name: 'Indent for starter kit',
            canComplete: false,
            options: [],
            actions: [
              {
                'id': 'indent-1',
                'type': 'text_list',
                'label': 'Request for new starter kit',
                'exclusive_group': 'indent-or-shift',
                'exclusive_choice': 'indent',
                'items': [
                  {'id': 'l1', 'text': 'Cement bags'},
                ],
              },
              {
                'id': 'shift-1',
                'type': 'kyp_material_shift',
                'label': 'Shift material from labour shed',
                'exclusive_group': 'indent-or-shift',
                'exclusive_choice': 'shift',
              },
            ],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
        ),
      ));
      await waitForTextContaining(tester, 'Request for new starter kit');
      expect(find.textContaining('Request for new starter kit'), findsOneWidget);
      expect(
        find.textContaining('Shift material from labour shed'),
        findsOneWidget,
      );
    });

    testWidgets('starter kit hides shift option after indent is submitted',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(openPayload(
            name: 'Indent for starter kit',
            canComplete: false,
            options: [],
            actionResponses: {
              'indent-1': {'submitted': true},
            },
            actions: [
              {
                'id': 'indent-1',
                'type': 'text_list',
                'label': 'Request for new starter kit',
                'exclusive_group': 'indent-or-shift',
                'exclusive_choice': 'indent',
              },
              {
                'id': 'shift-1',
                'type': 'kyp_material_shift',
                'label': 'Shift material from labour shed',
                'exclusive_group': 'indent-or-shift',
                'exclusive_choice': 'shift',
              },
            ],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
        ),
      ));
      await waitForTextContaining(tester, 'Request for new starter kit');
      expect(find.textContaining('Request for new starter kit'), findsOneWidget);
      expect(find.textContaining('Shift material from labour shed'), findsNothing);
    });

    testWidgets('parallel tasks remain visible on list screen', (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        if (request.url.path == MobileLiveTestAccess.sessionPath) {
          return http.Response(
            jsonEncode({
              'success': true,
              'test_mode': true,
              'active_run': {'run_id': 123, 'workflow_name': 'TEST-001'},
              'tasks': [
                {
                  'item_run_id': 456,
                  'name': 'Approve BOQ',
                  'role': 'QS Engineer',
                  'assigned_user_name': 'QS Test User',
                  'status': 'ready',
                },
                {
                  'item_run_id': 457,
                  'name': 'Approve Drawing',
                  'role': 'Site Engineer',
                  'assigned_user_name': 'Site Engineer Test User',
                  'status': 'ready',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(456)) {
          return http.Response(
            jsonEncode(openPayload(itemRunId: 456)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(457)) {
          return http.Response(
            jsonEncode(openPayload(
              itemRunId: 457,
              name: 'Approve Drawing',
              options: [
                {'decision': 'yes', 'label': 'Yes', 'kind': 'yes'},
                {'decision': 'no', 'label': 'No', 'kind': 'no'},
              ],
            )),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
        heartbeatInterval: const Duration(hours: 1),
        pollInterval: const Duration(hours: 1),
      )..enabled = true;
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      controller.stopSync();
      await waitForText(tester, 'Approve BOQ');
      expect(find.text('Approve BOQ'), findsWidgets);
      expect(find.text('Approve Drawing'), findsOneWidget);
      controller.dispose();
    });
  });

  group('action APIs', () {
    test('submitJsonAction uses live-test checklist path', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      String? path;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        path = request.url.path;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'test_execution': true,
            'message': 'Checklist saved',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      final result = await service.submitJsonAction(
        456,
        'checklist',
        payload: {
          'action_id': 'chk-1',
          'responses': {'a': true},
        },
      );
      expect(result.success, isTrue);
      expect(path, MobileLiveTestAccess.taskActionPath(456, 'checklist'));
      expect(body!['action_id'], 'chk-1');
      expect(body!.containsKey('acting_user'), isFalse);
    });

    test('addTaskComment uses live-test comments path', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({
            'success': true,
            'test_execution': true,
            'comment_id': 9,
            'comment': {'id': 9, 'body': 'Hello', 'author_name': 'QS Test User'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      final comment = await service.addTaskComment(456, 'Hello');
      expect(path, MobileLiveTestAccess.taskActionPath(456, 'comments'));
      expect(comment.body, 'Hello');
    });

    test('resolveActionSubmitPath never returns production item-runs', () {
      final path = MobileLiveTestAccess.resolveActionSubmitPath(
        456,
        {'type': 'upload', 'id': 'u1'},
      );
      expect(path.contains('mobile-live-test'), isTrue);
      expect(path.contains('item-runs'), isFalse);
    });
  });

  group('workflow task coverage', () {
    const interactiveActionTypes = [
      'upload',
      'update_status',
      'yes_no',
      'checklist',
      'user_checklist',
      'user_checklist_followup',
      'slot_selection',
      'slot_confirmation',
      'kyp_material_shift',
      'text_list',
      'picture_choice_list',
      'picture_choice_pick',
      'complete_button',
      'view_prior_response',
    ];

    test('every interactive workflow action type resolves a live-test path', () {
      for (final type in interactiveActionTypes) {
        final path = MobileLiveTestAccess.resolveActionSubmitPath(
          456,
          {'type': type, 'id': 'a1'},
        );
        if (type == 'yes_no' ||
            type == 'complete_button' ||
            (type == 'view_prior_response')) {
          continue;
        }
        expect(
          path.contains('mobile-live-test'),
          isTrue,
          reason: 'missing live-test path for $type',
        );
        expect(path.contains('item-runs'), isFalse, reason: type);
      }
    });

    test('read-only workflow action types are not interactive', () {
      for (final type in MobileLiveTestWorkflowAction.readOnlyTypes) {
        final action = MobileLiveTestWorkflowAction.fromJson({'type': type});
        expect(action.isInteractive, isFalse, reason: type);
      }
    });

    test('each interactive type is recognized as interactive when configured', () {
      for (final type in interactiveActionTypes) {
        final raw = <String, dynamic>{
          'id': 'a1',
          'type': type,
          if (type == 'view_prior_response') 'enable_approve': true,
        };
        final action = MobileLiveTestWorkflowAction.fromJson(raw);
        expect(action.isInteractive, isTrue, reason: type);
      }
    });

    test('starter kit indent and labour shed shift hide each other after selection',
        () {
      final indent = MobileLiveTestWorkflowAction.fromJson({
        'id': 'indent-1',
        'type': 'text_list',
        'label': 'Request for new starter kit',
        'exclusive_group': 'indent-or-shift',
        'exclusive_choice': 'indent',
        'exclusive_hides_on_select': true,
      });
      final shift = MobileLiveTestWorkflowAction.fromJson({
        'id': 'shift-1',
        'type': 'kyp_material_shift',
        'label': 'Shift material from labour shed',
        'exclusive_group': 'indent-or-shift',
        'exclusive_choice': 'shift',
        'exclusive_hides_on_select': true,
      });
      final actions = [indent, shift];

      expect(
        MobileLiveTestWorkflowAction.filterExclusiveActions(actions, const {}),
        hasLength(2),
      );

      final afterIndent = MobileLiveTestWorkflowAction.filterExclusiveActions(
        actions,
        {
          'indent-1': {'submitted': true},
        },
      );
      expect(afterIndent, hasLength(1));
      expect(afterIndent.first.exclusiveChoice, 'indent');

      final afterShift = MobileLiveTestWorkflowAction.filterExclusiveActions(
        actions,
        {
          'shift-1': {'materials': [{'name': 'Cement'}]},
        },
      );
      expect(afterShift, hasLength(1));
      expect(afterShift.first.exclusiveChoice, 'shift');
    });

    test('task detail interactiveActions respects exclusive filtering', () {
      final task = MobileLiveTestTaskDetail.fromJson({
        'name': 'Indent for starter kit',
        'can_complete': false,
        'action_responses': {
          'indent-1': {'submitted': true},
        },
        'actions': [
          {
            'id': 'indent-1',
            'type': 'text_list',
            'label': 'Request for new starter kit',
            'exclusive_group': 'indent-or-shift',
            'exclusive_choice': 'indent',
          },
          {
            'id': 'shift-1',
            'type': 'kyp_material_shift',
            'label': 'Shift material',
            'exclusive_group': 'indent-or-shift',
            'exclusive_choice': 'shift',
          },
        ],
      });
      expect(task.interactiveActions, hasLength(1));
      expect(task.interactiveActions.first.type, 'text_list');
    });

    test('session dedupes tasks by node_key keeping first ready task', () {
      final session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'tasks': [
          {
            'item_run_id': 100,
            'node_key': '21',
            'name': 'Indent for starter kit',
            'status': 'ready',
          },
          {
            'item_run_id': 101,
            'node_key': '21',
            'name': 'Indent for starter kit',
            'status': 'ready',
          },
          {
            'item_run_id': 200,
            'node_key': '7',
            'name': 'Start labour shed',
            'status': 'ready',
          },
        ],
      });
      expect(session.dedupedTasks, hasLength(2));
      expect(session.dedupedTasks.first.itemRunId, 100);
      expect(session.dedupedTasks.last.name, 'Start labour shed');
    });
  });

  group('post-completion speed', () {
    test('dismissTask removes completed task from visible list immediately', () {
      final controller = MobileLiveTestController(
        service: MobileLiveTestService(
          client: MockClient((_) async => http.Response('{}', 500)),
          store: MemoryMobileLiveTestStore(),
          authParams: () async => superAdmin,
        ),
      )..enabled = true;

      controller.session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'tasks': [
          {
            'item_run_id': 456,
            'node_key': '1',
            'name': 'Approve BOQ',
            'status': 'ready',
          },
          {
            'item_run_id': 457,
            'node_key': '2',
            'name': 'Approve Drawing',
            'status': 'ready',
          },
        ],
      });

      expect(controller.visibleTasks, hasLength(2));
      controller.dismissTask(456);
      expect(controller.visibleTasks, hasLength(1));
      expect(controller.visibleTasks.first.itemRunId, 457);
      controller.dispose();
    });

    test('applyCompletionResult adds new_ready tasks immediately', () {
      final controller = MobileLiveTestController(
        service: MobileLiveTestService(
          client: MockClient((_) async => http.Response('{}', 500)),
          store: MemoryMobileLiveTestStore(),
          authParams: () async => superAdmin,
        ),
      )..enabled = true;

      controller.session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'tasks': [
          {
            'item_run_id': 456,
            'node_key': '1',
            'name': 'Approve BOQ',
            'status': 'ready',
          },
        ],
      });

      controller.applyCompletionResult(
        const MobileLiveTestCompletionResult(
          success: true,
          taskCompleted: true,
          itemRunId: 456,
          newReady: [
            {
              'item_run_id': 789,
              'node_key': '3',
              'name': 'Site marking',
              'status': 'ready',
            },
          ],
        ),
      );

      expect(controller.visibleTasks, hasLength(1));
      expect(controller.visibleTasks.first.itemRunId, 789);
      controller.dispose();
    });

    testWidgets('all assigned live-test tasks appear in My Tasks',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      var openCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == MobileLiveTestAccess.sessionPath) {
          return http.Response(
            jsonEncode({
              'success': true,
              'test_mode': true,
              'active_run': {'run_id': 123, 'workflow_name': 'TEST-001'},
              'tasks': [
                {
                  'item_run_id': 456,
                  'name': 'Approve BOQ',
                  'role': 'QS Engineer',
                  'assigned_user_name': 'QS Test User',
                  'status': 'ready',
                },
                {
                  'item_run_id': 457,
                  'name': 'Approve Drawing',
                  'role': 'Site Engineer',
                  'assigned_user_name': 'Site Engineer Test User',
                  'status': 'ready',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(456)) {
          openCalls += 1;
          return http.Response(
            jsonEncode(openPayload(itemRunId: 456)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(457)) {
          openCalls += 1;
          return http.Response(
            jsonEncode(openPayload(
              itemRunId: 457,
              name: 'Approve Drawing',
            )),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
        heartbeatInterval: const Duration(hours: 1),
        pollInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      controller.stopSync();
      await waitForText(tester, 'Approve BOQ');
      expect(find.text('Approve Drawing'), findsOneWidget);
      expect(openCalls, greaterThanOrEqualTo(1));
      expect(find.text('Pending (2)'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('completed task disappears before session refresh returns',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      var sessionCalls = 0;
      var completeCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == MobileLiveTestAccess.taskOpenPath(456)) {
          return http.Response(
            jsonEncode(openPayload()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.taskCompletePath(456)) {
          completeCalls += 1;
          return http.Response(
            jsonEncode({
              'success': true,
              'test_execution': true,
              'task_completed': true,
              'status': 'completed',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == MobileLiveTestAccess.sessionPath) {
          sessionCalls += 1;
          return http.Response(
            jsonEncode({
              'success': true,
              'test_mode': true,
              'active_run': {'run_id': 123},
              'tasks': [
                {
                  'item_run_id': 457,
                  'node_key': '2',
                  'name': 'Approve Drawing',
                  'role': 'Site Engineer',
                  'assigned_user_name': 'Site Engineer Test User',
                  'status': 'ready',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
      )..enabled = true;
      controller.session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'active_run': {'run_id': 123},
        'tasks': [
          {
            'item_run_id': 456,
            'node_key': '1',
            'name': 'Approve BOQ',
            'role': 'QS Engineer',
            'assigned_user_name': 'QS Test User',
            'status': 'ready',
          },
          {
            'item_run_id': 457,
            'node_key': '2',
            'name': 'Approve Drawing',
            'role': 'Site Engineer',
            'assigned_user_name': 'Site Engineer Test User',
            'status': 'ready',
          },
        ],
      });

      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestTaskScreen(
          itemRunId: 456,
          service: buildService(client: client, store: store),
          listController: controller,
        ),
      ));
      await waitForText(tester, 'Yes');
      expect(controller.visibleTasks, hasLength(2));

      await tester.tap(find.text('Yes'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (controller.visibleTasks.length == 1) break;
      }

      expect(completeCalls, 1);
      expect(controller.visibleTasks, hasLength(1));
      expect(controller.visibleTasks.first.name, 'Approve Drawing');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (sessionCalls > 0) break;
      }
      expect(sessionCalls, greaterThanOrEqualTo(1));
      controller.dispose();
      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('workflow action completion APIs', () {
    test('update_status action posts to status path', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({'success': true, 'test_execution': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      await service.submitJsonAction(
        456,
        'status',
        payload: {'action_id': 'st1', 'status': 'finished'},
      );
      expect(path, MobileLiveTestAccess.taskActionPath(456, 'status'));
    });

    test('text_list action posts to text-list path', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({'success': true, 'test_execution': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      await service.submitJsonAction(
        456,
        'text-list',
        payload: {
          'action_id': 'tl1',
          'lines': [
            {'id': 'l1', 'quantity': '10'},
          ],
        },
      );
      expect(path, MobileLiveTestAccess.taskActionPath(456, 'text-list'));
    });

    test('material-shift action posts to material-shift path', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({'success': true, 'test_execution': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      final action = MobileLiveTestWorkflowAction.fromJson({
        'id': 'ms1',
        'type': 'kyp_material_shift',
      });
      await service.submitWorkflowAction(
        456,
        action,
        jsonPayload: {'action_id': 'ms1'},
      );
      expect(path, MobileLiveTestAccess.taskActionPath(456, 'material-shift'));
    });

    test('picture-choice actions resolve dedicated paths', () {
      expect(
        MobileLiveTestAccess.resolveActionSubmitPath(
          456,
          {'type': 'picture_choice_list', 'id': 'pc1'},
        ),
        MobileLiveTestAccess.taskActionPath(456, 'picture-choice-list'),
      );
      expect(
        MobileLiveTestAccess.resolveActionSubmitPath(
          456,
          {'type': 'picture_choice_pick', 'id': 'pc2'},
        ),
        MobileLiveTestAccess.taskActionPath(456, 'picture-choice-pick'),
      );
    });
  });

  group('production isolation', () {
    test('live-test paths never include production item-run APIs', () {
      expect(MobileLiveTestAccess.productionTasksPath, '/API/get_tasks');
      expect(
        MobileLiveTestAccess.taskOpenPath(1),
        '/API/workflow/mobile-live-test/tasks/1/open',
      );
      expect(
        MobileLiveTestAccess.taskCompletePath(1),
        '/API/workflow/mobile-live-test/tasks/1/complete',
      );
      expect(
        MobileLiveTestAccess.taskOpenPath(1)
            .contains(MobileLiveTestAccess.productionItemRunCompletePath),
        isFalse,
      );
    });
  });
}
