import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/workflow_document_viewer.dart';
import 'client_portal_document_ui.dart';
import 'client_portal_kyc_ui.dart';
import 'kyc_document_record.dart';

/// Uploaded KYC document — view or replace (no re-upload on row tap).
class ClientPortalKycDocumentScreen extends StatelessWidget {
  final String label;
  final KycDocumentRecord record;
  final VoidCallback onReplace;

  const ClientPortalKycDocumentScreen({
    super.key,
    required this.label,
    required this.record,
    required this.onReplace,
  });

  Future<void> _confirmReplace(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Replace $label?'),
        content: const Text('Your current document will be replaced.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navy,
              foregroundColor: Colors.white,
            ),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.pop(context);
      onReplace();
    }
  }

  void _viewDocument(BuildContext context) {
    if (!record.hasUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document is no longer available.')),
      );
      return;
    }
    openWorkflowDocument(
      context,
      record.toWorkflowUpload(label),
      clientMode: true,
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View document'),
              onTap: () {
                Navigator.pop(ctx);
                _viewDocument(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Replace document'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmReplace(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploadedAt = record.uploadedAtDisplay;
    final status = record.displayStatus ?? 'Uploaded';
    final visual = kycDocVisualFor(docKey: record.docKey, label: label);

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          label,
          style: const TextStyle(
            color: AppTheme.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: ClientPortalDocTheme.cardDecoration(),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: visual.iconBg,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: visual.iconFg.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          visual.icon,
                          color: visual.iconFg,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (record.hasUrl) const KycUploadedBadge(),
                  if (uploadedAt != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Uploaded on $uploadedAt',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: record.hasUrl ? () => _viewDocument(context) : null,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View Document'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmReplace(context),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Replace Document'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ClientPortalDocTheme.accentBlue,
                  side: const BorderSide(color: ClientPortalDocTheme.accentBlue),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Document Details',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: ClientPortalDocTheme.cardDecoration(),
              child: Column(
                children: [
                  if (uploadedAt != null)
                    KycDetailRow(
                      icon: Icons.calendar_today_outlined,
                      iconBg: const Color(0xFFF3E8FF),
                      iconFg: const Color(0xFF9333EA),
                      label: 'Uploaded On',
                      value: uploadedAt,
                    ),
                  if (record.uploadedBy != null)
                    KycDetailRow(
                      icon: Icons.person_outline_rounded,
                      iconBg: const Color(0xFFEFF6FF),
                      iconFg: ClientPortalDocTheme.accentBlue,
                      label: 'Uploaded By',
                      value: record.uploadedBy!,
                    ),
                  if (record.filename != null)
                    KycDetailRow(
                      icon: Icons.insert_drive_file_outlined,
                      iconBg: const Color(0xFFECFDF5),
                      iconFg: const Color(0xFF059669),
                      label: 'File Name',
                      value: record.filename!,
                    ),
                  if (record.fileTypeDisplay != null)
                    KycDetailRow(
                      icon: Icons.picture_as_pdf_outlined,
                      iconBg: const Color(0xFFFFF7ED),
                      iconFg: const Color(0xFFEA580C),
                      label: 'File Type',
                      value: record.fileTypeDisplay!,
                    ),
                  if (record.fileSizeDisplay != null)
                    KycDetailRow(
                      icon: Icons.sd_storage_outlined,
                      iconBg: const Color(0xFFF3E8FF),
                      iconFg: const Color(0xFF9333EA),
                      label: 'File Size',
                      value: record.fileSizeDisplay!,
                    ),
                  KycDetailRow(
                    icon: Icons.verified_user_outlined,
                    iconBg: const Color(0xFFEFF6FF),
                    iconFg: ClientPortalDocTheme.accentBlue,
                    label: 'Document Status',
                    value: status,
                  ),
                ],
              ),
            ),
            if (!record.hasUrl) ...[
              const SizedBox(height: 16),
              const ClientPortalInfoBanner(
                message:
                    'This document record exists but the file link is unavailable. Try replacing the document.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
