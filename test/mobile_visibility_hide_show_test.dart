import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/services/mobile_more_menu.dart';
import 'package:buildAhome/services/mobile_quick_actions.dart';

/// What the home screens actually paint after the backend list is applied.
///
/// The resolvers honor hide/show. AdminDashboard, UserDashboard, and
/// LegacyClientHome then put some tiles back. These helpers copy that
/// post-processing so the test matches the screens, not only the resolver.

Map<String, dynamic> _tile(String title) => {'title': title};

List<String> _titles(List<Map<String, dynamic>> items) =>
    items.map((item) => item['title'].toString()).toList();

List<Map<String, dynamic>> _catalog(Iterable<String> titles) =>
    titles.map(_tile).toList();

MobileQuickActionsSnapshot _quick(MobileQuickActionSurface surface, List<String> keys) {
  return MobileQuickActionsSnapshot(
    surface: surface,
    configured: true,
    actionKeys: keys,
  );
}

List<Map<String, dynamic>> _resolvedQuick({
  required MobileQuickActionSurface surface,
  required List<Map<String, dynamic>> catalog,
  required List<String> keys,
}) {
  return resolveMobileQuickActions(
    surface: surface,
    catalog: catalog,
    fallback: const [],
    snapshot: _quick(surface, keys),
  );
}

bool _pinsDailyUpdate(String role) {
  final normalized = role.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return normalized == 'site engineer' ||
      normalized == 'super admin' ||
      normalized == 'admin';
}

/// AdminDashboard quick-action grid after a configured `staff_home` payload.
List<String> staffHomeShown({
  required List<Map<String, dynamic>> catalog,
  required List<String> keys,
  required String role,
}) {
  final items = List<Map<String, dynamic>>.from(
    _resolvedQuick(
      surface: MobileQuickActionSurface.staffHome,
      catalog: catalog,
      keys: keys,
    ),
  );

  if (_pinsDailyUpdate(role) &&
      !items.any((item) => item['title'] == 'Daily Update')) {
    Map<String, dynamic>? tile;
    for (final item in catalog) {
      if (item['title'] == 'Daily Update') {
        tile = item;
        break;
      }
    }
    if (tile != null) {
      final attendance = items.indexWhere((item) => item['title'] == 'Attendance');
      if (attendance >= 0) {
        items.insert(attendance + 1, tile);
      } else {
        items.add(tile);
      }
    }
  }

  if (role != 'Client' && !items.any((item) => item['title'] == 'Chat')) {
    items.add(_tile('Chat'));
  }
  return _titles(items);
}

/// UserDashboard project-home grid after a configured `project_home_new` payload.
List<String> projectHomeNewShown({
  required List<Map<String, dynamic>> menuItems,
  required List<Map<String, dynamic>> configurable,
  required List<String> keys,
  required bool isClient,
}) {
  var actions = List<Map<String, dynamic>>.from(
    _resolvedQuick(
      surface: MobileQuickActionSurface.projectHomeNew,
      catalog: configurable,
      keys: keys,
    ),
  );

  if (!actions.any((item) => item['title'] == 'Client Portal')) {
    for (final item in menuItems) {
      if (item['title'] == 'Client Portal') {
        actions = [item, ...actions];
        break;
      }
    }
  }

  if (isClient && !actions.any((item) => item['title'] == 'Project Timeline')) {
    Map<String, dynamic>? timeline;
    for (final item in menuItems) {
      if (item['title'] == 'Project Timeline') {
        timeline = item;
        break;
      }
    }
    if (timeline != null) {
      final portal = actions.indexWhere((item) => item['title'] == 'Client Portal');
      actions.insert(portal >= 0 ? portal + 1 : 0, timeline);
    }
  }

  actions = withoutLegacyDocumentsQuickActions(actions);

  if (isClient) {
    actions = actions
        .where((item) => item['title'] != 'Scheduler' && item['title'] != 'Checklist')
        .toList();
    void ensure(String title) {
      if (actions.any((item) => item['title'] == title)) return;
      for (final item in menuItems) {
        if (item['title'] == title) {
          actions.add(item);
          return;
        }
      }
    }

    ensure('My tasks');
    ensure('Slots');
    ensure('Site Visit Reports');
  }

  return _titles(actions);
}

/// LegacyClientHome grid after a configured `project_home_old` payload.
List<String> projectHomeOldShown({
  required List<Map<String, dynamic>> catalog,
  required List<String> keys,
}) {
  final actions = List<Map<String, dynamic>>.from(
    _resolvedQuick(
      surface: MobileQuickActionSurface.projectHomeOld,
      catalog: catalog,
      keys: keys,
    ),
  );
  if (!actions.any((item) => item['title'] == 'For me')) {
    actions.insert(
      0,
      catalog.firstWhere((item) => item['title'] == 'For me'),
    );
  }
  if (!actions.any((item) => item['title'] == 'Project Timeline')) {
    final timeline = catalog.firstWhere((item) => item['title'] == 'Project Timeline');
    final portal = actions.indexWhere((item) => item['title'] == 'For me');
    actions.insert(portal >= 0 ? portal + 1 : 0, timeline);
  }
  actions.removeWhere((item) {
    final title = item['title']?.toString();
    return title == 'Scheduler' || title == 'Checklist';
  });
  for (final title in ['My tasks', 'Slots', 'Site Visit Reports']) {
    if (actions.any((item) => item['title'] == title)) continue;
    for (final item in catalog) {
      if (item['title'] == title) {
        actions.add(item);
        break;
      }
    }
  }
  return _titles(actions);
}

List<String> moreMenuShown({
  required MobileMoreMenuSurface surface,
  required Set<String> catalogKeys,
  required List<String> keys,
}) {
  return resolveMobileMoreMenuActionKeys(
    surface: surface,
    catalogKeys: catalogKeys,
    fallbackKeys: catalogKeys.toList(),
    snapshot: MobileMoreMenuSnapshot(
      surface: surface,
      configured: true,
      actionKeys: keys,
    ),
  );
}

String? _quickKeyForTitle(MobileQuickActionSurface surface, String title) {
  for (final key in kMobileQuickActionCanonicalKeys) {
    if (flutterTitleForMobileQuickAction(surface, key) == title) return key;
  }
  return null;
}

void _expectEachCanShowAndHide({
  required String label,
  required List<String> controllableTitles,
  required List<String> Function(List<String> keys) shown,
  required String? Function(String title) keyFor,
  Set<String> cannotHide = const {},
  Set<String> cannotShow = const {},
}) {
  final keysByTitle = <String, String>{};
  for (final title in controllableTitles) {
    final key = keyFor(title);
    expect(key, isNotNull, reason: '$label has no backend key for "$title"');
    keysByTitle[title] = key!;
  }
  final allKeys = keysByTitle.values.toList();

  for (final title in controllableTitles) {
    final only = shown([keysByTitle[title]!]);
    if (cannotShow.contains(title)) {
      expect(only, isNot(contains(title)), reason: '$label should not show "$title"');
    } else {
      expect(only, contains(title), reason: '$label failed to show "$title"');
    }

    final without = shown([
      for (final key in allKeys)
        if (key != keysByTitle[title]) key,
    ]);
    if (cannotHide.contains(title)) {
      expect(without, contains(title), reason: '$label should keep "$title"');
    } else {
      expect(without, isNot(contains(title)), reason: '$label failed to hide "$title"');
    }
  }
}

void main() {
  // Titles from AdminDashboard.getQuickActionCatalog, excluding Mobile Live
  // Test (super admin only) and Technical Specs (mapped, but not on this catalog).
  const staffQuickTitles = [
    'Projects',
    'My tasks',
    'Attendance',
    'Daily Update',
    'Indents',
    'Create Indent',
    'Stock Report',
    'Site Visits',
    'Test Reports',
    'Checklist',
    'Project Status',
    'My Notifications',
    'Payments',
    'Upgrades and Additions Cost',
    'Upload proof',
    'Approved POs',
    'Work orders',
    'Documents',
    'Scheduler',
    'Project Gallery',
    'Request Drawings',
    'Client Portal',
    'Slots',
    'Project Timeline',
    'Chat',
    '3D House Tour',
    'Inspection Requests',
  ];

  // UserDashboard configurable project-home tiles for a staff user inside a project.
  const projectNewQuickTitles = [
    'Client Portal',
    'My tasks',
    'Project Timeline',
    'Slots',
    'Project Details',
    'Indents',
    'Approved POs',
    'Payments',
    'Upgrades and Additions Cost',
    'Updates',
    'Upload proof',
    'Documents',
    'Documents V1',
    'Scheduler',
    'Project Gallery',
    '3D House Tour',
    'ChatBox',
    'Chat',
    'Project Status',
    'Checklist',
    'Request Drawings',
    'Inspection Requests',
    'Site Visit Reports',
    'Stock Report',
    'Create Indent',
    'Attendance',
    'Test Reports',
    'My Notifications',
    'Projects',
    'Technical Specs',
    'Work orders',
  ];

  const projectOldQuickTitles = [
    'For me',
    'Project Timeline',
    'Payments',
    'Upgrades and Additions Cost',
    'My tasks',
    'Slots',
    'Site Visit Reports',
    'Project Gallery',
    'Request Drawings',
  ];

  // NavMenu rows for staff when every permission is on. Home and Log out are pinned.
  const staffMoreKeys = {
    'home',
    'projects',
    'my_tasks',
    'attendance',
    'notifications',
    'updates',
    'scheduler',
    'gallery',
    'virtual_tour',
    'slots',
    'payments',
    'nt_payments',
    'indents',
    'stock_report',
    'site_visit_reports',
    'test_reports',
    'inspection_requests',
    'chatbox',
    'project_status',
    'logout',
  };

  // NavMenu rows for a client inside a project when every permission is on.
  const projectMoreKeys = {
    'home',
    'client_portal',
    'project_timeline',
    'my_tasks',
    'notifications',
    'updates',
    'scheduler',
    'timeline_gallery',
    'virtual_tour',
    'slots',
    'payments',
    'nt_payments',
    'upload_payment_proof',
    'indents',
    'chatbox',
    'logout',
  };

  group('outside a project — staff home quick actions', () {
    final catalog = _catalog(staffQuickTitles);

    test('project coordinator can show and hide every catalog tile', () {
      _expectEachCanShowAndHide(
        label: 'staff home',
        controllableTitles: staffQuickTitles,
        keyFor: (title) =>
            _quickKeyForTitle(MobileQuickActionSurface.staffHome, title),
        shown: (keys) => staffHomeShown(
          catalog: catalog,
          keys: keys,
          role: 'Project Coordinator',
        ),
      );
    });

    test('hide-all still leaves Chat, and Daily Update for admin roles', () {
      expect(
        staffHomeShown(catalog: catalog, keys: const [], role: 'Project Coordinator'),
        ['Chat'],
      );
      expect(
        staffHomeShown(catalog: catalog, keys: const [], role: 'Admin'),
        ['Daily Update', 'Chat'],
      );
      expect(
        staffHomeShown(catalog: catalog, keys: const [], role: 'Site Engineer'),
        containsAll(['Daily Update', 'Chat']),
      );
    });

    test('Technical Specs is known to the server map but not on the staff catalog', () {
      expect(
        flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.staffHome,
          'technical_specs',
        ),
        'Technical Specs',
      );
      final shown = staffHomeShown(
        catalog: catalog,
        keys: const ['technical_specs'],
        role: 'Project Coordinator',
      );
      expect(shown, isNot(contains('Technical Specs')));
    });
  });

  group('inside a project — new project home quick actions', () {
    final menu = _catalog(projectNewQuickTitles);
    final withBackendKey = projectNewQuickTitles
        .where(
          (title) =>
              _quickKeyForTitle(MobileQuickActionSurface.projectHomeNew, title) !=
              null,
        )
        .toList();

    test('staff can show and hide every keyed tile except the forced ones', () {
      _expectEachCanShowAndHide(
        label: 'new project home (staff)',
        controllableTitles: withBackendKey,
        cannotHide: {'Client Portal'},
        cannotShow: {'Documents'},
        keyFor: (title) =>
            _quickKeyForTitle(MobileQuickActionSurface.projectHomeNew, title),
        shown: (keys) => projectHomeNewShown(
          menuItems: menu,
          configurable: menu,
          keys: keys,
          isClient: false,
        ),
      );
    });

    test('clients cannot hide the pinned client tiles or show Schedule and Checklist', () {
      _expectEachCanShowAndHide(
        label: 'new project home (client)',
        controllableTitles: withBackendKey,
        cannotHide: {
          'Client Portal',
          'Project Timeline',
          'My tasks',
          'Slots',
          'Site Visit Reports',
        },
        cannotShow: {'Documents', 'Scheduler', 'Checklist'},
        keyFor: (title) =>
            _quickKeyForTitle(MobileQuickActionSurface.projectHomeNew, title),
        shown: (keys) => projectHomeNewShown(
          menuItems: menu,
          configurable: menu,
          keys: keys,
          isClient: true,
        ),
      );
    });

    test('tiles with no backend key cannot be turned on', () {
      const noKey = ['Project Details', 'Documents V1'];
      for (final title in noKey) {
        expect(
          _quickKeyForTitle(MobileQuickActionSurface.projectHomeNew, title),
          isNull,
          reason: title,
        );
      }
    });
  });

  group('inside a project — old project home quick actions', () {
    final catalog = _catalog(projectOldQuickTitles);

    test('hide-all still leaves For me, Timeline, Tasks, Slots, and Site visits', () {
      expect(
        projectHomeOldShown(catalog: catalog, keys: const []),
        [
          'For me',
          'Project Timeline',
          'My tasks',
          'Slots',
          'Site Visit Reports',
        ],
      );
    });

    test('the other old-home tiles can be shown and hidden', () {
      const flexible = [
        'Payments',
        'Upgrades and Additions Cost',
        'Project Gallery',
        'Request Drawings',
      ];
      _expectEachCanShowAndHide(
        label: 'old project home',
        controllableTitles: flexible,
        keyFor: (title) =>
            _quickKeyForTitle(MobileQuickActionSurface.projectHomeOld, title),
        shown: (keys) => projectHomeOldShown(catalog: catalog, keys: keys),
      );
    });

    test('Notes, Checklist, Scheduler, and Technical Specs are not on the old catalog', () {
      for (final key in ['chatbox', 'checklist', 'scheduler', 'technical_specs']) {
        final title = flutterTitleForMobileQuickAction(
          MobileQuickActionSurface.projectHomeOld,
          key,
        );
        expect(title, isNotNull);
        expect(projectOldQuickTitles, isNot(contains(title)));
        final shown = projectHomeOldShown(catalog: catalog, keys: [key]);
        expect(shown, isNot(contains(title)));
      }
    });
  });

  group('more menu — outside a project (staff drawer)', () {
    final flexible = staffMoreKeys
        .where((key) => key != 'home' && key != 'logout' && key != 'nt_payments')
        .toList();

    test('hide-all leaves Home and Log out', () {
      expect(
        moreMenuShown(
          surface: MobileMoreMenuSurface.staff,
          catalogKeys: staffMoreKeys,
          keys: const [],
        ),
        ['home', 'logout'],
      );
    });

    test('every other staff drawer row can be shown and hidden', () {
      for (final key in flexible) {
        expect(
          moreMenuShown(
            surface: MobileMoreMenuSurface.staff,
            catalogKeys: staffMoreKeys,
            keys: [key],
          ),
          ['home', key, 'logout'],
          reason: key,
        );
        expect(
          moreMenuShown(
            surface: MobileMoreMenuSurface.staff,
            catalogKeys: staffMoreKeys,
            keys: [for (final other in flexible) if (other != key) other],
          ),
          isNot(contains(key)),
          reason: key,
        );
      }
    });

    test('Upgrades cannot be shown: staff drawer has the row, the title map does not', () {
      expect(
        flutterTitleForMobileMoreMenu(MobileMoreMenuSurface.staff, 'nt_payments'),
        isNull,
      );
      expect(
        moreMenuShown(
          surface: MobileMoreMenuSurface.staff,
          catalogKeys: staffMoreKeys,
          keys: const ['nt_payments'],
        ),
        ['home', 'logout'],
      );
    });

    test('Documents rows are not in the staff drawer, so the server cannot show them', () {
      expect(
        moreMenuShown(
          surface: MobileMoreMenuSurface.staff,
          catalogKeys: staffMoreKeys,
          keys: const ['documents', 'documents_v1'],
        ),
        ['home', 'logout'],
      );
    });
  });

  group('more menu — inside a project (client drawer)', () {
    final flexible =
        projectMoreKeys.where((key) => key != 'home' && key != 'logout').toList();

    for (final surface in [
      MobileMoreMenuSurface.projectNew,
      MobileMoreMenuSurface.projectOld,
    ]) {
      test('${surface.apiName} can show and hide every drawer row except Home and Log out', () {
        expect(
          moreMenuShown(
            surface: surface,
            catalogKeys: projectMoreKeys,
            keys: const [],
          ),
          ['home', 'logout'],
        );
        for (final key in flexible) {
          expect(
            moreMenuShown(
              surface: surface,
              catalogKeys: projectMoreKeys,
              keys: [key],
            ),
            ['home', key, 'logout'],
            reason: key,
          );
          expect(
            moreMenuShown(
              surface: surface,
              catalogKeys: projectMoreKeys,
              keys: [for (final other in flexible) if (other != key) other],
            ),
            isNot(contains(key)),
            reason: key,
          );
        }
      });
    }
  });
}
