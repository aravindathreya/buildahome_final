import '../models/workflow_document.dart';
import '../services/workflow_document_service.dart';
import 'client_portal_document_ui.dart';

/// Pinned Client Portal rows that keep their existing special screens.
const Set<String> kPinnedClientPortalKeys = {
  'kyc',
  'kyc_documents',
  'office_documents',
  'receipts_and_agreements',
  'gallery',
};

enum ClientPortalHubKind {
  kyc,
  officeDocuments,
  receipts,
  catalog,
  sitePrep,
  demolition,
  inspection,
}

class ClientPortalHubItem {
  const ClientPortalHubItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.visual,
    this.badgeCount = 0,
    this.journeyKey,
    this.category,
  });

  final String id;
  final String title;
  final String subtitle;
  final ClientPortalHubKind kind;
  final ClientPortalCategoryVisual visual;
  final int badgeCount;
  final String? journeyKey;
  final WorkflowDocumentCategory? category;

  bool get isPinnedSpecial =>
      kind == ClientPortalHubKind.kyc ||
      kind == ClientPortalHubKind.officeDocuments ||
      kind == ClientPortalHubKind.receipts;

  bool get isCatalog => kind == ClientPortalHubKind.catalog;

  bool get isProjectStep =>
      kind == ClientPortalHubKind.sitePrep ||
      kind == ClientPortalHubKind.demolition ||
      kind == ClientPortalHubKind.inspection;
}

bool isPinnedClientPortalCategory(WorkflowDocumentCategory category) {
  return isPinnedClientPortalKey(
    category.clientJourneyKey ?? category.libraryGroupKey ?? category.id,
    category.label,
  );
}

bool isPinnedClientPortalKey(String? id, [String? label]) {
  final key = (id ?? '').trim().toLowerCase();
  final name = (label ?? '').trim().toLowerCase();
  if (kPinnedClientPortalKeys.contains(key)) return true;
  if (key.contains('kyc')) return true;
  if (key == 'gallery' || name == 'gallery') return true;
  if (key == 'office_documents') return true;
  if (key == 'receipts_and_agreements') return true;
  if (name.contains('receipt') && name.contains('agreement')) return true;
  return false;
}

bool _libraryHasJourney(WorkflowDocumentLibrary library, String journeyKey) {
  if (library.categoriesForJourney(journeyKey).isNotEmpty) return true;
  if (library.sectionsForJourney(journeyKey).isNotEmpty) return true;
  final normalized = journeyKey.trim().toLowerCase();
  return library.libraryCategories.any((category) {
    final key = (category.clientJourneyKey ?? category.id).toLowerCase();
    return key == normalized;
  });
}

WorkflowDocumentCategory? _categoryForJourney(
  WorkflowDocumentLibrary library,
  String journeyKey,
) {
  final normalized = journeyKey.trim().toLowerCase();
  for (final category in [
    ...library.libraryCategories,
    ...library.clientJourneyCategories,
  ]) {
    final key = (category.clientJourneyKey ?? category.id).toLowerCase();
    if (key == normalized) return category;
  }
  return null;
}

bool _catalogCoversSpecial(WorkflowDocumentLibrary library, String id) {
  bool hit(WorkflowDocumentCategory category) {
    final blob =
        '${category.id} ${category.label} ${category.clientJourneyKey ?? ''} ${category.libraryGroupKey ?? ''}'
            .toLowerCase();
    switch (id) {
      case 'site_prep':
        return blob.contains('site_prep') || blob.contains('site preparation');
      case 'demolition':
        return blob.contains('demolition');
      case 'inspection':
        return blob.contains('inspection');
      default:
        return false;
    }
  }

  return library.libraryCategories.any(hit) ||
      library.clientJourneyCategories.any(hit);
}

/// Client Portal hub rows: KYC / Office Documents / Receipts stay pinned.
/// Remaining rows come from the live catalog (same tree as staff Documents).
List<ClientPortalHubItem> buildClientPortalHubItems(
  WorkflowDocumentLibrary? library,
) {
  final items = <ClientPortalHubItem>[];

  items.add(
    ClientPortalHubItem(
      id: 'documents',
      title: 'KYC & Documents',
      subtitle: 'KYC and other project documents',
      kind: ClientPortalHubKind.kyc,
      visual: categoryVisualFor(categoryId: 'kyc', label: 'KYC & Documents'),
      badgeCount: library == null
          ? 0
          : workflowDocCountForJourney(library, ClientJourneyKeys.preConversion),
    ),
  );

  if (library != null &&
      _libraryHasJourney(library, ClientJourneyKeys.officeDocuments)) {
    final category =
        _categoryForJourney(library, ClientJourneyKeys.officeDocuments);
    final visual = category != null
        ? categoryVisualForCategory(category)
        : categoryVisualFor(
            journeyKey: ClientJourneyKeys.officeDocuments,
            label: 'Documents',
          );
    items.add(
      ClientPortalHubItem(
        id: 'office_documents',
        title: category?.label.isNotEmpty == true ? category!.label : 'Documents',
        subtitle: category != null
            ? catalogCategorySubtitle(category)
            : visual.subtitle,
        kind: ClientPortalHubKind.officeDocuments,
        visual: visual,
        badgeCount: workflowDocCountForJourney(
          library,
          ClientJourneyKeys.officeDocuments,
        ),
        journeyKey: ClientJourneyKeys.officeDocuments,
        category: category,
      ),
    );
  }

  if (library != null &&
      _libraryHasJourney(library, ClientJourneyKeys.receiptsAndAgreements)) {
    final category =
        _categoryForJourney(library, ClientJourneyKeys.receiptsAndAgreements);
    final visual = category != null
        ? categoryVisualForCategory(category)
        : categoryVisualFor(
            journeyKey: ClientJourneyKeys.receiptsAndAgreements,
            label: 'Receipts and Agreements',
          );
    items.add(
      ClientPortalHubItem(
        id: 'receipts_and_agreements',
        title: category?.label.isNotEmpty == true
            ? category!.label
            : 'Receipts and Agreements',
        subtitle: category != null
            ? catalogCategorySubtitle(category)
            : visual.subtitle,
        kind: ClientPortalHubKind.receipts,
        visual: visual,
        badgeCount: workflowDocCountForJourney(
          library,
          ClientJourneyKeys.receiptsAndAgreements,
        ),
        journeyKey: ClientJourneyKeys.receiptsAndAgreements,
        category: category,
      ),
    );
  }

  if (library != null) {
    final seen = <String>{};
    for (final category in library.libraryCategories) {
      if (isPinnedClientPortalCategory(category)) continue;
      if (!seen.add(category.id)) continue;
      items.add(
        ClientPortalHubItem(
          id: category.id,
          title: category.label,
          subtitle: catalogCategorySubtitle(category),
          kind: ClientPortalHubKind.catalog,
          visual: categoryVisualForCategory(category),
          badgeCount: workflowDocCountForCategory(category),
          journeyKey: category.clientJourneyKey,
          category: category,
        ),
      );
    }
  }

  void addSpecial({
    required String id,
    required String title,
    required String subtitle,
    required ClientPortalHubKind kind,
    required String journeyKey,
  }) {
    if (library != null && _catalogCoversSpecial(library, id)) return;
    items.add(
      ClientPortalHubItem(
        id: id,
        title: title,
        subtitle: subtitle,
        kind: kind,
        visual: categoryVisualFor(categoryId: id, journeyKey: journeyKey, label: title),
        journeyKey: journeyKey,
      ),
    );
  }

  addSpecial(
    id: 'site_prep',
    title: 'Site Preparation',
    subtitle: 'Demolition & borewell questionnaire',
    kind: ClientPortalHubKind.sitePrep,
    journeyKey: ClientJourneyKeys.sitePrep,
  );
  addSpecial(
    id: 'demolition',
    title: 'Demolition Details',
    subtitle: 'Demolition completion & comments',
    kind: ClientPortalHubKind.demolition,
    journeyKey: ClientJourneyKeys.demolition,
  );
  addSpecial(
    id: 'inspection',
    title: 'Site Inspection',
    subtitle: 'Book a slot or view reports',
    kind: ClientPortalHubKind.inspection,
    journeyKey: ClientJourneyKeys.inspection,
  );

  return items;
}
