import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/workflow_document_viewer.dart';
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
  final Future<bool> Function(String name) onUploadCustom;
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
    required this.onUploadCustom,
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
        const SizedBox(height: 8),
        _CustomDocumentsSection(
          data: data,
          kycDocs: kycDocs,
          saving: saving,
          onUploadCustom: onUploadCustom,
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
      if (key.isEmpty || key.toLowerCase() == 'custom') continue;
      final label = map['label']?.toString() ??
          map['name']?.toString() ??
          _labelForDocKey(key);
      final optional = _isOptionalDoc(map);

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

  /// Mandatory unless the API marks the type as optional.
  bool _isOptionalDoc(Map<String, dynamic> map) {
    if (map['optional'] == true) return true;
    if (map['optional'] == false) return false;
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
      case 'tax_receipt':
        return 'Tax Receipt';
      case 'layout_plan':
        return 'Layout Plan';
      default:
        return key
            .split('_')
            .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
    }
  }
}

class _CustomDocumentsSection extends StatefulWidget {
  final Map<String, dynamic> data;
  final List kycDocs;
  final bool saving;
  final Future<bool> Function(String name) onUploadCustom;

  const _CustomDocumentsSection({
    required this.data,
    required this.kycDocs,
    required this.saving,
    required this.onUploadCustom,
  });

  @override
  State<_CustomDocumentsSection> createState() =>
      _CustomDocumentsSectionState();
}

class _CustomDocumentsSectionState extends State<_CustomDocumentsSection> {
  final _nameCtrl = TextEditingController();
  String? _nameError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _config {
    final raw = widget.data['custom_documents'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  String get _title {
    final value = _config['title']?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return 'Custom Documents';
  }

  String get _placeholder {
    final value = _config['name_placeholder']?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return 'e.g. NOC, Agreement';
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = 'Please enter a document name before uploading.';
      });
      return;
    }
    setState(() => _nameError = null);
    final uploaded = await widget.onUploadCustom(name);
    if (!mounted) return;
    if (uploaded) {
      _nameCtrl.clear();
      setState(() => _nameError = null);
    }
  }

  void _view(KycDocumentRecord record) {
    if (!record.hasUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document is no longer available.')),
      );
      return;
    }
    openWorkflowDocument(
      context,
      record.toWorkflowUpload(record.displayLabel),
      clientMode: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploads = KycDocumentRecord.customUploadsFrom(
      data: widget.data,
      kycDocs: widget.kycDocs,
    );

    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.note_add_outlined,
                size: 20,
                color: AppTheme.navy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Optional',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mutedGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Type a name, then upload one or more files.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Document name',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            enabled: !widget.saving,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            decoration: InputDecoration(
              hintText: _placeholder,
              filled: true,
              fillColor: const Color(0xFFF7F8FB),
              errorText: _nameError,
              errorMaxLines: 2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _nameError == null
                      ? AppTheme.border
                      : const Color(0xFFDC2626),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: ClientPortalDocTheme.accentBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.saving ? null : _submit,
              icon: widget.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(widget.saving ? 'Uploading…' : 'Upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (uploads.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 10),
            ...uploads.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CustomUploadRow(
                  record: record,
                  onView: () => _view(record),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomUploadRow extends StatelessWidget {
  final KycDocumentRecord record;
  final VoidCallback onView;

  const _CustomUploadRow({
    required this.record,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: record.hasUrl ? onView : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 18,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.displayLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppTheme.navy,
                      ),
                    ),
                    if (record.filename != null &&
                        record.filename != record.displayLabel) ...[
                      const SizedBox(height: 2),
                      Text(
                        record.filename!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: record.hasUrl ? onView : null,
                child: const Text(
                  'View',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
