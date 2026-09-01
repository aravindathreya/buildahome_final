import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../models/workflow_document.dart';
import '../widgets/workflow_document_viewer.dart';

class DocumentsV1DetailScreen extends StatefulWidget {
  final WorkflowDocumentUpload document;
  final List<WorkflowDocumentUpload> allRevisions;
  final bool clientMode;
  final String? categoryLabel;

  const DocumentsV1DetailScreen({
    super.key,
    required this.document,
    required this.allRevisions,
    this.clientMode = false,
    this.categoryLabel,
  });

  @override
  State<DocumentsV1DetailScreen> createState() =>
      _DocumentsV1DetailScreenState();
}

class _DocumentsV1DetailScreenState extends State<DocumentsV1DetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<WorkflowDocumentUpload> get _revisions {
    final sorted = [...widget.allRevisions];
    sorted.sort((a, b) {
      final ar = a.revision ?? 0;
      final br = b.revision ?? 0;
      if (ar != br) return br.compareTo(ar);
      return (b.uploadedAt ?? '').compareTo(a.uploadedAt ?? '');
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          widget.document.displayTitle,
          style: const TextStyle(
            color: AppTheme.navy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.navy,
          unselectedLabelColor: AppTheme.mutedGrey,
          indicatorColor: ClientPortalDocTheme.accentBlue,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: [
            const Tab(text: 'Details'),
            Tab(
              text: _revisions.length > 1
                  ? 'Revisions (${_revisions.length})'
                  : 'Revisions',
            ),
            const Tab(text: 'Activity'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DetailsTab(
            document: widget.document,
            clientMode: widget.clientMode,
            categoryLabel: widget.categoryLabel,
          ),
          _RevisionsTab(
            revisions: _revisions,
            clientMode: widget.clientMode,
          ),
          _ActivityTab(document: widget.document),
        ],
      ),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final bool clientMode;
  final String? categoryLabel;

  const _DetailsTab({
    required this.document,
    required this.clientMode,
    this.categoryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final docType = document.isPdf
        ? 'PDF'
        : document.isImage
            ? 'Image'
            : (document.contentType?.trim().isNotEmpty == true
                ? document.contentType!
                : 'File');

    final badgeKind = ClientPortalStatusBadge.fromStatus(
      document.status,
      isLatest: document.isLatest,
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocIcon(document: document, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      categoryLabel ??
                          document.categoryLabel.ifEmpty(document.sectionLabel),
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 12.5,
                      ),
                    ),
                    if (document.displayRevision.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        document.displayRevision,
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (document.isLatest ||
                  document.isVerifiedStatus ||
                  (document.status?.isNotEmpty == true))
                ClientPortalStatusBadge(kind: badgeKind),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoTable(document: document, docType: docType),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: document.hasUrl
                ? () => openWorkflowDocument(
                      context,
                      document,
                      clientMode: clientMode,
                      relatedDocuments: [document],
                    )
                : null,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('View document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ClientPortalDocTheme.accentBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension _StringExt on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

class _DocIcon extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final double size;

  const _DocIcon({required this.document, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (document.isPdf) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.picture_as_pdf_rounded,
          color: const Color(0xFFDC2626),
          size: size * 0.5,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        document.isImage ? Icons.image_outlined : Icons.description_outlined,
        color: AppTheme.navy,
        size: size * 0.45,
      ),
    );
  }
}

class _InfoTable extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final String docType;

  const _InfoTable({
    required this.document,
    required this.docType,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_InfoRow>[
      _InfoRow(Icons.description_outlined, 'Document type', docType),
      if (document.sectionLabel.trim().isNotEmpty)
        _InfoRow(Icons.folder_outlined, 'Section', document.sectionLabel),
      if (document.displayRevision.isNotEmpty)
        _InfoRow(Icons.history_rounded, 'Revision', document.displayRevision),
      _InfoRow(
        Icons.flag_outlined,
        'Status',
        document.displayStatus,
      ),
      if (document.uploadedBy != null)
        _InfoRow(Icons.person_outline, 'Uploaded by', document.uploadedBy!),
      if (document.uploadedAt != null)
        _InfoRow(Icons.calendar_today_outlined, 'Uploaded on', document.uploadedAt!),
      if (document.fileSize != null)
        _InfoRow(Icons.storage_outlined, 'File size', document.fileSize!),
    ];

    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final isLast = entry.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isLast ? Colors.transparent : AppTheme.border,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(row.icon, size: 18, color: AppTheme.mutedGrey),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);
}

class _RevisionsTab extends StatelessWidget {
  final List<WorkflowDocumentUpload> revisions;
  final bool clientMode;

  const _RevisionsTab({
    required this.revisions,
    required this.clientMode,
  });

  @override
  Widget build(BuildContext context) {
    if (revisions.isEmpty) {
      return Center(
        child: Text(
          'No revision history yet.',
          style: TextStyle(color: AppTheme.getTextSecondary(context)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ClientPortalInfoBanner(
          message:
              'Only the latest revision is used for construction. Older revisions are shown for reference.',
        ),
        const SizedBox(height: 12),
        ...revisions.map((revision) {
          final badgeKind = ClientPortalStatusBadge.fromStatus(
            revision.status,
            isLatest: revision.isLatest,
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
              child: InkWell(
                onTap: revision.hasUrl
                    ? () => openWorkflowDocument(
                          context,
                          revision,
                          clientMode: clientMode,
                          relatedDocuments: revisions,
                        )
                    : null,
                borderRadius:
                    BorderRadius.circular(ClientPortalDocTheme.cardRadius),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: ClientPortalDocTheme.cardDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              revision.displayRevision.isNotEmpty
                                  ? revision.displayRevision
                                  : revision.displayTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.navy,
                                fontSize: 14,
                              ),
                            ),
                            if (revision.uploadedAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                revision.uploadedAt!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.getTextSecondary(context),
                                ),
                              ),
                            ],
                            if (revision.uploadedBy != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                revision.uploadedBy!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.getTextSecondary(context),
                                ),
                              ),
                            ],
                            if (revision.fileSize != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                revision.fileSize!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.getTextSecondary(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ClientPortalStatusBadge(kind: badgeKind),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  final WorkflowDocumentUpload document;

  const _ActivityTab({required this.document});

  @override
  Widget build(BuildContext context) {
    final activity = document.activity;
    if (activity.isEmpty) {
      return Center(
        child: Text(
          'No activity recorded yet.',
          style: TextStyle(color: AppTheme.getTextSecondary(context)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: activity.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = activity[index];
        final title = item['title']?.toString() ??
            item['action']?.toString() ??
            item['message']?.toString() ??
            'Activity';
        final subtitle = item['timestamp']?.toString() ??
            item['created_at']?.toString() ??
            item['user_name']?.toString();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
