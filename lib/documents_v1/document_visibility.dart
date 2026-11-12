import '../models/workflow_document.dart';

/// Docs visibility rules (Docs home, category and section screens).
///
/// * A section or category with no uploaded (openable) file is hidden.
/// * The Architectural "Section" checklist row is never shown under that bare
///   title. When it holds files they stay visible as "Section drawings", so
///   nothing is dropped.

bool isPlaceholderSectionLabel(String? label) {
  final text = (label ?? '').trim().toLowerCase();
  return text.isEmpty || text == 'section' || text == 'sections';
}

/// True when at least one row in the section has a file to open.
bool docsSectionHasFiles(WorkflowDocumentSection section) =>
    section.documents.any((doc) => doc.hasUrl);

/// Null when the section has no uploaded file; renames a bare "Section".
WorkflowDocumentSection? visibleDocsSection(WorkflowDocumentSection section) {
  if (!docsSectionHasFiles(section)) return null;
  if (!isPlaceholderSectionLabel(section.label)) return section;
  return WorkflowDocumentSection(
    id: section.id,
    label: 'Section drawings',
    iconName: section.iconName,
    categoryId: section.categoryId,
    categoryLabel: section.categoryLabel,
    clientJourneyKey: section.clientJourneyKey,
    libraryGroupKey: section.libraryGroupKey,
    documents: section.documents,
  );
}

List<WorkflowDocumentSection> visibleDocsSections(
  Iterable<WorkflowDocumentSection> sections,
) {
  return sections
      .map(visibleDocsSection)
      .whereType<WorkflowDocumentSection>()
      .toList();
}

/// Null when no section in the category has an uploaded file. Section labels
/// are left as-is here so checklist grouping on the category screen still
/// matches the backend rows.
WorkflowDocumentCategory? visibleDocsCategory(
  WorkflowDocumentCategory category,
) {
  final sections = category.sections.where(docsSectionHasFiles).toList();
  if (sections.isEmpty) return null;
  return category.copyWithSections(sections);
}

List<WorkflowDocumentCategory> visibleDocsCategories(
  Iterable<WorkflowDocumentCategory> categories,
) {
  return categories
      .map(visibleDocsCategory)
      .whereType<WorkflowDocumentCategory>()
      .toList();
}
