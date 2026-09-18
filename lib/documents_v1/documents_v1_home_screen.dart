import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../models/workflow_document.dart';
import '../services/mobile_documents.dart';
import '../services/mobile_documents_service.dart';
import '../services/workflow_document_service.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/workflow_document_viewer.dart';
import 'documents_v1_detail_screen.dart';

/// Centralized document library (Documents V1).
class DocumentsV1HomeScreen extends StatefulWidget {
  final bool clientMode;

  const DocumentsV1HomeScreen({
    super.key,
    this.clientMode = false,
  });

  @override
  State<DocumentsV1HomeScreen> createState() => _DocumentsV1HomeScreenState();
}

class _DocumentsV1HomeScreenState extends State<DocumentsV1HomeScreen>
    with _DebouncedSearchRebuild {
  bool _loading = true;
  String? _error;
  WorkflowDocumentLibrary? _library;
  String? _appliedProjectId;
  bool _usingBackend = false;
  int _loadSeq = 0;
  final _searchCtrl = TextEditingController();

  MobileDocumentsService get _docs => MobileDocumentsService.instance;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onDebouncedSearch);
    _docs.revision.addListener(_onDocumentsRevision);
    _load();
  }

  @override
  void dispose() {
    _docs.revision.removeListener(_onDocumentsRevision);
    _disposeSearchDebounce();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDocumentsRevision() {
    if (!mounted) return;
    _applyBackendSnapshotIfCurrent();
  }

  Future<String> _currentProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('project_id') ?? '').trim();
  }

  bool _applyBackendSnapshotIfCurrent({String? projectId}) {
    final expected = (projectId ?? _appliedProjectId ?? '').trim();
    final snapshot = _docs.snapshotFor(
      projectId: expected.isEmpty ? null : expected,
    );
    if (!shouldUseMobileDocumentsSnapshot(snapshot)) return false;
    if (expected.isNotEmpty && snapshot!.projectId != expected) return false;
    _setLibrary(
      snapshot!.library,
      projectId: snapshot.projectId,
      backend: true,
    );
    return true;
  }

  void _setLibrary(
    WorkflowDocumentLibrary library, {
    required String projectId,
    required bool backend,
  }) {
    if (!mounted) return;
    setState(() {
      _library = library;
      _appliedProjectId = projectId;
      _usingBackend = backend;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load({bool force = false}) async {
    final seq = ++_loadSeq;
    final projectId = await _currentProjectId();
    if (!mounted || seq != _loadSeq) return;

    if (_appliedProjectId != null &&
        projectId.isNotEmpty &&
        _appliedProjectId != projectId) {
      setState(() {
        _library = null;
        _error = null;
        _usingBackend = false;
        _appliedProjectId = projectId;
        _loading = true;
      });
    }

    final showingCurrentProject =
        _library != null &&
        (projectId.isEmpty || _appliedProjectId == projectId);
    if (!showingCurrentProject && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    await _docs.ensureLibrary(projectId: projectId, force: force);
    if (!mounted || seq != _loadSeq) return;

    if (_applyBackendSnapshotIfCurrent(projectId: projectId)) return;

    if (showingCurrentProject && _usingBackend) {
      setState(() => _loading = false);
      return;
    }

    try {
      final fallback = await WorkflowDocumentService().fetchLibrary(
        projectId: projectId.isEmpty ? null : projectId,
      );
      if (!mounted || seq != _loadSeq) return;
      _setLibrary(fallback, projectId: projectId, backend: false);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        if (_library == null) {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = filterWorkflowCategoriesBySearch(
      _library?.libraryCategories ?? const [],
      _searchCtrl.text,
    );

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: const Text(
          'Documents V1',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(force: true),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const SkeletonListLoader(cardCount: 6)
            : _error != null
                ? _ErrorPane(
                    message: _error!,
                    onRetry: () => _load(force: true),
                  )
                : (_library?.libraryCategories.isEmpty ?? true) &&
                        _searchCtrl.text.trim().isEmpty
                    ? _EmptyPane(onRetry: () => _load(force: true))
                    : RefreshIndicator(
                        color: ClientPortalDocTheme.accentBlue,
                        onRefresh: () => _load(force: true),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                          children: [
                            const ClientPortalSectionHeading(
                              label: 'Document Categories',
                            ),
                            const SizedBox(height: 10),
                            ClientPortalSearchBar(
                              controller: _searchCtrl,
                              hint: 'Search all documents…',
                            ),
                            const SizedBox(height: 14),
                            if (categories.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  _searchCtrl.text.trim().isEmpty
                                      ? 'No workflow documents yet.'
                                      : 'No documents match your search.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.getTextSecondary(context),
                                  ),
                                ),
                              )
                            else
                              ...categories.map(
                              (category) {
                                final visual = categoryVisualForCategory(category);
                                final cardCount =
                                    _library?.cardCountForLibraryCategory(category);
                                final count = cardCount ?? category.documentCount;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: ClientPortalCategoryCard(
                                    icon: visual.icon,
                                    title: category.label,
                                    subtitle: catalogCategorySubtitle(category),
                                    badgeCount: count,
                                    iconBg: visual.iconBg,
                                    iconFg: visual.iconFg,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            DocumentsV1CategoryScreen(
                                          category: category,
                                          clientMode: widget.clientMode,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}

class DocumentsV1CategoryScreen extends StatefulWidget {
  final WorkflowDocumentCategory category;
  final bool clientMode;

  const DocumentsV1CategoryScreen({
    super.key,
    required this.category,
    this.clientMode = false,
  });

  @override
  State<DocumentsV1CategoryScreen> createState() =>
      _DocumentsV1CategoryScreenState();
}

class _DocumentsV1CategoryScreenState extends State<DocumentsV1CategoryScreen>
    with _DebouncedSearchRebuild {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onDebouncedSearch);
  }

  @override
  void dispose() {
    _disposeSearchDebounce();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<WorkflowDocumentSection> get _filteredSections {
    return filterWorkflowSectionsBySearch(
      widget.category.sections,
      _searchCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections;

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          widget.category.label,
          style: const TextStyle(
            color: AppTheme.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: widget.category.sections.isEmpty
            ? Center(
                child: Text(
                  'No sections available yet.',
                  style: TextStyle(color: AppTheme.getTextSecondary(context)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  ClientPortalSearchBar(
                    controller: _searchCtrl,
                    hint: 'Search drawings…',
                  ),
                  const SizedBox(height: 16),
                  if (sections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No sections match your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    )
                  else
                    ...sections.map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ClientPortalSectionCard(
                          section: section,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentsV1ListScreen(
                                categoryLabel: widget.category.label,
                                section: section,
                                clientMode: widget.clientMode,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class DocumentsV1ListScreen extends StatefulWidget {
  final String categoryLabel;
  final WorkflowDocumentSection section;
  final bool clientMode;

  const DocumentsV1ListScreen({
    super.key,
    required this.categoryLabel,
    required this.section,
    this.clientMode = false,
  });

  @override
  State<DocumentsV1ListScreen> createState() => _DocumentsV1ListScreenState();
}

class _DocumentsV1ListScreenState extends State<DocumentsV1ListScreen>
    with _DebouncedSearchRebuild {
  final _searchCtrl = TextEditingController();
  int _filterIndex = 1;
  ClientPortalDocumentSort _sort = ClientPortalDocumentSort.newest;

  bool get _isQualityCategory =>
      widget.categoryLabel.toLowerCase().contains('quality');

  bool get _showThumbnails =>
      widget.categoryLabel.toLowerCase().contains('design') ||
      widget.categoryLabel.toLowerCase().contains('floor plan') ||
      widget.section.clientJourneyKey?.contains('design') == true ||
      widget.section.clientJourneyKey?.contains('floor_plan') == true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onDebouncedSearch);
  }

  @override
  void dispose() {
    _disposeSearchDebounce();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<WorkflowDocumentUpload> _filtered() {
    final docs = widget.section.documents;
    List<WorkflowDocumentUpload> base;
    switch (_filterIndex) {
      case 1:
        base = docs.where((doc) => doc.isLatest).toList();
        break;
      case 2:
        base = docs.where((doc) => !doc.isLatest).toList();
        break;
      default:
        base = docs;
    }

    final q = _searchCtrl.text.trim();
    final searched = q.isEmpty
        ? base
        : base.where((doc) => doc.matchesSearch(q)).toList();

    return sortWorkflowDocuments(searched, _sort);
  }

  void _openDocument(WorkflowDocumentUpload doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsV1DetailScreen(
          document: doc,
          allRevisions: widget.section.documents
              .where((item) => item.documentKey == doc.documentKey)
              .toList(),
          clientMode: widget.clientMode,
          categoryLabel: widget.categoryLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filtered();

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          widget.section.label,
          style: const TextStyle(
            color: AppTheme.navy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: const [
          IconButton(
            icon: Icon(Icons.search_rounded),
            onPressed: null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ClientPortalFilterTabs(
                selectedIndex: _filterIndex,
                onChanged: (index) => setState(() => _filterIndex = index),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: ClientPortalSearchBar(
                controller: _searchCtrl,
                hint: 'Search documents…',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ClientPortalDocumentListHeader(
                count: docs.length,
                sort: _sort,
                onSortChanged: (next) => setState(() => _sort = next),
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Text(
                        'No documents yet.',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        return ClientPortalDocumentRow(
                          document: doc,
                          showVerifiedBadge: _isQualityCategory,
                          showThumbnail: _showThumbnails,
                          onTap: () => _openDocument(doc),
                          onMenuTap: () => _showDocumentMenu(doc),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocumentMenu(WorkflowDocumentUpload doc) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View document'),
              onTap: () {
                Navigator.pop(context);
                _openDocument(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Document details'),
              onTap: () {
                Navigator.pop(context);
                _openDocument(doc);
              },
            ),
            if (!widget.clientMode && doc.hasUrl)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open externally'),
                onTap: () {
                  Navigator.pop(context);
                  openWorkflowDocument(
                    context,
                    doc,
                    clientMode: false,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class ClientJourneyDocumentsScreen extends StatefulWidget {
  final String title;
  final String journeyKey;
  final bool clientMode;
  final bool embedded;
  final String? legacyReportUrl;
  final String? legacyProofUrl;

  const ClientJourneyDocumentsScreen({
    super.key,
    required this.title,
    required this.journeyKey,
    this.clientMode = true,
    this.embedded = false,
    this.legacyReportUrl,
    this.legacyProofUrl,
  });

  @override
  State<ClientJourneyDocumentsScreen> createState() =>
      _ClientJourneyDocumentsScreenState();
}

class _ClientJourneyDocumentsScreenState
    extends State<ClientJourneyDocumentsScreen> with _DebouncedSearchRebuild {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<WorkflowDocumentSection> _sections = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onDebouncedSearch);
  }

  @override
  void dispose() {
    _disposeSearchDebounce();
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sections = library.sectionsForJourney(widget.journeyKey);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<WorkflowDocumentSection> get _filteredSections {
    return filterWorkflowSectionsBySearch(_sections, _searchCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final hasLegacy = (widget.legacyReportUrl?.trim().isNotEmpty == true) ||
        (widget.legacyProofUrl?.trim().isNotEmpty == true);
    final sections = _filteredSections;

    Widget content;
    if (_loading) {
      content = const SkeletonListLoader(cardCount: 4);
    } else if (_error != null) {
      content = _ErrorPane(message: _error!, onRetry: _load);
    } else if (_sections.isEmpty && !hasLegacy) {
      content = _EmptyPane(onRetry: _load);
    } else {
      content = RefreshIndicator(
        color: ClientPortalDocTheme.accentBlue,
        onRefresh: _load,
        child: widget.clientMode
            ? ClientPortalJourneySectionsBody(
                sections: _sections,
                searchController: _searchCtrl,
                searchHint: widget.embedded
                    ? 'Search reports…'
                    : 'Search ${widget.title.toLowerCase()}…',
                categoryLabel: widget.title,
                    emptyMessage: hasLegacy && _sections.isEmpty
                        ? 'No workflow reports yet. Legacy links may be available above.'
                        : 'No documents yet.',
                leadingChildren: [
                  if (widget.embedded) ...[
                    ClientPortalScreenHeader(
                      title: widget.title,
                      subtitle: 'Reports shared by your team',
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (hasLegacy) ...[
                    if (widget.legacyReportUrl?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _LegacyDocTile(
                          title: 'Inspection report',
                          url: widget.legacyReportUrl!,
                          icon: Icons.assignment_outlined,
                        ),
                      ),
                    if (widget.legacyProofUrl?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LegacyDocTile(
                          title: 'Site cleaned proof',
                          url: widget.legacyProofUrl!,
                          icon: Icons.cleaning_services_outlined,
                        ),
                      ),
                  ],
                ],
                onSectionTap: (section) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DocumentsV1ListScreen(
                      categoryLabel: widget.title,
                      section: section,
                      clientMode: widget.clientMode,
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  if (widget.clientMode && widget.embedded) ...[
                    ClientPortalScreenHeader(
                      title: widget.title,
                      subtitle: 'Reports shared by your team',
                    ),
                    const SizedBox(height: 12),
                  ],
                  ClientPortalSearchBar(
                    controller: _searchCtrl,
                    hint: 'Search drawings…',
                  ),
                  const SizedBox(height: 16),
                  if (hasLegacy) ...[
                    if (widget.legacyReportUrl?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _LegacyDocTile(
                          title: 'Inspection report',
                          url: widget.legacyReportUrl!,
                          icon: Icons.assignment_outlined,
                        ),
                      ),
                    if (widget.legacyProofUrl?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LegacyDocTile(
                          title: 'Site cleaned proof',
                          url: widget.legacyProofUrl!,
                          icon: Icons.cleaning_services_outlined,
                        ),
                      ),
                  ],
                  if (sections.isEmpty && hasLegacy)
                    const SizedBox.shrink()
                  else if (sections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No sections match your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    )
                  else
                    ...sections.map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ClientPortalSectionCard(
                          section: section,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentsV1ListScreen(
                                categoryLabel: widget.title,
                                section: section,
                                clientMode: widget.clientMode,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      );
    }

    if (widget.embedded) {
      return SafeArea(child: content);
    }

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
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
      body: SafeArea(child: content),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPane({required this.message, required this.onRetry});

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

class _EmptyPane extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyPane({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 56, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 16),
            Text(
              'No workflow documents yet.',
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}

class _LegacyDocTile extends StatelessWidget {
  final String title;
  final String url;
  final IconData icon;

  const _LegacyDocTile({
    required this.title,
    required this.url,
    required this.icon,
  });

  WorkflowDocumentUpload get _document => WorkflowDocumentUpload(
        id: url,
        documentKey: title,
        name: title,
        url: url,
        isLatest: true,
      );

  @override
  Widget build(BuildContext context) {
    final visual = categoryVisualFor(label: title);
    return ClientPortalCategoryCard(
      icon: icon,
      title: title,
      subtitle: 'Tap to view',
      badgeCount: 0,
      iconBg: visual.iconBg,
      iconFg: visual.iconFg,
      onTap: () => openWorkflowDocument(
        context,
        _document,
        clientMode: true,
      ),
    );
  }
}

mixin _DebouncedSearchRebuild<T extends StatefulWidget> on State<T> {
  Timer? _searchDebounce;
  void _onDebouncedSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() {});
    });
  }

  void _disposeSearchDebounce() {
    _searchDebounce?.cancel();
  }
}
