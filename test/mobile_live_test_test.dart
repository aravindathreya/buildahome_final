import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buildAhome/MyTasksScreen.dart';
import 'package:buildAhome/mobile_live_test_screen.dart';
import 'package:buildAhome/models/mobile_live_test.dart';
import 'package:buildAhome/services/mobile_live_test_access.dart';
import 'package:buildAhome/services/mobile_live_test_controller.dart';
import 'package:buildAhome/services/mobile_live_test_service.dart';
import 'package:buildAhome/services/mobile_live_test_storage.dart';
import 'package:buildAhome/services/mobile_live_test_workflow.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'userId': '12',
      'api_token': 'user-token',
      'role': 'Super Admin',
    });
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }
  const superAdmin = MobileLiveTestAuthParams(
    userId: '12',
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

  group('authorization', () {
    test('normal roles cannot enable Test Mode', () {
      for (final role in [
        'Client',
        'Site Engineer',
        'QS Engineer',
        'Admin',
        'Project Manager',
        '',
        null,
      ]) {
        expect(
          MobileLiveTestAccess.canEnable(role),
          isFalse,
          reason: 'role=$role',
        );
      }
    });

    test('authorized Super Admin can enable Test Mode', () {
      expect(MobileLiveTestAccess.canEnable('Super Admin'), isTrue);
    });

    test('production item-run URLs rewrite onto live-test task APIs', () {
      expect(
        MobileLiveTestAccess.rewriteProductionWorkflowUrl(
          'https://office.buildahome.in/API/workflow/item-runs/456/actions',
        ),
        'https://office.buildahome.in/API/workflow/mobile-live-test/tasks/456/open',
      );
      expect(
        MobileLiveTestAccess.rewriteProductionWorkflowUrl(
          'https://office.buildahome.in/API/workflow/item-runs/456/complete',
        ),
        'https://office.buildahome.in/API/workflow/mobile-live-test/tasks/456/complete',
      );
      expect(
        MobileLiveTestAccess.rewriteProductionWorkflowUrl(
          'https://office.buildahome.in/API/workflow/item-runs/456/upload',
        ),
        'https://office.buildahome.in/API/workflow/mobile-live-test/tasks/456/upload',
      );
    });

    test('submit_url from the server is used when it is a live-test path', () {
      expect(
        MobileLiveTestAccess.resolveActionSubmitPath(456, {
          'type': 'upload',
          'submit_url':
              '/API/workflow/mobile-live-test/tasks/456/upload',
        }),
        '/API/workflow/mobile-live-test/tasks/456/upload',
      );
      expect(
        MobileLiveTestAccess.resolveActionSubmitPath(456, {
          'type': 'upload',
          'submit_url':
              'https://office.buildahome.in/API/workflow/item-runs/456/upload',
        }),
        '/API/workflow/mobile-live-test/tasks/456/upload',
      );
    });
  });

  group('API isolation', () {
    test('live-test APIs never use production get_tasks', () {
      expect(MobileLiveTestAccess.productionTasksPath, '/API/get_tasks');
      expect(MobileLiveTestAccess.registerPath.contains('get_tasks'), isFalse);
      expect(MobileLiveTestAccess.heartbeatPath.contains('get_tasks'), isFalse);
      expect(MobileLiveTestAccess.sessionPath.contains('get_tasks'), isFalse);
      expect(MobileLiveTestAccess.tasksPath.contains('get_tasks'), isFalse);
      expect(
        MobileLiveTestAccess.sessionPath,
        '/API/workflow/mobile-live-test/session',
      );
    });
  });

  group('session parsing', () {
    test('no assigned run shows a waiting state', () {
      final session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'active_run': null,
        'tasks': [],
      });
      expect(session.isWaitingForAssignment, isTrue);
      expect(session.hasAssignedRun, isFalse);
      expect(session.tasks, isEmpty);
    });

    test('only assigned live-test tasks are displayed', () {
      final session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'active_run': {
          'run_id': 1,
          'workflow_name': 'TEST-001',
          'status': 'running',
        },
        'tasks': [
          {
            'name': 'Approve BOQ',
            'role': 'QS',
            'assigned_user_name': 'QS Test User',
            'status': 'ready',
          },
          {
            'name': 'Approve Drawing',
            'role': 'Site Engineer',
            'assigned_user_name': 'Site Engineer Test User',
            'status': 'ready',
          },
        ],
        'other_runs': [
          {'run_id': 99, 'workflow_name': 'Someone else'},
        ],
      });
      expect(session.activeRun!.displayLabel, 'TEST-001');
      expect(session.tasks.map((t) => t.name), [
        'Approve BOQ',
        'Approve Drawing',
      ]);
      expect(session.tasks, hasLength(2));
    });

    test('hides info_only reminder tasks', () {
      final session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'skip_project_gates': true,
        'active_run': {'run_id': 1, 'workflow_name': 'TEST-001'},
        'tasks': [
          {
            'item_run_id': 10,
            'name': 'Complete excavation',
            'status': 'ready',
          },
          {
            'item_run_id': 11,
            'name': 'Reminder',
            'status': 'ready',
            'info_only': true,
          },
        ],
      });
      expect(session.skipProjectGates, isTrue);
      expect(session.dedupedTasks.map((t) => t.name), ['Complete excavation']);
    });
  });

  group('skip project gates', () {
    test('detects Test Mode from session and open-task flags', () {
      expect(
        MobileLiveTestWorkflow.skipProjectGates({'skip_project_gates': true}),
        isTrue,
      );
      expect(
        MobileLiveTestWorkflow.skipProjectGates({'test_mode': true}),
        isTrue,
      );
      expect(
        MobileLiveTestWorkflow.skipProjectGates({'test_execution': true}),
        isTrue,
      );
      expect(
        MobileLiveTestWorkflow.skipProjectGates({
          'task': {'skip_project_gates': true},
        }),
        isTrue,
      );
      expect(MobileLiveTestWorkflow.skipProjectGates({'id': 1}), isFalse);
    });

    test('does not re-block delay, indent PH, or missing site', () {
      final task = MobileLiveTestWorkflow.applySkipProjectGates({
        'mobile_live_test': true,
        'workflow_delay_gate': {'is_delay_gated': true, 'seconds_remaining': 99},
        'indent_reason_blocks_complete': true,
        'can_complete_workflow_task': false,
        'can_update_workflow_task': false,
        'status': 'scheduled',
        'workflow_actions': [
          {
            'type': 'delay_timer',
            'blocked': true,
            'blocked_message': 'Waiting to start',
          },
          {
            'type': 'upload',
            'require_near_site': true,
            'require_gps_for_upload': true,
            'site_location_available': false,
            'blocked': true,
            'blocked_message': 'You must be at the project site',
          },
          {
            'type': 'upload',
            'id': 'step_2',
            'blocked': true,
            'blocked_message': 'Complete the previous upload first',
          },
        ],
      });
      expect(isWorkflowDelayGated(task), isFalse);
      expect(isIndentReasonBlockingComplete(task), isFalse);
      expect(canUpdateWorkflowTask(task), isTrue);
      expect(canCompleteWorkflowTask(task), isTrue);
      expect(task['workflow_status_label'], 'Pending');
      final actions = task['workflow_actions'] as List;
      expect(actions.any((a) => a['type'] == 'delay_timer'), isFalse);
      expect(actions.first['require_near_site'], isFalse);
      expect(actions.first['blocked'], isFalse);
      expect(actions.last['blocked'], isTrue);
    });

    test('still blocks complete when mandatory uploads are pending', () {
      final task = MobileLiveTestWorkflow.applySkipProjectGates({
        'mobile_live_test': true,
        'mandatory_uploads_pending': true,
        'workflow_mandatory_upload_block_msg': 'Upload the site photo first.',
        'can_complete_workflow_task': false,
      });
      expect(canCompleteWorkflowTask(task), isFalse);
      expect(canUpdateWorkflowTask(task), isTrue);
    });

    test('recognizes indent creation as a skipped project gate', () {
      expect(
        MobileLiveTestWorkflow.looksLikeSkippedProjectGate(
          message: 'A project is required to create an indent',
          actionType: 'text_list',
        ),
        isTrue,
      );
      expect(
        MobileLiveTestWorkflow.submitPayloadFlags({
          'mobile_live_test': true,
        })['skip_indent_creation'],
        isTrue,
      );
      expect(
        MobileLiveTestWorkflow.submitPayloadFlags({'id': 1}),
        isEmpty,
      );
    });
  });

  group('secure device credentials', () {
    test('registration persists device_token in the store', () async {
      final store = MemoryMobileLiveTestStore();
      final client = MockClient((request) async {
        expect(request.url.path, MobileLiveTestAccess.registerPath);
        expect(request.method, 'POST');
        expect(request.url.queryParameters['user_id'], '12');
        expect(request.headers['X-Api-Token'], 'user-token');
        expect(request.url.queryParameters.containsKey('impersonate'), isFalse);
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'device': {
              'public_id': 'abc123',
              'display_name': 'Android Test Device',
              'device_token': 'once-only-token',
              'enabled': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = buildService(client: client, store: store);
      final device = await service.enable(displayName: 'Android Test Device');
      expect(device.deviceToken, 'once-only-token');
      expect(await store.hasCredentials(), isTrue);
      expect(await store.readDeviceToken(), 'once-only-token');
      expect(await store.readPublicId(), 'abc123');
    });

    test('non Super Admin cannot register a device', () async {
      final store = MemoryMobileLiveTestStore();
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 500);
      });
      final service = buildService(
        client: client,
        store: store,
        auth: const MobileLiveTestAuthParams(
          userId: '9',
          apiToken: 'tok',
          role: 'Site Engineer',
        ),
      );
      await expectLater(
        service.enable(),
        throwsA(isA<MobileLiveTestException>().having(
          (e) => e.isPermissionDenied,
          'isPermissionDenied',
          isTrue,
        )),
      );
      expect(called, isFalse);
      expect(await store.hasCredentials(), isFalse);
    });

    test('403 from backend does not persist credentials', () async {
      final store = MemoryMobileLiveTestStore();
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'Only Super Admin can register or manage Test Devices.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = buildService(client: client, store: store);
      await expectLater(
        service.enable(),
        throwsA(isA<MobileLiveTestException>()),
      );
      expect(await store.hasCredentials(), isFalse);
    });

    test('disabling Test Mode clears credentials locally', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'secret',
        publicId: 'dev-1',
      );
      final service = buildService(
        client: MockClient((request) async => http.Response('{}', 500)),
        store: store,
      );
      await service.disable();
      expect(await store.hasCredentials(), isFalse);
      expect(await store.readDeviceToken(), isNull);
    });
  });

  group('assigned session retrieval', () {
    test('fetches only this device session and assigned tasks', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        expect(request.url.path, MobileLiveTestAccess.sessionPath);
        expect(request.url.queryParameters['device_token'], 'device-secret');
        expect(
          request.headers['X-Live-Test-Device-Token'],
          'device-secret',
        );
        expect(request.url.path.contains('get_tasks'), isFalse);
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'device': {
              'public_id': 'dev-1',
              'connection_status': 'connected',
              'connection_label': 'Connected',
            },
            'active_run': {
              'run_id': 44,
              'workflow_name': 'TEST-001',
            },
            'tasks': [
              {
                'name': 'Approve BOQ',
                'role': 'QS',
                'assigned_user_name': 'QS Test User',
                'status': 'ready',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final session = await buildService(client: client, store: store)
          .fetchSession();
      expect(session.activeRun!.displayLabel, 'TEST-001');
      expect(session.tasks.single.name, 'Approve BOQ');
    });
  });

  group('controller polling', () {
    test('heartbeat and polling stop when Test Mode is inactive', () async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'device': {
              'connection_status': 'connected',
              'connection_label': 'Connected',
            },
            'active_run': null,
            'tasks': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
        heartbeatInterval: const Duration(hours: 1),
        pollInterval: const Duration(hours: 1),
      );
      controller.enabled = true;
      controller.startSync();
      expect(controller.isSyncActive, isTrue);
      await Future<void>.delayed(Duration.zero);
      final whileActive = calls;
      expect(whileActive, greaterThan(0));
      controller.stopSync();
      expect(controller.isSyncActive, isFalse);
      await controller.disable();
      expect(controller.enabled, isFalse);
      expect(await store.hasCredentials(), isFalse);
      final afterStop = calls;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, afterStop);
      controller.dispose();
    });
  });

  group('Mobile Live Test screen', () {
    testWidgets('normal mode does not show live-test tasks before enable',
        (tester) async {
      final controller = MobileLiveTestController(
        service: buildService(
          client: MockClient((request) async => http.Response('{}', 500)),
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      expect(find.text('Enable Test Mode'), findsOneWidget);
      expect(find.text('ACTIVE TASKS'), findsNothing);
      expect(find.text('Approve BOQ'), findsNothing);
      controller.dispose();
    });

    testWidgets('waiting state when no run is assigned', (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'device': {
              'connection_status': 'connected',
              'connection_label': 'Connected',
            },
            'active_run': null,
            'tasks': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      expect(find.text('Mobile Test Mode Enabled'), findsOneWidget);
      expect(
        find.text('Waiting for a Mobile Live Test to be assigned.'),
        findsOneWidget,
      );
      expect(find.text('ACTIVE TASKS'), findsNothing);
      controller.dispose();
    });

    testWidgets('shows only assigned live-test tasks', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'device': {
              'connection_status': 'connected',
              'connection_label': 'Connected',
            },
            'active_run': {
              'run_id': 1,
              'workflow_name': 'TEST-001',
            },
            'tasks': [
              {
                'item_run_id': 456,
                'name': 'Approve BOQ',
                'role': 'QS',
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
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Approve BOQ'), findsOneWidget);
      expect(find.text('QS Test User'), findsOneWidget);
      expect(find.text('Approve Drawing'), findsOneWidget);
      expect(find.textContaining('Site Engineer Test User'), findsOneWidget);
      expect(find.text('Auto Run'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.textContaining('Status:'), findsWidgets);
      controller.dispose();
    });

    testWidgets('unauthorized users cannot enable Test Mode', (tester) async {
      final controller = MobileLiveTestController(
        service: buildService(
          client: MockClient((request) async => http.Response('{}', 500)),
          auth: const MobileLiveTestAuthParams(
            userId: '4',
            apiToken: 'tok',
            role: 'Client',
          ),
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      expect(
        find.text('Mobile Test Mode is restricted to Super Admin.'),
        findsOneWidget,
      );
      expect(find.text('Enable Test Mode'), findsNothing);
      controller.dispose();
    });

    testWidgets('disabling returns the screen to normal enable state',
        (tester) async {
      final store = MemoryMobileLiveTestStore();
      await store.saveCredentials(
        deviceToken: 'device-secret',
        publicId: 'dev-1',
      );
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'active_run': null,
            'tasks': [],
            'device': {'connection_label': 'Connected'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = MobileLiveTestController(
        service: buildService(client: client, store: store),
      );
      await tester.pumpWidget(MaterialApp(
        home: MobileLiveTestScreen(controller: controller),
      ));
      await pumpScreen(tester);
      expect(find.text('Mobile Test Mode Enabled'), findsOneWidget);

      await tester.tap(find.text('Disable'));
      await pumpScreen(tester);
      await tester.tap(find.text('Disable').last);
      await pumpScreen(tester);

      expect(find.text('Enable Test Mode'), findsOneWidget);
      expect(find.text('Mobile Test Mode Enabled'), findsNothing);
      expect(await store.hasCredentials(), isFalse);
      expect(controller.isSyncActive, isFalse);
      controller.dispose();
    });
  });
}
