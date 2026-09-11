/// Backend-driven Mobile More Menu (side drawer): keys, surfaces, and resolution.
///
/// The backend (`GET /API/mobile/more-menu`) controls **which known drawer
/// items appear and in what order**. Flutter still owns widgets, icons,
/// labels, routes, section chrome, and authorization checks in
/// `NavMenuWidget._sectionsForRole()`.
///
/// Quick Actions (`mobile_quick_actions.dart`) stay a separate catalog.
/// Canonical keys are reused when they name the same feature. Distinct
/// drawer rows that Quick Actions collapse (Documents vs Documents V1,
/// Project Timeline vs Timeline Gallery) keep separate keys.

import 'mobile_quick_actions.dart';

/// Canonical surfaces accepted by `GET /API/mobile/more-menu?surface=`.
///
/// Named from the real home shells, not assumed placeholders:
/// * [staff] — `AdminDashboard` / staff `NavMenuWidget` (role != Client)
/// * [projectNew] — new project home (`UserDashboard`) Client drawer
/// * [projectOld] — legacy project UI (`LegacyClientHome` has no drawer on
///   home itself; Client sub-screens still mount `NavMenuWidget`)
enum MobileMoreMenuSurface {
  staff('more_drawer_staff'),
  projectOld('more_drawer_project_old'),
  projectNew('more_drawer_project_new');

  const MobileMoreMenuSurface(this.apiName);
  final String apiName;

  static MobileMoreMenuSurface? parse(String? raw) {
    final value = (raw ?? '').trim();
    for (final surface in MobileMoreMenuSurface.values) {
      if (surface.apiName == value) return surface;
    }
    return null;
  }
}

/// Snapshot of one surface's More Menu configuration.
class MobileMoreMenuSnapshot {
  const MobileMoreMenuSnapshot({
    required this.surface,
    required this.configured,
    required this.actionKeys,
    this.role,
    this.userId,
    this.cachedAt,
  });

  final MobileMoreMenuSurface surface;

  /// `false` → Flutter must use the existing hardcoded drawer.
  /// `true` + empty [actionKeys] → intentional hide of configurable items.
  final bool configured;
  final List<String> actionKeys;
  final String? role;
  final String? userId;
  final DateTime? cachedAt;

  bool get isIntentionalEmpty => configured && actionKeys.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'surface': surface.apiName,
      'configured': configured,
      'actions': actionKeys,
      if (role != null) 'role': role,
      if (userId != null) 'user_id': userId,
      if (cachedAt != null) 'cached_at': cachedAt!.toIso8601String(),
    };
  }

  static MobileMoreMenuSnapshot? fromJson(
    Map<String, dynamic>? json, {
    MobileMoreMenuSurface? expectedSurface,
  }) {
    if (json == null) return null;
    final surface = MobileMoreMenuSurface.parse(json['surface']?.toString()) ??
        expectedSurface;
    if (surface == null) return null;
    if (expectedSurface != null && surface != expectedSurface) return null;

    final configured = parseConfiguredFlag(json['configured']);
    final keys = extractActionKeys(json['actions']);
    if (configured == null && keys.isEmpty) {
      return null;
    }
    return MobileMoreMenuSnapshot(
      surface: surface,
      configured: configured ?? keys.isNotEmpty,
      actionKeys: keys,
      role: json['role']?.toString(),
      userId: (json['user_id'] ?? json['userId'])?.toString(),
      cachedAt: DateTime.tryParse(json['cached_at']?.toString() ?? ''),
    );
  }
}

/// Always shown when present in the RBAC catalog. Backend cannot hide these.
const String kMobileMoreMenuHomeKey = 'home';
const String kMobileMoreMenuLogoutKey = 'logout';

const Set<String> kMobileMoreMenuPinnedKeys = {
  kMobileMoreMenuHomeKey,
  kMobileMoreMenuLogoutKey,
};

/// Canonical keys for More Menu rows that exist in `NavMenu.dart`.
/// Reuses Quick Action catalog keys wherever the feature is the same.
const Set<String> kMobileMoreMenuCanonicalKeys = {
  kMobileMoreMenuHomeKey,
  'projects',
  'client_portal',
  'project_timeline',
  'my_tasks',
  'attendance',
  'notifications',
  'updates',
  'scheduler',
  'documents',
  'documents_v1',
  'gallery',
  'timeline_gallery',
  'virtual_tour',
  'slots',
  'payments',
  'nt_payments',
  'upload_payment_proof',
  'indents',
  'stock_report',
  'site_visit_reports',
  'test_reports',
  'inspection_requests',
  'chatbox',
  'project_status',
  'mobile_live_test',
  kMobileMoreMenuLogoutKey,
};

/// More Menu aliases. `documents_v1` and `timeline_gallery` stay distinct
/// (they are separate drawer rows; Quick Actions collapse them).
const Map<String, String> kMobileMoreMenuAliases = {
  'chat_v1': 'chatbox',
  'daily_update': 'updates',
  'site_visits': 'site_visit_reports',
  'log_out': kMobileMoreMenuLogoutKey,
  'sign_out': kMobileMoreMenuLogoutKey,
};

/// Canonical backend key → existing Flutter drawer `entry.title`.
///
/// Keys with no title on a surface are skipped there (same as unknown keys).
const Map<String, String> kMobileMoreMenuProjectTitles = {
  kMobileMoreMenuHomeKey: 'Home',
  'client_portal': 'Client Portal',
  'project_timeline': 'Project Timeline',
  'my_tasks': 'My Tasks',
  'notifications': 'Notifications',
  'updates': 'Updates',
  'scheduler': 'Scheduler',
  'timeline_gallery': 'Timeline Gallery',
  'virtual_tour': 'Virtual Tour',
  'slots': 'Slots',
  'payments': 'Payments',
  'nt_payments': 'NT Payments',
  'upload_payment_proof': 'Upload proof',
  'indents': 'Indents',
  'chatbox': 'Chat V1',
  'mobile_live_test': 'Mobile Live Test',
  kMobileMoreMenuLogoutKey: 'Log out',
};

const Map<MobileMoreMenuSurface, Map<String, String>>
    kMobileMoreMenuTitlesBySurface = {
  MobileMoreMenuSurface.staff: {
    kMobileMoreMenuHomeKey: 'Home',
    'projects': 'Projects',
    'my_tasks': 'My Tasks',
    'attendance': 'Attendance',
    'notifications': 'Notifications',
    'updates': 'Daily Update',
    'scheduler': 'Scheduler',
    'documents': 'Documents',
    'documents_v1': 'Documents V1',
    'gallery': 'Gallery',
    'timeline_gallery': 'Timeline Gallery',
    'virtual_tour': 'Virtual Tour',
    'slots': 'Slots',
    'payments': 'Payments',
    'indents': 'Indents',
    'stock_report': 'Stock Report',
    'site_visit_reports': 'Site Visits',
    'test_reports': 'Test Reports',
    'inspection_requests': 'Inspection Requests',
    'chatbox': 'Chat V1',
    'project_status': 'Project Status',
    'mobile_live_test': 'Mobile Live Test',
    kMobileMoreMenuLogoutKey: 'Log out',
  },
  MobileMoreMenuSurface.projectOld: kMobileMoreMenuProjectTitles,
  MobileMoreMenuSurface.projectNew: kMobileMoreMenuProjectTitles,
};

/// Pick the More Menu surface from the stored login role + project generation.
///
/// Does not transform roles: Super Admin is already stored as `Admin`,
/// Assistant project coordinator as `Project Coordinator`.
MobileMoreMenuSurface moreMenuSurfaceFor({
  required String? role,
  required bool useLegacyProjectUi,
}) {
  if ((role ?? '').trim() == 'Client') {
    return useLegacyProjectUi
        ? MobileMoreMenuSurface.projectOld
        : MobileMoreMenuSurface.projectNew;
  }
  return MobileMoreMenuSurface.staff;
}

/// Collapse a backend/alias/title string onto a More Menu canonical key.
/// Returns empty when the installed app does not know the key.
String canonicalizeMobileMoreMenuKey(String? raw) {
  final slug = slugifyQuickActionKey(raw ?? '');
  if (slug.isEmpty) return '';
  if (kMobileMoreMenuCanonicalKeys.contains(slug)) return slug;

  final moreAlias = kMobileMoreMenuAliases[slug];
  if (moreAlias != null) return moreAlias;

  // Reuse Quick Action aliases except those that would merge distinct
  // drawer rows (`documents_v1`, `timeline_gallery`).
  if (slug == 'documents_v1' || slug == 'timeline_gallery') {
    return slug;
  }

  final backendAlias = kMobileQuickActionBackendAliases[slug];
  if (backendAlias != null &&
      kMobileMoreMenuCanonicalKeys.contains(backendAlias)) {
    return backendAlias;
  }
  final flutterAlias = kMobileQuickActionFlutterAliases[slug];
  if (flutterAlias != null &&
      kMobileMoreMenuCanonicalKeys.contains(flutterAlias)) {
    return flutterAlias;
  }
  return '';
}

String? flutterTitleForMobileMoreMenu(
  MobileMoreMenuSurface surface,
  String canonicalKey,
) {
  return kMobileMoreMenuTitlesBySurface[surface]?[canonicalKey];
}

bool isPinnedMoreMenuKey(String canonicalKey) {
  return kMobileMoreMenuPinnedKeys.contains(canonicalKey);
}

/// Parse a successful HTTP body. Returns null when the payload is unusable
/// (caller must fall back to the hardcoded drawer).
MobileMoreMenuSnapshot? parseMobileMoreMenuPayload(
  dynamic decoded, {
  required MobileMoreMenuSurface surface,
}) {
  if (decoded is! Map) return null;
  final json = Map<String, dynamic>.from(decoded);
  if (!isSuccessfulMobileActionsPayload(json)) return null;
  if (!json.containsKey('actions') && !json.containsKey('configured')) {
    return null;
  }

  final rawActions = json['actions'];
  if (rawActions != null && rawActions is! List) return null;

  final keys = extractActionKeys(rawActions);
  final configuredFlag = parseConfiguredFlag(json['configured']);
  final configured = configuredFlag ?? keys.isNotEmpty;

  return MobileMoreMenuSnapshot(
    surface: MobileMoreMenuSurface.parse(json['surface']?.toString()) ??
        surface,
    configured: configured,
    actionKeys: keys,
    role: json['role']?.toString(),
    userId: (json['user_id'] ?? json['userId'])?.toString(),
  );
}

/// Apply backend visibility/order on top of the existing RBAC drawer catalog.
///
/// * No snapshot / `configured != true` → [fallbackKeys] (hardcoded drawer).
/// * `configured == true` → backend order, skipping unknown keys and any
///   key that is not in [catalogKeys] (keeps RBAC / role checks intact).
/// * `home` and `logout` stay pinned when they exist in the catalog.
List<String> resolveMobileMoreMenuActionKeys({
  required MobileMoreMenuSurface surface,
  required Set<String> catalogKeys,
  required List<String> fallbackKeys,
  MobileMoreMenuSnapshot? snapshot,
}) {
  if (snapshot == null || !snapshot.configured) {
    return List<String>.from(fallbackKeys);
  }

  final resolved = <String>[];
  final seen = <String>{};

  void addIfAllowed(String key) {
    if (key.isEmpty) return;
    if (!catalogKeys.contains(key)) return;
    if (flutterTitleForMobileMoreMenu(surface, key) == null) return;
    if (!seen.add(key)) return;
    resolved.add(key);
  }

  addIfAllowed(kMobileMoreMenuHomeKey);

  for (final rawKey in snapshot.actionKeys) {
    final canonical = canonicalizeMobileMoreMenuKey(rawKey);
    if (canonical.isEmpty) continue;
    if (isPinnedMoreMenuKey(canonical)) continue;
    addIfAllowed(canonical);
  }

  addIfAllowed(kMobileMoreMenuLogoutKey);
  return resolved;
}

String mobileMoreMenuCacheKey({
  required String userId,
  required String role,
  required MobileMoreMenuSurface surface,
}) {
  final uid = userId.trim().isEmpty ? '_' : userId.trim();
  final roleKey = role.trim().isEmpty ? '_' : role.trim();
  return 'mobile_more_v1_${uid}_${roleKey}_${surface.apiName}';
}
