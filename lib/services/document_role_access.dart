/// For Me / Documents V1 access from BuildAhome_Documents matrix.
///
/// Legend: V = view, E = edit, U = upload. Empty = no access.
/// KYC is Client + Super Admin only (app rule), not Finance view from the sheet.

import '../models/workflow_document.dart';

class DocumentAccessRights {
  final bool view;
  final bool edit;
  final bool upload;
  final bool delete;

  const DocumentAccessRights({
    this.view = false,
    this.edit = false,
    this.upload = false,
    this.delete = false,
  });

  static const none = DocumentAccessRights();
  static const viewOnly = DocumentAccessRights(view: true);
  static const viewEditUpload = DocumentAccessRights(
    view: true,
    edit: true,
    upload: true,
  );
  static const full = DocumentAccessRights(
    view: true,
    edit: true,
    upload: true,
    delete: true,
  );

  DocumentAccessRights withDelete(bool allowed) {
    if (!allowed) return this;
    return DocumentAccessRights(
      view: view,
      edit: edit,
      upload: upload,
      delete: true,
    );
  }

  bool get canMutate => edit || upload || delete;
}

/// Canonical doc families matching the Excel "For ME - Docs" rows.
enum ForMeDocKind {
  kyc,
  architecturalFloorPlan,
  architecturalWorkingDrawing,
  architecturalFillerSlab,
  architecturalSection,
  architecturalElevation,
  architectural2dElevation,
  architecturalDoorWindowGrill,
  architecturalFlooring,
  architecturalDado,
  architecturalFabrication,
  architecturalSkylight,
  architecturalPaintShade,
  architecturalFinalAreaStatement,
  architecturalOther,
  structuralFraming,
  structuralFoundation,
  structuralFloorSlab,
  structuralOther,
  electrical,
  plumbing,
  qualitySoilTest,
  qualityQcReports,
  qualityOther,
  preConversionProposal,
  preConversionBooking,
  preConversionOther,
  contractsAgreement,
  contractsReceipts,
  contractsOther,
  officeDocuments,
  siteDocument,
  planningCommercial,
  unknown,
}

/// Role buckets from the Excel columns.
enum ForMeDocRoleBucket {
  client,
  architect,
  structural,
  mepDesigner,
  siteEngineer,
  pcApc,
  pm,
  mepEngineer,
  qc,
  finance,
  admin,
  other,
}

ForMeDocRoleBucket forMeDocRoleBucket(String? role) {
  final n = _norm(role);
  if (n.isEmpty) return ForMeDocRoleBucket.other;
  if (n == 'client') return ForMeDocRoleBucket.client;
  if (n == 'admin' || n == 'super admin') return ForMeDocRoleBucket.admin;

  if (n.contains('architect') ||
      n == 'jr. arch' ||
      n == 'sr. arch' ||
      n == 'design head') {
    return ForMeDocRoleBucket.architect;
  }

  if (n.contains('structural')) {
    return ForMeDocRoleBucket.structural;
  }

  // Designers before generic MEP engineer.
  if (n.contains('mep designer') ||
      n == 'electrical designer' ||
      n == 'phe designer') {
    return ForMeDocRoleBucket.mepDesigner;
  }

  if (n == 'site engineer') return ForMeDocRoleBucket.siteEngineer;

  if (n == 'project coordinator' ||
      n == 'project co-ordinator' ||
      n.contains('assistant project coordinator') ||
      n == 'apcc' ||
      n == 'apc') {
    return ForMeDocRoleBucket.pcApc;
  }

  if (n == 'project manager' ||
      n == 'pm' ||
      n == 'project head' ||
      n == 'ph') {
    return ForMeDocRoleBucket.pm;
  }

  if (n.contains('mep') ||
      n.contains('electrical engineer') ||
      n.contains('phe engineer')) {
    return ForMeDocRoleBucket.mepEngineer;
  }

  if (n == 'qc' ||
      n.contains('qa qc') ||
      n.contains('quality')) {
    return ForMeDocRoleBucket.qc;
  }

  if (n.contains('billing') ||
      n.contains('finance') ||
      n.contains('accounts')) {
    return ForMeDocRoleBucket.finance;
  }

  return ForMeDocRoleBucket.other;
}

bool roleIsDocumentSenior(String? role) {
  final n = _norm(role);
  if (n.isEmpty) return false;
  if (n == 'admin' || n == 'super admin') return true;
  if (n.contains('senior') || n.startsWith('sr.') || n.startsWith('sr ')) {
    return true;
  }
  if (n.contains('head')) return true;
  // Default Architect maps to Sr. Arch in RBAC.
  if (n == 'architect' || n == 'sr. arch' || n == 'senior architect') {
    return true;
  }
  return false;
}

/// KYC on For Me / Documents: Client + Super Admin only.
bool roleCanSeeForMeKyc(String? role) {
  final bucket = forMeDocRoleBucket(role);
  return bucket == ForMeDocRoleBucket.client ||
      bucket == ForMeDocRoleBucket.admin;
}

/// Project Coordinator and Assistant Project Coordinator use their own For me
/// rows. Other staff still see the client catalog, without KYC.
bool _usesOwnForMeCatalog(String? role) {
  final bucket = forMeDocRoleBucket(role);
  return bucket == ForMeDocRoleBucket.client ||
      bucket == ForMeDocRoleBucket.pcApc;
}

/// Role used to decide which categories and sections are listed.
///
/// Clients, Project Coordinators, and Assistant Project Coordinators use
/// their own matrix. Every other signed-in role sees the same catalog a
/// client sees. KYC is removed separately.
String? catalogVisibilityRole(String? role) {
  if (role == null || role.trim().isEmpty) return role;
  if (_usesOwnForMeCatalog(role)) return role;
  return 'Client';
}

/// Staff other than PC / APC use the client document catalog. KYC is omitted
/// separately.
bool usesClientDocumentCatalog(String? role) {
  return role != null &&
      role.trim().isNotEmpty &&
      !_usesOwnForMeCatalog(role);
}

ForMeDocKind classifyForMeDocument({
  String? categoryId,
  String? categoryLabel,
  String? sectionId,
  String? sectionLabel,
  String? documentKey,
  String? documentName,
  String? journeyKey,
  String? libraryGroupKey,
}) {
  final blob = _norm([
    categoryId,
    categoryLabel,
    sectionId,
    sectionLabel,
    documentKey,
    documentName,
    journeyKey,
    libraryGroupKey,
  ].whereType<String>().join(' '));

  if (blob.contains('kyc')) return ForMeDocKind.kyc;

  if (blob.contains('office document') || blob.contains('office_documents')) {
    return ForMeDocKind.officeDocuments;
  }

  if (blob.contains('site document') ||
      blob.contains('site_document') ||
      blob.contains('site inspection report') ||
      blob.contains('site_inspection') ||
      blob.contains('sipr') ||
      RegExp(r'\bsd\b').hasMatch(blob)) {
    return ForMeDocKind.siteDocument;
  }

  if ((blob.contains('planning') && blob.contains('commercial')) ||
      blob.contains('planning_commercial') ||
      blob.contains('final cost sheet') ||
      blob.contains('final_cost_sheet') ||
      blob.contains('cost sheet')) {
    return ForMeDocKind.planningCommercial;
  }

  if (blob.contains('receipt')) return ForMeDocKind.contractsReceipts;
  if (blob.contains('agreement') || blob.contains('contract')) {
    if (blob.contains('receipt')) return ForMeDocKind.contractsReceipts;
    if (blob.contains('agreement')) return ForMeDocKind.contractsAgreement;
    return ForMeDocKind.contractsOther;
  }
  if (blob.contains('receipts_and_agreements')) {
    return ForMeDocKind.contractsOther;
  }

  if (blob.contains('proposal')) return ForMeDocKind.preConversionProposal;
  if (blob.contains('booking')) return ForMeDocKind.preConversionBooking;
  if (blob.contains('pre conversion') || blob.contains('pre_conversion')) {
    return ForMeDocKind.preConversionOther;
  }

  if (blob.contains('soil')) return ForMeDocKind.qualitySoilTest;
  if (blob.contains('ndt') ||
      blob.contains('qc report') ||
      blob.contains('quality')) {
    if (blob.contains('soil')) return ForMeDocKind.qualitySoilTest;
    if (blob.contains('ndt') || blob.contains('qc report')) {
      return ForMeDocKind.qualityQcReports;
    }
    return ForMeDocKind.qualityOther;
  }

  if (blob.contains('electr')) return ForMeDocKind.electrical;
  if (blob.contains('plumb')) return ForMeDocKind.plumbing;

  if (blob.contains('framing')) return ForMeDocKind.structuralFraming;
  if (blob.contains('foundation') || blob.contains('plinth')) {
    return ForMeDocKind.structuralFoundation;
  }
  if (blob.contains('slab') && blob.contains('floor')) {
    return ForMeDocKind.structuralFloorSlab;
  }
  if (blob.contains('structural') || blob.contains('civil')) {
    return ForMeDocKind.structuralOther;
  }

  if (blob.contains('area statement')) {
    return ForMeDocKind.architecturalFinalAreaStatement;
  }
  if (blob.contains('floor plan')) return ForMeDocKind.architecturalFloorPlan;
  if (blob.contains('working drawing') || blob.contains('working draw')) {
    return ForMeDocKind.architecturalWorkingDrawing;
  }
  if (blob.contains('filler slab')) {
    return ForMeDocKind.architecturalFillerSlab;
  }
  if (blob.contains('2d elevation') || blob.contains('2 d elevation')) {
    return ForMeDocKind.architectural2dElevation;
  }
  if (blob.contains('elevation') && !blob.contains('floor plan')) {
    return ForMeDocKind.architecturalElevation;
  }
  if (blob.contains('section') &&
      (blob.contains('architect') || blob.contains('drawing'))) {
    return ForMeDocKind.architecturalSection;
  }
  if (blob.contains('door') ||
      blob.contains('window') ||
      blob.contains('grill')) {
    return ForMeDocKind.architecturalDoorWindowGrill;
  }
  if (blob.contains('flooring')) return ForMeDocKind.architecturalFlooring;
  if (blob.contains('dado')) return ForMeDocKind.architecturalDado;
  if (blob.contains('fabrication')) {
    return ForMeDocKind.architecturalFabrication;
  }
  if (blob.contains('skylight')) return ForMeDocKind.architecturalSkylight;
  if (blob.contains('paint')) return ForMeDocKind.architecturalPaintShade;
  if (blob.contains('architect') ||
      blob.contains('gfc') ||
      blob.contains('design element') ||
      blob.contains('floor_plan')) {
    return ForMeDocKind.architecturalOther;
  }

  return ForMeDocKind.unknown;
}

DocumentAccessRights documentAccessForRole({
  required String? role,
  required ForMeDocKind kind,
}) {
  final bucket = forMeDocRoleBucket(role);
  if (bucket == ForMeDocRoleBucket.admin) {
    return DocumentAccessRights.full;
  }

  // App rule: KYC only Client (+ Admin above).
  if (kind == ForMeDocKind.kyc) {
    if (bucket == ForMeDocRoleBucket.client) {
      return DocumentAccessRights.viewEditUpload;
    }
    return DocumentAccessRights.none;
  }

  final base = _matrixAccess(bucket, kind);
  if (!base.view && !base.edit && !base.upload) return base;

  final seniorKinds = {
    ForMeDocKind.architecturalFloorPlan,
    ForMeDocKind.architecturalWorkingDrawing,
    ForMeDocKind.architecturalFillerSlab,
    ForMeDocKind.architecturalSection,
    ForMeDocKind.architecturalElevation,
    ForMeDocKind.architectural2dElevation,
    ForMeDocKind.architecturalDoorWindowGrill,
    ForMeDocKind.architecturalFlooring,
    ForMeDocKind.architecturalDado,
    ForMeDocKind.architecturalFabrication,
    ForMeDocKind.architecturalSkylight,
    ForMeDocKind.architecturalPaintShade,
    ForMeDocKind.architecturalFinalAreaStatement,
    ForMeDocKind.architecturalOther,
    ForMeDocKind.structuralFraming,
    ForMeDocKind.structuralFoundation,
    ForMeDocKind.structuralFloorSlab,
    ForMeDocKind.structuralOther,
    ForMeDocKind.electrical,
    ForMeDocKind.plumbing,
    ForMeDocKind.qualityQcReports,
    ForMeDocKind.qualityOther,
  };

  final canDelete = roleIsDocumentSenior(role) &&
      seniorKinds.contains(kind) &&
      (bucket == ForMeDocRoleBucket.architect ||
          bucket == ForMeDocRoleBucket.structural ||
          bucket == ForMeDocRoleBucket.mepDesigner ||
          bucket == ForMeDocRoleBucket.qc);

  return base.withDelete(canDelete);
}

DocumentAccessRights documentAccessForRef({
  required String? role,
  String? categoryId,
  String? categoryLabel,
  String? sectionId,
  String? sectionLabel,
  String? documentKey,
  String? documentName,
  String? journeyKey,
  String? libraryGroupKey,
}) {
  final kind = classifyForMeDocument(
    categoryId: categoryId,
    categoryLabel: categoryLabel,
    sectionId: sectionId,
    sectionLabel: sectionLabel,
    documentKey: documentKey,
    documentName: documentName,
    journeyKey: journeyKey,
    libraryGroupKey: libraryGroupKey,
  );
  return documentAccessForRole(role: role, kind: kind);
}

bool roleCanViewDocumentCategory({
  required String? role,
  required String categoryId,
  required String categoryLabel,
  String? journeyKey,
  String? libraryGroupKey,
}) {
  final kind = classifyForMeDocument(
    categoryId: categoryId,
    categoryLabel: categoryLabel,
    journeyKey: journeyKey,
    libraryGroupKey: libraryGroupKey,
  );
  // Unknown catalog rows stay visible so new backend categories are not dropped.
  if (kind == ForMeDocKind.unknown) {
    return forMeDocRoleBucket(role) != ForMeDocRoleBucket.other ||
        forMeDocRoleBucket(role) == ForMeDocRoleBucket.client ||
        forMeDocRoleBucket(role) == ForMeDocRoleBucket.admin;
  }
  return documentAccessForRole(role: role, kind: kind).view;
}

bool roleCanViewDocumentSection({
  required String? role,
  required String categoryId,
  required String categoryLabel,
  required String sectionId,
  required String sectionLabel,
  String? journeyKey,
  String? libraryGroupKey,
}) {
  return documentAccessForRef(
    role: role,
    categoryId: categoryId,
    categoryLabel: categoryLabel,
    sectionId: sectionId,
    sectionLabel: sectionLabel,
    journeyKey: journeyKey,
    libraryGroupKey: libraryGroupKey,
  ).view;
}

String _norm(String? raw) {
  return (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_/-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

DocumentAccessRights _matrixAccess(ForMeDocRoleBucket bucket, ForMeDocKind kind) {
  const v = DocumentAccessRights.viewOnly;
  const evu = DocumentAccessRights.viewEditUpload;
  const none = DocumentAccessRights.none;

  DocumentAccessRights pick({
    DocumentAccessRights client = none,
    DocumentAccessRights architect = none,
    DocumentAccessRights structural = none,
    DocumentAccessRights mepDesigner = none,
    DocumentAccessRights siteEngineer = none,
    DocumentAccessRights pcApc = none,
    DocumentAccessRights pm = none,
    DocumentAccessRights mepEngineer = none,
    DocumentAccessRights qc = none,
    DocumentAccessRights finance = none,
  }) {
    switch (bucket) {
      case ForMeDocRoleBucket.client:
        return client;
      case ForMeDocRoleBucket.architect:
        return architect;
      case ForMeDocRoleBucket.structural:
        return structural;
      case ForMeDocRoleBucket.mepDesigner:
        return mepDesigner;
      case ForMeDocRoleBucket.siteEngineer:
        return siteEngineer;
      case ForMeDocRoleBucket.pcApc:
        return pcApc;
      case ForMeDocRoleBucket.pm:
        return pm;
      case ForMeDocRoleBucket.mepEngineer:
        return mepEngineer;
      case ForMeDocRoleBucket.qc:
        return qc;
      case ForMeDocRoleBucket.finance:
        return finance;
      case ForMeDocRoleBucket.admin:
        return DocumentAccessRights.full;
      case ForMeDocRoleBucket.other:
        return none;
    }
  }

  switch (kind) {
    case ForMeDocKind.kyc:
      return pick(client: evu, finance: v); // finance overridden to none above

    case ForMeDocKind.architecturalFloorPlan:
    case ForMeDocKind.architecturalWorkingDrawing:
    case ForMeDocKind.architecturalFillerSlab:
    case ForMeDocKind.architecturalElevation:
      return pick(
        client: v,
        architect: evu,
        structural: v,
        mepDesigner: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        mepEngineer: v,
        qc: v,
      );

    case ForMeDocKind.architecturalSection:
      return pick(
        client: v,
        architect: evu,
        structural: v,
        mepDesigner: v,
        pcApc: v,
        pm: v,
        qc: v,
      );

    case ForMeDocKind.architectural2dElevation:
    case ForMeDocKind.architecturalDoorWindowGrill:
    case ForMeDocKind.architecturalFlooring:
    case ForMeDocKind.architecturalDado:
    case ForMeDocKind.architecturalFabrication:
    case ForMeDocKind.architecturalSkylight:
    case ForMeDocKind.architecturalPaintShade:
      return pick(
        client: v,
        architect: evu,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        qc: v,
      );

    case ForMeDocKind.architecturalFinalAreaStatement:
      return pick(
        architect: evu,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        qc: v,
      );

    case ForMeDocKind.architecturalOther:
      return pick(
        client: v,
        architect: evu,
        structural: v,
        mepDesigner: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        mepEngineer: v,
        qc: v,
      );

    case ForMeDocKind.structuralFraming:
    case ForMeDocKind.structuralFoundation:
    case ForMeDocKind.structuralFloorSlab:
    case ForMeDocKind.structuralOther:
      return pick(
        client: v,
        structural: evu,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        qc: v,
      );

    case ForMeDocKind.electrical:
    case ForMeDocKind.plumbing:
      return pick(
        client: v,
        mepDesigner: evu,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        mepEngineer: v,
        qc: v,
      );

    case ForMeDocKind.qualitySoilTest:
      return pick(
        client: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        qc: v,
      );

    case ForMeDocKind.qualityQcReports:
      return pick(
        client: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        qc: const DocumentAccessRights(view: true, edit: true, upload: true),
      );

    case ForMeDocKind.qualityOther:
      return pick(
        client: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        qc: v,
      );

    case ForMeDocKind.preConversionProposal:
    case ForMeDocKind.preConversionBooking:
    case ForMeDocKind.preConversionOther:
      return pick(client: v);

    case ForMeDocKind.contractsAgreement:
      return pick(
        client: v,
        pcApc: v,
        pm: v,
        finance: evu,
      );

    case ForMeDocKind.contractsReceipts:
      return pick(client: v);

    case ForMeDocKind.contractsOther:
      return pick(
        client: v,
        pcApc: v,
        pm: v,
        finance: evu,
      );

    case ForMeDocKind.officeDocuments:
      return pick(
        client: v,
        pcApc: v,
        pm: v,
        finance: evu,
      );

    case ForMeDocKind.siteDocument:
      // Internal Docs only — not shown to Client.
      return pick(
        architect: v,
        structural: v,
        mepDesigner: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        mepEngineer: v,
        qc: v,
        finance: v,
      );

    case ForMeDocKind.planningCommercial:
      // Planning & Commercial Documents (Final Cost Sheet only).
      return pick(
        architect: v,
        structural: v,
        mepDesigner: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        mepEngineer: v,
        qc: v,
        finance: v,
      );

    case ForMeDocKind.unknown:
      return pick(
        client: v,
        architect: v,
        structural: v,
        mepDesigner: v,
        siteEngineer: v,
        pcApc: v,
        pm: v,
        mepEngineer: v,
        qc: v,
        finance: v,
      );
  }
}

bool _isKycCategory(WorkflowDocumentCategory category) {
  final blob = [
    category.id,
    category.label,
    category.clientJourneyKey,
    category.libraryGroupKey,
  ].whereType<String>().join(' ').toLowerCase();
  return blob.contains('kyc');
}

/// Filters library categories for the signed-in role (Excel matrix + KYC rule).
List<WorkflowDocumentCategory> filterDocumentCategoriesForRole(
  List<WorkflowDocumentCategory> categories,
  String? role, {
  bool clientMode = false,
}) {
  final isClientRole =
      forMeDocRoleBucket(role) == ForMeDocRoleBucket.client;
  final visibilityRole = catalogVisibilityRole(role);
  final hideKyc = usesClientDocumentCatalog(role) || !roleCanSeeForMeKyc(role);
  // Client catalog hides Area Statement. Non-clients use that same catalog.
  final hideAreaStatement = isClientRole ||
      usesClientDocumentCatalog(role) ||
      (clientMode && forMeDocRoleBucket(role) == ForMeDocRoleBucket.other);

  var next = categories.where((category) {
    if (isUncategorizedDocumentCategory(category)) return false;
    if (hideKyc && _isKycCategory(category)) return false;
    return roleCanViewDocumentCategory(
      role: visibilityRole,
      categoryId: category.id,
      categoryLabel: category.label,
      journeyKey: category.clientJourneyKey,
      libraryGroupKey: category.libraryGroupKey,
    );
  }).map((category) {
    final isPlanningCommercial = classifyForMeDocument(
          categoryId: category.id,
          categoryLabel: category.label,
          journeyKey: category.clientJourneyKey,
          libraryGroupKey: category.libraryGroupKey,
        ) ==
        ForMeDocKind.planningCommercial;

    final sections = category.sections
        .where(
          (section) => roleCanViewDocumentSection(
            role: visibilityRole,
            categoryId: category.id,
            categoryLabel: category.label,
            sectionId: section.id,
            sectionLabel: section.label,
            journeyKey: section.clientJourneyKey ?? category.clientJourneyKey,
            libraryGroupKey:
                section.libraryGroupKey ?? category.libraryGroupKey,
          ),
        )
        // Planning & Commercial never lists Final Area Statement.
        .where((section) {
          if (!isPlanningCommercial) return true;
          final label = section.label.trim().toLowerCase();
          final id = section.id.trim().toLowerCase();
          if (label.contains('area statement') ||
              id.contains('area_statement') ||
              id.contains('area-statement')) {
            return false;
          }
          return true;
        })
        .map((section) {
      var docs = section.documents;
      if (hideAreaStatement || isPlanningCommercial) {
        docs = docs.where((doc) => !doc.isAreaStatement).toList();
      }
      return section.copyWithDocuments(docs);
    }).where((section) {
      if (hideAreaStatement || isPlanningCommercial) {
        return section.documents.isNotEmpty;
      }
      return true;
    }).toList();

    return category.copyWithSections(sections);
  }).where((category) => category.sections.isNotEmpty).toList();

  if (hideAreaStatement) {
    next = withoutAreaStatementCategories(next);
  }
  return next;
}

DocumentAccessRights documentAccessForUpload(
  String? role,
  WorkflowDocumentUpload doc,
) {
  return documentAccessForRef(
    role: role,
    categoryId: doc.categoryId,
    categoryLabel: doc.categoryLabel,
    sectionId: doc.sectionId,
    sectionLabel: doc.sectionLabel,
    documentKey: doc.documentKey,
    documentName: doc.name,
    journeyKey: doc.clientJourneyKey,
    libraryGroupKey: doc.libraryGroupKey,
  );
}
