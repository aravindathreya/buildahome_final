import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workflow_document.dart';
import 'api_http.dart';
import 'session_manager.dart';

/// One tab on the Receipts and Agreements screen (Receipts, Agreements, ...).
class ReceiptsAgreementsGroup {
  final String id;
  final String label;
  final List<WorkflowDocumentUpload> documents;

  const ReceiptsAgreementsGroup({
    required this.id,
    required this.label,
    this.documents = const [],
  });
}

class ReceiptsAgreementsResult {
  /// False when the backend says this role may not see the ERP page.
  final bool canView;
  final String projectId;
  final List<ReceiptsAgreementsGroup> groups;

  const ReceiptsAgreementsResult({
    required this.canView,
    required this.projectId,
    this.groups = const [],
  });

  int get total =>
      groups.fold<int>(0, (sum, group) => sum + group.documents.length);

  /// Only tabs that have files (hide-when-empty rule).
  List<ReceiptsAgreementsGroup> get nonEmptyGroups =>
      groups.where((group) => group.documents.isNotEmpty).toList();
}

/// GET /api/mobile/project/<id>/receipts_agreements — the same Docs rows the
/// ERP "Receipts and Agreements" page lists.
class ReceiptsAgreementsService {
  ReceiptsAgreementsService._();
  static final ReceiptsAgreementsService instance =
      ReceiptsAgreementsService._();

  static const List<String> baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];
  static const Duration requestTimeout = Duration(seconds: 15);

  final Map<String, ReceiptsAgreementsResult> _cache = {};

  ReceiptsAgreementsResult? cached(String projectId) => _cache[projectId];

  Future<ReceiptsAgreementsResult> fetch(
    String projectId, {
    bool force = false,
  }) async {
    final pid = projectId.trim();
    if (pid.isEmpty) {
      throw Exception('Select a project first');
    }
    if (!force && _cache.containsKey(pid)) return _cache[pid]!;

    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('api_token') ?? '').trim();
    if (token.isEmpty || token.toLowerCase() == 'null') {
      throw Exception('Please log in again');
    }
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    final query = <String, String>{
      'api_token': token,
      if (userId.isNotEmpty) 'user_id': userId,
    };
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };

    Object? lastError;
    for (final base in baseUrls) {
      for (final prefix in const ['api', 'API']) {
        final uri = Uri.parse(
          '$base/$prefix/mobile/project/${Uri.encodeComponent(pid)}/receipts_agreements',
        ).replace(queryParameters: query);
        try {
          final response =
              await ApiHttp.get(uri, headers: headers).timeout(requestTimeout);
          if (response.statusCode == 403) {
            final denied = _parseDenied(response.body);
            if (denied) {
              final result = ReceiptsAgreementsResult(
                canView: false,
                projectId: pid,
              );
              _cache[pid] = result;
              return result;
            }
            lastError = 'You cannot access this project';
            continue;
          }
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['success'] != true) {
            lastError = (decoded is Map ? decoded['message'] : null) ??
                'Unexpected response';
            continue;
          }
          final result = parseReceiptsAgreementsPayload(
            Map<String, dynamic>.from(decoded),
            projectId: pid,
          );
          _cache[pid] = result;
          return result;
        } on SessionInvalidatedException {
          rethrow;
        } catch (e) {
          lastError = e;
        }
      }
    }
    throw Exception(
      'Could not load receipts and agreements${lastError == null ? '' : ' ($lastError)'}',
    );
  }

  bool _parseDenied(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['can_view'] == false;
    } catch (_) {
      return false;
    }
  }
}

ReceiptsAgreementsResult parseReceiptsAgreementsPayload(
  Map<String, dynamic> json, {
  required String projectId,
}) {
  final groups = <ReceiptsAgreementsGroup>[];
  final rawGroups = json['groups'];
  if (rawGroups is List) {
    for (final raw in rawGroups) {
      if (raw is! Map) continue;
      final group = Map<String, dynamic>.from(raw);
      final id = (group['id'] ?? '').toString();
      final label = (group['label'] ?? id).toString();
      final docs = <WorkflowDocumentUpload>[];
      final rawDocs = group['documents'];
      if (rawDocs is List) {
        for (final rawDoc in rawDocs) {
          if (rawDoc is! Map) continue;
          final doc = _documentFromJson(
            Map<String, dynamic>.from(rawDoc),
            groupId: id,
            groupLabel: label,
          );
          if (doc != null) docs.add(doc);
        }
      }
      groups.add(ReceiptsAgreementsGroup(id: id, label: label, documents: docs));
    }
  }
  return ReceiptsAgreementsResult(
    canView: json['can_view'] != false,
    projectId: (json['project_id'] ?? projectId).toString(),
    groups: groups,
  );
}

WorkflowDocumentUpload? _documentFromJson(
  Map<String, dynamic> map, {
  required String groupId,
  required String groupLabel,
}) {
  final url = (map['url'] ?? '').toString().trim();
  if (url.isEmpty) return null;
  final docId = (map['doc_id'] ?? map['id'] ?? '').toString();
  final name = (map['name'] ?? map['filename'] ?? groupLabel).toString();
  final uploadedIso = (map['uploaded_at_iso'] ?? '').toString().trim();
  final uploadedRaw = (map['uploaded_at'] ?? '').toString().trim();
  return WorkflowDocumentUpload(
    id: 'receipt_$docId',
    documentKey: 'receipt:$docId',
    name: name,
    url: url,
    contentType: map['content_type']?.toString(),
    isLatest: true,
    uploadedAt: uploadedIso.isNotEmpty
        ? uploadedIso
        : (uploadedRaw.isNotEmpty ? uploadedRaw : null),
    uploadedBy: map['uploaded_by']?.toString(),
    status: 'uploaded',
    sectionId: groupId,
    sectionLabel: groupLabel,
    categoryId: 'receipts_and_agreements',
    categoryLabel: 'Receipts and Agreements',
    clientJourneyKey: 'receipts_and_agreements',
    libraryGroupKey: 'receipts_and_agreements',
    raw: map,
  );
}