import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/workflow_document.dart';

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

  static const cardBackground = Colors.white;

  static TabBarTheme tabBarTheme() => const TabBarTheme(
        labelColor: AppTheme.navy,
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
    this.iconFg = AppTheme.navy,
  });
}

ClientPortalCategoryVisual categoryVisualFor({
  String? journeyKey,
  String? categoryId,
  String? label,
}) {
  final key = (journeyKey ?? categoryId ?? label ?? '').toLowerCase();

  if (key.contains('kyc') || key.contains('pre_conversion')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.badge_outlined,
      subtitle: 'KYC and other project documents',
      iconBg: Color(0xFFEEF2FF),
      iconFg: Color(0xFF4338CA),
    );
  }
  if (key.contains('floor_plan')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.architecture_outlined,
      subtitle: 'View floor plans and elevations',
      iconBg: Color(0xFFECFEFF),
      iconFg: Color(0xFF0891B2),
    );
  }
  if (key.contains('design')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.auto_awesome_outlined,
      subtitle: 'Vastu, elevation refs & bylaws',
      iconBg: Color(0xFFF3E8FF),
      iconFg: Color(0xFF9333EA),
    );
  }
  if (key.contains('gfc') || key.contains('construction_drawings')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.domain_outlined,
      subtitle: 'Architectural, structural & electrical',
      iconBg: Color(0xFFEEF2FF),
      iconFg: Color(0xFF2563EB),
    );
  }
  if (key.contains('quality') || key.contains('ndt')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.science_outlined,
      subtitle: 'NDT & construction test reports',
      iconBg: Color(0xFFECFDF5),
      iconFg: Color(0xFF059669),
    );
  }
  if (key.contains('site_record') || key.contains('site_construction')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.engineering_outlined,
      subtitle: 'Site marking, conduit marking & more',
      iconBg: Color(0xFFFFF7ED),
      iconFg: Color(0xFFEA580C),
    );
  }
  if (key.contains('door') || key.contains('window') || key.contains('grill')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.grid_view_rounded,
      subtitle: 'Designs and details',
      iconBg: Color(0xFFF0FDF4),
      iconFg: Color(0xFF16A34A),
    );
  }
  if (key.contains('site_prep')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.construction_outlined,
      subtitle: 'Demolition & borewell questionnaire',
      iconBg: Color(0xFFFEF3C7),
      iconFg: Color(0xFFD97706),
    );
  }
  if (key.contains('demolition')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.home_work_outlined,
      subtitle: 'Demolition completion & comments',
      iconBg: Color(0xFFFEE2E2),
      iconFg: Color(0xFFDC2626),
    );
  }
  if (key.contains('inspection')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.fact_check_outlined,
      subtitle: 'Book a slot or view reports',
      iconBg: Color(0xFFE0F2FE),
      iconFg: Color(0xFF0284C7),
    );
  }

  return const ClientPortalCategoryVisual(
    icon: Icons.folder_open_outlined,
    subtitle: 'View documents in this category',
    iconBg: Color(0xFFF0F4FF),
  );
}

ClientPortalCategoryVisual categoryVisualForCategory(
  WorkflowDocumentCategory category,
) {
  return categoryVisualFor(
    journeyKey: category.clientJourneyKey,
    categoryId: category.id,
    label: category.label,
  );
}

ClientPortalCategoryVisual sectionVisualFor(WorkflowDocumentSection section) {
  final label = section.label.toLowerCase();
  final id = section.id.toLowerCase();

  if (label.contains('architectural') || id.contains('architectural')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.apartment_outlined,
      subtitle: 'Floor plans, elevations, working drawings',
      iconBg: Color(0xFFEEF2FF),
      iconFg: Color(0xFF2563EB),
    );
  }
  if (label.contains('structural') || id.contains('structural')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.account_tree_outlined,
      subtitle: 'Foundation, framing & structural details',
      iconBg: Color(0xFFECFDF5),
      iconFg: Color(0xFF059669),
    );
  }
  if (label.contains('electrical') || id.contains('electrical')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.electrical_services_outlined,
      subtitle: 'Electrical layouts & wiring diagrams',
      iconBg: Color(0xFFFFF7ED),
      iconFg: Color(0xFFEA580C),
    );
  }
  if (label.contains('ndt') || id.contains('ndt')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.biotech_outlined,
      subtitle: 'Non-destructive test reports',
      iconBg: Color(0xFFECFDF5),
      iconFg: Color(0xFF059669),
    );
  }
  if (label.contains('site marking') || id.contains('site_marking')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.location_on_outlined,
      subtitle: 'Site marking records & photos',
      iconBg: Color(0xFFFFF7ED),
      iconFg: Color(0xFFEA580C),
    );
  }
  if (label.contains('conduit') || label.contains('mep') || id.contains('conduit')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.cable_outlined,
      subtitle: 'Conduit & MEP marking records',
      iconBg: Color(0xFFE0F2FE),
      iconFg: Color(0xFF0284C7),
    );
  }
  if (label.contains('vastu')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.auto_awesome_outlined,
      subtitle: 'Vastu design documents',
      iconBg: Color(0xFFF3E8FF),
      iconFg: Color(0xFF9333EA),
    );
  }
  if (label.contains('elevation') && label.contains('reference')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.image_outlined,
      subtitle: 'Elevation reference designs',
      iconBg: Color(0xFFECFEFF),
      iconFg: Color(0xFF0891B2),
    );
  }
  if (label.contains('bylaw')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.gavel_outlined,
      subtitle: 'Bylaw compliance documents',
      iconBg: Color(0xFFFEF3C7),
      iconFg: Color(0xFFD97706),
    );
  }
  if (label.contains('floor plan') || label.contains('elevation')) {
    return const ClientPortalCategoryVisual(
      icon: Icons.architecture_outlined,
      subtitle: 'Plans and elevation drawings',
      iconBg: Color(0xFFECFEFF),
      iconFg: Color(0xFF0891B2),
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
  return category.documentCount;
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
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
          borderSide: const BorderSide(color: AppTheme.border),
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
        color: const Color(0xFFDBEAFE),
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: ClientPortalDocTheme.accentBlue,
        ),
      ),
    );
  }
}

enum ClientPortalStatusBadgeKind { latest, verified, superseded, optional, pending }

class ClientPortalStatusBadge extends StatelessWidget {
  final ClientPortalStatusBadgeKind kind;

  const ClientPortalStatusBadge({super.key, required this.kind});

  static ClientPortalStatusBadgeKind fromStatus(String? status, {required bool isLatest}) {
    final normalized = status?.trim().toLowerCase() ?? '';
    if (normalized == 'verified') return ClientPortalStatusBadgeKind.verified;
    if (normalized == 'superseded') return ClientPortalStatusBadgeKind.superseded;
    if (normalized == 'latest' || isLatest) return ClientPortalStatusBadgeKind.latest;
    if (normalized == 'pending') return ClientPortalStatusBadgeKind.pending;
    if (normalized == 'optional') return ClientPortalStatusBadgeKind.optional;
    return isLatest
        ? ClientPortalStatusBadgeKind.latest
        : ClientPortalStatusBadgeKind.superseded;
  }

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String label;
    switch (kind) {
      case ClientPortalStatusBadgeKind.latest:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        label = 'Latest';
        break;
      case ClientPortalStatusBadgeKind.verified:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        label = 'Verified';
        break;
      case ClientPortalStatusBadgeKind.superseded:
        bg = const Color(0xFFF3F4F6);
        fg = AppTheme.mutedGrey;
        label = 'Superseded';
        break;
      case ClientPortalStatusBadgeKind.optional:
        bg = const Color(0xFFF3F4F6);
        fg = AppTheme.mutedGrey;
        label = 'Optional';
        break;
      case ClientPortalStatusBadgeKind.pending:
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFEA580C);
        label = 'Pending';
        break;
    }
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
                  color: iconBg ?? const Color(0xFFE8F1FF),
                  borderRadius:
                      BorderRadius.circular(ClientPortalDocTheme.iconBoxRadius),
                ),
                child: Icon(
                  icon,
                  color: iconFg ?? AppTheme.navy,
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
                        color: AppTheme.navy,
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

  const ClientPortalSectionCard({
    super.key,
    required this.section,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visual = sectionVisualFor(section);
    return ClientPortalCategoryCard(
      icon: visual.icon,
      title: section.label,
      subtitle: visual.subtitle,
      badgeCount: section.documentCount,
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
                    color: selected ? AppTheme.navy : AppTheme.mutedGrey,
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
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppTheme.navy,
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

  const ClientPortalDocumentRow({
    super.key,
    required this.document,
    this.showVerifiedBadge = false,
    this.showThumbnail = false,
    required this.onTap,
    this.onMenuTap,
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
            document.status,
            isLatest: document.isLatest,
          );

    return Material(
      color: ClientPortalDocTheme.cardBackground,
      borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.navy,
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
                  if (document.isLatest || document.isVerifiedStatus)
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
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.picture_as_pdf_rounded,
          color: Color(0xFFDC2626),
          size: 22,
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        document.isImage ? Icons.image_outlined : Icons.description_outlined,
        color: AppTheme.navy,
        size: 20,
      ),
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
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBEAFE)),
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
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
}) {
  final q = searchQuery?.trim().toLowerCase() ?? '';
  final categories = library.documentsTabCategories.where((category) {
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
        subtitle: visual.subtitle,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: success ? const Color(0xFFA7F3D0) : const Color(0xFFFED7AA),
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
                  ? const Color(0xFF059669).withValues(alpha: 0.12)
                  : const Color(0xFFEA580C).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              success ? Icons.check_rounded : Icons.hourglass_bottom_rounded,
              size: 16,
              color: success ? const Color(0xFF059669) : const Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.35,
                color: AppTheme.navy,
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
      color: const Color(0xFFF5F3FF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.headset_mic_outlined,
                  color: Color(0xFF7C3AED),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Need help finding a document?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.getTextSecondary(context),
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
            visual.iconBg,
            Colors.white,
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
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.softShadow,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(visual.icon, color: visual.iconFg, size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                section.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.navy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    final uploadedLine = document.uploadedAt != null
        ? 'Uploaded on ${document.uploadedAt}'
        : null;

    return Material(
      color: ClientPortalDocTheme.cardBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocTypeIcon(document: document),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: AppTheme.navy,
                        height: 1.25,
                      ),
                    ),
                    if (uploadedLine != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        uploadedLine,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.getTextSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (document.fileSize != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        document.fileSize!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.getTextSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (document.isLatest) ...[
                      const SizedBox(height: 8),
                      const ClientPortalStatusBadge(
                        kind: ClientPortalStatusBadgeKind.latest,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.getTextSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocTypeIcon extends StatelessWidget {
  final WorkflowDocumentUpload document;

  const _DocTypeIcon({required this.document});

  @override
  Widget build(BuildContext context) {
    if (document.isPdf) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.picture_as_pdf_rounded,
          color: Color(0xFFDC2626),
          size: 24,
        ),
      );
    }
    if (document.isImage) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.image_outlined,
          color: Color(0xFF059669),
          size: 24,
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.description_outlined,
        color: ClientPortalDocTheme.accentBlue,
        size: 24,
      ),
    );
  }
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
  });

  @override
  Widget build(BuildContext context) {
    final filtered = filterWorkflowSectionsBySearch(
      sections,
      searchController.text,
    );

    return ListView(
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppTheme.navy,
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
