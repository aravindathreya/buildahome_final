import '../models/workflow_document.dart';
import '../services/client_portal_service.dart';

/// Parsed KYC document from portal `existing` / `client_kyc_documents` entries.
class KycDocumentRecord {
  final String docKey;
  final String? id;
  final String? filename;
  final String? uploadedAtDisplay;
  final String? status;
  final String? url;
  final String? contentType;
  final String? uploadedBy;
  final String? fileSizeDisplay;
  final Map<String, dynamic> raw;

  const KycDocumentRecord({
    required this.docKey,
    this.id,
    this.filename,
    this.uploadedAtDisplay,
    this.status,
    this.url,
    this.contentType,
    this.uploadedBy,
    this.fileSizeDisplay,
    this.raw = const {},
  });

  bool get hasUrl => url != null && url!.trim().isNotEmpty;

  bool get isPdf {
    final mime = (contentType ?? '').toLowerCase();
    if (mime.contains('pdf')) return true;
    final name = (filename ?? url ?? '').toLowerCase();
    return name.endsWith('.pdf');
  }

  bool get isImage {
    final mime = (contentType ?? '').toLowerCase();
    if (mime.startsWith('image/')) return true;
    final name = (filename ?? url ?? '').toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  String? get displayStatus {
    final value = status?.trim();
    if (value != null && value.isNotEmpty) return value;
    if (hasUrl) return 'Uploaded';
    return null;
  }

  String? get fileTypeDisplay {
    if (isPdf) return 'PDF';
    if (isImage) {
      final name = (filename ?? url ?? '').toLowerCase();
      if (name.endsWith('.png')) return 'PNG';
      if (name.endsWith('.webp')) return 'WEBP';
      return 'JPEG';
    }
    final mime = (contentType ?? '').toLowerCase();
    if (mime.isNotEmpty) {
      final parts = mime.split('/');
      if (parts.length == 2) return parts.last.toUpperCase();
    }
    return null;
  }

  static KycDocumentRecord? fromMap(Map<String, dynamic> map) {
    final docKey = _string(map['doc_key']) ??
        _string(map['doc_type']) ??
        _string(map['document_type']) ??
        '';
    if (docKey.isEmpty) return null;

    final rawUrl = _string(map['view_url']) ??
        _string(map['download_url']) ??
        _string(map['url']) ??
        _string(map['file_url']);

    return KycDocumentRecord(
      docKey: docKey,
      id: _string(map['id']) ?? _string(map['document_id']),
      filename: _string(map['filename']) ??
          _string(map['file_name']) ??
          _string(map['original_filename']),
      uploadedAtDisplay: _string(map['uploaded_at_display']) ??
          _string(map['uploaded_at']) ??
          _string(map['created_at']),
      status: _string(map['status']) ??
          _string(map['document_status']) ??
          _string(map['verification_status']),
      url: rawUrl != null ? ClientPortalService().serveUrl(rawUrl) : null,
      contentType: _string(map['content_type']) ?? _string(map['mime_type']),
      uploadedBy: _string(map['uploaded_by']) ??
          _string(map['uploaded_by_name']) ??
          _string(map['user_name']),
      fileSizeDisplay: _formatFileSize(map['file_size'] ?? map['size']),
      raw: map,
    );
  }

  static KycDocumentRecord? findForKey(String key, List<dynamic> kycDocs) {
    KycDocumentRecord? fallback;
    for (final raw in kycDocs) {
      if (raw is! Map) continue;
      final record = fromMap(Map<String, dynamic>.from(raw));
      if (record == null) continue;
      if (record.docKey == key) return record;
      // Custom uploads may use doc_key=custom with a separate name field.
      if (key == 'custom') {
        final customName = _string(raw['custom_doc_name']) ??
            _string(raw['document_label']);
        if (customName != null) {
          fallback ??= record;
        }
      }
    }
    return fallback;
  }

  WorkflowDocumentUpload toWorkflowUpload(String label) {
    final name = filename?.trim().isNotEmpty == true ? filename! : label;
    return WorkflowDocumentUpload(
      id: id ?? 'kyc-$docKey-${url ?? name}',
      documentKey: docKey,
      name: name,
      url: url,
      contentType: contentType,
      isLatest: true,
      status: displayStatus,
      uploadedAt: uploadedAtDisplay,
      sectionLabel: 'KYC',
      categoryLabel: 'KYC & Documents',
      raw: raw,
    );
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static String? _formatFileSize(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final bytes = value.toDouble();
      if (bytes >= 1048576) {
        return '${(bytes / 1048576).toStringAsFixed(2)} MB';
      }
      if (bytes >= 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      }
      return '${bytes.toStringAsFixed(0)} B';
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
