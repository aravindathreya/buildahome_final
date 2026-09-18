import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_document.dart';
import 'api_http.dart';

/// Loads workflow dashboard documents from `sales_sop_details`.
///
/// Data sources (merged, de-duplicated):
/// - `workflow_dashboard_sections` (documents tree)
/// - `workflow_dashboard_uploads` (flat upload list)
/// - Task payloads with `dashboard_card == documents`
class WorkflowDocumentService {
  WorkflowDocumentService._();
  static final WorkflowDocumentService instance = WorkflowDocumentService._();
  factory WorkflowDocumentService() => instance;

  static const String baseUrl = 'https://office.buildahome.in';

  Uri? _workingDetailsUri;
  Uri? _workingTasksUri;

  Future<WorkflowDocumentLibrary> fetchLibrary({String? projectId}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedProjectId =
        projectId?.trim() ?? prefs.getString('project_id')?.trim() ?? '';
    final salesSopId = prefs.getString('sales_sop_id')?.trim() ?? '';
    final apiToken = prefs.getString('api_token')?.trim() ?? '';
    if (apiToken.isEmpty) {
      throw Exception('Not signed in');
    }
    if (resolvedProjectId.isEmpty && salesSopId.isEmpty) {
      throw Exception('Project not selected');
    }

    final results = await Future.wait<dynamic>([
      _fetchSalesSopDetails(
        projectId: resolvedProjectId,
        salesSopId: salesSopId,
        apiToken: apiToken,
      ),
      _fetchProjectTasks(
        projectId: resolvedProjectId,
        apiToken: apiToken,
      ),
    ]);

    return _buildLibrary(
      salesSopDetails: results[0],
      taskData: results[1],
    );
  }

  Future<dynamic> _fetchSalesSopDetails({
    required String projectId,
    required String salesSopId,
    required String apiToken,
  }) async {
    final queryAttempts = <Map<String, String>>[];
    if (projectId.isNotEmpty) {
      queryAttempts.addAll([
        {'project_id': projectId, 'api_token': apiToken},
        {'id': projectId, 'api_token': apiToken},
      ]);
    }
    if (salesSopId.isNotEmpty) {
      queryAttempts.addAll([
        {'project_id': salesSopId, 'api_token': apiToken},
        {'id': salesSopId, 'api_token': apiToken},
        {'sales_sop_id': salesSopId, 'api_token': apiToken},
      ]);
    }
    queryAttempts.add({'api_token': apiToken});

    final paths = [
      '$baseUrl/api/sales_sop_details',
      '$baseUrl/API/sales_sop_details',
    ];

    Future<dynamic> tryUri(Uri uri) async {
      try {
        final response = await ApiHttp.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'X-Api-Token': apiToken,
            'Authorization': 'Bearer $apiToken',
          },
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) return null;
        return jsonDecode(response.body);
      } catch (_) {
        return null;
      }
    }

    if (_workingDetailsUri != null) {
      final cached = await tryUri(_workingDetailsUri!);
      if (cached != null) return cached;
      _workingDetailsUri = null;
    }

    for (final path in paths) {
      for (final query in queryAttempts) {
        final uri = Uri.parse(path).replace(queryParameters: query);
        final hit = await tryUri(uri);
        if (hit != null) {
          _workingDetailsUri = uri;
          return hit;
        }
      }
    }
    return null;
  }

  Future<dynamic> _fetchProjectTasks({
    required String projectId,
    required String apiToken,
  }) async {
    final attempts = [
      Uri.parse('$baseUrl/API/get_tasks').replace(
        queryParameters: {'id': projectId, 'api_token': apiToken},
      ),
      Uri.parse('$baseUrl/api/get_tasks').replace(
        queryParameters: {'id': projectId, 'api_token': apiToken},
      ),
    ];

    if (_workingTasksUri != null) {
      attempts.insert(0, _workingTasksUri!);
    }

    for (final uri in attempts) {
      try {
        final response = await ApiHttp.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'X-Api-Token': apiToken,
            'Authorization': 'Bearer $apiToken',
          },
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) continue;
        _workingTasksUri = uri;
        return jsonDecode(response.body);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  WorkflowDocumentLibrary _buildLibrary({
    dynamic salesSopDetails,
    dynamic taskData,
  }) {
    final sectionBlueprint = <String, _MutableSection>{};
    final categoryBlueprintOrder = <String>[];
    final uploads = <WorkflowDocumentUpload>[];

    void registerCategoryOrder(String libraryKey) {
      if (libraryKey.isEmpty) return;
      if (!categoryBlueprintOrder.contains(libraryKey)) {
        categoryBlueprintOrder.add(libraryKey);
      }
    }

    void registerSection({
      required String sectionId,
      required String sectionLabel,
      String? iconName,
      String categoryId = '',
      String categoryLabel = '',
      String? clientJourneyKey,
      String? libraryGroupKey,
      WorkflowDocumentPresentation presentation =
          WorkflowDocumentPresentation.library,
    }) {
      final id = sectionId.trim().isEmpty ? _slug(sectionLabel) : sectionId;
      if (id.isEmpty) return;
      final resolvedLibraryKey = _officeLibraryGroupKey(
        libraryGroupKey: libraryGroupKey,
        categoryId: categoryId,
        clientJourneyKey: clientJourneyKey,
      );
      final key = _isolatedSectionBlueprintKey(
        sectionId: id,
        categoryId: categoryId,
        libraryGroupKey: resolvedLibraryKey ?? libraryGroupKey,
        clientJourneyKey: clientJourneyKey,
      );
      final existing = sectionBlueprint[key];
      if (existing != null) {
        if (existing.label.isEmpty && sectionLabel.isNotEmpty) {
          existing.label = sectionLabel;
        }
        if (existing.categoryId.isEmpty && categoryId.isNotEmpty) {
          existing.categoryId = categoryId;
        }
        if (existing.categoryLabel.isEmpty && categoryLabel.isNotEmpty) {
          existing.categoryLabel = categoryLabel;
        }
        if (existing.clientJourneyKey == null && clientJourneyKey != null) {
          existing.clientJourneyKey = clientJourneyKey;
        }
        if (existing.libraryGroupKey == null) {
          existing.libraryGroupKey = resolvedLibraryKey ?? libraryGroupKey;
        }
        if (existing.iconName == null && iconName != null) {
          existing.iconName = iconName;
        }
        existing.presentation = presentation;
        return;
      }

      sectionBlueprint[key] = _MutableSection(
        id: id,
        label: sectionLabel.trim().isEmpty ? _titleFromKey(id) : sectionLabel,
        iconName: iconName,
        categoryId: categoryId,
        categoryLabel: categoryLabel,
        clientJourneyKey: clientJourneyKey,
        libraryGroupKey: resolvedLibraryKey ?? libraryGroupKey,
        presentation: presentation,
      );
      if ((resolvedLibraryKey ?? libraryGroupKey)?.isNotEmpty == true) {
        registerCategoryOrder(resolvedLibraryKey ?? libraryGroupKey!);
      } else if (categoryId.isNotEmpty) {
        registerCategoryOrder(categoryId);
      }
    }

    void addUpload(WorkflowDocumentUpload upload) {
      if (!upload.hasUrl) return;
      uploads.add(upload);
      registerSection(
        sectionId: upload.sectionId,
        sectionLabel: upload.sectionLabel,
        categoryId: upload.categoryId,
        categoryLabel: upload.categoryLabel,
        clientJourneyKey: upload.clientJourneyKey,
        libraryGroupKey: upload.libraryGroupKey ??
            _officeLibraryGroupKey(
              categoryId: upload.categoryId,
              clientJourneyKey: upload.clientJourneyKey,
            ),
      );
    }

    // Primary category tree: workflow_dashboard_sections.documents[]
    for (final categoryMap in _extractDocumentCategoryBlueprints(salesSopDetails)) {
      final categoryId = _stringValue(categoryMap['category_id']) ?? '';
      final categoryLabel = _stringValue(categoryMap['category_label']) ?? '';
      final libraryGroupKey = _stringValue(categoryMap['library_group_key']) ??
          categoryId;
      final clientJourneyKey = _stringValue(categoryMap['client_journey_key']);

      registerCategoryOrder(libraryGroupKey);

      final sections = categoryMap['sections'];
      if (sections is List && sections.isNotEmpty) {
        for (final sectionNode in sections) {
          if (sectionNode is! Map) continue;
          final sectionMap = Map<String, dynamic>.from(sectionNode);
          registerSection(
            sectionId: _stringValue(sectionMap['section_id']) ?? '',
            sectionLabel: _stringValue(sectionMap['section_label']) ?? '',
            iconName: _stringValue(sectionMap['section_icon']) ??
                _stringValue(sectionMap['icon']),
            categoryId: categoryId.isNotEmpty ? categoryId : libraryGroupKey,
            categoryLabel: categoryLabel,
            clientJourneyKey: _stringValue(sectionMap['client_journey_key']) ??
                clientJourneyKey,
            libraryGroupKey: libraryGroupKey,
          );
        }
      } else if (categoryId.isNotEmpty || libraryGroupKey.isNotEmpty) {
        registerSection(
          sectionId: categoryId.isNotEmpty ? categoryId : libraryGroupKey,
          sectionLabel: categoryLabel.isNotEmpty
              ? categoryLabel
              : _titleFromKey(libraryGroupKey),
          categoryId: categoryId.isNotEmpty ? categoryId : libraryGroupKey,
          categoryLabel: categoryLabel,
          clientJourneyKey: clientJourneyKey,
          libraryGroupKey: libraryGroupKey,
        );
      }
    }

    for (final sectionMap in _extractSectionMaps(salesSopDetails)) {
      registerSection(
        sectionId: _stringValue(sectionMap['section_id']) ??
            _stringValue(sectionMap['dashboard_section']) ??
            _stringValue(sectionMap['id']) ??
            '',
        sectionLabel: _stringValue(sectionMap['section_label']) ??
            _stringValue(sectionMap['dashboard_section_label']) ??
            _stringValue(sectionMap['label']) ??
            '',
        iconName: _stringValue(sectionMap['section_icon']) ??
            _stringValue(sectionMap['icon']) ??
            _stringValue(sectionMap['icon_name']),
        categoryId: _stringValue(sectionMap['category_id']) ??
            _stringValue(sectionMap['group_id']) ??
            _stringValue(sectionMap['library_group_key']) ??
            '',
        categoryLabel: _stringValue(sectionMap['category_label']) ??
            _stringValue(sectionMap['group_label']) ??
            _stringValue(sectionMap['library_group_label']) ??
            '',
        clientJourneyKey: _stringValue(sectionMap['client_journey_key']) ??
            _stringValue(sectionMap['journey_key']) ??
            _stringValue(sectionMap['client_portal_key']),
        libraryGroupKey: _stringValue(sectionMap['library_group_key']) ??
            _stringValue(sectionMap['library_category_key']) ??
            _stringValue(sectionMap['group_id']),
        presentation: _presentationFromMap(sectionMap),
      );

      final inlineItems = sectionMap['items'] ?? sectionMap['documents'];
      if (inlineItems is List) {
        for (final item in inlineItems) {
          if (item is! Map) continue;
          final upload = _uploadFromMap(
            Map<String, dynamic>.from(item),
            inherited: sectionMap,
          );
          if (upload != null) addUpload(upload);
        }
      }
    }

    for (final map in _extractUploadMaps(salesSopDetails)) {
      final upload = _uploadFromMap(map);
      if (upload != null) addUpload(upload);
    }

    for (final map in _extractTaskDocumentMaps(taskData)) {
      final upload = _uploadFromMap(map);
      if (upload != null) addUpload(upload);
    }

    for (final map in _extractCardDocumentMaps(salesSopDetails)) {
      final upload = _uploadFromMap(map);
      if (upload != null) addUpload(upload);
    }

    final dedupedUploads = _dedupeUploads(uploads);
    for (final upload in dedupedUploads) {
      final sectionId = upload.sectionId.isEmpty ? 'general' : upload.sectionId;
      final groupKey = upload.libraryGroupKey ??
          _officeLibraryGroupKey(
            categoryId: upload.categoryId,
            clientJourneyKey: upload.clientJourneyKey,
          );
      final key = _isolatedSectionBlueprintKey(
        sectionId: sectionId,
        categoryId: upload.categoryId,
        libraryGroupKey: groupKey,
        clientJourneyKey: upload.clientJourneyKey,
      );
      sectionBlueprint.putIfAbsent(
        key,
        () => _MutableSection(
          id: sectionId,
          label: upload.sectionLabel.isEmpty
              ? _titleFromKey(sectionId)
              : upload.sectionLabel,
          categoryId: upload.categoryId,
          categoryLabel: upload.categoryLabel,
          clientJourneyKey: upload.clientJourneyKey,
          libraryGroupKey: groupKey,
        ),
      );
      sectionBlueprint[key]!.documents.add(upload);
    }

    final cardFileCounts = _extractCardFileCounts(salesSopDetails);

    return _assembleLibrary(
      sectionBlueprint,
      categoryBlueprintOrder: categoryBlueprintOrder,
      cardFileCounts: cardFileCounts,
    );
  }

  WorkflowDocumentLibrary _assembleLibrary(
    Map<String, _MutableSection> sectionBlueprint, {
    List<String> categoryBlueprintOrder = const [],
    Map<String, int> cardFileCounts = const {},
  }) {
    final clientCategories = <String, _MutableCategory>{};
    final libraryCategories = <String, _MutableCategory>{};

    WorkflowDocumentSection _toSection(
      _MutableSection section,
      List<WorkflowDocumentUpload> documents,
      String categoryId,
      String categoryLabel,
    ) {
      return WorkflowDocumentSection(
        id: section.id,
        label: section.label,
        iconName: section.iconName,
        categoryId: categoryId,
        categoryLabel: categoryLabel,
        clientJourneyKey: section.clientJourneyKey,
        libraryGroupKey: section.libraryGroupKey,
        documents: documents,
      );
    }

    void appendToClient(
      _MutableSection section,
      List<WorkflowDocumentUpload> documents,
    ) {
      final journeyKey = section.clientJourneyKey?.trim();
      if (journeyKey == null || journeyKey.isEmpty) return;

      final categoryId =
          section.categoryId.isNotEmpty ? section.categoryId : journeyKey;
      final categoryLabel = section.categoryLabel.isNotEmpty
          ? section.categoryLabel
          : _titleFromKey(categoryId);

      final category = clientCategories.putIfAbsent(
        categoryId,
        () => _MutableCategory(
          id: categoryId,
          label: categoryLabel,
          iconName: section.iconName,
          clientJourneyKey: journeyKey,
          libraryGroupKey: section.libraryGroupKey,
          presentation: WorkflowDocumentPresentation.clientJourney,
        ),
      );

      category.sections.add(
        _toSection(section, documents, categoryId, categoryLabel),
      );
    }

    void appendToLibrary(
      _MutableSection section,
      List<WorkflowDocumentUpload> documents,
    ) {
      final libraryKey = section.libraryGroupKey?.trim();
      if (libraryKey == null || libraryKey.isEmpty) return;

      final categoryLabel = section.categoryLabel.isNotEmpty &&
              section.categoryId == libraryKey
          ? section.categoryLabel
          : _titleFromKey(libraryKey);

      final category = libraryCategories.putIfAbsent(
        libraryKey,
        () => _MutableCategory(
          id: libraryKey,
          label: categoryLabel,
          iconName: section.iconName,
          clientJourneyKey: section.clientJourneyKey,
          libraryGroupKey: libraryKey,
          presentation: WorkflowDocumentPresentation.library,
        ),
      );

      if (category.label == _titleFromKey(libraryKey) &&
          section.categoryLabel.isNotEmpty &&
          section.categoryId == libraryKey) {
        category.label = section.categoryLabel;
      }

      category.sections.add(
        _toSection(section, documents, libraryKey, category.label),
      );
    }

    for (final section in sectionBlueprint.values) {
      final groupedDocs = _groupRevisions(section.documents);
      // Same section/documents can appear in both client journey and library.
      appendToClient(section, groupedDocs);
      appendToLibrary(section, groupedDocs);
    }

    List<WorkflowDocumentCategory> finalize(
      Map<String, _MutableCategory> source,
    ) {
      final out = <WorkflowDocumentCategory>[];
      final seen = <String>{};

      void addCategory(_MutableCategory category) {
        if (seen.contains(category.id)) return;
        final dedupedSections = <String, WorkflowDocumentSection>{};
        for (final section in category.sections) {
          dedupedSections[section.id] = section;
        }
        final sections = dedupedSections.values.toList()
          ..sort((a, b) => a.label.compareTo(b.label));
        if (sections.isEmpty) return;
        seen.add(category.id);
        out.add(
          WorkflowDocumentCategory(
            id: category.id,
            label: category.label,
            iconName: category.iconName,
            clientJourneyKey: category.clientJourneyKey,
            libraryGroupKey: category.libraryGroupKey,
            presentation: category.presentation,
            sections: sections,
          ),
        );
      }

      for (final key in categoryBlueprintOrder) {
        final category = source[key];
        if (category != null) addCategory(category);
      }

      final remaining = source.values.toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      for (final category in remaining) {
        addCategory(category);
      }

      return out;
    }

    return WorkflowDocumentLibrary(
      clientJourneyCategories: finalize(clientCategories),
      libraryCategories: finalize(libraryCategories),
      cardFileCounts: cardFileCounts,
    );
  }

  List<WorkflowDocumentUpload> _groupRevisions(
    List<WorkflowDocumentUpload> uploads,
  ) {
    if (uploads.isEmpty) return const [];

    final byKey = <String, List<WorkflowDocumentUpload>>{};
    for (final upload in uploads) {
      final key = upload.documentKey.isNotEmpty
          ? upload.documentKey
          : _slug(upload.name);
      byKey.putIfAbsent(key, () => <WorkflowDocumentUpload>[]).add(upload);
    }

    final grouped = <WorkflowDocumentUpload>[];
    for (final entries in byKey.values) {
      entries.sort((a, b) {
        final ar = a.revision ?? 0;
        final br = b.revision ?? 0;
        if (ar != br) return br.compareTo(ar);
        return (b.uploadedAt ?? '').compareTo(a.uploadedAt ?? '');
      });

      var markedLatest = false;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final latest = entry.isLatest || (!markedLatest && i == 0);
        if (latest) markedLatest = true;
        grouped.add(
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
            status: latest ? 'latest' : (entry.status ?? 'superseded'),
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

    grouped.sort((a, b) => a.name.compareTo(b.name));
    return grouped;
  }

  List<WorkflowDocumentUpload> _dedupeUploads(
    List<WorkflowDocumentUpload> uploads,
  ) {
    final seen = <String>{};
    final out = <WorkflowDocumentUpload>[];
    for (final upload in uploads) {
      final key = [
        upload.documentKey,
        upload.url,
        upload.revision?.toString() ?? '',
        upload.id,
      ].join('|').toLowerCase();
      if (seen.add(key)) out.add(upload);
    }
    return out;
  }

  List<Map<String, dynamic>> _extractDocumentCategoryBlueprints(
    dynamic salesSopDetails,
  ) {
    final details = _coalesceSalesSopDetails(salesSopDetails);
    if (details.isEmpty) return const [];

    final workflowSections = details['workflow_dashboard_sections'];
    if (workflowSections is! Map) return const [];

    final documents = workflowSections['documents'];
    if (documents is! List) return const [];

    return documents
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, int> _extractCardFileCounts(dynamic salesSopDetails) {
    final details = _coalesceSalesSopDetails(salesSopDetails);
    final cards = details['cards'];
    if (cards is! Map) return const {};

    final counts = <String, int>{};
    for (final entry in cards.entries) {
      if (entry.value is! Map) continue;
      final map = Map<String, dynamic>.from(entry.value as Map);
      final count = _asInt(map['file_count']);
      if (count != null && count >= 0) {
        counts[entry.key.toString()] = count;
      }
    }
    return counts;
  }

  List<Map<String, dynamic>> _extractCardDocumentMaps(dynamic salesSopDetails) {
    final details = _coalesceSalesSopDetails(salesSopDetails);
    final cards = details['cards'];
    if (cards is! Map) return const [];

    final maps = <Map<String, dynamic>>[];
    final arch = cards['architectural_site_documents'];
    if (arch is Map) {
      final archMap = Map<String, dynamic>.from(arch);
      const fieldMeta = <String, List<String>>{
        'floor_plan': ['Floor Plan', 'dsec_floor_plan'],
        'elevation': ['Elevation', 'dsec_elevation'],
        'final_floor_plan': ['Final Floor Plan', 'dsec_final_floor_plan'],
        'final_elevation': ['Final Elevation', 'dsec_final_elevation'],
        'framing_drawing': ['Framing Drawing', 'dsec_framing_drawing'],
      };
      for (final entry in fieldMeta.entries) {
        final value = archMap[entry.key];
        if (value == null) continue;
        final sectionLabel = entry.value[0];
        final sectionId = entry.value[1];
        if (value is Map) {
          maps.add({
            ...Map<String, dynamic>.from(value),
            'document_name': _stringValue(value['document_name']) ??
                _stringValue(value['name']) ??
                sectionLabel,
            'section_id': sectionId,
            'section_label': sectionLabel,
            'category_id': 'floor_plan_elevation',
            'category_label': 'Floor Plan & Elevation',
            'client_journey_key': ClientJourneyKeys.floorPlan,
            'library_group_key': 'floor_plan_elevation',
            'is_latest': true,
            'status': 'latest',
          });
        } else {
          final url = value.toString().trim();
          if (url.isEmpty || url.toLowerCase() == 'null') continue;
          maps.add({
            'url': url,
            'document_name': sectionLabel,
            'filename': sectionLabel,
            'section_id': sectionId,
            'section_label': sectionLabel,
            'category_id': 'floor_plan_elevation',
            'category_label': 'Floor Plan & Elevation',
            'client_journey_key': ClientJourneyKeys.floorPlan,
            'library_group_key': 'floor_plan_elevation',
            'is_latest': true,
            'status': 'latest',
          });
        }
      }
    }

    final siteInspection = cards['site_inspection'];
    if (siteInspection is Map) {
      final report = siteInspection['site_inspection_report'];
      if (report is Map) {
        maps.add({
          ...Map<String, dynamic>.from(report),
          'section_id': 'dsec_site_inspection_report',
          'section_label': 'Site Inspection Report',
          'category_id': 'site_inspection',
          'category_label': 'Site Inspection',
          'client_journey_key': ClientJourneyKeys.inspection,
          'library_group_key': 'site_inspection',
          'is_latest': true,
          'status': 'latest',
        });
      }
    }

    return maps;
  }

  List<Map<String, dynamic>> _extractSectionMaps(dynamic salesSopDetails) {
    final details = _coalesceSalesSopDetails(salesSopDetails);
    if (details.isEmpty) return const [];

    final workflowSections = details['workflow_dashboard_sections'];
    if (workflowSections is! Map) return const [];

    final output = <Map<String, dynamic>>[];

    void visit(dynamic node, Map<String, dynamic> inherited) {
      if (node is List) {
        for (final child in node) {
          visit(child, inherited);
        }
        return;
      }
      if (node is! Map) return;

      final map = Map<String, dynamic>.from(node);
      final merged = Map<String, dynamic>.from(inherited);

      for (final key in const [
        'category_id',
        'category_label',
        'group_id',
        'group_label',
        'client_journey_key',
        'journey_key',
        'client_portal_key',
        'library_group_key',
        'library_category_key',
        'library_group_label',
        'presentation',
      ]) {
        if (map[key] != null) merged[key] = map[key];
      }

      final hasSection = map.containsKey('section_id') ||
          map.containsKey('dashboard_section') ||
          map.containsKey('section_label') ||
          map.containsKey('dashboard_section_label');

      final nestedSections = map['sections'];
      if (nestedSections is List) {
        for (final child in nestedSections) {
          if (child is Map) {
            visit(
              Map<String, dynamic>.from(child),
              merged,
            );
          }
        }
      }

      if (hasSection) {
        output.add({...merged, ...map});
      }

      final items = map['items'] ?? map['documents'];
      if (items is List && hasSection) {
        output.add({...merged, ...map});
      }
    }

    for (final entry in workflowSections.entries) {
      if (entry.key.toString().toLowerCase() == 'gallery') continue;
      if (entry.key.toString().toLowerCase() == 'documents') continue;
      final value = entry.value;
      if (value is List) {
        visit(value, {'library_group_key': entry.key.toString()});
      } else if (value is Map) {
        visit(
          Map<String, dynamic>.from(value),
          {'library_group_key': entry.key.toString()},
        );
      }
    }

    return output;
  }

  List<Map<String, dynamic>> _extractUploadMaps(dynamic salesSopDetails) {
    final details = _coalesceSalesSopDetails(salesSopDetails);
    if (details.isEmpty) return const [];

    final uploads = details['workflow_dashboard_uploads'];
    if (uploads is! List) return const [];

    return uploads
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _extractTaskDocumentMaps(dynamic taskData) {
    final maps = <Map<String, dynamic>>[];

    void visit(dynamic item, Map<String, dynamic> inherited) {
      if (item is List) {
        for (final child in item) {
          visit(child, inherited);
        }
        return;
      }
      if (item is! Map) return;

      final map = Map<String, dynamic>.from(item);
      final nextInherited = Map<String, dynamic>.from(inherited);
      for (final key in const [
        'dashboard_card',
        'dashboard_section',
        'dashboard_section_label',
        'category_id',
        'category_label',
        'client_journey_key',
        'journey_key',
        'library_group_key',
        'task_name',
        'task_id',
      ]) {
        if (map[key] != null) nextInherited[key] = map[key];
      }

      final card = _stringValue(nextInherited['dashboard_card'])?.toLowerCase();
      final mapCard = _stringValue(map['dashboard_card'])?.toLowerCase();
      if (card == 'documents' || mapCard == 'documents') {
        _appendDocumentFileMaps(maps, map, nextInherited);
      }

      for (final actionsKey in const [
        'workflow_actions',
        'workflow_task_actions',
      ]) {
        final actions = map[actionsKey];
        if (actions is! List) continue;
        for (final action in actions) {
          if (action is! Map) continue;
          final actionMap = Map<String, dynamic>.from(action);
          _appendDocumentFileMaps(maps, actionMap, nextInherited);
          final response = actionMap['response'];
          if (response is Map) {
            _appendDocumentFileMaps(
              maps,
              Map<String, dynamic>.from(response),
              nextInherited,
            );
          }
        }
      }

      for (final responsesKey in const [
        'workflow_action_responses',
        'workflow_prior_responses',
      ]) {
        final responses = map[responsesKey];
        if (responses is! List) continue;
        for (final response in responses) {
          if (response is! Map) continue;
          _appendDocumentFileMaps(
            maps,
            Map<String, dynamic>.from(response),
            nextInherited,
          );
        }
      }

      for (final child in map.values) {
        if (child is Map || child is List) visit(child, nextInherited);
      }
    }

    if (taskData is Map && taskData['tasks'] is List) {
      visit(taskData['tasks'], <String, dynamic>{});
    } else {
      visit(taskData, <String, dynamic>{});
    }

    return maps;
  }

  void _appendDocumentFileMaps(
    List<Map<String, dynamic>> maps,
    Map<String, dynamic> source,
    Map<String, dynamic> inherited,
  ) {
    for (final key in const [
      'files',
      'attachments',
      'uploaded_files',
      'uploads',
      'documents',
      'document',
    ]) {
      final children = source[key];
      if (children is! List) continue;
      for (final child in children) {
        if (child is! Map) continue;
        maps.add({...inherited, ...Map<String, dynamic>.from(child)});
      }
    }

    final url = _resolveDocumentUrl(source);
    if (url != null) {
      maps.add({...inherited, ...source});
    }
  }

  WorkflowDocumentUpload? _uploadFromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? inherited,
  }) {
    final merged = inherited == null
        ? map
        : {...inherited, ...map};

    final url = _resolveDocumentUrl(merged);
    if (url == null) return null;

    final name = _stringValue(merged['document_name']) ??
        _stringValue(merged['filename']) ??
        _stringValue(merged['file_name']) ??
        _stringValue(merged['name']) ??
        _stringValue(merged['title']) ??
        url.split('/').last;

    final sectionId = _stringValue(merged['dashboard_section']) ??
        _stringValue(merged['section_id']) ??
        _slug(_stringValue(merged['dashboard_section_label']) ?? 'general');

    final sectionLabel = _stringValue(merged['dashboard_section_label']) ??
        _stringValue(merged['section_label']) ??
        _titleFromKey(sectionId);

    final categoryId = _stringValue(merged['category_id']) ??
        _stringValue(merged['group_id']) ??
        _stringValue(merged['library_group_key']) ??
        '';

    final categoryLabel = _stringValue(merged['category_label']) ??
        _stringValue(merged['group_label']) ??
        _stringValue(merged['library_group_label']) ??
        '';

    final documentKey = _stringValue(merged['document_id']) ??
        _stringValue(merged['document_key']) ??
        _slug(name);

    final revision = _asInt(
      merged['revision'] ?? merged['rev'] ?? merged['version'],
    );

    List<Map<String, dynamic>> activity = const [];
    final rawActivity = merged['activity'] ?? merged['activities'];
    if (rawActivity is List) {
      activity = rawActivity
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return WorkflowDocumentUpload(
      id: _stringValue(merged['upload_id']) ??
          _stringValue(merged['id']) ??
          '$documentKey-${revision ?? url.hashCode}',
      documentKey: documentKey,
      name: name,
      url: url,
      contentType: _stringValue(merged['content_type']) ??
          _stringValue(merged['mime_type']),
      fileSize: _formatFileSize(merged['file_size'] ?? merged['size']),
      revision: revision,
      revisionLabel: _stringValue(merged['revision_label']) ??
          _stringValue(merged['rev_label']),
      isLatest: _truthy(merged['is_latest']) ||
          _stringValue(merged['status'])?.toLowerCase() == 'latest',
      uploadedAt: _formatDateTime(
        _stringValue(merged['uploaded_at']) ??
            _stringValue(merged['created_at']) ??
            _stringValue(merged['updated_at']),
      ),
      uploadedBy: _stringValue(merged['uploaded_by']) ??
          _stringValue(merged['user_name']) ??
          _stringValue(merged['uploaded_by_name']),
      taskName: _stringValue(merged['task_name']) ??
          _stringValue(merged['task']) ??
          _stringValue(merged['note']),
      taskId: _stringValue(merged['task_id']),
      status: _stringValue(merged['status']),
      sectionId: sectionId,
      sectionLabel: sectionLabel,
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      clientJourneyKey: _stringValue(merged['client_journey_key']) ??
          _stringValue(merged['journey_key']) ??
          _stringValue(merged['client_portal_key']),
      libraryGroupKey: _stringValue(merged['library_group_key']) ??
          _stringValue(merged['library_category_key']) ??
          _stringValue(merged['group_id']) ??
          _officeLibraryGroupKey(
            categoryId: _stringValue(merged['category_id']) ?? '',
            clientJourneyKey: _stringValue(merged['client_journey_key']) ??
                _stringValue(merged['journey_key']) ??
                _stringValue(merged['client_portal_key']),
          ),
      activity: activity,
      raw: merged,
    );
  }

  String? _resolveDocumentUrl(Map<String, dynamic> map) {
    final direct = _stringValue(map['url']) ??
        _stringValue(map['file_url']) ??
        _stringValue(map['download_url']) ??
        _stringValue(map['signed_url']) ??
        _stringValue(map['public_url']) ??
        _stringValue(map['view_url']) ??
        _stringValue(map['file_path']) ??
        _stringValue(map['path']) ??
        _stringValue(map['attachment_url']) ??
        _stringValue(map['storage_path']);
    if (direct == null) return null;
    return _absoluteUrl(direct);
  }

  String _absoluteUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) return '$baseUrl$trimmed';
    return '$baseUrl/$trimmed';
  }

  Map<String, dynamic> _coalesceSalesSopDetails(dynamic value) {
    if (value is! Map) return <String, dynamic>{};

    final root = Map<String, dynamic>.from(value);
    final nested = _unwrapSalesSopDetails(value);
    final details = nested is Map
        ? Map<String, dynamic>.from(nested)
        : <String, dynamic>{};

    for (final key in const [
      'workflow_dashboard_sections',
      'workflow_dashboard_uploads',
      'workflow_dashboard_uploads_by_card',
      'workflow_dashboard_sections_by_card',
    ]) {
      if (!details.containsKey(key) && root.containsKey(key)) {
        details[key] = root[key];
      }
    }

    return details;
  }

  dynamic _unwrapSalesSopDetails(dynamic value) {
    if (value is! Map) return value;
    return value['api_sales_sop_details'] ??
        value['sales_sop_details'] ??
        value['data'] ??
        value['project'] ??
        value;
  }

  WorkflowDocumentPresentation _presentationFromMap(Map<String, dynamic> map) {
    final raw = (_stringValue(map['presentation']) ??
            _stringValue(map['audience']) ??
            '')
        .toLowerCase();
    if (raw.contains('client') || raw.contains('journey')) {
      return WorkflowDocumentPresentation.clientJourney;
    }
    if (_stringValue(map['client_journey_key']) != null &&
        _stringValue(map['library_group_key']) == null) {
      return WorkflowDocumentPresentation.clientJourney;
    }
    return WorkflowDocumentPresentation.library;
  }
}

class _MutableSection {
  final String id;
  String label;
  String? iconName;
  String categoryId;
  String categoryLabel;
  String? clientJourneyKey;
  String? libraryGroupKey;
  WorkflowDocumentPresentation presentation;
  final List<WorkflowDocumentUpload> documents = [];

  _MutableSection({
    required this.id,
    required this.label,
    this.iconName,
    this.categoryId = '',
    this.categoryLabel = '',
    this.clientJourneyKey,
    this.libraryGroupKey,
    this.presentation = WorkflowDocumentPresentation.library,
  });
}

class _MutableCategory {
  final String id;
  String label;
  String? iconName;
  String? clientJourneyKey;
  String? libraryGroupKey;
  WorkflowDocumentPresentation presentation;
  final List<WorkflowDocumentSection> sections = [];

  _MutableCategory({
    required this.id,
    required this.label,
    this.iconName,
    this.clientJourneyKey,
    this.libraryGroupKey,
    this.presentation = WorkflowDocumentPresentation.library,
  });
}

String? _stringValue(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool _truthy(dynamic value) {
  if (value == true) return true;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

/// Office `/documents` and `/View_receipt_and_agreement` lists.
/// Do not invent these on the client — only fill missing library keys.
String? _officeLibraryGroupKey({
  String? libraryGroupKey,
  String categoryId = '',
  String? clientJourneyKey,
}) {
  final explicit = libraryGroupKey?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final fallback = categoryId.trim().isNotEmpty
      ? categoryId.trim()
      : (clientJourneyKey ?? '').trim();
  if (fallback == ClientJourneyKeys.officeDocuments ||
      fallback == ClientJourneyKeys.receiptsAndAgreements) {
    return fallback;
  }
  return null;
}

/// Keep office library lists out of workflow sections that share short ids
/// (e.g. receipts `agreements` vs workflow `dsec_agreements`).
String _isolatedSectionBlueprintKey({
  required String sectionId,
  String categoryId = '',
  String? libraryGroupKey,
  String? clientJourneyKey,
}) {
  final group = _officeLibraryGroupKey(
        libraryGroupKey: libraryGroupKey,
        categoryId: categoryId,
        clientJourneyKey: clientJourneyKey,
      ) ??
      '';
  if (group.isEmpty) return sectionId;
  return '$group::$sectionId';
}

String _slug(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _titleFromKey(String key) {
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

String? _formatFileSize(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final bytes = value.toDouble();
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${bytes.toStringAsFixed(0)} B';
  }
  return value.toString();
}

String? _formatDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
}

/// Client journey keys used by Client Portal tiles.
class ClientJourneyKeys {
  static const kycDocuments = 'kyc_documents';
  static const floorPlan = 'floor_plan_elevation';
  static const design = 'design_elements';
  static const gfc = 'gfc_construction_drawings';
  static const quality = 'quality_test_reports';
  static const siteRecords = 'site_construction_records';
  static const doorsWindows = 'doors_windows_grills';
  static const sitePrep = 'site_preparation';
  static const demolition = 'demolition_details';
  static const inspection = 'site_inspection';
  static const preConversion = 'pre_conversion_documents';
  static const officeDocuments = 'office_documents';
  static const receiptsAndAgreements = 'receipts_and_agreements';
}
