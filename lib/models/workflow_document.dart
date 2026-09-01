/// Typed models for workflow dashboard documents.
/// Parsed from `workflow_dashboard_sections` and `workflow_dashboard_uploads`
/// on `sales_sop_details` — backend is the source of truth.

enum WorkflowDocumentPresentation {
  clientJourney,
  library,
}

class WorkflowDocumentUpload {
  final String id;
  final String documentKey;
  final String name;
  final String? url;
  final String? contentType;
  final String? fileSize;
  final int? revision;
  final String? revisionLabel;
  final bool isLatest;
  final String? uploadedAt;
  final String? uploadedBy;
  final String? taskName;
  final String? taskId;
  final String? status;
  final String sectionId;
  final String sectionLabel;
  final String categoryId;
  final String categoryLabel;
  final String? clientJourneyKey;
  final String? libraryGroupKey;
  final List<Map<String, dynamic>> activity;
  final Map<String, dynamic> raw;

  const WorkflowDocumentUpload({
    required this.id,
    required this.documentKey,
    required this.name,
    this.url,
    this.contentType,
    this.fileSize,
    this.revision,
    this.revisionLabel,
    this.isLatest = false,
    this.uploadedAt,
    this.uploadedBy,
    this.taskName,
    this.taskId,
    this.status,
    this.sectionId = '',
    this.sectionLabel = '',
    this.categoryId = '',
    this.categoryLabel = '',
    this.clientJourneyKey,
    this.libraryGroupKey,
    this.activity = const [],
    this.raw = const {},
  });

  bool get hasUrl => url != null && url!.trim().isNotEmpty;

  bool get isImage {
    final mime = (contentType ?? '').toLowerCase();
    if (mime.startsWith('image/')) return true;
    final lower = '${url ?? ''} $name'.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  bool get isPdf {
    final mime = (contentType ?? '').toLowerCase();
    if (mime == 'application/pdf') return true;
    final lower = '${url ?? ''} $name'.toLowerCase().split('?').first;
    return lower.endsWith('.pdf');
  }

  String get displayRevision =>
      revisionLabel ??
      (revision != null ? 'Rev ${revision.toString().padLeft(2, '0')}' : '');

  /// Primary list title — prefer task name when the backend provides it.
  String get displayTitle {
    final task = taskName?.trim();
    if (task != null && task.isNotEmpty) return task;
    return name;
  }

  /// Secondary line under the title in document rows.
  String? get displaySubtitle {
    final task = taskName?.trim();
    final docName = name.trim();
    if (task != null && task.isNotEmpty && docName.isNotEmpty && docName != task) {
      return docName;
    }
    final section = sectionLabel.trim();
    if (section.isNotEmpty &&
        section != displayTitle &&
        section.toLowerCase() != displayTitle.toLowerCase()) {
      return section;
    }
    return null;
  }

  /// Status label from backend when available; otherwise derived from isLatest.
  String get displayStatus {
    final rawStatus = status?.trim().toLowerCase();
    if (rawStatus != null && rawStatus.isNotEmpty) {
      if (rawStatus == 'latest') return 'Latest';
      if (rawStatus == 'superseded') return 'Superseded';
      if (rawStatus == 'verified') return 'Verified';
      return status!.trim();
    }
    return isLatest ? 'Latest' : 'Superseded';
  }

  bool get isVerifiedStatus =>
      displayStatus.toLowerCase() == 'verified';

  bool matchesSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    bool hit(String? value) =>
        value != null && value.trim().toLowerCase().contains(q);
    return hit(name) ||
        hit(raw['filename']?.toString()) ||
        hit(raw['file_name']?.toString()) ||
        hit(taskName) ||
        hit(sectionLabel) ||
        hit(categoryLabel);
  }
}

class WorkflowDocumentSection {
  final String id;
  final String label;
  final String? iconName;
  final String categoryId;
  final String categoryLabel;
  final String? clientJourneyKey;
  final String? libraryGroupKey;
  final List<WorkflowDocumentUpload> documents;

  const WorkflowDocumentSection({
    required this.id,
    required this.label,
    this.iconName,
    this.categoryId = '',
    this.categoryLabel = '',
    this.clientJourneyKey,
    this.libraryGroupKey,
    this.documents = const [],
  });

  List<WorkflowDocumentUpload> get latestDocuments =>
      documents.where((doc) => doc.isLatest).toList();

  int get documentCount => latestDocuments.length;

  WorkflowDocumentSection copyWithDocuments(List<WorkflowDocumentUpload> docs) {
    return WorkflowDocumentSection(
      id: id,
      label: label,
      iconName: iconName,
      categoryId: categoryId,
      categoryLabel: categoryLabel,
      clientJourneyKey: clientJourneyKey,
      libraryGroupKey: libraryGroupKey,
      documents: docs,
    );
  }
}

class WorkflowDocumentCategory {
  final String id;
  final String label;
  final String? iconName;
  final String? clientJourneyKey;
  final String? libraryGroupKey;
  final WorkflowDocumentPresentation presentation;
  final List<WorkflowDocumentSection> sections;

  const WorkflowDocumentCategory({
    required this.id,
    required this.label,
    this.iconName,
    this.clientJourneyKey,
    this.libraryGroupKey,
    this.presentation = WorkflowDocumentPresentation.library,
    this.sections = const [],
  });

  int get documentCount =>
      sections.fold<int>(0, (sum, section) => sum + section.documentCount);

  WorkflowDocumentCategory copyWithSections(
    List<WorkflowDocumentSection> nextSections,
  ) {
    return WorkflowDocumentCategory(
      id: id,
      label: label,
      iconName: iconName,
      clientJourneyKey: clientJourneyKey,
      libraryGroupKey: libraryGroupKey,
      presentation: presentation,
      sections: nextSections,
    );
  }
}

class WorkflowDocumentLibrary {
  final List<WorkflowDocumentCategory> clientJourneyCategories;
  final List<WorkflowDocumentCategory> libraryCategories;
  final Map<String, int> cardFileCounts;

  const WorkflowDocumentLibrary({
    this.clientJourneyCategories = const [],
    this.libraryCategories = const [],
    this.cardFileCounts = const {},
  });

  bool get isEmpty =>
      clientJourneyCategories.isEmpty && libraryCategories.isEmpty;

  List<WorkflowDocumentCategory> categoriesForJourney(String journeyKey) {
    final normalized = journeyKey.trim().toLowerCase();
    return clientJourneyCategories.where((category) {
      final key = (category.clientJourneyKey ?? category.id).toLowerCase();
      return key == normalized;
    }).toList();
  }

  List<WorkflowDocumentSection> sectionsForJourney(String journeyKey) {
    final normalized = journeyKey.trim().toLowerCase();
    final seen = <String>{};
    final out = <WorkflowDocumentSection>[];

    void addSection(WorkflowDocumentSection section) {
      if (seen.add(section.id)) out.add(section);
    }

    for (final category in categoriesForJourney(journeyKey)) {
      for (final section in category.sections) {
        addSection(section);
      }
    }

    for (final category in clientJourneyCategories) {
      for (final section in category.sections) {
        final sectionKey = (section.clientJourneyKey ?? '').toLowerCase();
        if (sectionKey == normalized) addSection(section);
      }
    }

    out.sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  List<WorkflowDocumentUpload> allLatestUploads({
    String? categoryId,
    String? sectionId,
    String? journeyKey,
  }) {
    final out = <WorkflowDocumentUpload>[];
    Iterable<WorkflowDocumentCategory> categories = [
      ...libraryCategories,
      ...clientJourneyCategories,
    ];
    if (journeyKey != null) {
      categories = categoriesForJourney(journeyKey);
    }
    for (final category in categories) {
      if (categoryId != null && category.id != categoryId) continue;
      for (final section in category.sections) {
        if (sectionId != null && section.id != sectionId) continue;
        out.addAll(section.latestDocuments);
      }
    }
    return out;
  }

  int? cardCountForLibraryCategory(WorkflowDocumentCategory category) {
    final keys = [
      category.libraryGroupKey,
      category.id,
      category.clientJourneyKey,
    ];
    for (final key in keys) {
      if (key == null || key.isEmpty) continue;
      final count = cardFileCounts[key];
      if (count != null && count > 0) return count;
    }
    return null;
  }

  /// Categories for the Documents tab (excludes KYC-only journey).
  List<WorkflowDocumentCategory> get documentsTabCategories {
    const excluded = {'kyc_documents'};
    return clientJourneyCategories
        .where((category) {
          final key = (category.clientJourneyKey ?? category.id).toLowerCase();
          return !excluded.contains(key);
        })
        .toList();
  }
}
