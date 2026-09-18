/// Backend-driven Mobile Bottom Nav: keys, surfaces, and resolution.
///
/// The backend (`GET /API/mobile/bottom-nav`) controls **which known tabs
/// appear and in what order**. Flutter still owns icons, short labels,
/// routes, and shell behavior (`home` / `more`).
///
/// Same contract shape as Quick Actions / More Menu (`configured` + ordered
/// `{key, sort_order}` actions).

import 'package:flutter/material.dart';

import 'mobile_quick_actions.dart';

/// Canonical surfaces accepted by `GET /API/mobile/bottom-nav?surface=`.
enum MobileBottomNavSurface {
  staff('bottom_nav_staff'),
  projectNew('bottom_nav_project_new'),
  projectOld('bottom_nav_project_old');

  const MobileBottomNavSurface(this.apiName);
  final String apiName;

  static MobileBottomNavSurface? parse(String? raw) {
    final value = (raw ?? '').trim();
    for (final surface in MobileBottomNavSurface.values) {
      if (surface.apiName == value) return surface;
    }
    return null;
  }
}

/// Snapshot of one surface's bottom-nav configuration.
class MobileBottomNavSnapshot {
  const MobileBottomNavSnapshot({
    required this.surface,
    required this.configured,
    required this.actionKeys,
    this.role,
    this.userId,
    this.cachedAt,
  });

  final MobileBottomNavSurface surface;

  /// `false` → Flutter must use the hardcoded fallback bar.
  /// `true` + empty middle keys → still show pinned `home` / `more`.
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

  static MobileBottomNavSnapshot? fromJson(
    Map<String, dynamic>? json, {
    MobileBottomNavSurface? expectedSurface,
  }) {
    if (json == null) return null;
    final surface =
        MobileBottomNavSurface.parse(json['surface']?.toString()) ??
            expectedSurface;
    if (surface == null) return null;
    if (expectedSurface != null && surface != expectedSurface) return null;

    final configured = parseConfiguredFlag(json['configured']);
    final keys = extractActionKeys(json['actions']);
    if (configured == null && keys.isEmpty) {
      return null;
    }
    return MobileBottomNavSnapshot(
      surface: surface,
      configured: configured ?? keys.isNotEmpty,
      actionKeys: keys,
      role: json['role']?.toString(),
      userId: (json['user_id'] ?? json['userId'])?.toString(),
      cachedAt: DateTime.tryParse(json['cached_at']?.toString() ?? ''),
    );
  }
}

const String kMobileBottomNavHomeKey = 'home';
const String kMobileBottomNavMoreKey = 'more';

const Set<String> kMobileBottomNavPinnedKeys = {
  kMobileBottomNavHomeKey,
  kMobileBottomNavMoreKey,
};

/// Hard UI cap including Home + More (matches backend).
const int kMobileBottomNavHardMaxTabs = 7;

/// Canonical keys the installed app can render in the bottom bar.
const Set<String> kMobileBottomNavCanonicalKeys = {
  kMobileBottomNavHomeKey,
  kMobileBottomNavMoreKey,
  'my_tasks',
  'projects',
  'site_visit_reports',
  'updates',
  'chatbox',
  'documents',
  'documents_v1',
  'gallery',
  'scheduler',
  'payments',
  'nt_payments',
  'upload_payment_proof',
  'indents',
  'approved_pos',
  'work_orders',
  'client_portal',
  'project_timeline',
  'slots',
  'attendance',
  'notifications',
  'stock_report',
  'test_reports',
  'inspection_requests',
  'project_status',
  'virtual_tour',
  'checklist',
  'request_drawings',
  'create_indent',
  'mobile_live_test',
};

const Map<String, String> kMobileBottomNavAliases = {
  'chat_v1': 'chatbox',
  'daily_update': 'updates',
  'site_visits': 'site_visit_reports',
  'tasks': 'my_tasks',
  'chat': 'chatbox',
};

/// Short bottom-bar labels (not Quick Action titles).
const Map<String, String> kMobileBottomNavLabels = {
  kMobileBottomNavHomeKey: 'Home',
  kMobileBottomNavMoreKey: 'More',
  'my_tasks': 'Tasks',
  'projects': 'Projects',
  'site_visit_reports': 'Site Visits',
  'updates': 'Updates',
  'chatbox': 'Chat',
  'documents': 'Docs',
  'documents_v1': 'Docs',
  'gallery': 'Gallery',
  'scheduler': 'Schedule',
  'payments': 'Payments',
  'nt_payments': 'NT Pay',
  'upload_payment_proof': 'Proof',
  'indents': 'Indents',
  'approved_pos': 'POs',
  'work_orders': 'WOs',
  'client_portal': 'Portal',
  'project_timeline': 'Timeline',
  'slots': 'Slots',
  'attendance': 'Attendance',
  'notifications': 'Alerts',
  'stock_report': 'Stock',
  'test_reports': 'Tests',
  'inspection_requests': 'Inspect',
  'project_status': 'Status',
  'virtual_tour': 'Tour',
  'checklist': 'Checklist',
  'request_drawings': 'Drawings',
  'create_indent': 'New Indent',
  'mobile_live_test': 'Live Test',
};

/// Active (selected) icons for each tab.
const Map<String, IconData> kMobileBottomNavActiveIcons = {
  kMobileBottomNavHomeKey: Icons.home_rounded,
  kMobileBottomNavMoreKey: Icons.menu_rounded,
  'my_tasks': Icons.pending_actions_rounded,
  'projects': Icons.folder_special_rounded,
  'site_visit_reports': Icons.location_on_rounded,
  'updates': Icons.description_rounded,
  'chatbox': Icons.chat_bubble_rounded,
  'documents': Icons.folder_copy_rounded,
  'documents_v1': Icons.folder_copy_rounded,
  'gallery': Icons.photo_library_rounded,
  'scheduler': Icons.calendar_today_rounded,
  'payments': Icons.payments_rounded,
  'nt_payments': Icons.receipt_long_rounded,
  'upload_payment_proof': Icons.cloud_upload_rounded,
  'indents': Icons.request_quote_rounded,
  'approved_pos': Icons.receipt_long_rounded,
  'work_orders': Icons.engineering_rounded,
  'client_portal': Icons.dashboard_customize_rounded,
  'project_timeline': Icons.timeline_rounded,
  'slots': Icons.event_available_rounded,
  'attendance': Icons.fingerprint_rounded,
  'notifications': Icons.notifications_rounded,
  'stock_report': Icons.inventory_2_rounded,
  'test_reports': Icons.science_rounded,
  'inspection_requests': Icons.fact_check_rounded,
  'project_status': Icons.flag_rounded,
  'virtual_tour': Icons.view_in_ar_rounded,
  'checklist': Icons.checklist_rtl_rounded,
  'request_drawings': Icons.architecture_rounded,
  'create_indent': Icons.add_box_rounded,
  'mobile_live_test': Icons.phonelink_setup_rounded,
};

/// Inactive (outlined) icons for each tab.
const Map<String, IconData> kMobileBottomNavOutlinedIcons = {
  kMobileBottomNavHomeKey: Icons.home_outlined,
  kMobileBottomNavMoreKey: Icons.menu_rounded,
  'my_tasks': Icons.pending_actions_outlined,
  'projects': Icons.folder_special_outlined,
  'site_visit_reports': Icons.location_on_outlined,
  'updates': Icons.description_outlined,
  'chatbox': Icons.chat_bubble_outline_rounded,
  'documents': Icons.folder_copy_outlined,
  'documents_v1': Icons.folder_copy_outlined,
  'gallery': Icons.photo_library_outlined,
  'scheduler': Icons.calendar_today_outlined,
  'payments': Icons.payments_outlined,
  'nt_payments': Icons.receipt_long_outlined,
  'upload_payment_proof': Icons.cloud_upload_outlined,
  'indents': Icons.request_quote_outlined,
  'approved_pos': Icons.receipt_long_outlined,
  'work_orders': Icons.engineering_outlined,
  'client_portal': Icons.dashboard_customize_outlined,
  'project_timeline': Icons.timeline_outlined,
  'slots': Icons.event_available_outlined,
  'attendance': Icons.fingerprint_rounded,
  'notifications': Icons.notifications_none_rounded,
  'stock_report': Icons.inventory_2_outlined,
  'test_reports': Icons.science_outlined,
  'inspection_requests': Icons.fact_check_outlined,
  'project_status': Icons.flag_outlined,
  'virtual_tour': Icons.view_in_ar_outlined,
  'checklist': Icons.checklist_rtl_rounded,
  'request_drawings': Icons.architecture_outlined,
  'create_indent': Icons.add_box_outlined,
  'mobile_live_test': Icons.phonelink_setup_outlined,
};

/// Canonical key → Flutter Quick Action / menu `title` used for navigation.
const Map<MobileBottomNavSurface, Map<String, String>>
    kMobileBottomNavTitlesBySurface = {
  MobileBottomNavSurface.staff: {
    'my_tasks': 'My tasks',
    'projects': 'Projects',
    'site_visit_reports': 'Site Visits',
    'updates': 'Daily Update',
    'chatbox': 'Chat V1',
    'documents': 'Documents',
    'gallery': 'Gallery',
    'scheduler': 'Scheduler',
    'payments': 'Payments',
    'nt_payments': 'NT Payments',
    'upload_payment_proof': 'Upload proof',
    'indents': 'Indents',
    'approved_pos': 'Approved POs',
    'work_orders': 'Work orders',
    'client_portal': 'Client Portal',
    'project_timeline': 'Project Timeline',
    'slots': 'Slots',
    'attendance': 'Attendance',
    'notifications': 'My Notifications',
    'stock_report': 'Stock Report',
    'test_reports': 'Test Reports',
    'inspection_requests': 'Inspection Requests',
    'project_status': 'Project Status',
    'virtual_tour': 'Virtual Tour',
    'checklist': 'Checklist',
    'request_drawings': 'Request Drawings',
    'create_indent': 'Create Indent',
    'mobile_live_test': 'Mobile Live Test',
  },
  MobileBottomNavSurface.projectNew: {
    'my_tasks': 'My tasks',
    'updates': 'Updates',
    'chatbox': 'ChatBox',
    'documents': 'Documents',
    'documents_v1': 'Documents',
    'gallery': 'Gallery',
    'scheduler': 'Scheduler',
    'payments': 'Payments',
    'nt_payments': 'NT Payments',
    'upload_payment_proof': 'Upload proof',
    'indents': 'Indents',
    'approved_pos': 'Approved POs',
    'work_orders': 'Work orders',
    'client_portal': 'Client Portal',
    'project_timeline': 'Project Timeline',
    'slots': 'Slots',
    'notifications': 'Notifications',
    'inspection_requests': 'Inspection Requests',
    'site_visit_reports': 'Site Visit Reports',
    'project_status': 'Project Status',
    'virtual_tour': 'Virtual Tour',
    'checklist': 'Checklist',
    'request_drawings': 'Request Drawings',
    'mobile_live_test': 'Mobile Live Test',
  },
  MobileBottomNavSurface.projectOld: {
    'my_tasks': 'My tasks',
    'updates': 'Updates',
    'chatbox': 'ChatBox',
    'documents': 'Documents',
    'gallery': 'Gallery',
    'scheduler': 'Scheduler',
    'payments': 'Payments',
    'nt_payments': 'NT Payments',
    'upload_payment_proof': 'Upload proof',
    'indents': 'Indents',
    'client_portal': 'Client Portal',
    'project_timeline': 'Project Timeline',
    'slots': 'Slots',
    'notifications': 'Notifications',
    'project_status': 'Project Status',
    'virtual_tour': 'Virtual Tour',
    'checklist': 'Checklist',
    'request_drawings': 'Request Drawings',
    'mobile_live_test': 'Mobile Live Test',
  },
};

const List<String> kMobileBottomNavStaffFallback = [
  kMobileBottomNavHomeKey,
  'my_tasks',
  'projects',
  'site_visit_reports',
  kMobileBottomNavMoreKey,
];

const List<String> kMobileBottomNavProjectFallback = [
  kMobileBottomNavHomeKey,
  'my_tasks',
  'updates',
  'chatbox',
  kMobileBottomNavMoreKey,
];

/// Staff home bar vs project home bar (new/old by client generation).
MobileBottomNavSurface bottomNavSurfaceFor({
  required bool isStaffHome,
  required bool useLegacyProjectUi,
}) {
  if (isStaffHome) return MobileBottomNavSurface.staff;
  return useLegacyProjectUi
      ? MobileBottomNavSurface.projectOld
      : MobileBottomNavSurface.projectNew;
}

List<String> fallbackBottomNavKeysFor(MobileBottomNavSurface surface) {
  switch (surface) {
    case MobileBottomNavSurface.staff:
      return List<String>.from(kMobileBottomNavStaffFallback);
    case MobileBottomNavSurface.projectNew:
    case MobileBottomNavSurface.projectOld:
      return List<String>.from(kMobileBottomNavProjectFallback);
  }
}

String canonicalizeMobileBottomNavKey(String? raw) {
  final slug = slugifyQuickActionKey(raw ?? '');
  if (slug.isEmpty) return '';
  if (kMobileBottomNavCanonicalKeys.contains(slug)) return slug;

  final alias = kMobileBottomNavAliases[slug];
  if (alias != null) return alias;

  final backendAlias = kMobileQuickActionBackendAliases[slug];
  if (backendAlias != null &&
      kMobileBottomNavCanonicalKeys.contains(backendAlias)) {
    return backendAlias;
  }
  final flutterAlias = kMobileQuickActionFlutterAliases[slug];
  if (flutterAlias != null &&
      kMobileBottomNavCanonicalKeys.contains(flutterAlias)) {
    return flutterAlias;
  }
  return '';
}

bool isPinnedBottomNavKey(String canonicalKey) {
  return kMobileBottomNavPinnedKeys.contains(canonicalKey);
}

String? labelForMobileBottomNav(String canonicalKey) {
  return kMobileBottomNavLabels[canonicalKey];
}

IconData? activeIconForMobileBottomNav(String canonicalKey) {
  return kMobileBottomNavActiveIcons[canonicalKey];
}

IconData? outlinedIconForMobileBottomNav(String canonicalKey) {
  return kMobileBottomNavOutlinedIcons[canonicalKey];
}

/// Flutter menu / Quick Action title used to open a tab (null for pins).
String? flutterTitleForMobileBottomNav(
  MobileBottomNavSurface surface,
  String canonicalKey,
) {
  if (isPinnedBottomNavKey(canonicalKey)) return null;
  return kMobileBottomNavTitlesBySurface[surface]?[canonicalKey];
}

bool isKnownBottomNavKeyOnSurface(
  MobileBottomNavSurface surface,
  String canonicalKey,
) {
  if (isPinnedBottomNavKey(canonicalKey)) return true;
  return flutterTitleForMobileBottomNav(surface, canonicalKey) != null &&
      labelForMobileBottomNav(canonicalKey) != null;
}

/// Parse a successful HTTP body. Returns null when unusable (fallback).
MobileBottomNavSnapshot? parseMobileBottomNavPayload(
  dynamic decoded, {
  required MobileBottomNavSurface surface,
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

  return MobileBottomNavSnapshot(
    surface: MobileBottomNavSurface.parse(json['surface']?.toString()) ??
        surface,
    configured: configured,
    actionKeys: keys,
    role: json['role']?.toString(),
    userId: (json['user_id'] ?? json['userId'])?.toString(),
  );
}

/// Apply backend visibility/order on top of the hardcoded fallback bar.
///
/// * No snapshot / `configured != true` → [fallbackKeys].
/// * `configured == true` → `home` first, middle keys in backend order,
///   `more` last. Unknown / surface-invalid keys skipped. Cap at 7 tabs.
List<String> resolveMobileBottomNavActionKeys({
  required MobileBottomNavSurface surface,
  required List<String> fallbackKeys,
  MobileBottomNavSnapshot? snapshot,
  Set<String>? catalogKeys,
}) {
  if (snapshot == null || !snapshot.configured) {
    return List<String>.from(fallbackKeys);
  }

  final allowed = catalogKeys ?? kMobileBottomNavCanonicalKeys;
  final resolved = <String>[];
  final seen = <String>{};
  // Home + More always consume two slots when present.
  final middleBudget = kMobileBottomNavHardMaxTabs - 2;
  var middleCount = 0;

  void addIfAllowed(String key, {required bool isMiddle}) {
    if (key.isEmpty) return;
    if (!allowed.contains(key)) return;
    if (!isKnownBottomNavKeyOnSurface(surface, key)) return;
    if (seen.contains(key)) return;
    if (isMiddle && middleCount >= middleBudget) return;
    seen.add(key);
    if (isMiddle) middleCount++;
    resolved.add(key);
  }

  addIfAllowed(kMobileBottomNavHomeKey, isMiddle: false);

  for (final rawKey in snapshot.actionKeys) {
    final canonical = canonicalizeMobileBottomNavKey(rawKey);
    if (canonical.isEmpty) continue;
    if (isPinnedBottomNavKey(canonical)) continue;
    addIfAllowed(canonical, isMiddle: true);
  }

  addIfAllowed(kMobileBottomNavMoreKey, isMiddle: false);
  return resolved;
}

String mobileBottomNavCacheKey({
  required String userId,
  required String role,
  required MobileBottomNavSurface surface,
}) {
  final uid = userId.trim().isEmpty ? '_' : userId.trim();
  final roleKey = role.trim().isEmpty ? '_' : role.trim();
  return 'mobile_bottom_nav_v1_${uid}_${roleKey}_${surface.apiName}';
}
