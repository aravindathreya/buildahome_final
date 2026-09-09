import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:buildAhome/models/mobile_live_test.dart';
import 'package:buildAhome/services/mobile_live_test_auto_runner.dart';
import 'package:buildAhome/services/mobile_live_test_controller.dart';
import 'package:buildAhome/services/mobile_live_test_service.dart';
import 'package:buildAhome/services/mobile_live_test_storage.dart';

void main() {
  const superAdmin = MobileLiveTestAuthParams(
    userId: '12',
    apiToken: 'user-token',
    role: 'Super Admin',
  );

  Future<String> sampleJpeg() async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}live_test_auto_sample.jpg',
    );
    await file.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xD9], flush: true);
    return file.path;
  }

  Map<String, dynamic> sessionPayload({List<Map<String, dynamic>> tasks = const []}) {
    return {
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
      'tasks': tasks,
    };
  }

  test('auto run uploads a file and completes the task', () async {
    final store = MemoryMobileLiveTestStore();
    await store.saveCredentials(
      deviceToken: 'device-secret',
      publicId: 'dev-1',
    );
    var completed = false;
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      final path = request.url.path;
      if (path.endsWith('/session')) {
        final tasks = completed
            ? <Map<String, dynamic>>[]
            : [
                {
                  'item_run_id': 456,
                  'name': 'Site photo',
                  'status': 'ready',
                },
              ];
        return http.Response(
          jsonEncode(sessionPayload(tasks: tasks)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/open')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'item_run_id': 456,
            'task': {
              'item_run_id': 456,
              'name': 'Site photo',
              'can_complete': false,
              'actions': [
                {
                  'id': 'upload_1',
                  'type': 'upload',
                  'label': 'Upload photo',
                  'require_near_site': true,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/upload')) {
        completed = true;
        return http.Response(
          jsonEncode({
            'success': true,
            'task_completed': true,
            'item_run_id': 456,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final service = MobileLiveTestService(
      client: client,
      store: store,
      authParams: () async => superAdmin,
      baseUrl: 'https://office.buildahome.in',
    );
    final controller = MobileLiveTestController(service: service);
    await controller.restoreAndRefresh();

    final runner = MobileLiveTestAutoRunner(
      delayBetweenTasks: Duration.zero,
      sampleJpegPath: sampleJpeg,
    );
    await runner.run(controller: controller);

    expect(paths.any((p) => p.contains('POST') && p.endsWith('/upload')), isTrue);
    expect(controller.visibleTasks, isEmpty);
    expect(runner.status, contains('finished'));
    controller.dispose();
  });

  test('auto run sends completion percent then finalizes', () async {
    final store = MemoryMobileLiveTestStore();
    await store.saveCredentials(
      deviceToken: 'device-secret',
      publicId: 'dev-1',
    );
    var completed = false;
    var uploadRound = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/session')) {
        final tasks = completed
            ? <Map<String, dynamic>>[]
            : [
                {
                  'item_run_id': 789,
                  'name': 'Progress upload',
                  'status': 'ready',
                },
              ];
        return http.Response(
          jsonEncode(sessionPayload(tasks: tasks)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/open')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'test_mode': true,
            'item_run_id': 789,
            'task': {
              'item_run_id': 789,
              'name': 'Progress upload',
              'can_complete': false,
              'actions': [
                {
                  'id': 'upload_pct',
                  'type': 'upload',
                  'add_percent_to_task': true,
                  'current_percent': 0,
                  'min_next_percent': 1,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/upload')) {
        uploadRound++;
        if (uploadRound == 1) {
          return http.Response(
            jsonEncode({
              'success': true,
              'task_completed': false,
              'current_percent': 100,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        completed = true;
        return http.Response(
          jsonEncode({
            'success': true,
            'task_completed': true,
            'item_run_id': 789,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final service = MobileLiveTestService(
      client: client,
      store: store,
      authParams: () async => superAdmin,
      baseUrl: 'https://office.buildahome.in',
    );
    final controller = MobileLiveTestController(service: service);
    await controller.restoreAndRefresh();

    final runner = MobileLiveTestAutoRunner(
      delayBetweenTasks: Duration.zero,
      sampleJpegPath: sampleJpeg,
    );
    await runner.run(controller: controller);

    expect(uploadRound, 2);
    expect(controller.visibleTasks, isEmpty);
    controller.dispose();
  });
}
