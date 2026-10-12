/// Backend-driven Mobile Documents catalog.
///
/// `GET /API/mobile/documents?project_id=` is the source of truth for which
/// Category → Type → Document rows a signed-in user may see on a project.
/// Flutter renders the returned tree and does not recreate visibility rules.

import '../models/workflow_document.dart';

/// Snapshot of one project's document catalog.
class MobileDocumentsSnapshot {
  const MobileDocumentsSnapshot({
    required this.configured,
    required this.projectId,
    required this.library,
    this.canDownload = false,
    this.role,
    this.userId,
    this.cachedAt,
    this.payload = const {},
  });

  /// `false` → Documents V1 must use the existing `WorkflowDocumentService`
  /// fallback. `true` + empty categories → intentional empty catalog.
  final bool configured;
  final String projectId;
  final WorkflowDocumentLibrary library;

  /// Office web allowed this signed-in user to download project documents.
  final bool canDownload;
  final String? role;
  final String? userId;
  final DateTime? cachedAt;

  /// Original categories payload so unknown fields survive cache round-trips.
  final Map<String, dynamic> payload;

  bool get isIntentionalEmpty =>
      configured && library.libraryCategories.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'configured': configured,
      'project_id': projectId,
      'payload': payload,
      if (role != null) 'role': role,
      if (userId != null) 'user_id': userId,
      if (cachedAt != null) 'cached_at': cachedAt!.toIso8601String(),
    };
  }

  static MobileDocumentsSnapshot? fromJson(
    Map<String, dynamic>? json, {
    String? expectedProjectId,
    String? expectedUserId,
    String? viewerRole,
  }) {
    if (json == null) return null;
    final projectId = _stringValue(json['project_id'] ?? json['projectId']);
    if (projectId == null || projectId.isEmpty) return null;
    if (expectedProjectId != null &&
        expectedProjectId.trim().isNotEmpty &&
        projectId != expectedProjectId.trim()) {
      return null;
    }
    final userId = _stringValue(json['user_id'] ?? json['userId']);
    if (expectedUserId != null &&
        expectedUserId.trim().isNotEmpty &&
        userId != null &&
        userId.isNotEmpty &&
        userId != expectedUserId.trim()) {
      return null;
    }

    final wrapped = <String, dynamic>{
      ...json,
      if (json['payload'] is Map)
        ...Map<String, dynamic>.from(json['payload'] as Map),
    };
    return parseMobileDocumentsPayload(
      wrapped,
      expectedProjectId: expectedProjectId ?? projectId,
      viewerRole: viewerRole ?? _stringValue(json['role'] ?? wrapped['role']),
    );
  }
}

bool shouldUseMobileDocumentsSnapshot(MobileDocumentsSnapshot? snapshot) {
  return snapshot != null && snapshot.configured;
}

String mobileDocumentsCacheKey({
  required String userId,
  required String role,
  required String projectId,
}) {
  final uid = userId.trim().isEmpty ? '_' : userId.trim();
  final roleKey = role.trim().isEmpty ? '_' : role.trim();
  final pid = projectId.trim().isEmpty ? '_' : projectId.trim();
  return 'mobile_documents_v1_${uid}_${roleKey}_$pid';
}

/// Coalesce concurrent fetches for the same project. Different projects
/// never share an in-flight request.
class MobileDocumentsInFlight {
  final Map<String, Future<void>> _inFlight = {};

  bool isInFlightFor(String projectId) {
    final key = projectId.trim();
    return key.isNotEmpty && _inFlight.containsKey(key);
  }

  int get inFlightCount => _inFlight.length;

  Future<void> run(
    String projectId,
    Future<void> Function() work,
  ) async {
    final key = projectId.trim();
    if (key.isEmpty) {
      await work();
      return;
    }
    final existing = _inFlight[key];
    if (existing != null) {
      await existing;
      return;
    }
    final future = work();
    _inFlight[key] = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }

  void clear() => _inFlight.clear();
}

bool isSuccessfulMobileDocumentsPayload(Map<String, dynamic> json) {
  final message = json['message']?.toString().trim().toLowerCase();
  if (message == 'success') return true;
  final success = json['success'];
  if (success is bool) return success;
  if (success == 1 || success == '1' || success == 'true') return true;
  if (success == false ||
      success == 0 ||
      success == '0' ||
      success == 'false') {
    return false;
  }
  return json.containsKey('categories') ||
      json.containsKey('configured') ||
      json.containsKey('documents') ||
      json.containsKey('catalog') ||
      json.containsKey('types');
}

/// Parse a successful HTTP body. Returns null when the payload is unusable
/// (caller must fall back to [WorkflowDocumentService]).
MobileDocumentsSnapshot? parseMobileDocumentsPayload(
  dynamic decoded, {
  String? expectedProjectId,
  String? viewerRole,
}) {
  if (decoded is! Map) return null;
  var json = Map<String, dynamic>.from(decoded);
  final nestedData = json['data'];
  if (nestedData is Map) {
    json = {...json, ...Map<String, dynamic>.from(nestedData)};
  }

  if (!isSuccessfulMobileDocumentsPayload(json)) return null;

  final projectId = _stringValue(json['project_id'] ?? json['projectId']) ??
      expectedProjectId?.trim();
  if (projectId == null || projectId.isEmpty) return null;
  if (expectedProjectId != null &&
      expectedProjectId.trim().isNotEmpty &&
      projectId != expectedProjectId.trim()) {
    return null;
  }

  final configuredFlag = _parseConfiguredFlag(json['configured']);
  final categories = _extractCategoryMaps(json);
  if (configuredFlag == null &&
      categories.isEmpty &&
      !_hasCatalogKeys(json)) {
    return null;
  }

  final configured = configuredFlag ??
      categories.isNotEmpty ||
          json.containsKey('categories') ||
          json.containsKey('catalog');

  final role = viewerRole ?? _stringValue(json['role']);
  final downloadPermission = readCatalogDownloadPermission(json, role);
  final library = buildWorkflowDocumentLibraryFromCatalog(
    categories,
    catalogCanDownload: downloadPermission,
    viewerRole: role,
  );
  final payload = <String, dynamic>{
    'configured': configured,
    'project_id': projectId,
    'categories': categories,
  };
  _copyDownloadPolicy(json, payload);

  return MobileDocumentsSnapshot(
    configured: configured,
    projectId: projectId,
    library: library,
    canDownload: downloadPermission != false,
    role: _stringValue(json['role']) ?? role,
    userId: _stringValue(json['user_id'] ?? json['userId']),
    payload: payload,
  );
}

bool _hasCatalogKeys(Map<String, dynamic> json) {
  return json.containsKey('categories') ||
      json.containsKey('catalog') ||
      json.containsKey('documents') ||
      json.containsKey('document_definitions') ||
      json.containsKey('types') ||
      json.containsKey('document_types');
}

/// Gallery photos/videos are not catalog documents.
bool isGalleryCatalogNode(Map<String, dynamic> map) {
  String lower(dynamic raw) => (raw ?? '').toString().trim().toLowerCase();

  final card = lower(map['dashboard_card']);
  final slug = lower(map['slug']);
  final id = lower(map['id'] ?? map['category_id'] ?? map['type_id']);
  final name = lower(map['name'] ?? map['label'] ?? map['title']);

  if (card == 'gallery' || slug == 'gallery' || id == 'gallery' || name == 'gallery') {
    return true;
  }
  if (card == 'gallery' && (name == 'first' || name == 'second' || id == 'first' || id == 'second')) {
    return true;
  }
  return false;
}

/// Drop the Contracts folder from Docs and For me catalog payloads.
bool isContractsCatalogNode(Map<String, dynamic> map) {
  return isContractsDocumentCategoryRef(
    id: (map['id'] ?? map['category_id'] ?? map['category_key'] ?? map['slug'])
        ?.toString(),
    label: (map['name'] ??
            map['label'] ??
            map['title'] ??
            map['category_name'] ??
            map['category_label'])
        ?.toString(),
    libraryGroupKey: map['library_group_key']?.toString(),
    clientJourneyKey:
        (map['client_journey_key'] ?? map['journey_key'])?.toString(),
  );
}

/// Drop the unused Uncategorized bucket from mobile catalog payloads.
bool isUncategorizedCatalogNode(Map<String, dynamic> map) {
  return isUncategorizedDocumentCategoryRef(
    id: (map['id'] ?? map['category_id'] ?? map['category_key'] ?? map['slug'])
        ?.toString(),
    label: (map['name'] ??
            map['label'] ??
            map['title'] ??
            map['category_name'] ??
            map['category_label'])
        ?.toString(),
    libraryGroupKey: map['library_group_key']?.toString(),
    clientJourneyKey:
        (map['client_journey_key'] ?? map['journey_key'])?.toString(),
  );
}

/// Catalog IDs only — never dashboard_card / dashboard_section / task_id.
String? catalogIdFromMap(
  Map<String, dynamic> map, {
  required List<String> keys,
}) {
  for (final key in keys) {
    if (key == 'dashboard_card' ||
        key == 'dashboard_section' ||
        key == 'task_id' ||
        key == 'taskId') {
      continue;
    }
    final value = _stringValue(map[key]);
    if (value != null) return value;
  }
  return null;
}

/// Live catalog `.name` first. Dashboard card/section labels are never used.
String? catalogNameFromMap(
  Map<String, dynamic> map, {
  required List<String> keys,
}) {
  for (final key in keys) {
    if (key == 'dashboard_card' ||
        key == 'dashboard_section' ||
        key == 'dashboard_section_label' ||
        key == 'section_label') {
      continue;
    }
    final value = _stringValue(map[key]);
    if (value != null) return value;
  }
  return null;
}

List<Map<String, dynamic>> _extractCategoryMaps(Map<String, dynamic> json) {
  final direct = json['categories'] ?? json['catalog'];
  if (direct is List) {
    return [
      for (final item in direct)
        if (item is Map &&
            !isGalleryCatalogNode(Map<String, dynamic>.from(item)))
          Map<String, dynamic>.from(item),
    ];
  }

  final flat = json['documents'] ?? json['document_definitions'];
  if (flat is List) {
    return _categoriesFromFlatDocuments(flat);
  }
  return const [];
}

List<Map<String, dynamic>> _categoriesFromFlatDocuments(List<dynamic> rows) {
  final categories = <String, Map<String, dynamic>>{};
  final typesByCategory = <String, Map<String, Map<String, dynamic>>>{};

  for (final row in rows) {
    if (row is! Map) continue;
    final map = Map<String, dynamic>.from(row);
    if (isGalleryCatalogNode(map)) continue;
    if (_isDashboardInventedRow(map)) continue;

    final categoryId = catalogIdFromMap(
          map,
          keys: const ['category_id', 'category_key'],
        );
    final typeId = catalogIdFromMap(
          map,
          keys: const ['type_id', 'document_type_id', 'type_key'],
        );
    if (categoryId == null || typeId == null) continue;

    final categoryLabel = catalogNameFromMap(
          map,
          keys: const ['category_name', 'name', 'category_label', 'label'],
        ) ??
        _titleFromKey(categoryId);
    final typeLabel = catalogNameFromMap(
          map,
          keys: const ['type_name', 'type_label', 'type'],
        ) ??
        _titleFromKey(typeId);

    categories.putIfAbsent(categoryId, () {
      return {
        'category_id': categoryId,
        'name': categoryLabel,
        'types': <Map<String, dynamic>>[],
      };
    });
    final types = typesByCategory.putIfAbsent(
      categoryId,
      () => <String, Map<String, dynamic>>{},
    );
    final type = types.putIfAbsent(typeId, () {
      return {
        'type_id': typeId,
        'name': typeLabel,
        'documents': <Map<String, dynamic>>[],
      };
    });
    (type['documents'] as List).add(map);
  }

  return [
    for (final entry in categories.entries)
      {
        ...entry.value,
        'types': [
          ...?(typesByCategory[entry.key]?.values),
        ],
      },
  ];
}

/// Do not invent a catalog row from dashboard_card/dashboard_section when
/// [document_definition_id] is missing.
bool _isDashboardInventedRow(Map<String, dynamic> map) {
  final definitionId = catalogIdFromMap(
    map,
    keys: const ['document_definition_id', 'document_key'],
  );
  if (definitionId != null) return false;
  final hasDashboard = _stringValue(map['dashboard_card']) != null ||
      _stringValue(map['dashboard_section']) != null;
  if (!hasDashboard) return false;
  final hasCatalogParent = catalogIdFromMap(
        map,
        keys: const ['category_id', 'type_id', 'document_type_id'],
      ) !=
      null;
  return !hasCatalogParent;
}

WorkflowDocumentLibrary buildWorkflowDocumentLibraryFromCatalog(
  List<Map<String, dynamic>> categoryMaps, {
  bool? catalogCanDownload,
  String? viewerRole,
}) {
  final libraryCategories = <WorkflowDocumentCategory>[];
  final clientJourneyCategories = <WorkflowDocumentCategory>[];
  final seenLibrary = <String>{};
  final seenJourney = <String>{};

  for (final categoryMap in categoryMaps) {
    final category = _categoryFromMap(
      categoryMap,
      catalogCanDownload: catalogCanDownload,
      viewerRole: viewerRole,
    );
    if (category == null) continue;
    if (seenLibrary.add(category.id)) {
      libraryCategories.add(category);
    }
    final journeyKey = category.clientJourneyKey?.trim();
    if (journeyKey != null &&
        journeyKey.isNotEmpty &&
        seenJourney.add(category.id)) {
      clientJourneyCategories.add(category);
    }
  }

  return WorkflowDocumentLibrary(
    libraryCategories: libraryCategories,
    clientJourneyCategories: clientJourneyCategories,
  );
}

WorkflowDocumentCategory? _categoryFromMap(
  Map<String, dynamic> map, {
  bool? catalogCanDownload,
  String? viewerRole,
}) {
  if (isGalleryCatalogNode(map)) return null;
  if (isUncategorizedCatalogNode(map)) return null;
  if (isContractsCatalogNode(map)) return null;

  final id = catalogIdFromMap(
        map,
        keys: const ['category_id', 'id', 'category_key'],
      ) ??
      '';
  final label = catalogNameFromMap(
        map,
        keys: const ['name', 'category_name', 'label', 'category_label', 'title'],
      ) ??
      (id.isEmpty ? '' : _titleFromKey(id));
  if (id.isEmpty && label.isEmpty) return null;
  final resolvedId = id.isEmpty ? _slug(label) : id;
  if (resolvedId.isEmpty) return null;
  if (isUncategorizedDocumentCategoryRef(id: resolvedId, label: label)) {
    return null;
  }
  if (isContractsDocumentCategoryRef(id: resolvedId, label: label)) {
    return null;
  }

  final typeMaps = _extractTypeMaps(map);
  final sections = <WorkflowDocumentSection>[];
  final seenTypes = <String>{};
  for (final typeMap in typeMaps) {
    if (isGalleryCatalogNode(typeMap)) continue;
    final section = _sectionFromMap(
      typeMap,
      categoryId: resolvedId,
      categoryLabel: label.isEmpty ? _titleFromKey(resolvedId) : label,
      clientJourneyKey: _stringValue(
        map['client_journey_key'] ?? map['journey_key'],
      ),
      libraryGroupKey: resolvedId,
      catalogCanDownload: catalogCanDownload,
      viewerRole: viewerRole,
    );
    if (section == null) continue;
    if (!seenTypes.add(section.id)) continue;
    sections.add(section);
  }

  return WorkflowDocumentCategory(
    id: resolvedId,
    label: label.isEmpty ? _titleFromKey(resolvedId) : label,
    iconName: _stringValue(map['icon'] ?? map['icon_name']),
    clientJourneyKey: _stringValue(
      map['client_journey_key'] ?? map['journey_key'],
    ),
    libraryGroupKey: resolvedId,
    presentation: WorkflowDocumentPresentation.library,
    sections: sections,
  );
}

List<Map<String, dynamic>> _extractTypeMaps(Map<String, dynamic> categoryMap) {
  final raw = categoryMap['types'] ??
      categoryMap['document_types'] ??
      categoryMap['children'];
  if (raw is List) {
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  final docs = categoryMap['documents'] ??
      categoryMap['document_definitions'] ??
      categoryMap['items'];
  if (docs is List && docs.isNotEmpty) {
    return [categoryMap];
  }
  return const [];
}

WorkflowDocumentSection? _sectionFromMap(
  Map<String, dynamic> map, {
  required String categoryId,
  required String categoryLabel,
  String? clientJourneyKey,
  String? libraryGroupKey,
  bool? catalogCanDownload,
  String? viewerRole,
}) {
  if (isGalleryCatalogNode(map)) return null;

  final id = catalogIdFromMap(
        map,
        keys: const ['type_id', 'document_type_id', 'id', 'type_key'],
      ) ??
      '';
  final label = catalogNameFromMap(
        map,
        keys: const ['name', 'type_name', 'label', 'type_label', 'title'],
      ) ??
      (id.isEmpty ? '' : _titleFromKey(id));
  if (id.isEmpty && label.isEmpty) return null;
  final resolvedId = id.isEmpty ? _slug(label) : id;
  if (resolvedId.isEmpty) return null;

  final documents = <WorkflowDocumentUpload>[];
  final seen = <String>{};
  final rawDocs = map['documents'] ??
      map['document_definitions'] ??
      map['items'] ??
      map['files'];
  if (rawDocs is List) {
    for (final item in rawDocs) {
      if (item is! Map) continue;
      final docMap = Map<String, dynamic>.from(item);
      if (isGalleryCatalogNode(docMap)) continue;
      // One catalog row can hold several PDFs (Electrical / Plumbing points).
      for (final fileMap in expandMobileDocumentFileMaps(docMap)) {
        final upload = documentFromMobileMap(
          fileMap,
          categoryId: categoryId,
          categoryLabel: categoryLabel,
          sectionId: resolvedId,
          sectionLabel: label.isEmpty ? _titleFromKey(resolvedId) : label,
          clientJourneyKey: clientJourneyKey,
          libraryGroupKey: libraryGroupKey,
          catalogCanDownload: catalogCanDownload,
          viewerRole: viewerRole,
        );
        if (upload == null) continue;
        final dedupeKey = [
          upload.id,
          upload.url ?? '',
          upload.documentKey,
          upload.revision?.toString() ?? '',
          upload.name,
        ].join('|').toLowerCase();
        if (!seen.add(dedupeKey)) continue;
        documents.add(upload);
      }
    }
  }

  final sectionLabel = label.isEmpty ? _titleFromKey(resolvedId) : label;
  return WorkflowDocumentSection(
    id: resolvedId,
    label: sectionLabel,
    iconName: _stringValue(map['icon'] ?? map['icon_name'] ?? map['section_icon']),
    categoryId: categoryId,
    categoryLabel: categoryLabel,
    clientJourneyKey: clientJourneyKey ??
        _stringValue(map['client_journey_key'] ?? map['journey_key']),
    libraryGroupKey: libraryGroupKey ?? categoryId,
    documents: _peerFilesForMultiFileSection(
      sectionLabel: sectionLabel,
      categoryLabel: categoryLabel,
      documents: _markLatestPerKey(documents),
    ),
  );
}

/// Soil / Booking / Plumbing / Electrical keep every uploaded file as a
/// current peer (not hidden behind a single "latest" revision).
List<WorkflowDocumentUpload> _peerFilesForMultiFileSection({
  required String sectionLabel,
  required String categoryLabel,
  required List<WorkflowDocumentUpload> documents,
}) {
  final blob = '$sectionLabel $categoryLabel'.toLowerCase();
  final multiFile = blob.contains('electrical') ||
      blob.contains('plumb') ||
      blob.contains('soil') ||
      blob.contains('booking');
  if (!multiFile) return documents;

  // Prefer unique file URLs so the list/count matches what the user uploaded.
  final out = <WorkflowDocumentUpload>[];
  final seenUrls = <String>{};
  for (final doc in documents) {
    final url = (doc.url ?? '').trim().toLowerCase();
    if (url.isNotEmpty && !seenUrls.add(url)) continue;
    out.add(
      WorkflowDocumentUpload(
        id: doc.id,
        documentKey: doc.documentKey,
        name: doc.name,
        url: doc.url,
        contentType: doc.contentType,
        fileSize: doc.fileSize,
        revision: doc.revision,
        revisionLabel: doc.revisionLabel,
        isLatest: true,
        uploadedAt: doc.uploadedAt,
        uploadedBy: doc.uploadedBy,
        taskName: doc.taskName,
        taskId: doc.taskId,
        status: doc.status ?? 'uploaded',
        sectionId: doc.sectionId,
        sectionLabel: doc.sectionLabel,
        categoryId: doc.categoryId,
        categoryLabel: doc.categoryLabel,
        clientJourneyKey: doc.clientJourneyKey,
        libraryGroupKey: doc.libraryGroupKey,
        activity: doc.activity,
        raw: doc.raw,
      ),
    );
  }
  return out;
}

bool _looksLikeMultiFileDocumentMap(Map<String, dynamic> map) {
  final blob = [
    map['document_key'],
    map['document_definition_id'],
    map['document_id'],
    map['name'],
    map['document_name'],
    map['title'],
    map['label'],
    map['type_name'],
    map['type_label'],
  ].where((value) => value != null).join(' ').toLowerCase();
  return blob.contains('electrical') ||
      blob.contains('plumb') ||
      blob.contains('soil') ||
      blob.contains('booking');
}

bool _looksLikeFileUrl(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty || lower == 'null') return false;
  // Signed S3 / CDN links often have no extension — still real files.
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    if (lower.contains('javascript:') || lower.endsWith('/api')) return false;
    return true;
  }
  return lower.contains('.pdf') ||
      lower.contains('.png') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.webp') ||
      lower.contains('.doc') ||
      lower.contains('.xls') ||
      lower.contains('/files/') ||
      lower.startsWith('uploads/') ||
      lower.startsWith('/uploads/') ||
      lower.startsWith('media/') ||
      lower.startsWith('/media/');
}

bool _mapHasOfficeVersionVisibilityFlag(Map<String, dynamic> map) {
  for (final key in const [
    'checked',
    'is_checked',
    'selected',
    'is_selected',
    'show_in_app',
    'show_on_app',
    'show_in_mobile',
    'visible_in_app',
    'client_visible',
    'visible_to_client',
    'include_in_app',
    'share_to_client',
    'shared_to_client',
    'app_visible',
    'mobile_visible',
    'show_to_client',
  ]) {
    if (!map.containsKey(key)) continue;
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == 'null') continue;
    return true;
  }
  return false;
}

/// Office web 2 often stores "show in app" on nested `versions` / `revisions`
/// rows. Promote those into one map each so mobile can honor `checked`.
List<Map<String, dynamic>>? _expandOfficeVersionFileMaps(
  Map<String, dynamic> map,
) {
  for (final key in const ['versions', 'revisions']) {
    final list = map[key];
    if (list is! List || list.isEmpty) continue;

    final parent = Map<String, dynamic>.from(map)
      ..remove('versions')
      ..remove('revisions');
    final out = <Map<String, dynamic>>[];
    final seenUrls = <String>{};
    var anyExplicit = _mapHasOfficeVersionVisibilityFlag(parent);

    for (final item in list) {
      if (item is! Map) continue;
      final child = Map<String, dynamic>.from(item);
      final url = _resolveUrl(child);
      if (url == null || url.isEmpty) continue;
      final abs = _absoluteUrl(url);
      if (!seenUrls.add(abs.toLowerCase())) continue;
      if (_mapHasOfficeVersionVisibilityFlag(child)) anyExplicit = true;
      out.add({
        ...parent,
        ...child,
        'url': abs,
      });
    }

    // Expand when web sent multiple version files, or any checkbox/share flag
    // (so a single checked Working drawing still keeps `checked` on the row).
    if (out.isEmpty) continue;
    if (out.length > 1 || anyExplicit) return out;
  }
  return null;
}

/// Expands a catalog document that carries nested uploads into one map
/// per file. Used when Electrical / Plumbing / Soil / Booking have several PDFs.
///
/// Other docs (Architectural, etc.) only promote a single resolved URL onto
/// the parent row — splitting them duplicates every file in the list.
/// Exception: office `versions` / `revisions` with show-in-app checkboxes.
List<Map<String, dynamic>> expandMobileDocumentFileMaps(
  Map<String, dynamic> map,
) {
  // Floor plans / drawings: one definition = one row. Nested latest_upload /
  // files often repeat the same PDF under a different signed URL.
  if (!_looksLikeMultiFileDocumentMap(map)) {
    final versionRows = _expandOfficeVersionFileMaps(map);
    if (versionRows != null) return versionRows;
    final url = _resolveUrl(map);
    if (url == null) return [map];
    return [
      {
        ...map,
        'url': url,
      },
    ];
  }

  final nested = <Map<String, dynamic>>[];
  final seenUrls = <String>{};

  void takeUrl(String? raw, [Map<String, dynamic>? source]) {
    final trimmed = (raw ?? '').trim();
    if (!_looksLikeFileUrl(trimmed)) return;
    final abs = _absoluteUrl(trimmed);
    if (!seenUrls.add(abs.toLowerCase())) return;
    if (source != null) {
      nested.add({
        ...source,
        // Normalize so parent.url cannot mask file_url / path variants.
        'url': abs,
      });
    } else {
      nested.add({'url': abs});
    }
  }

  void takeList(dynamic children) {
    if (children is Map) {
      for (final value in children.values) {
        if (value is Map) {
          takeList([value]);
        } else if (value is List) {
          takeList(value);
        } else if (value != null) {
          takeUrl(value.toString());
        }
      }
      return;
    }
    if (children is! List) return;
    for (final child in children) {
      if (child is Map) {
        final childMap = Map<String, dynamic>.from(child);
        final url = _resolveUrl(childMap);
        // Only keep maps that actually point at a file. Empty maps would
        // inherit the parent URL and collapse into a single visible row.
        if (url == null || url.isEmpty) continue;
        takeUrl(url, childMap);
      } else if (child != null) {
        takeUrl(child.toString());
      }
    }
  }

  void harvestUrls(dynamic node, [int depth = 0]) {
    if (depth > 5 || node == null) return;
    if (node is Map) {
      final asMap = Map<String, dynamic>.from(node);
      final url = _resolveUrl(asMap);
      if (url != null) takeUrl(url, asMap);
      for (final entry in asMap.entries) {
        final key = entry.key.toString().toLowerCase();
        // Skip huge unrelated blobs.
        if (key.contains('permission') ||
            key.contains('role') ||
            key == 'raw' ||
            key == 'meta') {
          continue;
        }
        harvestUrls(entry.value, depth + 1);
      }
      return;
    }
    if (node is List) {
      for (final child in node) {
        harvestUrls(child, depth + 1);
      }
      return;
    }
    if (node is String) takeUrl(node);
  }

  // Collect from every list key — do not stop at the first non-empty one.
  // Soil / Booking / MEP often put the real multi-file list under `uploads`
  // while `files` still has a single primary entry.
  const nestedKeys = [
    'files',
    'attachments',
    'uploaded_files',
    'uploads',
    'versions',
    'revisions',
    'file_urls',
    'urls',
    'documents',
    'document_files',
    'pdfs',
    'pdf_files',
    'uploaded_documents',
    'file_list',
    'uploaded_file_urls',
    'pdf_urls',
    'all_files',
    'all_uploads',
    'current_files',
    'latest_uploads',
    'media',
    'activity',
    'activities',
    'history',
    'upload_history',
    'file_history',
    'previous_files',
    'prior_uploads',
  ];
  for (final key in nestedKeys) {
    takeList(map[key]);
  }

  // Singular nested file objects (common on Plumbing / Electrical / web uploads).
  for (final key in const [
    'file',
    'attachment',
    'uploaded_file',
    'latest_file',
    'latest_upload',
    'current_file',
    'primary_file',
    'secondary_file',
    'previous_file',
    'upload',
  ]) {
    final singular = map[key];
    if (singular is Map) {
      takeList([singular]);
    } else if (singular != null) {
      takeUrl(singular.toString());
    }
  }

  final nestedDoc = map['document'];
  if (nestedDoc is Map) {
    for (final key in nestedKeys) {
      takeList(nestedDoc[key]);
    }
  }

  // Deep-scan when Soil / Booking / Plumbing still only exposed one file.
  if (nested.length < 2) {
    harvestUrls(map);
  }

  if (nested.isEmpty) return [map];

  // Keep a distinct parent URL that is not already in the nested list.
  final parentUrl = _resolveUrl(map);
  if (parentUrl != null) takeUrl(parentUrl);

  final parent = Map<String, dynamic>.from(map);
  for (final key in nestedKeys) {
    parent.remove(key);
  }
  parent.remove('document');
  for (final key in const [
    'file',
    'attachment',
    'uploaded_file',
    'latest_file',
    'latest_upload',
    'current_file',
    'primary_file',
    'secondary_file',
    'previous_file',
    'upload',
  ]) {
    parent.remove(key);
  }

  final parentId = catalogIdFromMap(
        parent,
        keys: const [
          'id',
          'upload_id',
          'document_definition_id',
          'document_key',
        ],
      ) ??
      _slug(
        catalogNameFromMap(
              parent,
              keys: const ['name', 'document_name', 'title', 'label'],
            ) ??
            'doc',
      );

  return [
    for (var i = 0; i < nested.length; i++)
      {
        ...parent,
        ...nested[i],
        // Peer uploads under one definition are all current files.
        'is_latest': true,
        'status': nested[i]['status'] ?? parent['status'] ?? 'uploaded',
        if (catalogIdFromMap(
              nested[i],
              keys: const ['id', 'upload_id'],
            ) ==
            null)
          'id': '${parentId}_file_$i',
      },
  ];
}

/// Include pending / missing / inactive required documents. Unlike the
/// legacy sales-sop parser, a missing URL is a valid catalog row.
WorkflowDocumentUpload? documentFromMobileMap(
  Map<String, dynamic> map, {
  String categoryId = '',
  String categoryLabel = '',
  String sectionId = '',
  String sectionLabel = '',
  String? clientJourneyKey,
  String? libraryGroupKey,
  bool? catalogCanDownload,
  String? viewerRole,
}) {
  final name = catalogNameFromMap(
        map,
        keys: const [
          'name',
          'document_name',
          'definition_name',
          'title',
          'label',
        ],
      ) ??
      '';
  final documentKey = catalogIdFromMap(
        map,
        keys: const [
          'document_definition_id',
          'document_key',
          'document_id',
        ],
      ) ??
      (name.isEmpty ? '' : _slug(name));
  final id = catalogIdFromMap(
        map,
        keys: const ['id', 'upload_id'],
      ) ??
      (documentKey.isEmpty ? '' : documentKey);
  if (id.isEmpty && documentKey.isEmpty && name.isEmpty) return null;
  if (isGalleryCatalogNode(map)) return null;

  final canDownload = documentDownloadAllowed(
    map,
    catalogCanDownload: catalogCanDownload,
    viewerRole: viewerRole,
  );

  final url = _resolveUrl(map);
  final rawStatus = _stringValue(map['status']);
  // Web catalog often keeps status=pending/required after a file exists.
  // Once we have a URL, treat it as uploaded so Docs matches For Me / web.
  final status = () {
    if (url == null) return rawStatus;
    switch ((rawStatus ?? '').trim().toLowerCase()) {
      case '':
      case 'pending':
      case 'missing':
      case 'required':
      case 'mandatory':
      case 'inactive':
        return 'uploaded';
      default:
        return rawStatus;
    }
  }();
  final revision = _asInt(map['revision'] ?? map['rev'] ?? map['version']);

  List<Map<String, dynamic>> activity = const [];
  final rawActivity = map['activity'] ?? map['activities'];
  if (rawActivity is List) {
    activity = rawActivity
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  return WorkflowDocumentUpload(
    id: id.isEmpty ? '${documentKey.isEmpty ? _slug(name) : documentKey}' : id,
    documentKey: documentKey.isEmpty ? _slug(name.isEmpty ? id : name) : documentKey,
    name: name.isEmpty ? _titleFromKey(documentKey.isEmpty ? id : documentKey) : name,
    url: url,
    contentType:
        _stringValue(map['content_type'] ?? map['mime_type'] ?? map['type']),
    fileSize: _formatFileSize(map['file_size'] ?? map['size']),
    revision: revision,
    revisionLabel: _stringValue(map['revision_label'] ?? map['rev_label']),
    isLatest: _isLatestStatus(status, map, hasUrl: url != null),
    uploadedAt: _stringValue(
      map['uploaded_at'] ?? map['created_at'] ?? map['updated_at'],
    ),
    uploadedBy: _stringValue(
      map['uploaded_by'] ?? map['user_name'] ?? map['uploaded_by_name'],
    ),
    taskName: _stringValue(map['task_name'] ?? map['note']),
    taskId: _stringValue(map['task_id']),
    status: status,
    sectionId: catalogIdFromMap(
          map,
          keys: const ['type_id', 'document_type_id'],
        ) ??
        sectionId,
    sectionLabel: catalogNameFromMap(
          map,
          keys: const ['type_name', 'type_label'],
        ) ??
        sectionLabel,
    categoryId: catalogIdFromMap(
          map,
          keys: const ['category_id'],
        ) ??
        categoryId,
    categoryLabel: catalogNameFromMap(
          map,
          keys: const ['category_name', 'category_label'],
        ) ??
        categoryLabel,
    clientJourneyKey: _stringValue(
          map['client_journey_key'] ?? map['journey_key'],
        ) ??
        clientJourneyKey,
    libraryGroupKey: _stringValue(map['library_group_key']) ?? libraryGroupKey,
    activity: activity,
    raw: {
      ...map,
      'can_download': canDownload,
    },
  );
}

List<WorkflowDocumentUpload> _markLatestPerKey(
  List<WorkflowDocumentUpload> uploads,
) {
  if (uploads.isEmpty) return const [];
  final byKey = <String, List<WorkflowDocumentUpload>>{};
  for (final upload in uploads) {
    final key = upload.documentKey.isNotEmpty
        ? upload.documentKey
        : upload.id;
    byKey.putIfAbsent(key, () => <WorkflowDocumentUpload>[]).add(upload);
  }

  final out = <WorkflowDocumentUpload>[];
  for (final group in byKey.values) {
    group.sort((a, b) {
      final ar = a.revision ?? 0;
      final br = b.revision ?? 0;
      if (ar != br) return br.compareTo(ar);
      return (b.uploadedAt ?? '').compareTo(a.uploadedAt ?? '');
    });
    var markedLatest = false;
    for (var i = 0; i < group.length; i++) {
      final entry = group[i];
      final status = (entry.status ?? '').trim().toLowerCase();
      final superseded = status == 'superseded' || status == 'older';
      final latest = !superseded && (entry.isLatest || (!markedLatest && i == 0));
      if (latest) markedLatest = true;
      out.add(
        WorkflowDocumentUpload(
          id: entry.id,
          documentKey: entry.documentKey,
          name: entry.name,
          url: entry.url,
          contentType: entry.contentType,
          fileSize: entry.fileSize,
          revision: entry.revision,
          revisionLabel: entry.revisionLabel,
          isLatest: latest,
          uploadedAt: entry.uploadedAt,
          uploadedBy: entry.uploadedBy,
          taskName: entry.taskName,
          taskId: entry.taskId,
          status: entry.status,
          sectionId: entry.sectionId,
          sectionLabel: entry.sectionLabel,
          categoryId: entry.categoryId,
          categoryLabel: entry.categoryLabel,
          clientJourneyKey: entry.clientJourneyKey,
          libraryGroupKey: entry.libraryGroupKey,
          activity: entry.activity,
          raw: entry.raw,
        ),
      );
    }
  }
  return out;
}

bool _isLatestStatus(
  String? status,
  Map<String, dynamic> map, {
  required bool hasUrl,
}) {
  if (_truthy(map['is_latest']) || _truthy(map['isLatest'])) return true;
  final normalized = (status ?? '').trim().toLowerCase();
  if (normalized == 'superseded' || normalized == 'older') return false;
  if (normalized == 'latest' ||
      normalized == 'uploaded' ||
      normalized == 'available' ||
      normalized == 'pending' ||
      normalized == 'missing' ||
      normalized == 'required' ||
      normalized == 'mandatory' ||
      normalized == 'inactive') {
    return true;
  }
  if (!hasUrl) return true;
  return normalized.isEmpty;
}

String? _resolveUrl(Map<String, dynamic> map, [int depth = 0]) {
  if (depth > 4) return null;
  final direct = _stringValue(
    map['url'] ??
        map['file_url'] ??
        map['download_url'] ??
        map['signed_url'] ??
        map['public_url'] ??
        map['view_url'] ??
        map['document_url'] ??
        map['pdf_url'] ??
        map['s3_url'] ??
        map['media_url'] ??
        map['file_path'] ??
        map['path'] ??
        map['attachment_url'] ??
        map['storage_path'] ??
        map['link'],
  );
  // Explicit url-like fields from the API are trusted as-is.
  if (direct != null) return _absoluteUrl(direct);

  // Web often nests the real file under file / latest_upload / uploads[0].
  for (final key in const [
    'file',
    'attachment',
    'uploaded_file',
    'latest_file',
    'latest_upload',
    'current_file',
    'primary_file',
    'secondary_file',
    'previous_file',
    'upload',
    'document',
  ]) {
    final nested = map[key];
    if (nested is Map) {
      final url = _resolveUrl(Map<String, dynamic>.from(nested), depth + 1);
      if (url != null) return url;
    } else if (nested != null) {
      final text = nested.toString().trim();
      if (_looksLikeFileUrl(text)) return _absoluteUrl(text);
    }
  }

  for (final key in const [
    'files',
    'attachments',
    'uploaded_files',
    'uploads',
    'versions',
    'revisions',
    'file_urls',
    'urls',
    'document_files',
    'pdfs',
    'pdf_files',
    'uploaded_documents',
    'media',
  ]) {
    final list = map[key];
    if (list is! List) continue;
    for (final item in list) {
      if (item is Map) {
        final url = _resolveUrl(Map<String, dynamic>.from(item), depth + 1);
        if (url != null) return url;
      } else if (item != null) {
        final text = item.toString().trim();
        if (_looksLikeFileUrl(text)) return _absoluteUrl(text);
      }
    }
  }
  return null;
}

String _absoluteUrl(String value) {
  const baseUrl = 'https://office.buildahome.in';
  final trimmed = value.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) return '$baseUrl$trimmed';
  return '$baseUrl/$trimmed';
}

String? _formatFileSize(dynamic raw) {
  if (raw == null) return null;
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  final bytes = _asInt(raw);
  if (bytes == null || bytes < 0) return null;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Office web decides who may download documents.
///
/// `GET /API/mobile/documents` can send any one of:
/// * `can_download` — true/false already decided for this signed-in user
/// * `download_roles` — role names that should see Download
/// * `download_access.roles` — same list, nested
///
/// `can_download` wins when it is present. With no policy, Download is shown.
/// An empty role list hides it for every role. A file can override the
/// catalog with its own `can_download`.
bool? readCatalogDownloadPermission(
  Map<String, dynamic> json,
  String? viewerRole,
) {
  if (json.containsKey('can_download') ||
      json.containsKey('allow_download') ||
      json.containsKey('download_enabled')) {
    final direct = _optionalBool(
      json['can_download'] ??
          json['allow_download'] ??
          json['download_enabled'],
    );
    if (direct != null) return direct;
  }
  final roles = _downloadRoleList(json);
  if (roles != null) {
    return roleIsAllowedToDownloadDocuments(viewerRole, roles);
  }
  final access = json['download_access'];
  if (access is Map &&
      !json.containsKey('download_roles') &&
      !json.containsKey('download_allowed_roles')) {
    final direct = _optionalBool(
      access['can_download'] ?? access['enabled'] ?? access['allowed'],
    );
    if (direct != null) return direct;
  }
  return null;
}

/// Per-file flag wins. Otherwise the catalog decision applies.
bool documentDownloadAllowed(
  Map<String, dynamic> document, {
  bool? catalogCanDownload,
  String? viewerRole,
}) {
  if (document.containsKey('download_roles') ||
      document.containsKey('download_allowed_roles')) {
    final roles = _stringList(
          document['download_roles'] ?? document['download_allowed_roles'],
        ) ??
        const <String>[];
    return roleIsAllowedToDownloadDocuments(viewerRole, roles);
  }
  final own = _optionalBool(
    document['can_download'] ??
        document['allow_download'] ??
        document['download_allowed'],
  );
  if (own != null) return own;
  return catalogCanDownload != false;
}

bool roleIsAllowedToDownloadDocuments(String? role, Iterable<String> allowed) {
  final mine = _normRole(role);
  if (mine.isEmpty) return false;
  for (final entry in allowed) {
    final normalized = _normRole(entry);
    if (normalized == 'all' || normalized == '*') return true;
    if (normalized == mine) return true;
    if (_coordinatorAlias(normalized) == _coordinatorAlias(mine) &&
        _coordinatorAlias(mine).isNotEmpty) {
      return true;
    }
  }
  return false;
}

String _coordinatorAlias(String normalized) {
  if (normalized == 'project co ordinator' ||
      normalized == 'project coordinator') {
    return 'project coordinator';
  }
  if (normalized == 'assistant project coordinator' ||
      normalized == 'assistant project co ordinator' ||
      normalized == 'apcc' ||
      normalized == 'apc') {
    return 'assistant project coordinator';
  }
  return '';
}

String _normRole(String? raw) {
  return (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_/-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<String>? _downloadRoleList(Map<String, dynamic> json) {
  if (json.containsKey('download_roles')) {
    return _stringList(json['download_roles']) ?? const [];
  }
  if (json.containsKey('download_allowed_roles')) {
    return _stringList(json['download_allowed_roles']) ?? const [];
  }
  final access = json['download_access'];
  if (access is Map) {
    final map = Map<String, dynamic>.from(access);
    if (map.containsKey('roles') || map.containsKey('allowed_roles')) {
      return _stringList(map['roles'] ?? map['allowed_roles']) ?? const [];
    }
  }
  return null;
}

List<String>? _stringList(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) {
    return raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }
  if (raw is List) {
    return [
      for (final item in raw)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }
  return null;
}

bool? _optionalBool(dynamic raw) {
  if (raw == null) return null;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final text = raw.toString().trim().toLowerCase();
  if (text.isEmpty || text == 'null') return null;
  if (text == 'true' || text == 'yes' || text == '1') return true;
  if (text == 'false' || text == 'no' || text == '0') return false;
  return null;
}

void _copyDownloadPolicy(Map<String, dynamic> from, Map<String, dynamic> to) {
  for (final key in const [
    'can_download',
    'allow_download',
    'download_enabled',
    'download_roles',
    'download_allowed_roles',
    'download_access',
    'role',
  ]) {
    if (from.containsKey(key)) to[key] = from[key];
  }
}

bool? _parseConfiguredFlag(dynamic raw) {
  if (raw is bool) return raw;
  if (raw == 1 || raw == '1' || raw == 'true' || raw == 'True') return true;
  if (raw == 0 || raw == '0' || raw == 'false' || raw == 'False') return false;
  return null;
}

bool _truthy(dynamic raw) {
  if (raw == true || raw == 1 || raw == '1') return true;
  final text = raw?.toString().trim().toLowerCase();
  return text == 'true' || text == 'yes';
}

int? _asInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

String? _stringValue(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

String _slug(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

String _titleFromKey(String value) {
  final cleaned = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (cleaned.isEmpty) return value;
  return cleaned
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
