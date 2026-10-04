import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/services/mobile_more_menu.dart';
import 'package:buildAhome/services/mobile_quick_actions.dart';

void main() {
  group('canonicalizeMobileMoreMenuKey', () {
    test('reuses Quick Action catalog keys for the same features', () {
      expect(canonicalizeMobileMoreMenuKey('gallery'), 'gallery');
      expect(canonicalizeMobileMoreMenuKey('my_tasks'), 'my_tasks');
      expect(canonicalizeMobileMoreMenuKey('My Tasks'), 'my_tasks');
      expect(
        canonicalizeMobileMoreMenuKey('upload_payment_proof'),
        'upload_payment_proof',
      );
      expect(canonicalizeMobileMoreMenuKey('notifications'), 'notifications');
    });

    test('keeps documents_v1 distinct from documents', () {
      expect(canonicalizeMobileMoreMenuKey('documents'), 'documents');
      expect(canonicalizeMobileMoreMenuKey('documents_v1'), 'documents_v1');
      expect(canonicalizeMobileMoreMenuKey('Documents V1'), 'documents_v1');
    });

    test('keeps timeline_gallery distinct from project_timeline', () {
      expect(
        canonicalizeMobileMoreMenuKey('project_timeline'),
        'project_timeline',
      );
      expect(
        canonicalizeMobileMoreMenuKey('timeline_gallery'),
        'timeline_gallery',
      );
      expect(
        canonicalizeMobileMoreMenuKey('Timeline Gallery'),
        'timeline_gallery',
      );
    });

    test('collapses more-menu aliases without duplicating Quick Action keys', () {
      expect(canonicalizeMobileMoreMenuKey('chat_v1'), 'chatbox');
      expect(canonicalizeMobileMoreMenuKey('daily_update'), 'updates');
      expect(canonicalizeMobileMoreMenuKey('upload_proof'), 'upload_payment_proof');
      expect(canonicalizeMobileMoreMenuKey('site_visits'), 'site_visit_reports');
      expect(canonicalizeMobileMoreMenuKey('log_out'), 'logout');
    });

    test('ignores unknown keys', () {
      expect(canonicalizeMobileMoreMenuKey('future_action'), '');
      expect(canonicalizeMobileMoreMenuKey('documents_more'), '');
      expect(canonicalizeMobileMoreMenuKey(''), '');
      expect(canonicalizeMobileMoreMenuKey(null), '');
    });
  });

  group('surface title mapping', () {
    test('staff drawer titles match NavMenu.dart', () {
      expect(
        flutterTitleForMobileMoreMenu(MobileMoreMenuSurface.staff, 'updates'),
        'Daily Update',
      );
      expect(
        flutterTitleForMobileMoreMenu(MobileMoreMenuSurface.staff, 'my_tasks'),
        'My Tasks',
      );
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.staff,
          'documents_v1',
        ),
        'Documents V1',
      );
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.staff,
          'site_visit_reports',
        ),
        'Site Visits',
      );
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.staff,
          'notifications',
        ),
        'Notifications',
      );
    });

    test('project drawers use client titles', () {
      for (final surface in [
        MobileMoreMenuSurface.projectNew,
        MobileMoreMenuSurface.projectOld,
      ]) {
        expect(
          flutterTitleForMobileMoreMenu(surface, 'updates'),
          'Updates',
        );
        expect(
          flutterTitleForMobileMoreMenu(surface, 'client_portal'),
          'Client Portal',
        );
        expect(
          flutterTitleForMobileMoreMenu(surface, 'upload_payment_proof'),
          'Upload proof',
        );
      }
    });

    test('does not leak staff-only keys onto project surfaces', () {
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.projectNew,
          'attendance',
        ),
        isNull,
      );
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.projectOld,
          'projects',
        ),
        isNull,
      );
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.projectNew,
          'documents_v1',
        ),
        isNull,
      );
    });

    test('does not leak client-only keys onto staff surface', () {
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.staff,
          'client_portal',
        ),
        isNull,
      );
      expect(
        flutterTitleForMobileMoreMenu(
          MobileMoreMenuSurface.staff,
          'nt_payments',
        ),
        isNull,
      );
    });
  });

  group('moreMenuSurfaceFor', () {
    test('staff roles use more_drawer_staff without extra role transforms', () {
      expect(
        moreMenuSurfaceFor(role: 'Admin', useLegacyProjectUi: false),
        MobileMoreMenuSurface.staff,
      );
      expect(
        moreMenuSurfaceFor(
          role: 'Project Coordinator',
          useLegacyProjectUi: true,
        ),
        MobileMoreMenuSurface.staff,
      );
    });

    test('Client old vs new project homes are isolated surfaces', () {
      expect(
        moreMenuSurfaceFor(role: 'Client', useLegacyProjectUi: false),
        MobileMoreMenuSurface.projectNew,
      );
      expect(
        moreMenuSurfaceFor(role: 'Client', useLegacyProjectUi: true),
        MobileMoreMenuSurface.projectOld,
      );
    });
  });

  group('parseMobileMoreMenuPayload', () {
    test('reads ordered object keys', () {
      final snapshot = parseMobileMoreMenuPayload(
        {
          'message': 'success',
          'configured': true,
          'surface': 'more_drawer_staff',
          'role': 'Admin',
          'actions': [
            {'key': 'gallery', 'sort_order': 2},
            {'key': 'projects', 'sort_order': 1},
            {'key': 'documents', 'sort_order': 3},
          ],
        },
        surface: MobileMoreMenuSurface.staff,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.configured, isTrue);
      expect(snapshot.actionKeys, ['projects', 'gallery', 'documents']);
    });

    test('configured false with empty actions', () {
      final snapshot = parseMobileMoreMenuPayload(
        {
          'message': 'success',
          'configured': false,
          'actions': [],
        },
        surface: MobileMoreMenuSurface.staff,
      );
      expect(snapshot!.configured, isFalse);
      expect(snapshot.actionKeys, isEmpty);
    });

    test('configured true with empty actions is intentional hide-all', () {
      final snapshot = parseMobileMoreMenuPayload(
        {
          'success': true,
          'configured': true,
          'actions': [],
        },
        surface: MobileMoreMenuSurface.projectNew,
      );
      expect(snapshot!.configured, isTrue);
      expect(snapshot.isIntentionalEmpty, isTrue);
    });

    test('missing configured with empty actions falls back (not hide-all)', () {
      final snapshot = parseMobileMoreMenuPayload(
        {
          'message': 'success',
          'actions': [],
        },
        surface: MobileMoreMenuSurface.staff,
      );
      expect(snapshot!.configured, isFalse);
    });

    test('invalid JSON shape returns null so caller falls back', () {
      expect(
        parseMobileMoreMenuPayload(
          ['not', 'a', 'map'],
          surface: MobileMoreMenuSurface.staff,
        ),
        isNull,
      );
      expect(
        parseMobileMoreMenuPayload(
          {'message': 'success', 'actions': 'gallery'},
          surface: MobileMoreMenuSurface.staff,
        ),
        isNull,
      );
      expect(
        parseMobileMoreMenuPayload(
          {'success': false, 'actions': []},
          surface: MobileMoreMenuSurface.staff,
        ),
        isNull,
      );
    });
  });

  group('resolveMobileMoreMenuActionKeys', () {
    const staffCatalog = {
      'home',
      'projects',
      'my_tasks',
      'attendance',
      'notifications',
      'updates',
      'gallery',
      'documents',
      'documents_v1',
      'logout',
    };
    const staffFallback = [
      'home',
      'projects',
      'my_tasks',
      'attendance',
      'notifications',
      'updates',
      'gallery',
      'documents',
      'documents_v1',
      'logout',
    ];
    const projectCatalog = {
      'home',
      'client_portal',
      'project_timeline',
      'my_tasks',
      'notifications',
      'updates',
      'payments',
      'logout',
    };
    const projectFallback = [
      'home',
      'client_portal',
      'project_timeline',
      'my_tasks',
      'notifications',
      'updates',
      'payments',
      'logout',
    ];

    test('uses hardcoded fallback when snapshot is missing (API failure)', () {
      final result = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.staff,
        catalogKeys: staffCatalog,
        fallbackKeys: staffFallback,
        snapshot: null,
      );
      expect(result, staffFallback);
    });

    test('configured=false uses hardcoded fallback', () {
      final result = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.staff,
        catalogKeys: staffCatalog,
        fallbackKeys: staffFallback,
        snapshot: const MobileMoreMenuSnapshot(
          surface: MobileMoreMenuSurface.staff,
          configured: false,
          actionKeys: ['gallery'],
        ),
      );
      expect(result, staffFallback);
    });

    test('configured=true empty list hides configurable items but keeps pins', () {
      final result = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.projectNew,
        catalogKeys: projectCatalog,
        fallbackKeys: projectFallback,
        snapshot: const MobileMoreMenuSnapshot(
          surface: MobileMoreMenuSurface.projectNew,
          configured: true,
          actionKeys: [],
        ),
      );
      expect(result, ['home', 'logout']);
    });

    test('honors backend order and skips unknown keys', () {
      final result = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.staff,
        catalogKeys: staffCatalog,
        fallbackKeys: staffFallback,
        snapshot: const MobileMoreMenuSnapshot(
          surface: MobileMoreMenuSurface.staff,
          configured: true,
          actionKeys: [
            'gallery',
            'future_action',
            'documents_v1',
            'projects',
          ],
        ),
      );
      expect(result, ['home', 'gallery', 'documents_v1', 'projects', 'logout']);
    });

    test('does not bypass catalog/RBAC: missing key is skipped', () {
      final result = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.staff,
        catalogKeys: {'home', 'payments', 'logout'},
        fallbackKeys: const ['home', 'payments', 'logout'],
        snapshot: const MobileMoreMenuSnapshot(
          surface: MobileMoreMenuSurface.staff,
          configured: true,
          actionKeys: ['gallery', 'payments'],
        ),
      );
      expect(result, ['home', 'payments', 'logout']);
    });

    test('staff and project surfaces stay isolated', () {
      final projectResult = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.projectNew,
        catalogKeys: projectCatalog,
        fallbackKeys: projectFallback,
        snapshot: const MobileMoreMenuSnapshot(
          surface: MobileMoreMenuSurface.projectNew,
          configured: true,
          actionKeys: ['attendance', 'projects', 'payments'],
        ),
      );
      expect(projectResult, ['home', 'payments', 'logout']);

      final staffResult = resolveMobileMoreMenuActionKeys(
        surface: MobileMoreMenuSurface.staff,
        catalogKeys: {'home', 'attendance', 'projects', 'logout'},
        fallbackKeys: const ['home', 'attendance', 'projects', 'logout'],
        snapshot: const MobileMoreMenuSnapshot(
          surface: MobileMoreMenuSurface.staff,
          configured: true,
          actionKeys: ['attendance', 'client_portal'],
        ),
      );
      expect(staffResult, ['home', 'attendance', 'logout']);
    });

    test('old and new project surfaces resolve independently', () {
      const snapshotNew = MobileMoreMenuSnapshot(
        surface: MobileMoreMenuSurface.projectNew,
        configured: true,
        actionKeys: ['payments', 'updates'],
      );
      const snapshotOld = MobileMoreMenuSnapshot(
        surface: MobileMoreMenuSurface.projectOld,
        configured: true,
        actionKeys: ['notifications', 'client_portal'],
      );

      expect(
        resolveMobileMoreMenuActionKeys(
          surface: MobileMoreMenuSurface.projectNew,
          catalogKeys: projectCatalog,
          fallbackKeys: projectFallback,
          snapshot: snapshotNew,
        ),
        ['home', 'payments', 'updates', 'logout'],
      );
      expect(
        resolveMobileMoreMenuActionKeys(
          surface: MobileMoreMenuSurface.projectOld,
          catalogKeys: projectCatalog,
          fallbackKeys: projectFallback,
          snapshot: snapshotOld,
        ),
        ['home', 'notifications', 'client_portal', 'logout'],
      );
    });

    test('cached snapshot is used when present; null snapshot is hardcoded', () {
      const cached = MobileMoreMenuSnapshot(
        surface: MobileMoreMenuSurface.staff,
        configured: true,
        actionKeys: ['notifications', 'projects'],
        userId: '1',
        role: 'Admin',
      );
      expect(
        resolveMobileMoreMenuActionKeys(
          surface: MobileMoreMenuSurface.staff,
          catalogKeys: staffCatalog,
          fallbackKeys: staffFallback,
          snapshot: cached,
        ),
        ['home', 'notifications', 'projects', 'logout'],
      );
      expect(
        resolveMobileMoreMenuActionKeys(
          surface: MobileMoreMenuSurface.staff,
          catalogKeys: staffCatalog,
          fallbackKeys: staffFallback,
          snapshot: null,
        ),
        staffFallback,
      );
    });
  });

  group('cache keys', () {
    test('include user, role, and surface so accounts cannot leak', () {
      final a = mobileMoreMenuCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileMoreMenuSurface.staff,
      );
      final b = mobileMoreMenuCacheKey(
        userId: '2',
        role: 'Admin',
        surface: MobileMoreMenuSurface.staff,
      );
      final c = mobileMoreMenuCacheKey(
        userId: '1',
        role: 'Client',
        surface: MobileMoreMenuSurface.staff,
      );
      final d = mobileMoreMenuCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileMoreMenuSurface.projectNew,
      );
      final e = mobileMoreMenuCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileMoreMenuSurface.projectOld,
      );
      expect({a, b, c, d, e}.length, 5);
      expect(a, 'mobile_more_v1_1_Admin_more_drawer_staff');
      expect(d, contains('more_drawer_project_new'));
      expect(e, contains('more_drawer_project_old'));
    });

    test('Quick Action cache prefix stays distinct from More Menu', () {
      final qa = mobileQuickActionsCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileQuickActionSurface.staffHome,
      );
      final more = mobileMoreMenuCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileMoreMenuSurface.staff,
      );
      expect(qa, isNot(more));
      expect(qa, contains('mobile_qa_v1_'));
      expect(more, contains('mobile_more_v1_'));
    });

    test('fromJson rejects a snapshot for a different surface', () {
      final json = {
        'surface': 'more_drawer_staff',
        'configured': true,
        'actions': ['gallery'],
        'user_id': '1',
      };
      expect(
        MobileMoreMenuSnapshot.fromJson(
          json,
          expectedSurface: MobileMoreMenuSurface.projectNew,
        ),
        isNull,
      );
      expect(
        MobileMoreMenuSnapshot.fromJson(
          json,
          expectedSurface: MobileMoreMenuSurface.staff,
        ),
        isNotNull,
      );
    });

    test('fromJson rejects a snapshot for a different user', () {
      final snapshot = MobileMoreMenuSnapshot.fromJson(
        {
          'surface': 'more_drawer_staff',
          'configured': true,
          'actions': ['gallery'],
          'user_id': '1',
        },
        expectedSurface: MobileMoreMenuSurface.staff,
      );
      expect(snapshot!.userId, '1');
      expect(snapshot.userId, isNot('2'));
    });
  });
}
