import '../models/workflow_document.dart';
import '../services/document_role_access.dart';
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

bool _labelIsOfficeDocuments(String? label) {
  final name = (label ?? '').trim().toLowerCase();
  return name == 'documents' || name == 'office documents';
}

bool _labelIsReceipts(String? label) {
  final name = (label ?? '').trim().toLowerCase();
  return name.contains('receipt') && name.contains('agreement');
}

WorkflowDocumentCategory? _categoryForJourneyOrLabel(
  WorkflowDocumentLibrary library,
  String journeyKey,
  bool Function(String? label) labelMatch,
) {
  final byJourney = _categoryForJourney(library, journeyKey);
  if (byJourney != null) return byJourney;
  for (final category in library.libraryCategories) {
    if (labelMatch(category.label)) return category;
  }
  return null;
}

int _badgeForPinnedCategory(
  WorkflowDocumentLibrary library,
  String journeyKey,
  WorkflowDocumentCategory category,
) {
  final byJourney = workflowDocCountForJourney(library, journeyKey);
  if (byJourney > 0) return byJourney;
  return workflowDocCountForCategory(category);
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

/// Site Prep / Demolition are not shown in the client app —
/// clients only get login after the 10% payment (post site-prep stage).
/// Legacy `site_inspection` steps stay hidden for Client; staff see
/// "Site Document" separately via [isSiteDocumentCategory].
bool isClientPortalSitePrepCategory(WorkflowDocumentCategory category) {
  final journey = (category.clientJourneyKey ?? '').trim().toLowerCase();
  if (journey == ClientJourneyKeys.sitePrep ||
      journey == ClientJourneyKeys.demolition) {
    return true;
  }
  if (journey == ClientJourneyKeys.siteDocument ||
      journey == ClientJourneyKeys.planningCommercial) {
    return false;
  }
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''}'
          .toLowerCase();
  if (blob.contains('site_prep') || blob.contains('site preparation')) {
    return true;
  }
  if (blob.contains('demolition')) return true;
  // Old inspection journey (not the renamed Site Document category).
  if (journey == ClientJourneyKeys.inspection ||
      blob.contains('site_inspection') ||
      blob.contains('site inspection')) {
    return true;
  }
  return false;
}

bool isSiteDocumentCategory(WorkflowDocumentCategory category) {
  return classifyForMeDocument(
        categoryId: category.id,
        categoryLabel: category.label,
        journeyKey: category.clientJourneyKey,
        libraryGroupKey: category.libraryGroupKey,
      ) ==
      ForMeDocKind.siteDocument;
}

bool isPlanningCommercialCategory(WorkflowDocumentCategory category) {
  return classifyForMeDocument(
        categoryId: category.id,
        categoryLabel: category.label,
        journeyKey: category.clientJourneyKey,
        libraryGroupKey: category.libraryGroupKey,
      ) ==
      ForMeDocKind.planningCommercial;
}

String displayTitleForDocumentCategory(WorkflowDocumentCategory category) {
  if (isSiteDocumentCategory(category)) return 'Site Document';
  if (isPlanningCommercialCategory(category)) {
    return 'Planning & Commercial Documents';
  }
  return category.label;
}

/// KYC on For me is Client only. Non-client Docs omits it.
/// Super Admin is often stored as `Admin` in prefs.
bool roleCanSeeClientPortalKyc(String? role) => roleCanSeeForMeKyc(role);

/// Client Portal hub rows: KYC / Office Documents / Receipts stay pinned.
/// Most staff get the same rows as clients, without KYC.
/// Site Engineers also omit project documents and contracts.
/// Project Coordinator and APC use their own For me rows.
List<ClientPortalHubItem> buildClientPortalHubItems(
  WorkflowDocumentLibrary? library, {
  bool includeKyc = true,
  String? role,
}) {
  final items = <ClientPortalHubItem>[];
  final visibilityRole = catalogVisibilityRole(role);
  final showKyc = includeKyc &&
      !usesClientDocumentCatalog(role) &&
      (role == null || role.trim().isEmpty || roleCanSeeForMeKyc(role));

  if (showKyc) {
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

  final officeCategory = library == null
      ? null
      : _categoryForJourneyOrLabel(
          library,
          ClientJourneyKeys.officeDocuments,
          _labelIsOfficeDocuments,
        );
  if (officeCategory != null &&
      !siteEngineerHidesForMeDocument(
        role: role,
        categoryId: officeCategory.id,
        categoryLabel: officeCategory.label,
        journeyKey: officeCategory.clientJourneyKey ??
            ClientJourneyKeys.officeDocuments,
        libraryGroupKey: officeCategory.libraryGroupKey,
      ) &&
      (visibilityRole == null ||
          visibilityRole.trim().isEmpty ||
          documentAccessForRole(
            role: visibilityRole,
            kind: ForMeDocKind.officeDocuments,
          ).view)) {
    final category = officeCategory;
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
        badgeCount: _badgeForPinnedCategory(
          library!,
          ClientJourneyKeys.officeDocuments,
          category,
        ),
        journeyKey: ClientJourneyKeys.officeDocuments,
        category: category,
      ),
    );
  }

  final receiptsCategory = library == null
      ? null
      : _categoryForJourneyOrLabel(
          library,
          ClientJourneyKeys.receiptsAndAgreements,
          _labelIsReceipts,
        );
  if (receiptsCategory != null &&
      !isContractsDocumentCategory(receiptsCategory) &&
      !siteEngineerHidesForMeDocument(
        role: role,
        categoryId: receiptsCategory.id,
        categoryLabel: receiptsCategory.label,
        journeyKey: receiptsCategory.clientJourneyKey ??
            ClientJourneyKeys.receiptsAndAgreements,
        libraryGroupKey: receiptsCategory.libraryGroupKey,
      ) &&
      (visibilityRole == null ||
          visibilityRole.trim().isEmpty ||
          documentAccessForRole(
            role: visibilityRole,
            kind: ForMeDocKind.contractsOther,
          ).view)) {
    final category = receiptsCategory;
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
        badgeCount: _badgeForPinnedCategory(
          library!,
          ClientJourneyKeys.receiptsAndAgreements,
          category,
        ),
        journeyKey: ClientJourneyKeys.receiptsAndAgreements,
        category: category,
      ),
    );
  }

  if (library != null) {
    final seen = <String>{};
    final isClientRole =
        forMeDocRoleBucket(role) == ForMeDocRoleBucket.client;
    final matchClientCatalog = usesClientDocumentCatalog(role);
    for (final category in library.libraryCategories) {
      if (items.any((item) => item.category?.id == category.id)) continue;
      if (isPinnedClientPortalCategory(category)) continue;
      if (isUncategorizedDocumentCategory(category)) continue;
      if (isContractsDocumentCategory(category)) continue;
      if (siteEngineerHidesForMeDocument(
        role: role,
        categoryId: category.id,
        categoryLabel: category.label,
        journeyKey: category.clientJourneyKey,
        libraryGroupKey: category.libraryGroupKey,
      )) {
        continue;
      }
      final siteDoc = isSiteDocumentCategory(category);
      final planning = isPlanningCommercialCategory(category);
      if (isClientPortalSitePrepCategory(category) && !siteDoc) continue;
      // Clients never see Site Document or Planning & Commercial.
      // Staff on the client catalog use that same list.
      // Project Coordinator and APC keep those rows when their matrix allows.
      if ((siteDoc || planning) &&
          (role == null ? false : isClientRole || matchClientCatalog)) {
        continue;
      }
      if (visibilityRole != null &&
          visibilityRole.trim().isNotEmpty &&
          !roleCanViewDocumentCategory(
            role: visibilityRole,
            categoryId: category.id,
            categoryLabel: category.label,
            journeyKey: category.clientJourneyKey,
            libraryGroupKey: category.libraryGroupKey,
          )) {
        continue;
      }
      if (!seen.add(category.id)) continue;
      final title = displayTitleForDocumentCategory(category);
      items.add(
        ClientPortalHubItem(
          id: category.id,
          title: title,
          subtitle: siteDoc
              ? 'Site inspection report'
              : planning
                  ? 'Final Cost Sheet'
                  : catalogCategorySubtitle(category),
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
