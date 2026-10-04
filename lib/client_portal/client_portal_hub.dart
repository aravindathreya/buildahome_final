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

/// Site Prep / Demolition / Site Inspection are not shown in the client app —
/// clients only get login after the 10% payment (post site-prep stage).
bool isClientPortalSitePrepCategory(WorkflowDocumentCategory category) {
  final journey = (category.clientJourneyKey ?? '').trim().toLowerCase();
  if (journey == ClientJourneyKeys.sitePrep ||
      journey == ClientJourneyKeys.demolition ||
      journey == ClientJourneyKeys.inspection) {
    return true;
  }
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''}'
          .toLowerCase();
  if (blob.contains('site_prep') || blob.contains('site preparation')) {
    return true;
  }
  if (blob.contains('demolition')) return true;
  if (blob.contains('site_inspection') || blob.contains('site inspection')) {
    return true;
  }
  return false;
}

/// KYC on For me / Client Portal is Client + Super Admin only.
/// Super Admin is often stored as `Admin` in prefs.
bool roleCanSeeClientPortalKyc(String? role) {
  final normalized =
      (role ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return normalized == 'client' ||
      normalized == 'super admin' ||
      normalized == 'admin';
}

/// Client Portal hub rows: KYC / Office Documents / Receipts stay pinned.
/// Remaining rows come from the live catalog (same tree as staff Documents).
List<ClientPortalHubItem> buildClientPortalHubItems(
  WorkflowDocumentLibrary? library, {
  bool includeKyc = true,
}) {
  final items = <ClientPortalHubItem>[];

  if (includeKyc) {
    items.add(
      ClientPortalHubItem(
        id: 'documents',
        title: 'KYC & Documents',
        subtitle: 'KYC and other project documents',
        kind: ClientPortalHubKind.kyc,
        visual: categoryVisualFor(categoryId: 'kyc', label: 'KYC & Documents'),
        badgeCount: library == null
            ? 0
            : workflowDocCountForJourney(
                library,
                ClientJourneyKeys.preConversion,
              ),
      ),
    );
  }

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
      if (isUncategorizedDocumentCategory(category)) continue;
      if (isClientPortalSitePrepCategory(category)) continue;
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

  return items;
}
