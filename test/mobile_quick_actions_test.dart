import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/services/mobile_quick_actions.dart';

Map<String, dynamic> _item(String title) => {
      'title': title,
      'icon': title,
      'route': () => title,
    };

void main() {
  group('canonicalizeMobileQuickActionKey', () {
    test('keeps canonical catalog keys', () {
      expect(canonicalizeMobileQuickActionKey('gallery'), 'gallery');
      expect(canonicalizeMobileQuickActionKey('upload_payment_proof'),
          'upload_payment_proof');
    });

    test('collapses backend aliases onto canonical keys', () {
      expect(canonicalizeMobileQuickActionKey('documents_v1'), 'documents');
      expect(canonicalizeMobileQuickActionKey('chat_v1'), 'chatbox');
      expect(canonicalizeMobileQuickActionKey('daily_update'), 'updates');
      expect(
        canonicalizeMobileQuickActionKey('timeline_gallery'),
        'project_timeline',
      );
    });

    test('maps Upload proof titles onto upload_payment_proof', () {
      expect(canonicalizeMobileQuickActionKey('upload_proof'),
          'upload_payment_proof');
      expect(canonicalizeMobileQuickActionKey('Upload proof'),
          'upload_payment_proof');
      expect(canonicalizeMobileQuickActionKey('Upload payment proofs'),
          'upload_payment_proof');
    });

    test('ignores unknown keys', () {
      expect(canonicalizeMobileQuickActionKey('future_action'), '');
      expect(canonicalizeMobileQuickActionKey(''), '');
      expect(canonicalizeMobileQuickActionKey(null), '');
    });
  });

  group('surface title mapping', () {
    test('staff home maps ERP catalog keys used on that screen', () {
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'attendance',
        ),
        'Attendance',
      );
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'updates',
        ),
        'Daily Update',
      );
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'gallery',
        ),
        'Gallery',
      );
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'payments',
        ),
        'Payments',
      );
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'chatbox',
        ),
        'Chat V1',
      );
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'documents',
        ),
        'Documents',
      );
    });

    test('old project home chatbox is Notes & Comments', () {
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.projectHomeOld,
          'chatbox',
        ),
        'Notes & Comments',
      );
    });

    test('new project home upload_payment_proof is Upload proof', () {
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.projectHomeNew,
          'upload_payment_proof',
        ),
        'Upload proof',
      );
    });

    test('does not leak staff_home titles onto project homes', () {
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.projectHomeNew,
          'attendance',
        ),
        isNull,
      );
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.projectHomeOld,
          'projects',
        ),
        isNull,
      );
    });
  });

  group('parseMobileQuickActionsPayload', () {
    test('reads ordered object keys', () {
      final snapshot = parseMobileQuickActionsPayload(
        {
          'message': 'success',
          'configured': true,
          'surface': 'staff_home',
          'role': 'Admin',
          'actions': [
            {'key': 'gallery', 'sort_order': 2},
            {'key': 'payments', 'sort_order': 1},
            {'key': 'documents', 'sort_order': 3},
          ],
        },
        surface: MobileQuickActionSurface.staffHome,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.configured, isTrue);
      expect(snapshot.actionKeys, ['payments', 'gallery', 'documents']);
    });

    test('configured false with empty actions', () {
      final snapshot = parseMobileQuickActionsPayload(
        {
          'message': 'success',
          'configured': false,
          'actions': [],
        },
        surface: MobileQuickActionSurface.staffHome,
      );
      expect(snapshot!.configured, isFalse);
      expect(snapshot.actionKeys, isEmpty);
    });

    test('configured true with empty actions is intentional hide-all', () {
      final snapshot = parseMobileQuickActionsPayload(
        {
          'success': true,
          'configured': true,
          'actions': [],
        },
        surface: MobileQuickActionSurface.projectHomeNew,
      );
      expect(snapshot!.configured, isTrue);
      expect(snapshot.isIntentionalEmpty, isTrue);
    });

    test('missing configured with empty actions falls back (not hide-all)', () {
      final snapshot = parseMobileQuickActionsPayload(
        {
          'message': 'success',
          'actions': [],
        },
        surface: MobileQuickActionSurface.staffHome,
      );
      expect(snapshot!.configured, isFalse);
    });

    test('invalid JSON shape returns null so caller falls back', () {
      expect(
        parseMobileQuickActionsPayload(
          ['not', 'a', 'map'],
          surface: MobileQuickActionSurface.staffHome,
        ),
        isNull,
      );
      expect(
        parseMobileQuickActionsPayload(
          {'message': 'success', 'actions': 'gallery'},
          surface: MobileQuickActionSurface.staffHome,
        ),
        isNull,
      );
      expect(
        parseMobileQuickActionsPayload(
          {'success': false, 'actions': []},
          surface: MobileQuickActionSurface.staffHome,
        ),
        isNull,
      );
    });
  });

  group('resolveMobileQuickActions', () {
    final newHomeCatalog = [
      _item('Client Portal'),
      _item('Gallery'),
      _item('Payments'),
      _item('Documents'),
      _item('Upload proof'),
      _item('Approved POs'),
    ];
    final hardcoded = [
      _item('Client Portal'),
      _item('Payments'),
      _item('Upload proof'),
    ];

    test('uses hardcoded fallback when snapshot is missing', () {
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: newHomeCatalog,
        fallback: hardcoded,
        snapshot: null,
      );
      expect(
        result.map((e) => e['title']),
        ['Client Portal', 'Payments', 'Upload proof'],
      );
    });

    test('configured=false uses hardcoded fallback', () {
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: newHomeCatalog,
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.projectHomeNew,
          configured: false,
          actionKeys: ['gallery'],
        ),
      );
      expect(
        result.map((e) => e['title']),
        ['Client Portal', 'Payments', 'Upload proof'],
      );
    });

    test('configured=true empty list shows no actions', () {
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: newHomeCatalog,
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.projectHomeNew,
          configured: true,
          actionKeys: [],
        ),
      );
      expect(result, isEmpty);
    });

    test('honors backend order and skips unknown keys', () {
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: newHomeCatalog,
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.projectHomeNew,
          configured: true,
          actionKeys: [
            'gallery',
            'future_action',
            'payments',
            'documents',
          ],
        ),
      );
      expect(
        result.map((e) => e['title']),
        ['Gallery', 'Payments', 'Documents'],
      );
    });

    test('maps upload_payment_proof to existing Upload proof tile', () {
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: newHomeCatalog,
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.projectHomeNew,
          configured: true,
          actionKeys: ['upload_payment_proof'],
        ),
      );
      expect(result.single['title'], 'Upload proof');
    });

    test('does not bypass catalog/RBAC: missing title is skipped', () {
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: [_item('Payments')],
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.projectHomeNew,
          configured: true,
          actionKeys: ['approved_pos', 'payments'],
        ),
      );
      expect(result.map((e) => e['title']), ['Payments']);
    });

    test('staff home configured list can include gallery when catalog has it', () {
      final staffCatalog = [
        _item('Projects'),
        _item('Attendance'),
        _item('Gallery'),
        _item('Payments'),
      ];
      final hardcoded = [_item('Projects'), _item('Attendance')];
      final result = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.staffHome,
        catalog: staffCatalog,
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.staffHome,
          configured: true,
          actionKeys: ['gallery', 'attendance', 'future_action'],
        ),
      );
      expect(result.map((e) => e['title']), ['Gallery', 'Attendance']);
    });

    test('staff home and project home mappings stay isolated', () {
      final staffCatalog = [_item('Attendance'), _item('Projects')];
      final projectResult = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.projectHomeNew,
        catalog: newHomeCatalog,
        fallback: hardcoded,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.projectHomeNew,
          configured: true,
          actionKeys: ['attendance', 'projects', 'gallery'],
        ),
      );
      expect(projectResult.map((e) => e['title']), ['Gallery']);

      final staffResult = resolveMobileQuickActions(
        surface: MobileQuickActionSurface.staffHome,
        catalog: staffCatalog,
        fallback: staffCatalog,
        snapshot: const MobileQuickActionsSnapshot(
          surface: MobileQuickActionSurface.staffHome,
          configured: true,
          actionKeys: ['attendance', 'gallery'],
        ),
      );
      expect(staffResult.map((e) => e['title']), ['Attendance']);
    });
  });

  group('cache keys', () {
    test('include user, role, and surface so accounts cannot leak', () {
      final a = mobileQuickActionsCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileQuickActionSurface.staffHome,
      );
      final b = mobileQuickActionsCacheKey(
        userId: '2',
        role: 'Admin',
        surface: MobileQuickActionSurface.staffHome,
      );
      final c = mobileQuickActionsCacheKey(
        userId: '1',
        role: 'Client',
        surface: MobileQuickActionSurface.staffHome,
      );
      final d = mobileQuickActionsCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileQuickActionSurface.projectHomeNew,
      );
      expect({a, b, c, d}.length, 4);
      expect(a, contains('staff_home'));
      expect(d, contains('project_home_new'));
    });
  });
}
