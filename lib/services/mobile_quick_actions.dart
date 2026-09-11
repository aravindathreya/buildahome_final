/// Backend-driven Mobile Quick Actions: keys, surfaces, and resolution.
///
/// The backend (`GET /API/mobile/actions`) controls **which known actions
/// appear and in what order**. Flutter still owns widgets, icons, labels,
/// routes, and authorization checks in each surface's `getMenuItems()`.

/// Canonical surfaces accepted by `GET /API/mobile/actions?surface=`.
enum MobileQuickActionSurface {
  staffHome('staff_home'),
  projectHomeOld('project_home_old'),
  projectHomeNew('project_home_new');

  const MobileQuickActionSurface(this.apiName);
  final String apiName;

  static MobileQuickActionSurface? parse(String? raw) {
    final value = (raw ?? '').trim();
    for (final surface in MobileQuickActionSurface.values) {
      if (surface.apiName == value) return surface;
    }
    return null;
  }
}

/// Snapshot of one surface's Quick Action configuration.
class MobileQuickActionsSnapshot {
  const MobileQuickActionsSnapshot({
    required this.surface,
    required this.configured,
    required this.actionKeys,
    this.role,
    this.userId,
    this.cachedAt,
  });

  final MobileQuickActionSurface surface;

  /// `false` → Flutter must use the existing hardcoded list.
  /// `true` + empty [actionKeys] → intentional hide-all.
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

  static MobileQuickActionsSnapshot? fromJson(
    Map<String, dynamic>? json, {
    MobileQuickActionSurface? expectedSurface,
  }) {
    if (json == null) return null;
    final surface = MobileQuickActionSurface.parse(json['surface']?.toString()) ??
        expectedSurface;
    if (surface == null) return null;
    if (expectedSurface != null && surface != expectedSurface) return null;

    final configured = parseConfiguredFlag(json['configured']);
    final keys = extractActionKeys(json['actions']);
    if (configured == null && keys.isEmpty) {
      // Cached payload without a flag and with no keys is not usable.
      return null;
    }
    return MobileQuickActionsSnapshot(
      surface: surface,
      configured: configured ?? keys.isNotEmpty,
      actionKeys: keys,
      role: json['role']?.toString(),
      userId: (json['user_id'] ?? json['userId'])?.toString(),
      cachedAt: DateTime.tryParse(json['cached_at']?.toString() ?? ''),
    );
  }
}

/// Canonical keys from `mobile_actions.catalog` (backend).
/// Aliases collapse onto these — do not add duplicate catalog keys.
const Set<String> kMobileQuickActionCanonicalKeys = {
  'payments',
  'nt_payments',
  'upload_payment_proof',
  'my_tasks',
  'project_status',
  'indents',
  'create_indent',
  'approved_pos',
  'documents',
  'scheduler',
  'gallery',
  'checklist',
  'request_drawings',
  'client_portal',
  'slots',
  'project_timeline',
  'chatbox',
  'updates',
  'virtual_tour',
  'inspection_requests',
  'site_visit_reports',
  'projects',
  'attendance',
  'stock_report',
  'test_reports',
  'notifications',
  'mobile_live_test',
  'work_orders',
};

/// Backend catalog aliases → canonical key.
const Map<String, String> kMobileQuickActionBackendAliases = {
  'documents_v1': 'documents',
  'chat_v1': 'chatbox',
  'daily_update': 'updates',
  'timeline_gallery': 'project_timeline',
};

/// Extra incoming strings that must resolve to a canonical key.
/// `upload_proof` is the live Flutter title; `upload_payment_proofs` was a
/// hardcoded pin-list typo and must not become its own key.
const Map<String, String> kMobileQuickActionFlutterAliases = {
  'upload_proof': 'upload_payment_proof',
  'upload_payment_proofs': 'upload_payment_proof',
};

/// Canonical backend key → existing Flutter `item['title']` on each surface.
///
/// Keys with no title on a surface are skipped there (same as unknown keys).
const Map<MobileQuickActionSurface, Map<String, String>>
    kMobileQuickActionTitlesBySurface = {
  MobileQuickActionSurface.staffHome: {
    'payments': 'Payments',
    'nt_payments': 'NT Payments',
    'upload_payment_proof': 'Upload proof',
    'my_tasks': 'My tasks',
    'project_status': 'Project Status',
    'indents': 'Indents',
    'create_indent': 'Create Indent',
    'approved_pos': 'Approved POs',
    'documents': 'Documents',
    'scheduler': 'Scheduler',
    'gallery': 'Gallery',
    'checklist': 'Checklist',
    'request_drawings': 'Request Drawings',
    'client_portal': 'Client Portal',
    'slots': 'Slots',
    'project_timeline': 'Project Timeline',
    'chatbox': 'Chat V1',
    'updates': 'Daily Update',
    'virtual_tour': 'Virtual Tour',
    'inspection_requests': 'Inspection Requests',
    'site_visit_reports': 'Site Visits',
    'projects': 'Projects',
    'attendance': 'Attendance',
    'stock_report': 'Stock Report',
    'test_reports': 'Test Reports',
    'notifications': 'My Notifications',
    'mobile_live_test': 'Mobile Live Test',
    'work_orders': 'Work orders',
  },
  MobileQuickActionSurface.projectHomeOld: {
    'payments': 'Payments',
    'nt_payments': 'NT Payments',
    'scheduler': 'Scheduler',
    'gallery': 'Gallery',
    'chatbox': 'Notes & Comments',
    'checklist': 'Checklist',
    'request_drawings': 'Request Drawings',
  },
  MobileQuickActionSurface.projectHomeNew: {
    'client_portal': 'Client Portal',
    'my_tasks': 'My tasks',
    'project_timeline': 'Project Timeline',
    'slots': 'Slots',
    'indents': 'Indents',
    'approved_pos': 'Approved POs',
    'work_orders': 'Work orders',
    'payments': 'Payments',
    'nt_payments': 'NT Payments',
    'updates': 'Updates',
    'upload_payment_proof': 'Upload proof',
    'documents': 'Documents',
    'scheduler': 'Scheduler',
    'gallery': 'Gallery',
    'virtual_tour': 'Virtual Tour',
    'chatbox': 'ChatBox',
    'project_status': 'Project Status',
    'checklist': 'Checklist',
    'request_drawings': 'Request Drawings',
    'inspection_requests': 'Inspection Requests',
    'site_visit_reports': 'Site Visit Reports',
    'mobile_live_test': 'Mobile Live Test',
  },
};

String slugifyQuickActionKey(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
}

/// Collapse a backend/alias/title string onto a canonical catalog key.
/// Returns empty when the installed app does not know the key.
String canonicalizeMobileQuickActionKey(String? raw) {
  final slug = slugifyQuickActionKey(raw ?? '');
  if (slug.isEmpty) return '';
  if (kMobileQuickActionCanonicalKeys.contains(slug)) return slug;
  final backendAlias = kMobileQuickActionBackendAliases[slug];
  if (backendAlias != null) return backendAlias;
  final flutterAlias = kMobileQuickActionFlutterAliases[slug];
  if (flutterAlias != null) return flutterAlias;
  return '';
}

String? flutterTitleForMobileQuickAction(
  MobileQuickActionSurface surface,
  String canonicalKey,
) {
  return kMobileQuickActionTitlesBySurface[surface]?[canonicalKey];
}

bool? parseConfiguredFlag(dynamic raw) {
  if (raw is bool) return raw;
  if (raw == 1 || raw == '1' || raw == 'true' || raw == 'True') return true;
  if (raw == 0 || raw == '0' || raw == 'false' || raw == 'False') return false;
  return null;
}

/// Pull ordered keys from `actions: ["gallery", {"key":"payments"}]`.
List<String> extractActionKeys(dynamic raw) {
  if (raw is! List) return const [];
  final rows = <_ActionKeyRow>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    String? key;
    var sort = i;
    if (item is String) {
      key = item;
    } else if (item is Map) {
      key = (item['key'] ?? item['action_key'] ?? item['actionKey'])
          ?.toString();
      sort = int.tryParse('${item['sort_order'] ?? item['sortOrder'] ?? i}') ??
          i;
    }
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) continue;
    rows.add(_ActionKeyRow(trimmed, sort, i));
  }
  rows.sort((a, b) {
    final bySort = a.sort.compareTo(b.sort);
    return bySort != 0 ? bySort : a.index.compareTo(b.index);
  });
  return [for (final row in rows) row.key];
}

class _ActionKeyRow {
  const _ActionKeyRow(this.key, this.sort, this.index);
  final String key;
  final int sort;
  final int index;
}

bool isSuccessfulMobileActionsPayload(Map<String, dynamic> json) {
  final message = json['message']?.toString().trim().toLowerCase();
  if (message == 'success') return true;
  final success = json['success'];
  if (success is bool) return success;
  if (success == 1 || success == '1' || success == 'true') return true;
  if (success == false || success == 0 || success == '0' || success == 'false') {
    return false;
  }
  // Some office APIs omit both fields on 200. Presence of `actions` is enough.
  return json.containsKey('actions') || json.containsKey('configured');
}

/// Parse a successful HTTP body. Returns null when the payload is unusable
/// (caller must fall back to hardcoded Quick Actions).
MobileQuickActionsSnapshot? parseMobileQuickActionsPayload(
  dynamic decoded, {
  required MobileQuickActionSurface surface,
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

  return MobileQuickActionsSnapshot(
    surface: MobileQuickActionSurface.parse(json['surface']?.toString()) ??
        surface,
    configured: configured,
    actionKeys: keys,
    role: json['role']?.toString(),
    userId: (json['user_id'] ?? json['userId'])?.toString(),
  );
}

/// Apply backend visibility/order on top of an existing `getMenuItems()` list.
///
/// * No snapshot / `configured != true` → [fallback] (hardcoded behavior).
/// * `configured == true` → backend order, skipping unknown keys and any
///   title that is not in [catalog] (keeps RBAC / role checks intact).
List<Map<String, dynamic>> resolveMobileQuickActions({
  required MobileQuickActionSurface surface,
  required List<Map<String, dynamic>> catalog,
  required List<Map<String, dynamic>> fallback,
  MobileQuickActionsSnapshot? snapshot,
}) {
  if (snapshot == null || !snapshot.configured) {
    return List<Map<String, dynamic>>.from(fallback);
  }

  final byTitle = <String, Map<String, dynamic>>{};
  for (final item in catalog) {
    final title = item['title']?.toString();
    if (title == null || title.isEmpty) continue;
    byTitle.putIfAbsent(title, () => item);
  }

  final resolved = <Map<String, dynamic>>[];
  final seenTitles = <String>{};
  for (final rawKey in snapshot.actionKeys) {
    final canonical = canonicalizeMobileQuickActionKey(rawKey);
    if (canonical.isEmpty) continue;
    final title = flutterTitleForMobileQuickAction(surface, canonical);
    if (title == null) continue;
    if (!seenTitles.add(title)) continue;
    final item = byTitle[title];
    if (item == null) continue;
    resolved.add(item);
  }
  return resolved;
}

String mobileQuickActionsCacheKey({
  required String userId,
  required String role,
  required MobileQuickActionSurface surface,
}) {
  final uid = userId.trim().isEmpty ? '_' : userId.trim();
  final roleKey = role.trim().isEmpty ? '_' : role.trim();
  return 'mobile_qa_v1_${uid}_${roleKey}_${surface.apiName}';
}
