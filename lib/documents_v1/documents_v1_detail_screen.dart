import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../models/workflow_document.dart';
import '../widgets/workflow_document_viewer.dart';

class DocumentsV1DetailScreen extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final bool clientMode;
  final String? categoryLabel;
  final String? viewerRole;

  const DocumentsV1DetailScreen({
    super.key,
    required this.document,
    this.clientMode = false,
    this.categoryLabel,
    this.viewerRole,
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

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: Text(
          document.displayTitle,
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
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
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.darkTextPrimary,
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
      ),
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
          color: const Color(0xFF2C1618),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.picture_as_pdf_rounded,
          color: const Color(0xFFF87171),
          size: size * 0.5,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2040),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        document.isImage ? Icons.image_outlined : Icons.description_outlined,
        color: AppTheme.darkTextPrimary,
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
      _InfoRow(
        Icons.flag_outlined,
        'Status',
        document.displayStatus,
      ),
      if (document.uploadedBy != null)
        _InfoRow(Icons.person_outline, 'Uploaded by', document.uploadedBy!),
      if (document.uploadedAt != null)
        _InfoRow(
          Icons.calendar_today_outlined,
          'Uploaded on',
          document.uploadedAt!,
        ),
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
                    style: TextStyle(
                      color: AppTheme.darkTextPrimary,
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
