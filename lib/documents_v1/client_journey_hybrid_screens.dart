import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../models/workflow_document.dart';
import '../services/client_portal_service.dart';
import '../services/workflow_document_service.dart';
import '../widgets/skeleton_loader.dart';
import 'documents_v1_home_screen.dart';

/// Floor Plan & Elevation — merges workflow library, SOP cards, and portal API.
class ClientFloorPlanElevationScreen extends StatefulWidget {
  const ClientFloorPlanElevationScreen({super.key});

  @override
  State<ClientFloorPlanElevationScreen> createState() =>
      _ClientFloorPlanElevationScreenState();
}

class _ClientFloorPlanElevationScreenState
    extends State<ClientFloorPlanElevationScreen> {
  final _portal = ClientPortalService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<WorkflowDocumentSection> _sections = const [];
  Map<String, dynamic> _portalData = const {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await WorkflowDocumentService().fetchLibrary();
      Map<String, dynamic> portalData = const {};
      try {
        final result = await _portal.getFloorPlanElevation();
        portalData = _portal.sectionOf(result);
      } catch (_) {}

      final sections = _mergeFloorPlanSections(library, portalData);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sections = sections;
        _portalData = portalData;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<WorkflowDocumentSection> _mergeFloorPlanSections(
    WorkflowDocumentLibrary library,
    Map<String, dynamic> portalData,
  ) {
    final byId = <String, WorkflowDocumentSection>{};

    for (final section
        in library.sectionsForJourney(ClientJourneyKeys.floorPlan)) {
      byId[section.id] = section;
    }

    void addPortalDoc({
      required String sectionId,
      required String sectionLabel,
      required String? url,
      String? name,
    }) {
      if (url == null || url.trim().isEmpty) return;
      final resolved = _portal.serveUrl(url);
      final upload = WorkflowDocumentUpload(
        id: 'portal-$sectionId-$resolved',
        documentKey: sectionId,
        name: name ?? sectionLabel,
        url: resolved,
        isLatest: true,
        status: 'latest',
        sectionId: sectionId,
        sectionLabel: sectionLabel,
        categoryId: 'floor_plan_elevation',
        categoryLabel: 'Floor Plan & Elevation',
        clientJourneyKey: ClientJourneyKeys.floorPlan,
        libraryGroupKey: 'floor_plan_elevation',
      );
      final existing = byId[sectionId];
      if (existing != null) {
        final urls = existing.documents.map((d) => d.url).toSet();
        if (urls.contains(resolved)) return;
        byId[sectionId] = existing.copyWithDocuments([
          ...existing.documents,
          upload,
        ]);
      } else {
        byId[sectionId] = WorkflowDocumentSection(
          id: sectionId,
          label: sectionLabel,
          categoryId: 'floor_plan_elevation',
          categoryLabel: 'Floor Plan & Elevation',
          clientJourneyKey: ClientJourneyKeys.floorPlan,
          libraryGroupKey: 'floor_plan_elevation',
          documents: [upload],
        );
      }
    }

    addPortalDoc(
      sectionId: 'dsec_floor_plan',
      sectionLabel: 'Floor Plan',
      url: portalData['floor_plan_url']?.toString(),
    );
    addPortalDoc(
      sectionId: 'dsec_elevation',
      sectionLabel: 'Elevation',
      url: portalData['elevation_url']?.toString(),
    );
    addPortalDoc(
      sectionId: 'dsec_framing_drawing',
      sectionLabel: 'Framing Drawing',
      url: portalData['framing_drawing_url']?.toString(),
    );

    final out = byId.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final status = _portalData['final_status']?.toString() ??
        (_portalData['finalize_elevation_completed'] == true
            ? 'finalized'
            : null);

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: const Text(
          'Floor Plan & Elevation',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const SkeletonListLoader(cardCount: 4)
            : _error != null
                ? _HybridErrorPane(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    color: AppTheme.navy,
                    onRefresh: _load,
                    child: ClientPortalJourneySectionsBody(
                      sections: _sections,
                      searchController: _searchCtrl,
                      searchHint: 'Search floor plans & elevations…',
                      categoryLabel: 'Floor Plan & Elevation',
                      emptyMessage:
                          'No floor plan or elevation documents yet.',
                      statusMessage: status == 'finalized'
                          ? 'Elevation finalized. You can now view all documents.'
                          : status != null
                              ? 'Drawings in progress. New documents will appear here.'
                              : null,
                      statusSuccess: status == 'finalized',
                      onSectionTap: (section) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentsV1ListScreen(
                            categoryLabel: 'Floor Plan & Elevation',
                            section: section,
                            clientMode: true,
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// Design Elements — workflow uploads plus portal design_element API docs.
class ClientDesignElementsScreen extends StatefulWidget {
  const ClientDesignElementsScreen({super.key});

  @override
  State<ClientDesignElementsScreen> createState() =>
      _ClientDesignElementsScreenState();
}

class _ClientDesignElementsScreenState
    extends State<ClientDesignElementsScreen> {
  final _portal = ClientPortalService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<WorkflowDocumentSection> _sections = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await WorkflowDocumentService().fetchLibrary();
      Map<String, dynamic> portalData = const {};
      try {
        final result = await _portal.getDesignElement();
        portalData = _portal.sectionOf(result);
      } catch (_) {}

      final sections = _mergeDesignSections(library, portalData);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sections = sections;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<WorkflowDocumentSection> _mergeDesignSections(
    WorkflowDocumentLibrary library,
    Map<String, dynamic> portalData,
  ) {
    final byId = <String, WorkflowDocumentSection>{};

    for (final section in library.sectionsForJourney(ClientJourneyKeys.design)) {
      byId[section.id] = section;
    }

    void addPortalGroup({
      required String sectionId,
      required String sectionLabel,
      required dynamic rawList,
    }) {
      if (rawList is! List || rawList.isEmpty) return;
      final uploads = <WorkflowDocumentUpload>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final doc = Map<String, dynamic>.from(raw);
        final url = doc['view_url']?.toString() ??
            doc['download_url']?.toString() ??
            doc['url']?.toString() ??
            doc['file_url']?.toString();
        if (url == null || url.trim().isEmpty) continue;
        final resolved = _portal.serveUrl(url);
        final name = doc['name']?.toString() ??
            doc['title']?.toString() ??
            doc['label']?.toString() ??
            doc['document_label']?.toString() ??
            doc['filename']?.toString() ??
            doc['file_name']?.toString() ??
            sectionLabel;
        uploads.add(
          WorkflowDocumentUpload(
            id: 'portal-$sectionId-$resolved',
            documentKey: 'portal_${_slug(name)}',
            name: name,
            url: resolved,
            contentType: doc['content_type']?.toString() ??
                doc['mime_type']?.toString(),
            fileSize: _formatPortalFileSize(
              doc['file_size'] ?? doc['size'],
            ),
            uploadedAt: doc['uploaded_at_display']?.toString() ??
                doc['uploaded_at']?.toString() ??
                doc['created_at']?.toString(),
            isLatest: true,
            status: 'latest',
            sectionId: sectionId,
            sectionLabel: sectionLabel,
            categoryId: 'design_elements',
            categoryLabel: 'Design Elements',
            clientJourneyKey: ClientJourneyKeys.design,
            libraryGroupKey: 'design',
            raw: doc,
          ),
        );
      }
      if (uploads.isEmpty) return;

      final existing = byId[sectionId];
      if (existing != null) {
        final urls = existing.documents.map((d) => d.url).toSet();
        final merged = [
          ...existing.documents,
          ...uploads.where((u) => !urls.contains(u.url)),
        ];
        byId[sectionId] = existing.copyWithDocuments(merged);
      } else {
        byId[sectionId] = WorkflowDocumentSection(
          id: sectionId,
          label: sectionLabel,
          categoryId: 'design_elements',
          categoryLabel: 'Design Elements',
          clientJourneyKey: ClientJourneyKeys.design,
          libraryGroupKey: 'design',
          documents: uploads,
        );
      }
    }

    addPortalGroup(
      sectionId: 'dsec_vastu_design',
      sectionLabel: 'Vastu Design',
      rawList: portalData['vastu_design_docs'],
    );
    addPortalGroup(
      sectionId: 'dsec_elevation_references',
      sectionLabel: 'Elevation References',
      rawList: portalData['elevation_reference_design_docs'],
    );
    addPortalGroup(
      sectionId: 'dsec_bylaws',
      sectionLabel: 'Bylaws',
      rawList: portalData['bylaws_design_docs'],
    );

    return byId.values.toList()..sort((a, b) => a.label.compareTo(b.label));
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String? _formatPortalFileSize(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final bytes = value.toDouble();
      if (bytes >= 1048576) {
        return '${(bytes / 1048576).toStringAsFixed(2)} MB';
      }
      if (bytes >= 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      }
      return '${bytes.toStringAsFixed(0)} B';
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: const Text(
          'Design Elements',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const SkeletonListLoader(cardCount: 4)
            : _error != null
                ? _HybridErrorPane(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    color: AppTheme.navy,
                    onRefresh: _load,
                    child: ClientPortalJourneySectionsBody(
                      sections: _sections,
                      searchController: _searchCtrl,
                      searchHint: 'Search design documents…',
                      categoryLabel: 'Design Elements',
                      emptyMessage: 'No design documents yet.',
                      onSectionTap: (section) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentsV1ListScreen(
                            categoryLabel: 'Design Elements',
                            section: section,
                            clientMode: true,
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _HybridErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _HybridErrorPane({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 56, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
