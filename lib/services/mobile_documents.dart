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

  final library = buildWorkflowDocumentLibraryFromCatalog(categories);
  final payload = <String, dynamic>{
    'configured': configured,
    'project_id': projectId,
    'categories': categories,
  };

  return MobileDocumentsSnapshot(
    configured: configured,
    projectId: projectId,
    library: library,
    role: _stringValue(json['role']),
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
  List<Map<String, dynamic>> categoryMaps,
) {
  final libraryCategories = <WorkflowDocumentCategory>[];
  final clientJourneyCategories = <WorkflowDocumentCategory>[];
  final seenLibrary = <String>{};
  final seenJourney = <String>{};

  for (final categoryMap in categoryMaps) {
    final category = _categoryFromMap(categoryMap);
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

WorkflowDocumentCategory? _categoryFromMap(Map<String, dynamic> map) {
  if (isGalleryCatalogNode(map)) return null;

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
      final upload = documentFromMobileMap(
        docMap,
        categoryId: categoryId,
        categoryLabel: categoryLabel,
        sectionId: resolvedId,
        sectionLabel: label.isEmpty ? _titleFromKey(resolvedId) : label,
        clientJourneyKey: clientJourneyKey,
        libraryGroupKey: libraryGroupKey,
      );
      if (upload == null) continue;
      final dedupeKey = [
        upload.documentKey,
        upload.id,
        upload.url ?? '',
        upload.revision?.toString() ?? '',
      ].join('|').toLowerCase();
      if (!seen.add(dedupeKey)) continue;
      documents.add(upload);
    }
  }

  return WorkflowDocumentSection(
    id: resolvedId,
    label: label.isEmpty ? _titleFromKey(resolvedId) : label,
    iconName: _stringValue(map['icon'] ?? map['icon_name'] ?? map['section_icon']),
    categoryId: categoryId,
    categoryLabel: categoryLabel,
    clientJourneyKey: clientJourneyKey ??
        _stringValue(map['client_journey_key'] ?? map['journey_key']),
    libraryGroupKey: libraryGroupKey ?? categoryId,
    documents: _markLatestPerKey(documents),
  );
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

  final url = _resolveUrl(map);
  final status = _stringValue(map['status']);
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
    raw: map,
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

String? _resolveUrl(Map<String, dynamic> map) {
  final direct = _stringValue(
    map['url'] ??
        map['file_url'] ??
        map['download_url'] ??
        map['signed_url'] ??
        map['public_url'] ??
        map['view_url'] ??
        map['file_path'] ??
        map['path'] ??
        map['attachment_url'] ??
        map['storage_path'] ??
        map['link'],
  );
  if (direct == null) return null;
  return _absoluteUrl(direct);
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
