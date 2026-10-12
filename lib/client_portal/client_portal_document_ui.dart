import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/workflow_document.dart';
import '../services/document_role_access.dart';

/// Reference design tokens for the client portal documents flow.
class ClientPortalDocTheme {
  static const accentBlue = AppTheme.accentBlue;
  static const cardRadius = 14.0;
  static const iconBoxRadius = 12.0;

  static BoxDecoration cardDecoration({Color? bg}) => BoxDecoration(
        color: bg ?? cardBackground,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );

  static Color get cardBackground => AppTheme.darkBackgroundSecondary;

  static TabBarTheme tabBarTheme() => TabBarTheme(
        labelColor: AppTheme.darkTextPrimary,
        unselectedLabelColor: AppTheme.mutedGrey,
        indicatorColor: accentBlue,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      );
}

/// Visual metadata for categories — icons, subtitles, pastel backgrounds.
class ClientPortalCategoryVisual {
  final IconData icon;
  final String subtitle;
  final Color iconBg;
  final Color iconFg;

  const ClientPortalCategoryVisual({
    required this.icon,
    required this.subtitle,
    required this.iconBg,
    this.iconFg = const Color(0xFFF4F4F5),
  });
}

ClientPortalCategoryVisual categoryVisualFor({
  String? journeyKey,
  String? categoryId,
  String? label,
  String? iconName,
}) {
  final blob = [
    journeyKey,
    categoryId,
    label,
    iconName,
  ].whereType<String>().join(' ').toLowerCase();

  ClientPortalCategoryVisual? fromKeywords() {
    if (blob.contains('office_documents')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.folder_shared_outlined,
        subtitle: 'Office project library',
        iconBg: Color(0xFF2A2040),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('receipts_and_agreements') ||
        (blob.contains('receipt') && blob.contains('agreement'))) {
      return const ClientPortalCategoryVisual(
        icon: Icons.receipt_long_outlined,
        subtitle: 'Receipts, agreements & tax invoices',
        iconBg: Color(0xFF143028),
        iconFg: Color(0xFF34D399),
      );
    }
    if (blob.contains('site_document') ||
        blob.contains('site document') ||
        blob.contains('site_inspection')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.fact_check_outlined,
        subtitle: 'Site inspection report',
        iconBg: Color(0xFF1F2937),
        iconFg: Color(0xFFFBBF24),
      );
    }
    if (blob.contains('planning_commercial') ||
        (blob.contains('planning') && blob.contains('commercial')) ||
        blob.contains('cost sheet')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.folder_special_outlined,
        subtitle: 'Final Cost Sheet',
        iconBg: Color(0xFF1E3A5F),
        iconFg: Color(0xFF93C5FD),
      );
    }
    if (blob.contains('kyc') || blob.contains('pre_conversion')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.badge_outlined,
        subtitle: 'KYC and other project documents',
        iconBg: Color(0xFF2A2040),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('floor_plan')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.architecture_outlined,
        subtitle: 'View floor plans and elevations',
        iconBg: Color(0xFF142830),
        iconFg: Color(0xFF67E8F9),
      );
    }
    if (blob.contains('architectural') || blob.contains('architecture')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.apartment_outlined,
        subtitle: 'Architectural drawings',
        iconBg: Color(0xFF2A2040),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('structural') || blob.contains('civil')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.account_tree_outlined,
        subtitle: 'Structural & civil drawings',
        iconBg: Color(0xFF143028),
        iconFg: Color(0xFF34D399),
      );
    }
    if (blob.contains('electrical')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.electrical_services_outlined,
        subtitle: 'Electrical layouts',
        iconBg: Color(0xFF2A2112),
        iconFg: Color(0xFFFBBF24),
      );
    }
    if (blob.contains('plumb')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.water_drop_outlined,
        subtitle: 'Plumbing drawings',
        iconBg: Color(0xFF142830),
        iconFg: Color(0xFF67E8F9),
      );
    }
    if (blob.contains('landscape') || blob.contains('planting')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.park_outlined,
        subtitle: 'Landscape documents',
        iconBg: Color(0xFF143028),
        iconFg: Color(0xFF34D399),
      );
    }
    if (blob.contains('fire') || blob.contains('safety')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.local_fire_department_outlined,
        subtitle: 'Fire & safety documents',
        iconBg: Color(0xFF2C1618),
        iconFg: Color(0xFFF87171),
      );
    }
    if (blob.contains('interior') || blob.contains('mep')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.weekend_outlined,
        subtitle: 'Interior & MEP documents',
        iconBg: Color(0xFF241A33),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('handover') || blob.contains('final document')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.handshake_outlined,
        subtitle: 'Handover & final documents',
        iconBg: Color(0xFF2A2040),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('cost') || blob.contains('variation')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.request_quote_outlined,
        subtitle: 'Cost variations',
        iconBg: Color(0xFF2A2112),
        iconFg: Color(0xFFFBBF24),
      );
    }
    if (blob.contains('design')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.auto_awesome_outlined,
        subtitle: 'Vastu, elevation refs & bylaws',
        iconBg: Color(0xFF241A33),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('gfc') || blob.contains('construction_drawings')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.domain_outlined,
        subtitle: 'Working drawings & elevations',
        iconBg: Color(0xFF2A2040),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (blob.contains('quality') || blob.contains('ndt')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.science_outlined,
        subtitle: 'NDT & construction test reports',
        iconBg: Color(0xFF143028),
        iconFg: Color(0xFF34D399),
      );
    }
    if (blob.contains('site_record') || blob.contains('site_construction')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.engineering_outlined,
        subtitle: 'Site marking, conduit marking & more',
        iconBg: Color(0xFF2A2112),
        iconFg: Color(0xFFFBBF24),
      );
    }
    if (blob.contains('door') || blob.contains('window') || blob.contains('grill')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.grid_view_rounded,
        subtitle: 'Designs and details',
        iconBg: Color(0xFF143028),
        iconFg: Color(0xFF34D399),
      );
    }
    if (blob.contains('site_prep')) {
      return ClientPortalCategoryVisual(
        icon: Icons.construction_outlined,
        subtitle: 'Demolition & borewell questionnaire',
        iconBg: Color(0xFF2A2112),
        iconFg: Color(0xFFFBBF24),
      );
    }
    if (blob.contains('demolition')) {
      return ClientPortalCategoryVisual(
        icon: Icons.home_work_outlined,
        subtitle: 'Demolition completion & comments',
        iconBg: Color(0xFF2C1618),
        iconFg: Color(0xFFF87171),
      );
    }
    if (blob.contains('inspection')) {
      return ClientPortalCategoryVisual(
        icon: Icons.fact_check_outlined,
        subtitle: 'Book a slot or view reports',
        iconBg: Color(0xFF142830),
        iconFg: Color(0xFF67E8F9),
      );
    }
    return null;
  }

  final namedIcon = iconDataFromCatalogName(iconName);
  final matched = fromKeywords();
  if (matched != null) {
    if (namedIcon == null) return matched;
    return ClientPortalCategoryVisual(
      icon: namedIcon,
      subtitle: matched.subtitle,
      iconBg: matched.iconBg,
      iconFg: matched.iconFg,
    );
  }

  return hashedCatalogVisual(
    seed: categoryId ?? journeyKey ?? label ?? iconName ?? 'category',
    subtitle: 'View documents in this category',
    iconOverride: namedIcon,
  );
}

/// Backend `icon` / `icon_name` strings → Material icons.
IconData? iconDataFromCatalogName(String? raw) {
  final key = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
  if (key.isEmpty) return null;
  const mapped = <String, IconData>{
    'architecture': Icons.architecture_outlined,
    'apartment': Icons.apartment_outlined,
    'domain': Icons.domain_outlined,
    'account_tree': Icons.account_tree_outlined,
    'electrical': Icons.electrical_services_outlined,
    'electrical_services': Icons.electrical_services_outlined,
    'plumbing': Icons.water_drop_outlined,
    'water_drop': Icons.water_drop_outlined,
    'park': Icons.park_outlined,
    'landscape': Icons.park_outlined,
    'fire': Icons.local_fire_department_outlined,
    'local_fire_department': Icons.local_fire_department_outlined,
    'science': Icons.science_outlined,
    'biotech': Icons.biotech_outlined,
    'engineering': Icons.engineering_outlined,
    'handshake': Icons.handshake_outlined,
    'receipt': Icons.receipt_long_outlined,
    'receipt_long': Icons.receipt_long_outlined,
    'folder': Icons.folder_open_outlined,
    'folder_shared': Icons.folder_shared_outlined,
    'description': Icons.description_outlined,
    'home_work': Icons.home_work_outlined,
    'weekend': Icons.weekend_outlined,
    'request_quote': Icons.request_quote_outlined,
  };
  return mapped[key];
}

List<ClientPortalCategoryVisual> kCatalogIconPalette = [
  ClientPortalCategoryVisual(
    icon: Icons.apartment_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF2A2040),
    iconFg: Color(0xFFC4B5FD),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.account_tree_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF143028),
    iconFg: Color(0xFF34D399),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.electrical_services_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF2A2112),
    iconFg: Color(0xFFFBBF24),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.water_drop_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF142830),
    iconFg: Color(0xFF67E8F9),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.park_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF143028),
    iconFg: Color(0xFF34D399),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.local_fire_department_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF2C1618),
    iconFg: Color(0xFFF87171),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.weekend_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF241A33),
    iconFg: Color(0xFFC4B5FD),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.science_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF143028),
    iconFg: Color(0xFF34D399),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.request_quote_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF2A2112),
    iconFg: Color(0xFFFBBF24),
  ),
  ClientPortalCategoryVisual(
    icon: Icons.handshake_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFF2A2040),
    iconFg: Color(0xFFC4B5FD),
  ),
];

int catalogVisualSeed(String value) {
  var hash = 0;
  for (final code in value.toLowerCase().codeUnits) {
    hash = 0x1fffffff & (hash * 31 + code);
  }
  return hash;
}

/// Stable colored icon for brand-new catalog categories (no hardcoded names).
ClientPortalCategoryVisual hashedCatalogVisual({
  required String seed,
  String subtitle = 'View documents in this category',
  IconData? iconOverride,
}) {
  final visual =
      kCatalogIconPalette[catalogVisualSeed(seed) % kCatalogIconPalette.length];
  return ClientPortalCategoryVisual(
    icon: iconOverride ?? visual.icon,
    subtitle: subtitle,
    iconBg: visual.iconBg,
    iconFg: visual.iconFg,
  );
}

ClientPortalCategoryVisual categoryVisualForCategory(
  WorkflowDocumentCategory category,
) {
  return categoryVisualFor(
    journeyKey: category.clientJourneyKey,
    categoryId: category.id,
    label: category.label,
    iconName: category.iconName,
  );
}

String catalogCategorySubtitle(WorkflowDocumentCategory category) {
  final types = substantiveDocumentSections(category)
      .map((section) => section.label.trim())
      .where((label) => label.isNotEmpty)
      .take(3)
      .toList();
  if (types.isNotEmpty) return types.join(', ');
  return categoryVisualForCategory(category).subtitle;
}

String _normFolderKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

String _folderStem(String normalized) {
  return normalized
      .replaceAll(
        RegExp(r'\b(documents?|reports?|docs?|and|the|test)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when two folder names are the same label with punctuation / filler
/// words ignored (e.g. "Quality & Test Reports" ≈ "Quality and test report").
bool folderKeysLookSame(String a, String b) {
  final left = _normFolderKey(a);
  final right = _normFolderKey(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  if (left.replaceAll(' ', '') == right.replaceAll(' ', '')) return true;
  final stemL = _folderStem(left);
  final stemR = _folderStem(right);
  return stemL.isNotEmpty && stemR.isNotEmpty && stemL == stemR;
}

/// Section that only repeats the parent category name (Quality → Quality).
bool sectionMirrorsDocumentCategory(
  WorkflowDocumentSection section,
  WorkflowDocumentCategory category,
) {
  if (section.label.trim().isEmpty) return true;
  return folderKeysLookSame(section.label, category.label) ||
      folderKeysLookSame(section.id, category.id) ||
      folderKeysLookSame(section.label, category.id) ||
      folderKeysLookSame(section.id, category.label);
}

/// Real child folders only — drops mirrored category-named sections.
List<WorkflowDocumentSection> substantiveDocumentSections(
  WorkflowDocumentCategory category,
) {
  final sections = category.sections;
  if (sections.length <= 1) return sections;
  final trimmed = sections
      .where((section) => !sectionMirrorsDocumentCategory(section, category))
      .toList();
  return trimmed.isEmpty ? sections : trimmed;
}

ClientPortalCategoryVisual sectionVisualFor(WorkflowDocumentSection section) {
  final label = section.label.toLowerCase();
  final id = section.id.toLowerCase();
  final categoryKey =
      (section.clientJourneyKey ?? section.categoryId).toLowerCase();

  if (categoryKey == 'receipts_and_agreements') {
    if (id == 'receipts' || label == 'receipts') {
      return const ClientPortalCategoryVisual(
        icon: Icons.receipt_long_outlined,
        subtitle: 'Payment receipts',
        iconBg: Color(0xFF143028),
        iconFg: Color(0xFF34D399),
      );
    }
    if (id == 'agreements' || label == 'agreements') {
      return const ClientPortalCategoryVisual(
        icon: Icons.handshake_outlined,
        subtitle: 'Signed agreements',
        iconBg: Color(0xFF2A2040),
        iconFg: Color(0xFFC4B5FD),
      );
    }
    if (id.contains('tax_invoice') || label.contains('tax invoice')) {
      return const ClientPortalCategoryVisual(
        icon: Icons.request_quote_outlined,
        subtitle: 'Tax invoices',
        iconBg: Color(0xFF2A2112),
        iconFg: Color(0xFFFBBF24),
      );
    }
  }
  if (categoryKey == 'office_documents') {
    return const ClientPortalCategoryVisual(
      icon: Icons.folder_shared_outlined,
      subtitle: 'Office project library',
      iconBg: Color(0xFF2A2040),
      iconFg: Color(0xFFC4B5FD),
    );
  }

  if (label.contains('architectural') || id.contains('architectural')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.apartment_outlined,
      subtitle: 'Floor plans, elevations, working drawings',
      iconBg: Color(0xFF2A2040),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (label.contains('structural') || id.contains('structural')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.account_tree_outlined,
      subtitle: 'Foundation, framing & structural details',
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (label.contains('electrical') || id.contains('electrical')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.electrical_services_outlined,
      subtitle: 'Electrical layouts & wiring diagrams',
      iconBg: Color(0xFF2A2112),
      iconFg: Color(0xFFFBBF24),
    );
  }
  if (label.contains('soil') || id.contains('soil')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.science_outlined,
      subtitle: 'Soil investigation reports',
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (label.contains('qc') ||
      id.contains('qc') ||
      label.contains('ndt') ||
      id.contains('ndt')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.biotech_outlined,
      subtitle: 'Non-destructive test reports',
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (label.contains('site inspection') ||
      id.contains('site_inspection') ||
      id.contains('sipr') ||
      label.contains('sipr')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.fact_check_outlined,
      subtitle: 'Site inspection reports',
      iconBg: Color(0xFF2A2112),
      iconFg: Color(0xFFFBBF24),
    );
  }
  if (label == 'site document' ||
      id == 'site_document' ||
      (label.contains('site document') || id.contains('site_document'))) {
    return const ClientPortalCategoryVisual(
      icon: Icons.description_outlined,
      subtitle: 'Site documents',
      iconBg: Color(0xFF142830),
      iconFg: Color(0xFF67E8F9),
    );
  }
  if (label.contains('framing') || id.contains('framing')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.account_tree_outlined,
      subtitle: 'Framing drawings',
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (label.contains('foundation') || label.contains('plinth')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.foundation_outlined,
      subtitle: 'Foundation drawings',
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (label.contains('working drawing') || id.contains('working_drawing')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.architecture_outlined,
      subtitle: 'Working drawings',
      iconBg: Color(0xFF2A2040),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (label.contains('floor plan') || id.contains('floor_plan')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.apartment_outlined,
      subtitle: 'Floor plan drawings',
      iconBg: Color(0xFF2A2040),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (label.contains('proposal') || id.contains('proposal')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.description_outlined,
      subtitle: 'Project proposal',
      iconBg: Color(0xFF2A2040),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (label.contains('booking') || id.contains('booking')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.bookmark_added_outlined,
      subtitle: 'Booking forms',
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (label.contains('site marking') || id.contains('site_marking')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.location_on_outlined,
      subtitle: 'Site marking records & photos',
      iconBg: Color(0xFF2A2112),
      iconFg: Color(0xFFFBBF24),
    );
  }
  if (label.contains('conduit') || label.contains('mep') || id.contains('conduit')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.cable_outlined,
      subtitle: 'Conduit & MEP marking records',
      iconBg: Color(0xFF142830),
      iconFg: Color(0xFF67E8F9),
    );
  }
  if (label.contains('vastu')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.auto_awesome_outlined,
      subtitle: 'Vastu design documents',
      iconBg: Color(0xFF241A33),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (label.contains('elevation') && label.contains('reference')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.image_outlined,
      subtitle: 'Elevation reference designs',
      iconBg: Color(0xFF142830),
      iconFg: Color(0xFF67E8F9),
    );
  }
  if (label.contains('bylaw')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.gavel_outlined,
      subtitle: 'Bylaw compliance documents',
      iconBg: Color(0xFF2A2112),
      iconFg: Color(0xFFFBBF24),
    );
  }
  if (label.contains('floor plan') || label.contains('elevation')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.architecture_outlined,
      subtitle: 'Plans and elevation drawings',
      iconBg: Color(0xFF142830),
      iconFg: Color(0xFF67E8F9),
    );
  }

  return categoryVisualFor(
    journeyKey: section.clientJourneyKey,
    categoryId: section.categoryId,
    label: section.label,
  );
}

int workflowDocCountForJourney(
  WorkflowDocumentLibrary? library,
  String journeyKey,
) {
  if (library == null) return 0;
  return library
      .sectionsForJourney(journeyKey)
      .fold<int>(0, (sum, section) => sum + section.documentCount);
}

int workflowDocCountForCategory(WorkflowDocumentCategory category) {
  // Multi-file folders / sections can have several PDFs under one key —
  // count every row, not only "latest".
  return category.sections.fold<int>(0, (sum, section) {
    if (isMultiFileDocumentCategory(category) ||
        isMultiFileDocumentSection(section)) {
      return sum + section.documents.length;
    }
    return sum + section.documentCount;
  });
}

class ClientPortalSectionHeading extends StatelessWidget {
  final String label;

  const ClientPortalSectionHeading({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: AppTheme.mutedGrey,
        ),
      ),
    );
  }
}

class ClientPortalSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;

  const ClientPortalSearchBar({
    super.key,
    required this.controller,
    this.hint = 'Search documents…',
    this.onClear,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppTheme.getTextSecondary(context),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppTheme.getTextSecondary(context),
          size: 22,
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onClear ?? () => controller.clear(),
              )
            : null,
        filled: true,
        fillColor: AppTheme.darkBackgroundPrimaryLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
          borderSide: const BorderSide(
            color: ClientPortalDocTheme.accentBlue,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class ClientPortalCountBadge extends StatelessWidget {
  final int count;

  const ClientPortalCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? const Color(0xFF3A2A55)
            : ClientPortalDocTheme.accentBlue.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: AppTheme.isDark ? ClientPortalDocTheme.accentBlue : AppTheme.navy,
        ),
      ),
    );
  }
}

enum ClientPortalStatusBadgeKind { latest, verified, superseded, optional, pending }

class ClientPortalStatusBadge extends StatelessWidget {
  final ClientPortalStatusBadgeKind kind;

  const ClientPortalStatusBadge({super.key, required this.kind});

  static ClientPortalStatusBadgeKind fromStatus(
    String? status, {
    required bool isLatest,
    bool hasUrl = false,
  }) {
    final normalized = status?.trim().toLowerCase() ?? '';
    if (normalized == 'verified') return ClientPortalStatusBadgeKind.verified;
    if (normalized == 'superseded' || normalized == 'older') {
      return ClientPortalStatusBadgeKind.superseded;
    }
    // Catalog rows often stay "pending"/"required" even after a file exists.
    // If there is a URL, never show Pending — match For Me / openable state.
    final catalogPending = normalized == 'pending' ||
        normalized == 'missing' ||
        normalized == 'inactive' ||
        normalized == 'required' ||
        normalized == 'mandatory';
    if (catalogPending && !hasUrl) {
      return ClientPortalStatusBadgeKind.pending;
    }
    if (normalized == 'optional' && !hasUrl) {
      return ClientPortalStatusBadgeKind.optional;
    }
    if (normalized == 'latest' ||
        normalized == 'uploaded' ||
        normalized == 'available' ||
        hasUrl ||
        isLatest) {
      return ClientPortalStatusBadgeKind.latest;
    }
    return isLatest
        ? ClientPortalStatusBadgeKind.latest
        : ClientPortalStatusBadgeKind.superseded;
  }

  @override
  Widget build(BuildContext context) {
    late Color darkBg;
    late Color accent;
    late String label;
    switch (kind) {
      case ClientPortalStatusBadgeKind.latest:
        darkBg = const Color(0xFF143028);
        accent = const Color(0xFF34D399);
        label = 'Latest';
        break;
      case ClientPortalStatusBadgeKind.verified:
        darkBg = const Color(0xFF143028);
        accent = const Color(0xFF34D399);
        label = 'Verified';
        break;
      case ClientPortalStatusBadgeKind.superseded:
        darkBg = const Color(0xFF2A2A2D);
        accent = AppTheme.mutedGrey;
        label = 'Superseded';
        break;
      case ClientPortalStatusBadgeKind.optional:
        darkBg = const Color(0xFF2A2A2D);
        accent = AppTheme.mutedGrey;
        label = 'Optional';
        break;
      case ClientPortalStatusBadgeKind.pending:
        darkBg = const Color(0xFF2A2112);
        accent = const Color(0xFFFBBF24);
        label = 'Pending';
        break;
    }
    final bg = AppTheme.isDark
        ? darkBg
        : accent.withValues(alpha: 0.16);
    final fg = AppTheme.isDark ? accent : AppTheme.iconBoxInk(accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class ClientPortalCategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int badgeCount;
  final VoidCallback onTap;
  final Color? iconBg;
  final Color? iconFg;
  final bool journeyStyle;

  const ClientPortalCategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badgeCount,
    required this.onTap,
    this.iconBg,
    this.iconFg,
    this.journeyStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ClientPortalDocTheme.cardBackground,
      borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: journeyStyle ? 16 : 13,
          ),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Row(
            children: [
              Container(
                width: journeyStyle ? 48 : 44,
                height: journeyStyle ? 48 : 44,
                decoration: BoxDecoration(
                  color: AppTheme.iconBoxFill(
                    iconBg ?? const Color(0xFF2A2040),
                    iconFg ?? AppTheme.accentBlue,
                  ),
                  borderRadius:
                      BorderRadius.circular(ClientPortalDocTheme.iconBoxRadius),
                ),
                child: Icon(
                  icon,
                  color: iconFg == null
                      ? AppTheme.textPrimary
                      : AppTheme.iconBoxInk(iconFg!),
                  size: journeyStyle ? 24 : 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: journeyStyle ? 15 : 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkTextPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppTheme.getTextSecondary(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (journeyStyle && badgeCount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 14,
                            color: AppTheme.getTextSecondary(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$badgeCount Document${badgeCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.getTextSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!journeyStyle) ...[
                ClientPortalCountBadge(count: badgeCount),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.getTextSecondary(context),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClientPortalSectionCard extends StatelessWidget {
  final WorkflowDocumentSection section;
  final VoidCallback onTap;
  final String? viewerRole;

  const ClientPortalSectionCard({
    super.key,
    required this.section,
    required this.onTap,
    this.viewerRole,
  });

  @override
  Widget build(BuildContext context) {
    final visual = sectionVisualFor(section);
    var visibleDocs = sectionWithMobileVisibleDocuments(section).documents;
    final role = viewerRole?.trim();
    if (role != null && role.isNotEmpty) {
      visibleDocs = visibleDocs
          .where(
            (doc) => documentAccessForUpload(
              catalogVisibilityRole(role),
              doc,
            ).view,
          )
          .toList();
    }
    return ClientPortalCategoryCard(
      icon: visual.icon,
      title: section.label,
      subtitle: visual.subtitle,
      // Same rows the folder list will show (after access filter).
      badgeCount: visibleDocs.length,
      iconBg: visual.iconBg,
      iconFg: visual.iconFg,
      journeyStyle: true,
      onTap: onTap,
    );
  }
}

class ClientPortalFilterTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  const ClientPortalFilterTabs({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
    this.labels = const ['All', 'Latest', 'Others'],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (index) {
        final selected = index == selectedIndex;
        return Padding(
          padding: EdgeInsets.only(right: index < labels.length - 1 ? 20 : 0),
          child: InkWell(
            onTap: () => onChanged(index),
            borderRadius: BorderRadius.circular(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labels[index],
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 14,
                    color: selected
                        ? AppTheme.darkTextPrimary
                        : AppTheme.mutedGrey,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2.5,
                  width: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? ClientPortalDocTheme.accentBlue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class ClientPortalDocumentListHeader extends StatelessWidget {
  final int count;
  final ClientPortalDocumentSort sort;
  final ValueChanged<ClientPortalDocumentSort> onSortChanged;

  const ClientPortalDocumentListHeader({
    super.key,
    required this.count,
    required this.sort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$count Document${count == 1 ? '' : 's'}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppTheme.darkTextPrimary,
          ),
        ),
        const Spacer(),
        ClientPortalSortButton(value: sort, onChanged: onSortChanged),
      ],
    );
  }
}

class ClientPortalDocumentRow extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final bool showVerifiedBadge;
  final bool showThumbnail;
  final VoidCallback onTap;
  final VoidCallback? onMenuTap;
  final VoidCallback? onPressStart;

  const ClientPortalDocumentRow({
    super.key,
    required this.document,
    this.showVerifiedBadge = false,
    this.showThumbnail = false,
    required this.onTap,
    this.onMenuTap,
    this.onPressStart,
  });

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (document.displayRevision.isNotEmpty) document.displayRevision,
      if (document.uploadedAt != null) document.uploadedAt,
      if (document.fileSize != null) document.fileSize,
    ].join(' · ');

    final badgeKind = showVerifiedBadge && document.isVerifiedStatus
        ? ClientPortalStatusBadgeKind.verified
        : ClientPortalStatusBadge.fromStatus(
            document.displayStatus,
            isLatest: document.isLatest,
            hasUrl: document.hasUrl,
          );

    return Material(
      color: ClientPortalDocTheme.cardBackground,
      borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        onTapDown: onPressStart == null ? null : (_) => onPressStart!(),
        borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeadingPreview(
                document: document,
                showThumbnail: showThumbnail,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.darkTextPrimary,
                        height: 1.25,
                      ),
                    ),
                    if (document.displaySubtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        document.displaySubtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (document.isLatest ||
                      document.isVerifiedStatus ||
                      (document.status?.trim().isNotEmpty == true) ||
                      !document.hasUrl)
                    ClientPortalStatusBadge(kind: badgeKind),
                  const SizedBox(height: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppTheme.getTextSecondary(context),
                    ),
                    onPressed: onMenuTap ?? onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingPreview extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final bool showThumbnail;

  const _LeadingPreview({
    required this.document,
    required this.showThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    if (showThumbnail && document.isImage && document.hasUrl) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: document.url!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _iconBox(document),
        ),
      );
    }
    return _iconBox(document);
  }

  Widget _iconBox(WorkflowDocumentUpload document) {
    if (document.isPdf) {
      return _fileTypeIcon(
        icon: Icons.picture_as_pdf_rounded,
        darkBg: const Color(0xFF2C1618),
        accent: const Color(0xFFF87171),
        size: 40,
        iconSize: 22,
        radius: 10,
      );
    }
    final accent = document.isImage
        ? const Color(0xFF34D399)
        : const Color(0xFFC4B5FD);
    final darkBg = document.isImage
        ? const Color(0xFF143028)
        : const Color(0xFF2A2040);
    return _fileTypeIcon(
      icon: document.isImage
          ? Icons.image_outlined
          : Icons.description_outlined,
      darkBg: darkBg,
      accent: accent,
      size: 40,
      iconSize: 20,
      radius: 10,
    );
  }
}

class ClientPortalInfoBanner extends StatelessWidget {
  final String message;

  const ClientPortalInfoBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? const Color(0xFF241A33)
            : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.isDark
              ? const Color(0xFF3A2A55)
              : const Color(0xFFDDD6FE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: ClientPortalDocTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.getTextSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClientPortalScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const ClientPortalScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.darkTextPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
        ],
      ],
    );
  }
}

enum ClientPortalDocumentSort { newest, oldest, nameAz }

class ClientPortalSortButton extends StatelessWidget {
  final ClientPortalDocumentSort value;
  final ValueChanged<ClientPortalDocumentSort> onChanged;

  const ClientPortalSortButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ClientPortalDocumentSort>(
      initialValue: value,
      onSelected: onChanged,
      offset: const Offset(0, 36),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_vert_rounded,
            size: 18,
            color: AppTheme.getTextSecondary(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Sort',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
      itemBuilder: (context) => ClientPortalDocumentSort.values
          .map(
            (sort) => PopupMenuItem(
              value: sort,
              child: Text(_label(sort)),
            ),
          )
          .toList(),
    );
  }

  String _label(ClientPortalDocumentSort sort) {
    switch (sort) {
      case ClientPortalDocumentSort.newest:
        return 'Newest first';
      case ClientPortalDocumentSort.oldest:
        return 'Oldest first';
      case ClientPortalDocumentSort.nameAz:
        return 'Name A–Z';
    }
  }
}

List<WorkflowDocumentUpload> sortWorkflowDocuments(
  List<WorkflowDocumentUpload> docs,
  ClientPortalDocumentSort sort,
) {
  final copy = [...docs];
  switch (sort) {
    case ClientPortalDocumentSort.nameAz:
      copy.sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
      break;
    case ClientPortalDocumentSort.oldest:
      copy.sort((a, b) => (a.uploadedAt ?? '').compareTo(b.uploadedAt ?? ''));
      break;
    case ClientPortalDocumentSort.newest:
      copy.sort((a, b) => (b.uploadedAt ?? '').compareTo(a.uploadedAt ?? ''));
      break;
  }
  return copy;
}

List<WorkflowDocumentSection> filterWorkflowSectionsBySearch(
  List<WorkflowDocumentSection> sections,
  String query,
) {
  final q = query.trim();
  if (q.isEmpty) return sections;
  final lower = q.toLowerCase();
  return sections.where((section) {
    if (section.label.toLowerCase().contains(lower)) return true;
    return section.latestDocuments.any((doc) => doc.matchesSearch(q));
  }).toList();
}

/// Architectural category in Docs / For Me.
bool isArchitecturalDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  return blob.contains('architectural') || blob.contains('architecture');
}

bool isClientPortalFinalDocument(WorkflowDocumentUpload doc) {
  if (doc.isLatest) return true;
  final status = (doc.status ?? '').trim().toLowerCase();
  return status == 'final' ||
      status == 'finalized' ||
      status == 'latest';
}

bool isClientPortalArchitecturalGroupedSection(WorkflowDocumentSection section) {
  final id = section.id.trim().toLowerCase();
  final label = section.label.trim().toLowerCase();
  return id == 'final' ||
      id == 'revisions' ||
      label == 'final' ||
      label == 'revisions' ||
      _architecturalTypeDefs.any(
        (type) => type.id == id || type.label.toLowerCase() == label,
      );
}

class _ArchitecturalTypeDef {
  const _ArchitecturalTypeDef({
    required this.id,
    required this.label,
    required this.matches,
  });

  final String id;
  final String label;
  final bool Function(String blob) matches;
}

/// Canonical Architectural document types (office checklist order).
const List<_ArchitecturalTypeDef> _architecturalTypeDefs = [
  _ArchitecturalTypeDef(
    id: 'final_floor_plan',
    label: 'Final Floor plan',
    matches: _matchFinalFloorPlan,
  ),
  _ArchitecturalTypeDef(
    id: 'working_drawing',
    label: 'Working drawing',
    matches: _matchWorkingDrawing,
  ),
  _ArchitecturalTypeDef(
    id: 'filler_slab',
    label: 'Filler slab detail (if any)',
    matches: _matchFillerSlab,
  ),
  _ArchitecturalTypeDef(
    id: 'section',
    label: 'Section',
    matches: _matchSection,
  ),
  _ArchitecturalTypeDef(
    id: 'final_elevation',
    label: 'Final Elevation',
    matches: _matchFinalElevation,
  ),
  _ArchitecturalTypeDef(
    id: '2d_elevation',
    label: '2D Elevation',
    matches: _match2dElevation,
  ),
  _ArchitecturalTypeDef(
    id: 'door_window_grill',
    label: 'Door/Window/ grill detail',
    matches: _matchDoorWindowGrill,
  ),
  _ArchitecturalTypeDef(
    id: 'flooring_details',
    label: 'Flooring details',
    matches: _matchFlooring,
  ),
  _ArchitecturalTypeDef(
    id: 'dado_detail',
    label: 'Dado Detail - Kitchen/toilet',
    matches: _matchDado,
  ),
  _ArchitecturalTypeDef(
    id: 'fabrication_detail',
    label: 'Fabrication Detail',
    matches: _matchFabrication,
  ),
  _ArchitecturalTypeDef(
    id: 'skylight_detail',
    label: 'Skylight detail',
    matches: _matchSkylight,
  ),
  _ArchitecturalTypeDef(
    id: 'paint_shade',
    label: 'Paint shade',
    matches: _matchPaintShade,
  ),
  _ArchitecturalTypeDef(
    id: 'final_area_statement',
    label: 'Final Area statement',
    matches: _matchAreaStatement,
  ),
];

bool _matchAreaStatement(String blob) => blob.contains('area statement');

bool _matchFinalFloorPlan(String blob) =>
    blob.contains('floor plan') || blob.contains('floor_plan');

bool _matchWorkingDrawing(String blob) =>
    blob.contains('working draw') ||
    blob.contains('working_drawing') ||
    blob.contains('workingdrawing');

bool _matchFillerSlab(String blob) =>
    blob.contains('filler slab') || blob.contains('filler_slab');

bool _matchSection(String blob) {
  if (_matchAreaStatement(blob) ||
      _matchFinalFloorPlan(blob) ||
      _matchWorkingDrawing(blob) ||
      _matchFillerSlab(blob)) {
    return false;
  }
  return RegExp(r'\bsection\b').hasMatch(blob) ||
      blob.contains('section.pdf') ||
      blob.contains('section_');
}

bool _match2dElevation(String blob) =>
    blob.contains('2d elevation') ||
    blob.contains('2 d elevation') ||
    blob.contains('2d_elevation');

bool _matchFinalElevation(String blob) {
  if (_match2dElevation(blob)) return false;
  return blob.contains('elevation');
}

bool _matchDoorWindowGrill(String blob) =>
    blob.contains('door') ||
    blob.contains('window') ||
    blob.contains('grill');

bool _matchFlooring(String blob) => blob.contains('flooring');

bool _matchDado(String blob) => blob.contains('dado');

bool _matchFabrication(String blob) => blob.contains('fabrication');

bool _matchSkylight(String blob) => blob.contains('skylight');

bool _matchPaintShade(String blob) =>
    blob.contains('paint shade') ||
    blob.contains('paint_shade') ||
    (blob.contains('paint') && !blob.contains('repaint'));

String _architecturalDocBlob(WorkflowDocumentUpload doc) {
  return '${doc.sectionId} ${doc.documentKey} ${doc.name} ${doc.sectionLabel} ${doc.taskName ?? ''} ${doc.url ?? ''}'
      .toLowerCase();
}

/// Prefer the checklist section id so a file named cost_sheet.pdf still lands
/// in Final Elevation / Soil / etc. instead of being dropped as unmatched.
_ArchitecturalTypeDef? _typeForSectionId(
  String sectionId,
  List<_ArchitecturalTypeDef> types,
) {
  final id = sectionId.trim().toLowerCase();
  if (id.isEmpty) return null;
  const aliases = <String, String>{
    'filler_slab_detail': 'filler_slab',
    'elevation_2d': '2d_elevation',
    '2d_elevation': '2d_elevation',
  };
  final resolved = aliases[id] ?? id;
  for (final type in types) {
    if (type.id == resolved || type.id == id) return type;
  }
  return null;
}

_ArchitecturalTypeDef? _architecturalTypeForDoc(WorkflowDocumentUpload doc) {
  final bySection = _typeForSectionId(doc.sectionId, _architecturalTypeDefs);
  if (bySection != null) return bySection;
  final blob = _architecturalDocBlob(doc);
  for (final type in _architecturalTypeDefs) {
    if (type.matches(blob)) return type;
  }
  return null;
}

/// Groups Architectural uploads into the 13 checklist type folders.
/// Multiple uploads of the same type stay together under that section name.
List<WorkflowDocumentSection> buildArchitecturalTypeSections(
  WorkflowDocumentCategory category, {
  bool hideAreaStatement = false,
}) {
  final buckets = <String, List<WorkflowDocumentUpload>>{
    for (final type in _architecturalTypeDefs) type.id: <WorkflowDocumentUpload>[],
  };
  final seen = <String>{};

  for (final section in category.sections) {
    for (final doc in section.documents) {
      if (hideAreaStatement && doc.isAreaStatement) continue;
      final dedupe = [
        doc.id,
        doc.url ?? '',
        doc.documentKey,
        doc.revision?.toString() ?? '',
        doc.name,
      ].join('|').toLowerCase();
      if (!seen.add(dedupe)) continue;
      final type = _architecturalTypeForDoc(doc);
      if (type == null) continue;
      if (hideAreaStatement && type.id == 'final_area_statement') continue;
      buckets[type.id]!.add(doc);
    }
  }

  return [
    for (final type in _architecturalTypeDefs)
      if (!(hideAreaStatement && type.id == 'final_area_statement'))
        _checklistFolderWithPeers(
          WorkflowDocumentSection(
            id: type.id,
            label: type.label,
            categoryId: category.id,
            categoryLabel: category.label,
            clientJourneyKey: category.clientJourneyKey,
            libraryGroupKey: category.libraryGroupKey,
            documents: buckets[type.id] ?? const [],
          ),
        ),
  ];
}

WorkflowDocumentSection _architecturalGroupedSection({
  required WorkflowDocumentCategory category,
  required String id,
  required String label,
  required bool Function(WorkflowDocumentUpload doc) include,
  required String Function(WorkflowDocumentUpload doc) dedupeKey,
}) {
  final docs = <WorkflowDocumentUpload>[];
  final seen = <String>{};
  for (final section in category.sections) {
    for (final doc in section.documents) {
      if (!include(doc)) continue;
      if (!seen.add(dedupeKey(doc))) continue;
      docs.add(doc);
    }
  }
  return WorkflowDocumentSection(
    id: id,
    label: label,
    categoryId: category.id,
    categoryLabel: category.label,
    clientJourneyKey: category.clientJourneyKey,
    libraryGroupKey: category.libraryGroupKey,
    documents: docs,
  );
}

/// Legacy Final aggregate (tests / older callers).
WorkflowDocumentSection buildClientPortalArchitecturalFinalSection(
  WorkflowDocumentCategory category,
) {
  return _architecturalGroupedSection(
    category: category,
    id: 'final',
    label: 'Final',
    include: isClientPortalFinalDocument,
    dedupeKey: (doc) =>
        doc.documentKey.isNotEmpty ? doc.documentKey : doc.id,
  );
}

/// Legacy Revisions aggregate (tests / older callers).
WorkflowDocumentSection buildClientPortalArchitecturalRevisionsSection(
  WorkflowDocumentCategory category,
) {
  return _architecturalGroupedSection(
    category: category,
    id: 'revisions',
    label: 'Revisions',
    include: (doc) => !isClientPortalFinalDocument(doc),
    dedupeKey: (doc) {
      if (doc.id.isNotEmpty) return doc.id;
      return '${doc.documentKey}|${doc.revision ?? ''}|${doc.url ?? ''}|${doc.name}';
    },
  );
}

List<WorkflowDocumentSection> clientPortalArchitecturalSections(
  WorkflowDocumentCategory category,
  String query, {
  bool hideAreaStatement = false,
}) {
  final sections = buildArchitecturalTypeSections(
    category,
    hideAreaStatement: hideAreaStatement,
  );
  final q = query.trim();
  if (q.isEmpty) return sections;
  return sections
      .map(
        (section) => section.copyWithDocuments(
          section.documents.where((doc) => doc.matchesSearch(q)).toList(),
        ),
      )
      .where(
        (section) =>
            section.documents.isNotEmpty ||
            section.label.toLowerCase().contains(q.toLowerCase()),
      )
      .toList();
}

/// Flat file list under Architectural (legacy). Prefer type sections.
WorkflowDocumentSection buildClientPortalArchitecturalDocumentsSection(
  WorkflowDocumentCategory category,
) {
  return _flatCategoryDocumentsSection(category);
}

bool _mapTruthy(dynamic raw) {
  if (raw == true || raw == 1 || raw == '1') return true;
  final text = raw?.toString().trim().toLowerCase();
  return text == 'true' || text == 'yes';
}

bool? _truthyFlag(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty || text == 'null') return null;
  if (text == 'true' || text == 'yes' || text == '1') return true;
  if (text == 'false' || text == 'no' || text == '0') return false;
  return null;
}

/// Office "versions" checkbox / share flags (checked = show in app).
///
/// Checklist Original (`is_primary`) and `show_on_mobile` must win over generic
/// `selected`/`checked` fields — those were hiding Original on Plumbing/Soil.
bool? documentVersionExplicitVisibility(Map<String, dynamic> raw) {
  if (_mapTruthy(raw['is_primary'])) return true;
  if (raw.containsKey('show_on_mobile')) {
    final mobile = _truthyFlag(raw['show_on_mobile']);
    if (mobile != null) return mobile;
  }
  for (final key in const [
    'checked',
    'is_checked',
    'selected',
    'is_selected',
    'show_in_app',
    'show_on_app',
    'show_in_mobile',
    'visible_in_app',
    'client_visible',
    'visible_to_client',
    'is_visible',
    'include_in_app',
    'share_to_client',
    'shared_to_client',
    'is_shared',
    'app_visible',
    'mobile_visible',
    'show_to_client',
  ]) {
    if (!raw.containsKey(key)) continue;
    final parsed = _truthyFlag(raw[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

/// Checklist folder peers (Original + ticked extras) must not share one
/// version-family key or the app keeps only the newest upload.
bool _isChecklistPeerDocument(WorkflowDocumentUpload doc) {
  final raw = doc.raw;
  if (_mapTruthy(raw['is_primary']) || _mapTruthy(raw['show_on_mobile'])) {
    return true;
  }
  final fileKey = (raw['file_key'] ?? '').toString().trim().toLowerCase();
  if (fileKey.startsWith('slot:')) return true;
  final key = doc.documentKey.trim().toLowerCase();
  return key.startsWith('checklist:') || key.startsWith('slot:');
}

bool _documentIsCurrentVersion(WorkflowDocumentUpload doc) {
  if (doc.isLatest) return true;
  final raw = doc.raw;
  if (_mapTruthy(raw['is_current']) ||
      _mapTruthy(raw['current']) ||
      _mapTruthy(raw['is_active_version'])) {
    return true;
  }
  final status = (doc.status ?? '').trim().toLowerCase();
  return status == 'current' || status == 'latest' || status == 'final';
}

String _versionGroupKey(WorkflowDocumentUpload doc) {
  var key = doc.documentKey.trim().toLowerCase();
  if (key.isEmpty) key = doc.name.trim().toLowerCase();
  key = key
      .replaceAll(RegExp(r'(_|-)?v(er(sion)?)?\d+$'), '')
      .replaceAll(RegExp(r'(_|-)?rev(ision)?\d+$'), '')
      .replaceAll(RegExp(r'\s+v(er(sion)?)?\s*\d+$'), '')
      .trim();
  return key.isEmpty ? doc.id : key;
}

/// Never collapse an entire folder into one version family.
///
/// Docs + For Me both regroup into type folders (Architectural 13, Structural
/// 3, …). Folding the whole folder hid every extra file (filler slab, section,
/// elevation, framing sets, …). Revisions of the *same* drawing are still
/// collapsed via [_versionGroupKey] + checked / latest filtering below.
bool _sectionIsSingleVersionFamily(WorkflowDocumentSection section) => false;

/// Versions the office checked for mobile, plus current/latest when unchecked
/// flags are absent. Hides superseded / unchecked rows (fixes Framing ×3).
List<WorkflowDocumentUpload> filterDocumentsForMobileDisplay(
  List<WorkflowDocumentUpload> documents, {
  bool keepAllMultiFilePeers = false,
  bool singleVersionFamily = false,
}) {
  if (documents.isEmpty) return const [];

  final byKey = <String, List<WorkflowDocumentUpload>>{};
  if (singleVersionFamily && !keepAllMultiFilePeers) {
    byKey['__family__'] = List<WorkflowDocumentUpload>.from(documents);
  } else {
    for (final doc in documents) {
      // Original + each ticked checklist file is its own row (never one family).
      final key = (keepAllMultiFilePeers || _isChecklistPeerDocument(doc))
          ? (doc.id.isNotEmpty
              ? doc.id
              : ((doc.url ?? '').isNotEmpty ? doc.url! : doc.documentKey))
          : _versionGroupKey(doc);
      byKey.putIfAbsent(key, () => <WorkflowDocumentUpload>[]).add(doc);
    }
  }

  final out = <WorkflowDocumentUpload>[];
  final seenUrls = <String>{};

  for (final group in byKey.values) {
    final hasExplicit = group.any(
      (doc) => documentVersionExplicitVisibility(doc.raw) != null,
    );
    List<WorkflowDocumentUpload> chosen;
    if (hasExplicit) {
      chosen = group.where((doc) {
        final visibility = documentVersionExplicitVisibility(doc.raw);
        if (visibility == false) return false;
        if (visibility == true) return true;
        return _documentIsCurrentVersion(doc);
      }).toList();
    } else if (keepAllMultiFilePeers ||
        group.any(_isChecklistPeerDocument)) {
      chosen = group.where((doc) {
        final status = (doc.status ?? '').trim().toLowerCase();
        return status != 'superseded' && status != 'older';
      }).toList();
      if (chosen.isEmpty) {
        chosen = List<WorkflowDocumentUpload>.from(group);
      }
    } else {
      chosen = group.where(_documentIsCurrentVersion).toList();
      if (chosen.length > 1) {
        final sorted = List<WorkflowDocumentUpload>.from(chosen)
          ..sort((a, b) {
            final ar = a.revision ?? 0;
            final br = b.revision ?? 0;
            if (ar != br) return br.compareTo(ar);
            return (b.uploadedAt ?? '').compareTo(a.uploadedAt ?? '');
          });
        chosen = [sorted.first];
      } else if (chosen.isEmpty) {
        final sorted = List<WorkflowDocumentUpload>.from(group)
          ..sort((a, b) {
            final ar = a.revision ?? 0;
            final br = b.revision ?? 0;
            if (ar != br) return br.compareTo(ar);
            return (b.uploadedAt ?? '').compareTo(a.uploadedAt ?? '');
          });
        chosen = [sorted.first];
      }
    }

    for (final doc in chosen) {
      final url = (doc.url ?? '').trim().toLowerCase();
      if (url.isNotEmpty && !seenUrls.add(url)) continue;
      out.add(doc);
    }
  }
  return out;
}

/// Checklist type folders (Final Elevation, Soil, Plumbing, …): always keep
/// Original + every ticked peer. Do not collapse to the newest upload only.
WorkflowDocumentSection _checklistFolderWithPeers(
  WorkflowDocumentSection section,
) {
  return section.copyWithDocuments(
    filterDocumentsForMobileDisplay(
      section.documents,
      keepAllMultiFilePeers: true,
      singleVersionFamily: false,
    ),
  );
}

WorkflowDocumentSection sectionWithMobileVisibleDocuments(
  WorkflowDocumentSection section,
) {
  // Architectural Final Elevation, Plumbing, Soil, etc. — keep every
  // checklist Original + ticked peer, not only the newest revision.
  final keepPeers = isMultiFileDocumentSection(section) ||
      section.documents.any(_isChecklistPeerDocument);
  return section.copyWithDocuments(
    filterDocumentsForMobileDisplay(
      section.documents,
      keepAllMultiFilePeers: keepPeers,
      singleVersionFamily: _sectionIsSingleVersionFamily(section),
    ),
  );
}

bool isStructuralDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  return blob.contains('structural') || blob.contains('civil');
}

bool isQualityDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  return blob.contains('quality') || blob.contains('test report');
}

bool isElectricalDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  return blob.contains('electrical') && !blob.contains('plumb');
}

bool isPlumbingDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  return blob.contains('plumb');
}

bool isPreConversionDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  return blob.contains('pre_conversion') || blob.contains('pre conversion');
}

const List<_ArchitecturalTypeDef> _structuralTypeDefs = [
  _ArchitecturalTypeDef(
    id: 'framing_drawing',
    label: 'Framing drawing',
    matches: _matchFraming,
  ),
  _ArchitecturalTypeDef(
    id: 'foundation_upto_plinth',
    label: 'Foundation upto plinth',
    matches: _matchFoundation,
  ),
  _ArchitecturalTypeDef(
    id: 'floor_wise_slab',
    label: 'Floor wise slab drawings',
    matches: _matchFloorWiseSlab,
  ),
];

const List<_ArchitecturalTypeDef> _qualityTypeDefs = [
  _ArchitecturalTypeDef(
    id: 'soil_test_report',
    label: 'Soil test report',
    matches: _matchSoil,
  ),
  _ArchitecturalTypeDef(
    id: 'qc_reports',
    label: 'QC Reports(NDT test reports)',
    matches: _matchQcReports,
  ),
  _ArchitecturalTypeDef(
    id: 'site_inspection_report',
    label: 'Site inspection report',
    matches: _matchSiteInspectionReport,
  ),
  _ArchitecturalTypeDef(
    id: 'site_document',
    label: 'Site document',
    matches: _matchSiteDocument,
  ),
];

const List<_ArchitecturalTypeDef> _electricalTypeDefs = [
  _ArchitecturalTypeDef(
    id: 'electrical_point_drawing',
    label: 'Electrical point drawing',
    matches: _matchElectrical,
  ),
];

const List<_ArchitecturalTypeDef> _plumbingTypeDefs = [
  _ArchitecturalTypeDef(
    id: 'plumbing_drawing',
    label: 'Plumbing drawing',
    matches: _matchPlumbing,
  ),
];

const List<_ArchitecturalTypeDef> _preConversionTypeDefs = [
  _ArchitecturalTypeDef(
    id: 'proposal',
    label: 'Proposal',
    matches: _matchProposal,
  ),
  _ArchitecturalTypeDef(
    id: 'booking_form',
    label: 'Booking form',
    matches: _matchBooking,
  ),
];

bool _matchFraming(String blob) => blob.contains('framing');

bool _matchFoundation(String blob) =>
    blob.contains('foundation') || blob.contains('plinth');

bool _matchFloorWiseSlab(String blob) =>
    blob.contains('floor wise') ||
    blob.contains('floor_wise') ||
    blob.contains('floor slab') ||
    blob.contains('slab drawing') ||
    (blob.contains('slab') && !blob.contains('filler'));

bool _matchSoil(String blob) => blob.contains('soil');

bool _matchQcReports(String blob) =>
    blob.contains('qc') || blob.contains('ndt');

/// SIPR → Site inspection report (separate from Site document / SD).
bool _matchSiteInspectionReport(String blob) =>
    blob.contains('sipr') ||
    blob.contains('site inspection') ||
    blob.contains('site_inspection');

/// SD → Site document (not SIPR / inspection report).
bool _matchSiteDocument(String blob) {
  if (_matchSiteInspectionReport(blob)) return false;
  return blob.contains('site document') ||
      blob.contains('site_document') ||
      RegExp(r'(^|[^a-z])sd([^a-z]|$)').hasMatch(blob);
}

bool _matchElectrical(String blob) => blob.contains('electr');

bool _matchPlumbing(String blob) => blob.contains('plumb');

bool _matchProposal(String blob) => blob.contains('proposal');

bool _matchBooking(String blob) => blob.contains('booking');

bool _sectionLooksLikeSiprSdCombo(String sectionBlob) {
  final blob = sectionBlob.toLowerCase();
  if (blob.contains('sipr') &&
      (blob.contains(',sd') ||
          blob.contains(' sd') ||
          blob.endsWith(',sd') ||
          blob.contains('sipr,sd') ||
          blob.contains('sipr / sd') ||
          blob.contains('sipr/sd'))) {
    return true;
  }
  return blob.replaceAll(' ', '') == 'sipr,sd';
}

_ArchitecturalTypeDef? _typeById(
  List<_ArchitecturalTypeDef> types,
  String id,
) {
  for (final type in types) {
    if (type.id == id) return type;
  }
  return null;
}

_ArchitecturalTypeDef? _matchTypeForDocInSection({
  required WorkflowDocumentUpload doc,
  required WorkflowDocumentSection section,
  required List<_ArchitecturalTypeDef> types,
}) {
  final byDocSection = _typeForSectionId(doc.sectionId, types);
  if (byDocSection != null) return byDocSection;
  final byFolder = _typeForSectionId(section.id, types);
  if (byFolder != null) return byFolder;

  final docBlob = _architecturalDocBlob(doc);
  final sectionBlob = '${section.id} ${section.label}'.toLowerCase();

  for (final type in types) {
    if (type.matches(docBlob)) return type;
  }

  // Combined API folder "SIPR,SD" — route into the two separate folders.
  if (_sectionLooksLikeSiprSdCombo(sectionBlob)) {
    if (_matchSiteDocument(docBlob)) {
      return _typeById(types, 'site_document');
    }
    return _typeById(types, 'site_inspection_report');
  }

  for (final type in types) {
    if (type.matches(sectionBlob)) return type;
  }
  return null;
}

List<WorkflowDocumentSection> _buildTypeSectionsFromDefs(
  WorkflowDocumentCategory category,
  List<_ArchitecturalTypeDef> types, {
  bool hideAreaStatement = false,
}) {
  final buckets = <String, List<WorkflowDocumentUpload>>{
    for (final type in types) type.id: <WorkflowDocumentUpload>[],
  };
  final seen = <String>{};

  for (final section in category.sections) {
    for (final doc in section.documents) {
      if (hideAreaStatement && doc.isAreaStatement) continue;
      final dedupe = [
        doc.id,
        doc.url ?? '',
        doc.documentKey,
        doc.revision?.toString() ?? '',
        doc.name,
      ].join('|').toLowerCase();
      if (!seen.add(dedupe)) continue;

      final matched = _matchTypeForDocInSection(
        doc: doc,
        section: section,
        types: types,
      );
      if (matched == null) continue;
      buckets[matched.id]!.add(doc);
    }
  }

  // Named checklist folders only — no vague "Other" row.
  return [
    for (final type in types)
      _checklistFolderWithPeers(
        WorkflowDocumentSection(
          id: type.id,
          label: type.label,
          categoryId: category.id,
          categoryLabel: category.label,
          clientJourneyKey: category.clientJourneyKey,
          libraryGroupKey: category.libraryGroupKey,
          documents: buckets[type.id] ?? const [],
        ),
      ),
  ];
}

/// Checklist folders for Architectural / Structural / Quality / MEP / Pre-conversion.
List<WorkflowDocumentSection>? buildChecklistTypeSectionsForCategory(
  WorkflowDocumentCategory category, {
  bool hideAreaStatement = false,
}) {
  if (isArchitecturalDocumentCategory(category)) {
    return buildArchitecturalTypeSections(
      category,
      hideAreaStatement: hideAreaStatement,
    );
  }
  if (isStructuralDocumentCategory(category)) {
    return _buildTypeSectionsFromDefs(category, _structuralTypeDefs);
  }
  if (isQualityDocumentCategory(category)) {
    return _buildTypeSectionsFromDefs(category, _qualityTypeDefs);
  }
  if (isElectricalDocumentCategory(category)) {
    return _buildTypeSectionsFromDefs(category, _electricalTypeDefs);
  }
  if (isPlumbingDocumentCategory(category)) {
    return _buildTypeSectionsFromDefs(category, _plumbingTypeDefs);
  }
  if (isPreConversionDocumentCategory(category)) {
    return _buildTypeSectionsFromDefs(category, _preConversionTypeDefs);
  }
  return null;
}

bool usesChecklistTypeSections(WorkflowDocumentCategory category) =>
    buildChecklistTypeSectionsForCategory(category) != null;

bool isReceiptsAndAgreementsCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.clientJourneyKey ?? ''} ${category.libraryGroupKey ?? ''}'
          .toLowerCase();
  return blob.contains('receipts_and_agreements') ||
      (blob.contains('receipt') && blob.contains('agreement'));
}

/// True when a folder can hold several peer uploads under one definition
/// (Electrical / Plumbing points, Soil test, Booking form).
bool isMultiFileDocumentBlob(String blob) {
  final lower = blob.toLowerCase();
  return lower.contains('electrical') ||
      lower.contains('plumb') ||
      lower.contains('soil') ||
      lower.contains('booking');
}

bool _blobLooksLikePreConversion(String blob) {
  final lower = blob.toLowerCase();
  return lower.contains('pre_conversion') || lower.contains('pre conversion');
}

bool _sectionLooksLikeProposal(WorkflowDocumentSection section) {
  final blob = '${section.id} ${section.label}'.toLowerCase();
  return blob.contains('proposal');
}

bool _sectionLooksLikeBooking(WorkflowDocumentSection section) {
  final blob = '${section.id} ${section.label}'.toLowerCase();
  return blob.contains('booking');
}

/// Electrical / Plumbing / Soil / Booking: open as one file list so every
/// uploaded PDF under a point is visible.
///
/// Do not flatten parents like Quality or Pre-conversion — those keep their
/// section folders (e.g. Proposal + Booking form, Soil + NDT).
bool isMultiFileDocumentCategory(WorkflowDocumentCategory category) {
  final blob =
      '${category.id} ${category.label} ${category.libraryGroupKey ?? ''} ${category.clientJourneyKey ?? ''}'
          .toLowerCase();
  // Pre-conversion must show Proposal / Booking form as sections.
  if (_blobLooksLikePreConversion(blob)) return false;
  final hasProposal = category.sections.any(_sectionLooksLikeProposal);
  final hasBooking = category.sections.any(_sectionLooksLikeBooking);
  if (hasProposal && hasBooking) return false;

  if (isMultiFileDocumentBlob(blob)) return true;
  // Only MEP parents flatten to a file list (Electrical / Plumbing points).
  if (blob.contains('mep')) {
    return category.sections.any(isMultiFileDocumentSection);
  }
  return false;
}

/// Section-level multi-file check (Soil / Booking under Quality / Pre-conversion).
/// Checklist folders can hold several ticked peers — count/show all of them.
bool isMultiFileDocumentSection(WorkflowDocumentSection section) {
  final blob =
      '${section.id} ${section.label} ${section.categoryId} ${section.categoryLabel} ${section.clientJourneyKey ?? ''} ${section.libraryGroupKey ?? ''}';
  if (isMultiFileDocumentBlob(blob)) return true;
  // Any checklist row with 2+ openable peers (Final Floor plan, Proposal, …).
  final openable = section.documents.where((doc) => doc.hasUrl).length;
  return openable > 1;
}

/// Kept for callers that still use the Electrical / Plumbing name.
bool isElectricalOrPlumbingDocumentCategory(WorkflowDocumentCategory category) {
  return isMultiFileDocumentCategory(category);
}

/// Every file in the folder, so opening it shows the documents themselves.
WorkflowDocumentSection buildFlatCategoryDocumentsSection(
  WorkflowDocumentCategory category,
) {
  return _flatCategoryDocumentsSection(category);
}

WorkflowDocumentSection _flatCategoryDocumentsSection(
  WorkflowDocumentCategory category,
) {
  final keepAreaStatement = isArchitecturalDocumentCategory(category);
  final docs = <WorkflowDocumentUpload>[];
  final seen = <String>{};
  for (final section in category.sections) {
    for (final doc in section.documents) {
      if (doc.isAreaStatement && !keepAreaStatement) continue;
      // Same definition can have several PDFs — never collapse on id alone.
      final key = [
        doc.id,
        doc.url ?? '',
        doc.documentKey,
        doc.revision?.toString() ?? '',
        doc.name,
        doc.uploadedAt ?? '',
      ].join('|').toLowerCase();
      if (!seen.add(key)) continue;
      docs.add(doc);
    }
  }
  return WorkflowDocumentSection(
    id: category.id,
    label: category.label,
    categoryId: category.id,
    categoryLabel: category.label,
    clientJourneyKey: category.clientJourneyKey,
    libraryGroupKey: category.libraryGroupKey,
    documents: docs,
  );
}

List<WorkflowDocumentCategory> filterWorkflowCategoriesBySearch(
  List<WorkflowDocumentCategory> categories,
  String query,
) {
  final q = query.trim();
  if (q.isEmpty) return categories;
  final lower = q.toLowerCase();
  return categories
      .map((category) {
        if (category.label.toLowerCase().contains(lower)) return category;
        final sections = filterWorkflowSectionsBySearch(category.sections, q);
        if (sections.isEmpty) return null;
        return category.copyWithSections(sections);
      })
      .whereType<WorkflowDocumentCategory>()
      .toList();
}

List<WorkflowDocumentUpload> filterWorkflowDocumentsBySearch(
  List<WorkflowDocumentUpload> docs,
  String query,
) {
  return docs.where((doc) => doc.matchesSearch(query)).toList();
}

/// Builds category cards from backend library data for the Documents tab.
List<Widget> buildDocumentCategoryCards({
  required BuildContext context,
  required WorkflowDocumentLibrary library,
  required void Function(WorkflowDocumentCategory category) onCategoryTap,
  String? searchQuery,
  String? role,
}) {
  final q = searchQuery?.trim().toLowerCase() ?? '';
  final categories = filterDocumentCategoriesForRole(
    library.documentsTabCategories.map((category) {
      if (isArchitecturalDocumentCategory(category)) return category;
      return withoutAreaStatementDocuments(category);
    }).where((category) => category.sections.isNotEmpty).toList(),
    role,
    clientMode: true,
  ).where((category) {
    if (q.isEmpty) return true;
    return category.label.toLowerCase().contains(q) ||
        (category.clientJourneyKey ?? '').toLowerCase().contains(q);
  }).toList();

  return categories.map((category) {
    final visual = categoryVisualForCategory(category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClientPortalCategoryCard(
        icon: visual.icon,
        title: category.label,
        subtitle: catalogCategorySubtitle(category),
        badgeCount: workflowDocCountForCategory(category),
        iconBg: visual.iconBg,
        iconFg: visual.iconFg,
        onTap: () => onCategoryTap(category),
      ),
    );
  }).toList();
}

// ── Client journey document UI (reference design) ───────────────────────────

class ClientPortalJourneyStatusBanner extends StatelessWidget {
  final String message;
  final bool success;

  const ClientPortalJourneyStatusBanner({
    super.key,
    required this.message,
    this.success = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: success
            ? (dark ? const Color(0xFF143028) : const Color(0xFFECFDF5))
            : (dark ? const Color(0xFF2A2112) : const Color(0xFFFFF7ED)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: success
              ? (dark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0))
              : (dark ? const Color(0xFF92400E) : const Color(0xFFFDBA74)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: success
                  ? const Color(0xFF34D399).withValues(alpha: 0.12)
                  : const Color(0xFFFBBF24).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              success ? Icons.check_rounded : Icons.hourglass_bottom_rounded,
              size: 16,
              color: success
                  ? (dark ? const Color(0xFF34D399) : const Color(0xFF047857))
                  : (dark ? const Color(0xFFFBBF24) : const Color(0xFF9A3412)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.35,
                color: AppTheme.darkTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClientPortalHelpCard extends StatelessWidget {
  final VoidCallback? onTap;

  const ClientPortalHelpCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.isDark
          ? const Color(0xFF241A33)
          : AppTheme.darkBackgroundSecondary,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.isDark
                  ? const Color(0xFF5B3A8C)
                  : AppTheme.border,
            ),
            boxShadow: AppTheme.isDark ? null : AppTheme.liftedShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.iconBoxFill(
                    const Color(0xFF2A2040),
                    const Color(0xFFC4B5FD),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.headset_mic_outlined,
                  color: AppTheme.iconBoxInk(const Color(0xFFC4B5FD)),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Need help finding a document?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.chevronColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClientPortalSectionHeroCard extends StatelessWidget {
  final WorkflowDocumentSection section;

  const ClientPortalSectionHeroCard({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final visual = sectionVisualFor(section);
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.iconBoxFill(visual.iconBg, visual.iconFg),
            AppTheme.darkBackgroundSecondary,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(
              visual.icon,
              size: 120,
              color: visual.iconFg.withValues(alpha: 0.08),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.darkBackgroundPrimaryLight,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.softShadow,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  visual.icon,
                  color: AppTheme.iconBoxInk(visual.iconFg),
                  size: 30,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                section.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Same detailed row as Docs (revision, date, size, status badge).
class ClientPortalJourneyDocumentRow extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final VoidCallback onTap;

  const ClientPortalJourneyDocumentRow({
    super.key,
    required this.document,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClientPortalDocumentRow(
      document: document,
      onTap: onTap,
    );
  }
}

class _DocTypeIcon extends StatelessWidget {
  final WorkflowDocumentUpload document;

  const _DocTypeIcon({required this.document});

  @override
  Widget build(BuildContext context) {
    if (document.isPdf) {
      return _fileTypeIcon(
        icon: Icons.picture_as_pdf_rounded,
        darkBg: const Color(0xFF2C1618),
        accent: const Color(0xFFF87171),
      );
    }
    if (document.isImage) {
      return _fileTypeIcon(
        icon: Icons.image_outlined,
        darkBg: const Color(0xFF143028),
        accent: const Color(0xFF34D399),
      );
    }
    return _fileTypeIcon(
      icon: Icons.description_outlined,
      darkBg: const Color(0xFF241A33),
      accent: ClientPortalDocTheme.accentBlue,
    );
  }
}

Widget _fileTypeIcon({
  required IconData icon,
  required Color darkBg,
  required Color accent,
  double size = 44,
  double iconSize = 24,
  double radius = 12,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppTheme.iconBoxFill(darkBg, accent),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Icon(
      icon,
      color: AppTheme.iconBoxInk(accent),
      size: iconSize,
    ),
  );
}

/// Shared section-list body for client journey document categories.
class ClientPortalJourneySectionsBody extends StatelessWidget {
  final List<WorkflowDocumentSection> sections;
  final TextEditingController searchController;
  final String searchHint;
  final String categoryLabel;
  final String emptyMessage;
  final void Function(WorkflowDocumentSection section) onSectionTap;
  final String? statusMessage;
  final bool statusSuccess;
  final bool showHelpCard;
  final List<Widget>? leadingChildren;
  final String? viewerRole;

  const ClientPortalJourneySectionsBody({
    super.key,
    required this.sections,
    required this.searchController,
    required this.searchHint,
    required this.categoryLabel,
    required this.emptyMessage,
    required this.onSectionTap,
    this.statusMessage,
    this.statusSuccess = true,
    this.showHelpCard = true,
    this.leadingChildren,
    this.viewerRole,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = filterWorkflowSectionsBySearch(
      sections,
      searchController.text,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (leadingChildren != null) ...leadingChildren!,
        if (statusMessage != null) ...[
          ClientPortalJourneyStatusBanner(
            message: statusMessage!,
            success: statusSuccess,
          ),
          const SizedBox(height: 14),
        ],
        ClientPortalSearchBar(
          controller: searchController,
          hint: searchHint,
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.getTextSecondary(context)),
              ),
            ),
          )
        else
          ...filtered.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClientPortalSectionCard(
                section: section,
                viewerRole: viewerRole,
                onTap: () => onSectionTap(section),
              ),
            ),
          ),
        if (showHelpCard && filtered.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClientPortalHelpCard(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Contact your buildAhome team if you need help locating a document.',
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class ClientPortalViewerDocCard extends StatelessWidget {
  final WorkflowDocumentUpload document;

  const ClientPortalViewerDocCard({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (document.uploadedAt != null) document.uploadedAt,
      if (document.fileSize != null) document.fileSize,
      if (document.isPdf) 'PDF' else if (document.isImage) 'Image',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Row(
        children: [
          _DocTypeIcon(document: document),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.getTextSecondary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (document.isLatest) ...[
                  const SizedBox(height: 6),
                  const ClientPortalStatusBadge(
                    kind: ClientPortalStatusBadgeKind.latest,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
