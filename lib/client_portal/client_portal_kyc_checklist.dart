import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'client_portal_document_ui.dart';
import 'client_portal_kyc_ui.dart';
import 'kyc_document_record.dart';

/// KYC checklist UI — uses existing upload/save callbacks from parent state.
class ClientPortalKycChecklist extends StatelessWidget {
  final Map<String, dynamic> data;
  final List docTypes;
  final List kycDocs;
  final bool saving;
  final TextEditingController commentCtrl;
  final Future<void> Function(String docKey) onUpload;
  final void Function(String label, KycDocumentRecord record) onOpenUploaded;
  final VoidCallback onSaveComment;

  const ClientPortalKycChecklist({
    super.key,
    required this.data,
    required this.docTypes,
    required this.kycDocs,
    required this.saving,
    required this.commentCtrl,
    required this.onUpload,
    required this.onOpenUploaded,
    required this.onSaveComment,
  });

  @override
  Widget build(BuildContext context) {
    final mandatory = data['mandatory_docs'] is List
        ? List.from(data['mandatory_docs'] as List)
        : <dynamic>[];

    final checklist = _buildChecklist(mandatory);
    final mandatoryItems =
        checklist.where((item) => !item.optional).toList();
    final total = mandatoryItems.length;
    final done = mandatoryItems
        .where((item) => item.status == _KycItemStatus.done)
        .length;
    final allMandatoryDone = total > 0 && done >= total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        KycStatusCard(done: done, total: total),
        const SizedBox(height: 14),
        const ClientPortalInfoBanner(
          message:
              'Please upload all mandatory documents. Your team will verify them before construction begins.',
        ),
        const SizedBox(height: 18),
        const Text(
          'Document Checklist',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 12),
        ...checklist.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _KycChecklistTile(
              item: item,
              saving: saving,
              onTap: saving
                  ? null
                  : () {
                      if (item.uploadedDoc != null) {
                        onOpenUploaded(item.label, item.uploadedDoc!);
                      } else {
                        onUpload(item.key);
                      }
                    },
            ),
          ),
        ),
        if (allMandatoryDone) ...[
          const SizedBox(height: 8),
          const KycSuccessBanner(),
        ],
        const SizedBox(height: 20),
        _CommentSection(
          commentCtrl: commentCtrl,
          saving: saving,
          onSaveComment: onSaveComment,
        ),
      ],
    );
  }

  List<_KycChecklistItem> _buildChecklist(List mandatory) {
    final items = <_KycChecklistItem>[];
    final uploadedTypes = data['uploaded_types'] is List
        ? List.from(data['uploaded_types'] as List)
            .map((e) => e.toString())
            .toSet()
        : <String>{};

    for (final raw in docTypes) {
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'key': raw.toString(), 'label': raw.toString()};
      final key = map['key']?.toString() ?? map['doc_key']?.toString() ?? '';
      if (key.isEmpty) continue;
      final label = map['label']?.toString() ??
          map['name']?.toString() ??
          _labelForDocKey(key);
      final optional = _isOptionalDoc(map, key);

      final uploadedDoc = KycDocumentRecord.findForKey(key, kycDocs);
      final done = uploadedTypes.contains(key) || uploadedDoc != null;

      items.add(
        _KycChecklistItem(
          key: key,
          label: label,
          optional: optional,
          status: done
              ? _KycItemStatus.done
              : optional
                  ? _KycItemStatus.optional
                  : _KycItemStatus.pending,
          uploadedDoc: uploadedDoc,
        ),
      );
    }
    return items;
  }

  /// Mandatory unless API marks optional or it is a custom upload slot.
  bool _isOptionalDoc(Map<String, dynamic> map, String key) {
    if (map['optional'] == true) return true;
    if (map['optional'] == false) return false;
    if (key == 'custom') return true;
    // document_types drives the checklist; don't demote items missing from
    // mandatory_docs (that list can be incomplete vs displayed types).
    return false;
  }

  String _labelForDocKey(String key) {
    switch (key) {
      case 'aadhar':
        return 'Aadhaar Card';
      case 'pan_card':
        return 'PAN Card';
      case 'sale_deed':
        return 'Sale Deed';
      case 'ec':
        return 'EC (Last 20 Years)';
      case 'khata':
        return 'Khata';
      case 'photograph':
        return 'Photograph';
      case 'custom':
        return 'Other document';
      default:
        return key
            .split('_')
            .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
    }
  }
}

class _CommentSection extends StatefulWidget {
  final TextEditingController commentCtrl;
  final bool saving;
  final VoidCallback onSaveComment;

  const _CommentSection({
    required this.commentCtrl,
    required this.saving,
    required this.onSaveComment,
  });

  @override
  State<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<_CommentSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 20, color: AppTheme.navy),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Notes for your team',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.mutedGrey,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  TextField(
                    controller: widget.commentCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Any notes for the team…',
                      filled: true,
                      fillColor: const Color(0xFFF7F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.saving ? null : widget.onSaveComment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.navy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(widget.saving ? 'Saving…' : 'Save note'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _KycItemStatus { done, pending, optional }

class _KycChecklistItem {
  final String key;
  final String label;
  final bool optional;
  final _KycItemStatus status;
  final KycDocumentRecord? uploadedDoc;

  const _KycChecklistItem({
    required this.key,
    required this.label,
    required this.optional,
    required this.status,
    this.uploadedDoc,
  });
}

class _KycChecklistTile extends StatelessWidget {
  final _KycChecklistItem item;
  final bool saving;
  final VoidCallback? onTap;

  const _KycChecklistTile({
    required this.item,
    required this.saving,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = item.uploadedDoc;
    final isUploaded = item.status == _KycItemStatus.done && uploaded != null;
    final visual = kycDocVisualFor(docKey: item.key, label: item.label);

    String? subtitle;
    if (isUploaded && uploaded.uploadedAtDisplay != null) {
      subtitle = 'Uploaded ${uploaded.uploadedAtDisplay}';
    } else if (item.status == _KycItemStatus.pending) {
      subtitle = 'Tap to upload document';
    } else if (item.optional && !isUploaded) {
      subtitle = 'Optional — tap to upload';
    }

    return Material(
      color: ClientPortalDocTheme.cardBackground,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      shadowColor: AppTheme.softShadow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visual.icon, color: visual.iconFg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: AppTheme.navy,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isUploaded
                              ? AppTheme.getTextSecondary(context)
                              : const Color(0xFFEA580C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isUploaded)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF059669),
                    size: 22,
                  ),
                )
              else if (item.status == _KycItemStatus.pending)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.upload_file_rounded,
                    color: Color(0xFFEA580C),
                    size: 20,
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
