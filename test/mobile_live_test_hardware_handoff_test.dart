import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/models/mobile_live_test.dart';
import 'package:buildAhome/services/mobile_live_test_access.dart';

void main() {
  group('session parsing', () {
    test('ignores legacy auto_test and hardware_task fields', () {
      final session = MobileLiveTestSession.fromJson({
        'success': true,
        'test_mode': true,
        'active_run': {'run_id': 123, 'workflow_name': 'TEST-001'},
        'auto_test': {'status': 'waiting_for_mobile', 'auto_test_run_id': 9},
        'hardware_task': {
          'item_run_id': 999,
          'task_name': 'Legacy hardware handoff',
          'hardware_type': 'camera',
        },
        'tasks': [
          {
            'item_run_id': 456,
            'name': 'Approve BOQ',
            'status': 'ready',
          },
          {
            'item_run_id': 457,
            'name': 'Approve Drawing',
            'status': 'ready',
          },
        ],
      });

      expect(session.tasks, hasLength(2));
      expect(session.dedupedTasks, hasLength(2));
      expect(session.hasAssignedRun, isTrue);
    });
  });

  group('workflow action hardware getters', () {
    test('upload action exposes GPS and camera flags', () {
      final action = MobileLiveTestWorkflowAction.fromJson({
        'id': 'a1',
        'type': 'upload',
        'live_image_only': true,
        'require_near_site': true,
        'near_site_radius_meters': 250,
        'allow_video_upload': true,
        'max_video_duration_seconds': 45,
      });
      expect(action.liveImageOnly, isTrue);
      expect(action.requireNearSite, isTrue);
      expect(action.needsGpsForUpload, isTrue);
      expect(action.allowGalleryUpload, isFalse);
      expect(action.allowVideoUpload, isTrue);
      expect(action.maxVideoDurationSeconds, 45);
    });
  });

  group('API isolation', () {
    test('session path remains live-test only', () {
      expect(
        MobileLiveTestAccess.sessionPath,
        '/API/workflow/mobile-live-test/session',
      );
      expect(MobileLiveTestAccess.sessionPath.contains('get_tasks'), isFalse);
      expect(MobileLiveTestAccess.sessionPath.contains('item-runs'), isFalse);
      expect(
        MobileLiveTestAccess.sessionPath.contains('preview/auto-test'),
        isFalse,
      );
    });
  });
}
