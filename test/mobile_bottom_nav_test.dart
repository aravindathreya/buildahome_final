import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/services/mobile_bottom_nav.dart';

void main() {
  group('canonicalizeMobileBottomNavKey', () {
    test('keeps canonical catalog keys', () {
      expect(canonicalizeMobileBottomNavKey('home'), 'home');
      expect(canonicalizeMobileBottomNavKey('more'), 'more');
      expect(canonicalizeMobileBottomNavKey('my_tasks'), 'my_tasks');
      expect(canonicalizeMobileBottomNavKey('projects'), 'projects');
      expect(
        canonicalizeMobileBottomNavKey('site_visit_reports'),
        'site_visit_reports',
      );
      expect(canonicalizeMobileBottomNavKey('chatbox'), 'chatbox');
    });

    test('collapses aliases', () {
      expect(canonicalizeMobileBottomNavKey('chat_v1'), 'chatbox');
      expect(canonicalizeMobileBottomNavKey('daily_update'), 'updates');
      expect(canonicalizeMobileBottomNavKey('site_visits'), 'site_visit_reports');
      expect(canonicalizeMobileBottomNavKey('tasks'), 'my_tasks');
      expect(canonicalizeMobileBottomNavKey('My Tasks'), 'my_tasks');
      expect(canonicalizeMobileBottomNavKey('upload_proof'), 'upload_payment_proof');
    });

    test('ignores unknown keys', () {
      expect(canonicalizeMobileBottomNavKey('future_tab'), '');
      expect(canonicalizeMobileBottomNavKey(''), '');
      expect(canonicalizeMobileBottomNavKey(null), '');
    });
  });

  group('bottomNavSurfaceFor', () {
    test('staff home is isolated from project homes', () {
      expect(
        bottomNavSurfaceFor(isStaffHome: true, useLegacyProjectUi: false),
        MobileBottomNavSurface.staff,
      );
      expect(
        bottomNavSurfaceFor(isStaffHome: false, useLegacyProjectUi: false),
        MobileBottomNavSurface.projectNew,
      );
      expect(
        bottomNavSurfaceFor(isStaffHome: false, useLegacyProjectUi: true),
        MobileBottomNavSurface.projectOld,
      );
    });
  });

  group('parseMobileBottomNavPayload', () {
    test('reads ordered object keys', () {
      final snapshot = parseMobileBottomNavPayload(
        {
          'success': true,
          'message': 'success',
          'configured': true,
          'surface': 'bottom_nav_staff',
          'role': 'Admin',
          'actions': [
            {'key': 'home', 'sort_order': 1},
            {'key': 'projects', 'sort_order': 3},
            {'key': 'my_tasks', 'sort_order': 2},
            {'key': 'site_visit_reports', 'sort_order': 4},
            {'key': 'more', 'sort_order': 5},
          ],
        },
        surface: MobileBottomNavSurface.staff,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.configured, isTrue);
      expect(snapshot.actionKeys, [
        'home',
        'my_tasks',
        'projects',
        'site_visit_reports',
        'more',
      ]);
    });

    test('configured false with empty actions', () {
      final snapshot = parseMobileBottomNavPayload(
        {
          'message': 'success',
          'configured': false,
          'actions': [],
        },
        surface: MobileBottomNavSurface.staff,
      );
      expect(snapshot!.configured, isFalse);
      expect(snapshot.actionKeys, isEmpty);
    });

    test('invalid JSON shape returns null so caller falls back', () {
      expect(
        parseMobileBottomNavPayload(
          ['not', 'a', 'map'],
          surface: MobileBottomNavSurface.staff,
        ),
        isNull,
      );
      expect(
        parseMobileBottomNavPayload(
          {'success': false, 'actions': []},
          surface: MobileBottomNavSurface.staff,
        ),
        isNull,
      );
    });
  });

  group('resolveMobileBottomNavActionKeys', () {
    test('falls back when not configured', () {
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.staff,
        fallbackKeys: kMobileBottomNavStaffFallback,
        snapshot: const MobileBottomNavSnapshot(
          surface: MobileBottomNavSurface.staff,
          configured: false,
          actionKeys: ['gallery'],
        ),
      );
      expect(keys, kMobileBottomNavStaffFallback);
    });

    test('pins home first and more last', () {
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.staff,
        fallbackKeys: kMobileBottomNavStaffFallback,
        snapshot: const MobileBottomNavSnapshot(
          surface: MobileBottomNavSurface.staff,
          configured: true,
          actionKeys: [
            'more',
            'site_visit_reports',
            'my_tasks',
            'projects',
            'home',
          ],
        ),
      );
      expect(keys.first, 'home');
      expect(keys.last, 'more');
      expect(keys, [
        'home',
        'site_visit_reports',
        'my_tasks',
        'projects',
        'more',
      ]);
    });

    test('skips unknown keys and keeps saved project tabs', () {
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.projectNew,
        fallbackKeys: kMobileBottomNavProjectFallback,
        snapshot: const MobileBottomNavSnapshot(
          surface: MobileBottomNavSurface.projectNew,
          configured: true,
          actionKeys: [
            'home',
            'future_tab',
            'projects',
            'updates',
            'chatbox',
            'more',
          ],
        ),
      );
      expect(keys, [
        'home',
        'projects',
        'updates',
        'chatbox',
        'more',
      ]);
    });

    test('caps middle tabs so total stays at hard max including pins', () {
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.staff,
        fallbackKeys: kMobileBottomNavStaffFallback,
        snapshot: const MobileBottomNavSnapshot(
          surface: MobileBottomNavSurface.staff,
          configured: true,
          actionKeys: [
            'home',
            'my_tasks',
            'projects',
            'site_visit_reports',
            'attendance',
            'gallery',
            'scheduler',
            'payments',
            'documents',
            'more',
          ],
        ),
      );
      expect(keys.length, lessThanOrEqualTo(kMobileBottomNavHardMaxTabs));
      expect(keys.first, 'home');
      expect(keys.last, 'more');
      expect(keys.length, 7);
      expect(keys.sublist(1, keys.length - 1), [
        'my_tasks',
        'projects',
        'site_visit_reports',
        'attendance',
        'gallery',
      ]);
    });

    test('configured empty still keeps home and more', () {
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.staff,
        fallbackKeys: kMobileBottomNavStaffFallback,
        snapshot: const MobileBottomNavSnapshot(
          surface: MobileBottomNavSurface.staff,
          configured: true,
          actionKeys: [],
        ),
      );
      expect(keys, ['home', 'more']);
    });

    test('saved project bar keeps Daily Updates and Chat without adding Payments', () {
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.projectNew,
        fallbackKeys: kMobileBottomNavProjectFallback,
        snapshot: const MobileBottomNavSnapshot(
          surface: MobileBottomNavSurface.projectNew,
          configured: true,
          actionKeys: ['home', 'my_tasks', 'updates', 'chatbox', 'more'],
        ),
      );
      expect(keys, [
        'home',
        'my_tasks',
        'updates',
        'chatbox',
        'more',
      ]);
      expect(keys.contains('payments'), isFalse);
      expect(keys.length, lessThanOrEqualTo(kMobileBottomNavHardMaxTabs));
    });

    test('project home drops a middle tab to fit Payments under the cap', () {
      final keys = ensureProjectHomePaymentsTab([
        'home',
        'my_tasks',
        'gallery',
        'scheduler',
        'documents',
        'indents',
        'more',
      ]);
      expect(keys.first, 'home');
      expect(keys.last, 'more');
      expect(keys.contains('payments'), isTrue);
      expect(keys.length, kMobileBottomNavHardMaxTabs);
      expect(keys.contains('indents'), isFalse);
    });

    test('project home always inserts For me after Home', () {
      final keys = ensureProjectHomeForMeTab([
        'home',
        'my_tasks',
        'payments',
        'more',
      ]);
      expect(keys, [
        'home',
        'client_portal',
        'my_tasks',
        'payments',
        'more',
      ]);
      expect(labelForMobileBottomNav('client_portal'), 'For me');
    });

    test('project home keeps For me when fitting Payments under the cap', () {
      final withForMe = ensureProjectHomeForMeTab([
        'home',
        'my_tasks',
        'gallery',
        'scheduler',
        'documents',
        'indents',
        'more',
      ]);
      final keys = ensureProjectHomePaymentsTab(withForMe);
      expect(keys.first, 'home');
      expect(keys.contains('client_portal'), isTrue);
      expect(keys.contains('payments'), isTrue);
      expect(keys.length, lessThanOrEqualTo(kMobileBottomNavHardMaxTabs));
    });

    test('client project_new save keeps chat and updates on the bar', () {
      final snapshot = parseMobileBottomNavPayload(
        {
          'success': true,
          'message': 'success',
          'role': 'Client',
          'surface': 'bottom_nav_project_new',
          'configured': true,
          'actions': [
            {'key': 'home', 'sort_order': 1},
            {'key': 'my_tasks', 'sort_order': 2},
            {'key': 'updates', 'sort_order': 3},
            {'key': 'chatbox', 'sort_order': 4},
            {'key': 'more', 'sort_order': 5},
          ],
        },
        surface: MobileBottomNavSurface.projectNew,
      );
      expect(snapshot!.configured, isTrue);
      expect(snapshot.actionKeys, [
        'home',
        'my_tasks',
        'updates',
        'chatbox',
        'more',
      ]);

      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.projectNew,
        fallbackKeys: kMobileBottomNavProjectFallback,
        snapshot: snapshot,
      );
      expect(keys, [
        'home',
        'my_tasks',
        'updates',
        'chatbox',
        'more',
      ]);
    });

    test('project fallback omits updates, chat, and docs', () {
      expect(kMobileBottomNavProjectFallback.contains('updates'), isFalse);
      expect(kMobileBottomNavProjectFallback.contains('chatbox'), isFalse);
      expect(kMobileBottomNavProjectFallback.contains('documents'), isFalse);
      final keys = resolveMobileBottomNavActionKeys(
        surface: MobileBottomNavSurface.projectNew,
        fallbackKeys: kMobileBottomNavProjectFallback,
        snapshot: null,
      );
      expect(keys, kMobileBottomNavProjectFallback);
      expect(keys.contains('updates'), isFalse);
      expect(keys.contains('chatbox'), isFalse);
      expect(keys.contains('documents'), isFalse);
    });

    test('withoutProjectHomeDocsTabs strips documents keys', () {
      expect(
        withoutProjectHomeDocsTabs([
          'home',
          'my_tasks',
          'documents',
          'documents_v1',
          'payments',
          'more',
        ]),
        ['home', 'my_tasks', 'payments', 'more'],
      );
    });
  });
}
