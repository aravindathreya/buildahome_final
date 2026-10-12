import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'models/workflow_document.dart';
import 'services/api_http.dart';
import 'user_facing_error.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/workflow_document_viewer.dart';

/// Lists Technical Specs documents uploaded from the web project-details card
/// for the current project (same sales_sop.technical_specs_path files).
class TechnicalSpecsScreen extends StatefulWidget {
  const TechnicalSpecsScreen({
    Key? key,
    this.fixedProjectId,
    this.fixedSalesSopId,
  }) : super(key: key);

  final String? fixedProjectId;
  final String? fixedSalesSopId;

  @override
  State<TechnicalSpecsScreen> createState() => _TechnicalSpecsScreenState();
}

class _TechnicalSpecsScreenState extends State<TechnicalSpecsScreen> {
  static const List<String> _baseUrls = [
    'https://office.buildahome.in',
    'https://app.buildahome.in',
  ];

  bool _loading = true;
  bool _offline = false;
  String? _error;
  List<_TechSpecDoc> _docs = const [];
  String? _projectId;
  String? _salesSopId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final projectId =
          (widget.fixedProjectId ?? prefs.getString('project_id') ?? '')
              .trim();
      final salesSopId =
          (widget.fixedSalesSopId ?? prefs.getString('sales_sop_id') ?? '')
              .trim();
      final token = (prefs.getString('api_token') ?? '').trim();
      if (token.isEmpty || token.toLowerCase() == 'null') {
        setState(() {
          _loading = false;
          _error = 'Please sign in again to view Technical Specs.';
        });
        return;
      }
      if (projectId.isEmpty && salesSopId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Open a project first, then open Technical Specs.';
        });
        return;
      }
      final queryPid = projectId.isNotEmpty ? projectId : salesSopId;
      final docs = await _fetchDocs(queryPid, token);
      if (!mounted) return;
      setState(() {
        _projectId = projectId.isNotEmpty ? projectId : null;
        _salesSopId = salesSopId.isNotEmpty ? salesSopId : null;
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final offline = isConnectionError(e);
      setState(() {
        _loading = false;
        _offline = offline;
        _error = offline
            ? connectionErrorMessage
            : userFacingError(
                e,
                fallback: 'Could not load Technical Specs. Please try again.',
              );
      });
    }
  }

  Future<List<_TechSpecDoc>> _fetchDocs(String projectId, String token) async {
    final query = <String, String>{
      'project_id': projectId,
      'api_token': token,
    };
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };
    Object? httpError;
    var reachedServer = false;
    var sawMissingDocuments = false;
    for (final base in _baseUrls) {
      for (final prefix in const ['API', 'api']) {
        final uri = Uri.parse('$base/$prefix/mobile/technical_specs')
            .replace(queryParameters: query);
        try {
          final response =
              await ApiHttp.get(uri, headers: headers).timeout(
            const Duration(seconds: 20),
          );
          reachedServer = true;
          final outcome = _interpretResponse(
            response.statusCode,
            response.body,
          );
          if (outcome.documents != null) return outcome.documents!;
          if (outcome.missing) {
            sawMissingDocuments = true;
            continue;
          }
          httpError = outcome.error ??
              'Could not load Technical Specs. Please try again.';
        } catch (e) {
          if (isConnectionError(e)) continue;
          reachedServer = true;
          httpError = e;
        }
      }
    }
    if (sawMissingDocuments &&
        (httpError == null || !_isRealProblem('$httpError'))) {
      return const [];
    }
    if (!reachedServer) throw const NetworkUnavailableException();
    throw httpError ??
        Exception('Could not load Technical Specs. Please try again.');
  }

  _TechSpecOutcome _interpretResponse(int statusCode, String body) {
    dynamic decoded;
    var invalidJson = false;
    final trimmed = body.trim();
    if (trimmed.isNotEmpty) {
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        invalidJson = true;
      }
    }

    if (statusCode == 401 || statusCode == 403) {
      final authMessage = _messageOf(decoded);
      return _TechSpecOutcome.error(
        authMessage.isNotEmpty
            ? authMessage
            : 'Please sign in again to view Technical Specs.',
      );
    }

    if (invalidJson) {
      if (statusCode == 404 || statusCode == 204) {
        return const _TechSpecOutcome.missing();
      }
      return const _TechSpecOutcome.error(
        'Could not load Technical Specs. Please try again.',
      );
    }

    final message = _messageOf(decoded);
    final docs = _extractDocs(decoded);
    final emptyMessage = _isEmptyDocumentMessage(message.toLowerCase());

    if (docs != null && docs.isNotEmpty) {
      return _TechSpecOutcome.documents(docs);
    }

    if (docs != null && docs.isEmpty) {
      return _TechSpecOutcome.documents(const []);
    }

    if (emptyMessage ||
        statusCode == 404 ||
        statusCode == 204 ||
        (statusCode >= 400 &&
            statusCode < 500 &&
            !_isRealProblem(message))) {
      return const _TechSpecOutcome.missing();
    }

    if (statusCode >= 200 && statusCode < 300) {
      if (_isRealProblem(message)) {
        return _TechSpecOutcome.error(message);
      }
      return _TechSpecOutcome.documents(const []);
    }

    return _TechSpecOutcome.error(
      _isRealProblem(message)
          ? message
          : 'Could not load Technical Specs. Please try again.',
    );
  }

  String _messageOf(dynamic decoded) {
    if (decoded is! Map) return '';
    final map = Map<String, dynamic>.from(decoded);
    return (map['message'] ?? map['error'] ?? '').toString().trim();
  }

  /// Document rows when the payload includes a file list. Null when the
  /// payload has no file field at all.
  List<_TechSpecDoc>? _extractDocs(dynamic decoded) {
    if (decoded is List) return _docsFromList(decoded);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    for (final key in const [
      'documents',
      'files',
      'technical_specs',
      'items',
      'data',
    ]) {
      if (!map.containsKey(key)) continue;
      final raw = map[key];
      if (raw is List) return _docsFromList(raw);
      if (raw is Map) {
        final nested = _extractDocs(raw);
        if (nested != null) return nested;
      }
      if (raw == null || (raw is String && raw.trim().isEmpty)) {
        return const [];
      }
    }
    return null;
  }

  bool _isEmptyDocumentMessage(String lower) {
    if (lower.isEmpty) return false;
    const phrases = [
      'no document',
      'no file',
      'no doc',
      'not uploaded',
      'not added',
      'nothing uploaded',
      'nothing added',
      'none uploaded',
      'none added',
      'no technical',
      'no spec',
      'no data',
      'no record',
      'not found',
      'does not exist',
      "doesn't exist",
      'not exist',
      'not available',
      'no attachment',
      'path is empty',
      'empty path',
      'has no ',
      'have no ',
    ];
    for (final phrase in phrases) {
      if (lower.contains(phrase)) return true;
    }
    return false;
  }

  bool _isRealProblem(String message) {
    final lower = message.toLowerCase();
    if (lower.isEmpty || _isEmptyDocumentMessage(lower)) return false;
    return lower.contains('unauthor') ||
        lower.contains('forbidden') ||
        lower.contains('sign in') ||
        lower.contains('token') ||
        lower.contains('server error') ||
        lower.contains('exception') ||
        lower.contains('sql') ||
        lower.contains('permission denied') ||
        lower.contains('not allowed') ||
        lower.contains('invalid project');
  }

  List<_TechSpecDoc> _docsFromList(List<dynamic> raw) {
    return [
      for (final row in raw)
        if (row is Map) _TechSpecDoc.fromJson(Map<String, dynamic>.from(row)),
    ].where((d) => d.url.isNotEmpty).toList();
  }

  Future<void> _openDoc(_TechSpecDoc doc) async {
    final upload = WorkflowDocumentUpload(
      id: 'technical_specs_${doc.index}',
      documentKey: 'technical_specs:${doc.index}',
      name: doc.name,
      url: doc.url,
      contentType: doc.fileExt == 'pdf'
          ? 'application/pdf'
          : (const {'png', 'jpg', 'jpeg'}.contains(doc.fileExt)
              ? 'image/${doc.fileExt == 'jpg' ? 'jpeg' : doc.fileExt}'
              : null),
      uploadedAt: doc.uploadedAtDisplay,
      sectionId: 'technical_specs',
      sectionLabel: 'Technical Specs',
      categoryId: 'technical_specs',
      categoryLabel: 'Technical Specs',
      isLatest: true,
    );
    await openWorkflowDocument(context, upload, clientMode: false);
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Technical Specs',
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Icon(
            _offline ? Icons.wifi_off_rounded : Icons.info_outline,
            size: 48,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }
    if (_docs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.folder_open, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text(
            'No documents added',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Technical Specs will show up here once a document is uploaded for this project.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if ((_projectId ?? '').isNotEmpty || (_salesSopId ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Project: ${_projectId ?? _salesSopId}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = _docs[index];
        final isPdf = doc.fileExt == 'pdf';
        return Material(
          color: AppTheme.darkBackgroundSecondary,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _openDoc(doc),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkBackgroundSecondary,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isPdf
                          ? const Color(0xFF2C1618)
                          : const Color(0xFF2A2040),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPdf
                          ? Icons.picture_as_pdf_rounded
                          : Icons.description_outlined,
                      color: isPdf
                          ? const Color(0xFFF87171)
                          : AppTheme.darkTextPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkTextPrimary,
                            fontSize: 15,
                            height: 1.25,
                          ),
                        ),
                        if ((doc.uploadedAtDisplay ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            doc.uploadedAtDisplay!,
                            style: TextStyle(
                              color: AppTheme.darkTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: AppTheme.darkTextSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TechSpecOutcome {
  const _TechSpecOutcome.documents(this.documents)
      : missing = false,
        error = null;

  const _TechSpecOutcome.missing()
      : documents = null,
        missing = true,
        error = null;

  const _TechSpecOutcome.error(this.error)
      : documents = null,
        missing = false;

  final List<_TechSpecDoc>? documents;
  final bool missing;
  final Object? error;
}

class _TechSpecDoc {
  const _TechSpecDoc({
    required this.index,
    required this.name,
    required this.url,
    this.fileExt = '',
    this.uploadedAtDisplay,
  });

  final int index;
  final String name;
  final String url;
  final String fileExt;
  final String? uploadedAtDisplay;

  factory _TechSpecDoc.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] ?? 'Document').toString().trim();
    return _TechSpecDoc(
      index: int.tryParse('${json['index'] ?? 0}') ?? 0,
      name: rawName.isEmpty ? 'Document' : rawName,
      url: (json['url'] ?? '').toString().trim(),
      fileExt: (json['file_ext'] ?? json['fileExt'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      uploadedAtDisplay:
          (json['uploaded_at_display'] ?? json['uploadedAtDisplay'])
              ?.toString(),
    );
  }
}
