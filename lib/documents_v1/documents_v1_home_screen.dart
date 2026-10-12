import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../client_portal/client_portal_hub.dart';
import '../models/workflow_document.dart';
import '../services/document_file_download.dart';
import '../services/document_role_access.dart';
import '../services/mobile_documents.dart';
import '../services/mobile_documents_service.dart';
import '../services/workflow_document_service.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/workflow_document_viewer.dart';
import 'documents_v1_detail_screen.dart';
import '../user_facing_error.dart';

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
  String? _viewerRole;
  final _searchCtrl = TextEditingController();

  MobileDocumentsService get _docs => MobileDocumentsService.instance;

  @override
  void initState() {
    super.initState();
    final snap = _docs.snapshotFor();
    if (shouldUseMobileDocumentsSnapshot(snap)) {
      _library = snap!.library;
      _appliedProjectId = snap.projectId;
      _usingBackend = true;
      _loading = false;
      _viewerRole = snap.role;
    }
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
    _viewerRole = prefs.getString('role');
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
    final memoryReady = !force &&
        shouldUseMobileDocumentsSnapshot(
          _docs.snapshotFor(
            projectId: projectId.isEmpty ? null : projectId,
          ),
        );
    if (!showingCurrentProject && mounted && !memoryReady) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (!force) {
      final cached = await _docs.showCachedLibrary(projectId: projectId);
      if (!mounted || seq != _loadSeq) return;
      if (cached && _applyBackendSnapshotIfCurrent(projectId: projectId)) {
        unawaited(_docs.ensureLibrary(projectId: projectId));
        return;
      }
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
          _error = userFacingError(e);
        }
      });
    }
  }

  List<WorkflowDocumentCategory> get _visibleCategories {
    final filtered = filterDocumentCategoriesForRole(
      _library?.libraryCategories ?? const [],
      _viewerRole,
      clientMode: widget.clientMode,
    );
    return filterWorkflowCategoriesBySearch(filtered, _searchCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visibleCategories;

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: Text(
          'Documents V1',
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
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
                          physics: const AlwaysScrollableScrollPhysics(),
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
                                final count =
                                    workflowDocCountForCategory(category);
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
                                          viewerRole: _viewerRole,
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

/// Opens a section's file page. A single file opens directly. Several
/// uploads, even of the same document, stay in the list.
void openDocumentsV1Section(
  BuildContext context, {
  required String categoryLabel,
  required WorkflowDocumentSection section,
  bool clientMode = false,
  String? viewerRole,
}) {
  final folder =
      '$categoryLabel ${section.categoryLabel} ${section.label} ${section.clientJourneyKey ?? ''} ${section.libraryGroupKey ?? ''}'
          .toLowerCase();
  final architecturalFolder =
      folder.contains('architectural') || folder.contains('architecture');
  final hideArea = !architecturalFolder &&
      (forMeDocRoleBucket(viewerRole) == ForMeDocRoleBucket.client ||
          usesClientDocumentCatalog(viewerRole) ||
          (clientMode &&
              forMeDocRoleBucket(viewerRole) == ForMeDocRoleBucket.other));
  var docs = sectionWithMobileVisibleDocuments(section).documents;
  if (hideArea) {
    docs = docs.where((doc) => !doc.isAreaStatement).toList();
  }
  docs = docs
      .where(
        (doc) => documentAccessForUpload(
          catalogVisibilityRole(viewerRole),
          doc,
        ).view,
      )
      .toList();

  // Soil / Booking / Plumbing: always open the file list so every upload
  // is visible. Other sections still open a single file directly.
  final forceList = isMultiFileDocumentSection(section) || docs.length != 1;
  if (forceList) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsV1ListScreen(
          categoryLabel: categoryLabel,
          section: section.copyWithDocuments(docs),
          clientMode: clientMode,
          viewerRole: viewerRole,
        ),
      ),
    );
    return;
  }

  final doc = docs.first;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DocumentsV1DetailScreen(
        document: doc,
        clientMode: clientMode,
        categoryLabel: categoryLabel,
        viewerRole: viewerRole,
      ),
    ),
  );
}

/// Force a fresh document catalog for the open project.
Future<WorkflowDocumentLibrary> reloadWorkflowDocumentLibrary() async {
  final prefs = await SharedPreferences.getInstance();
  final projectId = (prefs.getString('project_id') ?? '').trim();
  final docs = MobileDocumentsService.instance;
  await docs.ensureLibrary(
    projectId: projectId.isEmpty ? null : projectId,
    force: true,
  );
  final snapshot = docs.snapshotFor(
    projectId: projectId.isEmpty ? null : projectId,
  );
  if (shouldUseMobileDocumentsSnapshot(snapshot)) {
    return snapshot!.library;
  }
  return WorkflowDocumentService().fetchLibrary(
    projectId: projectId.isEmpty ? null : projectId,
  );
}

bool _sameDocumentKey(String? a, String? b) {
  final left = (a ?? '').trim().toLowerCase();
  final right = (b ?? '').trim().toLowerCase();
  return left.isNotEmpty && left == right;
}

WorkflowDocumentCategory? findReloadedCategory(
  WorkflowDocumentLibrary library,
  WorkflowDocumentCategory current,
) {
  final all = <WorkflowDocumentCategory>[
    ...library.libraryCategories,
    ...library.clientJourneyCategories,
  ];
  for (final category in all) {
    if (_sameDocumentKey(category.id, current.id) ||
        _sameDocumentKey(category.libraryGroupKey, current.libraryGroupKey) ||
        _sameDocumentKey(category.clientJourneyKey, current.clientJourneyKey)) {
      return category;
    }
  }
  final label = current.label.trim().toLowerCase();
  for (final category in all) {
    if (category.label.trim().toLowerCase() == label) return category;
  }
  return null;
}

WorkflowDocumentSection? findReloadedSection(
  WorkflowDocumentLibrary library,
  WorkflowDocumentSection current,
) {
  final categories = <WorkflowDocumentCategory>[
    ...library.libraryCategories,
    ...library.clientJourneyCategories,
  ];
  for (final category in categories) {
    for (final section in category.sections) {
      if (_sameDocumentKey(section.id, current.id)) return section;
    }
  }
  final label = current.label.trim().toLowerCase();
  for (final category in categories) {
    final sameCategory = _sameDocumentKey(category.id, current.categoryId) ||
        category.label.trim().toLowerCase() ==
            current.categoryLabel.trim().toLowerCase();
    if (!sameCategory && current.categoryId.trim().isNotEmpty) continue;
    for (final section in category.sections) {
      if (section.label.trim().toLowerCase() == label) return section;
    }
  }
  return null;
}

class DocumentsV1CategoryScreen extends StatefulWidget {
  final WorkflowDocumentCategory category;
  final bool clientMode;
  final String? viewerRole;

  const DocumentsV1CategoryScreen({
    super.key,
    required this.category,
    this.clientMode = false,
    this.viewerRole,
  });

  @override
  State<DocumentsV1CategoryScreen> createState() =>
      _DocumentsV1CategoryScreenState();
}

class _DocumentsV1CategoryScreenState extends State<DocumentsV1CategoryScreen>
    with _DebouncedSearchRebuild {
  final _searchCtrl = TextEditingController();
  String? _viewerRole;
  WorkflowDocumentCategory? _reloaded;

  @override
  void initState() {
    super.initState();
    _viewerRole = widget.viewerRole;
    _searchCtrl.addListener(_onDebouncedSearch);
    if (_viewerRole == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        setState(() => _viewerRole = prefs.getString('role'));
      });
    }
  }

  @override
  void dispose() {
    _disposeSearchDebounce();
    _searchCtrl.dispose();
    super.dispose();
  }

  WorkflowDocumentCategory get _sourceCategory => _reloaded ?? widget.category;

  WorkflowDocumentCategory get _category {
    final filtered = filterDocumentCategoriesForRole(
      [_sourceCategory],
      _viewerRole,
      clientMode: widget.clientMode,
    );
    return filtered.isEmpty
        ? _sourceCategory.copyWithSections(const [])
        : filtered.first;
  }

  Future<void> _reload() async {
    try {
      final library = await reloadWorkflowDocumentLibrary();
      final next = findReloadedCategory(library, _sourceCategory);
      if (!mounted) return;
      setState(() {
        if (next != null) _reloaded = next;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  bool get _architecturalGrouped =>
      isArchitecturalDocumentCategory(_category);

  bool get _checklistCategory => usesChecklistTypeSections(_category);

  bool get _receiptsAndAgreements =>
      isReceiptsAndAgreementsCategory(_category);

  bool get _multiFileCategory => isMultiFileDocumentCategory(_category);

  bool get _siteInspectionReport => isSiteDocumentCategory(_category);

  /// Architectural checklist always includes Final Area statement (office
  /// list of 13). Other categories still strip Area Statement for clients.
  bool get _hideArchitecturalAreaStatement => false;

  WorkflowDocumentUpload? _singleOpenableDocument(
    WorkflowDocumentSection section,
  ) {
    final docs = sectionWithMobileVisibleDocuments(section).documents.where((doc) {
      if (doc.isAreaStatement && !_architecturalGrouped) return false;
      return documentAccessForUpload(
        catalogVisibilityRole(_viewerRole),
        doc,
      ).view;
    }).toList();
    if (docs.length != 1) return null;
    return docs.first;
  }

  /// Checklist folders (Architectural 13, Structural 3, …) or real API sections.
  List<WorkflowDocumentSection> get _substantiveSections {
    final checklist = buildChecklistTypeSectionsForCategory(
      _category,
      hideAreaStatement: _hideArchitecturalAreaStatement,
    );
    if (checklist != null) return checklist;
    return substantiveDocumentSections(_category)
        .map(sectionWithMobileVisibleDocuments)
        .toList();
  }

  List<WorkflowDocumentSection> get _filteredSections {
    if (_architecturalGrouped) {
      return clientPortalArchitecturalSections(
        _category,
        _searchCtrl.text,
        hideAreaStatement: _hideArchitecturalAreaStatement,
      );
    }
    return filterWorkflowSectionsBySearch(
      _substantiveSections,
      _searchCtrl.text,
    );
  }

  /// Checklist categories always show type folders. Otherwise skip a redundant
  /// single mirrored section.
  bool get _skipSectionList {
    if (_checklistCategory) return false;
    if (_receiptsAndAgreements ||
        _multiFileCategory ||
        _siteInspectionReport) {
      return true;
    }
    return _substantiveSections.length <= 1;
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    if (_skipSectionList) {
      final section = _substantiveSections.length == 1
          ? _substantiveSections.first
          : buildFlatCategoryDocumentsSection(category);
      // Multi-file folders always list files — several PDFs can share one key.
      final direct = _multiFileCategory
          ? null
          : _singleOpenableDocument(section);
      if (direct != null) {
        return DocumentsV1DetailScreen(
          document: direct,
          clientMode: widget.clientMode,
          categoryLabel: category.label,
          viewerRole: _viewerRole,
        );
      }
      return DocumentsV1ListScreen(
        categoryLabel: category.label,
        section: section,
        clientMode: widget.clientMode,
        viewerRole: _viewerRole,
      );
    }

    final sections = _filteredSections;

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: Text(
          category.label,
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: ClientPortalDocTheme.accentBlue,
          onRefresh: _reload,
          child: _substantiveSections.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.45,
                    child: Center(
                      child: Text(
                        'No sections available yet.',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  ClientPortalSearchBar(
                    controller: _searchCtrl,
                    hint: _checklistCategory
                        ? 'Search folders…'
                        : 'Search drawings…',
                  ),
                  const SizedBox(height: 16),
                  if (sections.isEmpty ||
                      (_architecturalGrouped &&
                          sections.every((s) => s.documents.isEmpty) &&
                          _searchCtrl.text.trim().isNotEmpty))
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
                          onTap: () => openDocumentsV1Section(
                            context,
                            categoryLabel: category.label,
                            section: section,
                            clientMode: widget.clientMode,
                            viewerRole: _viewerRole,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
        ),
      ),
    );
  }
}

class DocumentsV1ListScreen extends StatefulWidget {
  final String categoryLabel;
  final WorkflowDocumentSection section;
  final bool clientMode;
  final String? viewerRole;

  const DocumentsV1ListScreen({
    super.key,
    required this.categoryLabel,
    required this.section,
    this.clientMode = false,
    this.viewerRole,
  });

  @override
  State<DocumentsV1ListScreen> createState() => _DocumentsV1ListScreenState();
}

class _DocumentsV1ListScreenState extends State<DocumentsV1ListScreen>
    with _DebouncedSearchRebuild {
  final _searchCtrl = TextEditingController();
  ClientPortalDocumentSort _sort = ClientPortalDocumentSort.newest;
  String? _viewerRole;
  bool _mutating = false;
  WorkflowDocumentSection? _reloadedSection;

  WorkflowDocumentSection get _section => _reloadedSection ?? widget.section;

  bool get _isQualityCategory =>
      widget.categoryLabel.toLowerCase().contains('quality');

  bool get _showThumbnails =>
      widget.categoryLabel.toLowerCase().contains('design') ||
      widget.categoryLabel.toLowerCase().contains('floor plan') ||
      _section.clientJourneyKey?.contains('design') == true ||
      _section.clientJourneyKey?.contains('floor_plan') == true;

  bool get _isArchitecturalFolder {
    final blob =
        '${widget.categoryLabel} ${_section.categoryLabel} ${_section.label} ${_section.clientJourneyKey ?? ''} ${_section.libraryGroupKey ?? ''}'
            .toLowerCase();
    return blob.contains('architectural') || blob.contains('architecture');
  }

  bool get _hideAreaStatement =>
      !_isArchitecturalFolder &&
      (forMeDocRoleBucket(_viewerRole) == ForMeDocRoleBucket.client ||
          usesClientDocumentCatalog(_viewerRole) ||
          (widget.clientMode &&
              forMeDocRoleBucket(_viewerRole) == ForMeDocRoleBucket.other));

  @override
  void initState() {
    super.initState();
    _viewerRole = widget.viewerRole;
    _searchCtrl.addListener(_onDebouncedSearch);
    if (_viewerRole == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        setState(() => _viewerRole = prefs.getString('role'));
        _prefetchTop();
      });
    } else {
      _prefetchTop();
    }
  }

  @override
  void didUpdateWidget(covariant DocumentsV1ListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _reloadedSection = null;
    }
  }

  Future<void> _reload() async {
    try {
      final library = await reloadWorkflowDocumentLibrary();
      final next = findReloadedSection(library, _section);
      if (!mounted) return;
      setState(() {
        if (next != null) _reloadedSection = next;
      });
      _prefetchTop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  void _prefetchTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final docs = _filtered().where((doc) => doc.hasUrl).take(2);
      for (final doc in docs) {
        warmWorkflowDocument(doc);
      }
    });
  }

  @override
  void dispose() {
    _disposeSearchDebounce();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<WorkflowDocumentUpload> _filtered() {
    var docs = sectionWithMobileVisibleDocuments(_section).documents;
    if (_hideAreaStatement) {
      docs = docs.where((doc) => !doc.isAreaStatement).toList();
    }
    // Null role = prefs still loading. Do not treat as "other" (no access)
    // or every row disappears / looks empty until reload.
    final role = _viewerRole?.trim();
    if (role != null && role.isNotEmpty) {
      docs = docs
          .where(
            (doc) => documentAccessForUpload(
              catalogVisibilityRole(role),
              doc,
            ).view,
          )
          .toList();
    }

    List<WorkflowDocumentUpload> base = docs;

    final q = _searchCtrl.text.trim();
    final searched = q.isEmpty
        ? base
        : base.where((doc) => doc.matchesSearch(q)).toList();

    return sortWorkflowDocuments(searched, _sort);
  }

  void _openDocument(WorkflowDocumentUpload doc) {
    openWorkflowDocument(
      context,
      doc,
      clientMode: widget.clientMode,
    );
  }

  void _openDetails(WorkflowDocumentUpload doc) {
    warmWorkflowDocument(doc);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsV1DetailScreen(
          document: doc,
          clientMode: widget.clientMode,
          categoryLabel: widget.categoryLabel,
          viewerRole: _viewerRole,
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
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: Text(
          _section.label,
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _mutating ? null : _reload,
          ),
          if (documentAccessForRef(
            role: _viewerRole,
            categoryId: _section.categoryId,
            categoryLabel: widget.categoryLabel,
            sectionId: _section.id,
            sectionLabel: _section.label,
            journeyKey: _section.clientJourneyKey,
            libraryGroupKey: _section.libraryGroupKey,
          ).upload)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Upload',
              onPressed: _mutating
                  ? null
                  : () => _mutateDocument(
                        action: 'upload',
                        existing: null,
                      ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: ClientPortalDocTheme.accentBlue,
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: ClientPortalSearchBar(
                    controller: _searchCtrl,
                    hint: 'Search documents…',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: ClientPortalDocumentListHeader(
                    count: docs.length,
                    sort: _sort,
                    onSortChanged: (next) => setState(() => _sort = next),
                  ),
                ),
              ),
              if (docs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No documents yet.',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index.isOdd) return const SizedBox(height: 8);
                        final doc = docs[index ~/ 2];
                        return ClientPortalDocumentRow(
                          document: doc,
                          showVerifiedBadge: _isQualityCategory,
                          showThumbnail: _showThumbnails,
                          onPressStart: () => warmWorkflowDocument(doc),
                          onTap: () => _openDocument(doc),
                          onMenuTap: () => _showDocumentMenu(doc),
                        );
                      },
                      childCount: docs.isEmpty ? 0 : docs.length * 2 - 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDocumentMenu(WorkflowDocumentUpload doc) {
    final hostContext = context;
    final rights = documentAccessForUpload(_viewerRole, doc);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.darkBackgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rights.view)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('View document'),
                onTap: () {
                  Navigator.pop(context);
                  _openDocument(doc);
                },
              ),
            if (rights.view)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Document details'),
                onTap: () {
                  Navigator.pop(context);
                  _openDetails(doc);
                },
              ),
            if (doc.hasUrl && doc.canDownload)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  downloadWorkflowDocument(hostContext, doc);
                },
              ),
            if (rights.edit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit / Replace'),
                onTap: () {
                  Navigator.pop(context);
                  _mutateDocument(action: 'edit', existing: doc);
                },
              ),
            if (rights.upload)
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Upload'),
                onTap: () {
                  Navigator.pop(context);
                  _mutateDocument(action: 'upload', existing: doc);
                },
              ),
            if (rights.delete)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red[400]),
                title: Text('Delete', style: TextStyle(color: Colors.red[400])),
                onTap: () {
                  Navigator.pop(context);
                  _mutateDocument(action: 'delete', existing: doc);
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

  Future<void> _mutateDocument({
    required String action,
    WorkflowDocumentUpload? existing,
  }) async {
    if (_mutating) return;
    final messenger = ScaffoldMessenger.of(context);

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete document?'),
          content: Text(
            existing == null
                ? 'Remove this document?'
                : 'Remove "${existing.displayTitle}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    PlatformFile? picked;
    if (action == 'edit' || action == 'upload') {
      final result = await FilePicker.platform.pickFiles(
        withData: kIsWeb,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      picked = result.files.first;
      if (!kIsWeb && (picked.path == null || picked.path!.isEmpty)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not read the selected file.')),
        );
        return;
      }
    }

    setState(() => _mutating = true);
    try {
      await MobileDocumentsService.instance.mutateDocument(
        action: action,
        projectId: (await SharedPreferences.getInstance()).getString('project_id'),
        document: existing,
        section: _section,
        categoryLabel: widget.categoryLabel,
        filePath: kIsWeb ? null : picked?.path,
        fileBytes: picked?.bytes,
        fileName: picked?.name,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            action == 'delete'
                ? 'Document deleted'
                : action == 'edit'
                    ? 'Document updated'
                    : 'Document uploaded',
          ),
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(e),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
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
        final sections = library.sectionsForJourney(widget.journeyKey);
        _sections = widget.clientMode
            ? sections
                .map(
                  (section) => section.copyWithDocuments(
                    section.documents
                        .where((doc) => !doc.isAreaStatement)
                        .toList(),
                  ),
                )
                .where((section) => section.documents.isNotEmpty)
                .toList()
            : sections;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError(e);
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
                onSectionTap: (section) => openDocumentsV1Section(
                  context,
                  categoryLabel: widget.title,
                  section: section,
                  clientMode: widget.clientMode,
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                          onTap: () => openDocumentsV1Section(
                            context,
                            categoryLabel: widget.title,
                            section: section,
                            clientMode: widget.clientMode,
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
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
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
