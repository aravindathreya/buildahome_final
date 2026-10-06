import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'models/workflow_document.dart';
import 'services/api_http.dart';
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
      setState(() {
        _loading = false;
        _error = 'Could not load Technical Specs. $e';
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
    Object? lastError;
    for (final base in _baseUrls) {
      for (final prefix in const ['API', 'api']) {
        final uri = Uri.parse('$base/$prefix/mobile/technical_specs')
            .replace(queryParameters: query);
        try {
          final response =
              await ApiHttp.get(uri, headers: headers).timeout(
            const Duration(seconds: 20),
          );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map) continue;
          final map = Map<String, dynamic>.from(decoded);
          final message = map['message']?.toString().toLowerCase();
          final success = map['success'] == true || message == 'success';
          if (!success && map['documents'] is! List) {
            lastError = map['message']?.toString() ?? 'Request failed';
            continue;
          }
          final raw = map['documents'];
          if (raw is! List) return const [];
          return [
            for (final row in raw)
              if (row is Map)
                _TechSpecDoc.fromJson(Map<String, dynamic>.from(row)),
          ].where((d) => d.url.isNotEmpty).toList();
        } catch (e) {
          lastError = e;
        }
      }
    }
    throw lastError ?? Exception('Network error');
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
          Icon(Icons.info_outline, size: 48, color: Colors.grey.shade500),
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
            'No Technical Specs documents uploaded yet for this project.\n'
            'Upload them from the web project details Technical Specs card.',
            textAlign: TextAlign.center,
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
