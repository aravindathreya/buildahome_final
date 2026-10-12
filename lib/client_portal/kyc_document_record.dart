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
  final String? customLabel;
  final String? documentLabel;
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
    this.customLabel,
    this.documentLabel,
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

  /// Label for custom uploads — never the word "Custom".
  String get displayLabel {
    for (final value in [customLabel, documentLabel, filename]) {
      if (_usableLabel(value)) return value!.trim();
    }
    return 'Document';
  }

  bool get isCustom => docKey.toLowerCase() == 'custom';

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
    var docKey = _string(map['doc_key']) ??
        _string(map['doc_type']) ??
        _string(map['document_type']) ??
        '';
    final customLabel = _string(map['custom_label']) ??
        _string(map['custom_doc_name']);
    final documentLabel = _string(map['document_label']);
    if (docKey.isEmpty) {
      if (customLabel != null) {
        docKey = 'custom';
      } else {
        return null;
      }
    }

    final rawUrl = _string(map['view_url']) ??
        _string(map['download_url']) ??
        _string(map['url']) ??
        _string(map['file_url']);

    return KycDocumentRecord(
      docKey: docKey,
      id: _string(map['file_id']) ??
          _string(map['upload_id']) ??
          _string(map['document_id']) ??
          _string(map['id']),
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
      customLabel: customLabel,
      documentLabel: documentLabel,
      raw: map,
    );
  }

  /// Prefer `section.custom_documents.uploads`, then existing KYC rows.
  ///
  /// A named group can hold several files. Each file keeps the group name so
  /// delete can match the upload the server stored.
  static List<KycDocumentRecord> customUploadsFrom({
    required Map<String, dynamic> data,
    required List kycDocs,
  }) {
    final fromSection = _customRecords(
      data['custom_documents'] is Map
          ? (data['custom_documents'] as Map)['uploads']
          : null,
    );
    if (fromSection.isNotEmpty) return fromSection;

    return _recordsFromList(kycDocs)
        .where((record) => record.isCustom)
        .toList();
  }

  static List<KycDocumentRecord> _customRecords(dynamic rawUploads) {
    final items = <KycDocumentRecord>[];

    void addFile(
      Map<String, dynamic> file, {
      String? groupName,
      int? index,
    }) {
      final map = Map<String, dynamic>.from(file);
      map['doc_key'] ??= 'custom';
      final existingName =
          _string(map['custom_doc_name']) ?? _string(map['custom_label']);
      if (existingName == null) {
        final candidate = groupName ??
            _string(map['name']) ??
            _string(map['title']) ??
            _string(map['label']) ??
            _string(map['document_label']);
        final filename = _string(map['filename']) ??
            _string(map['file_name']) ??
            _string(map['original_filename']);
        if (candidate != null && candidate != filename) {
          map['custom_doc_name'] = candidate;
        }
      }
      map['index'] ??= index;
      final record = fromMap(map);
      if (record != null) items.add(record);
    }

    void addEntry(dynamic entry, {String? groupName, int? index}) {
      if (entry is! Map) return;
      final map = Map<String, dynamic>.from(entry);
      final nested = map['files'] ?? map['uploads'] ?? map['documents'];
      final name = groupName ??
          _string(map['custom_doc_name']) ??
          _string(map['custom_label']) ??
          _string(map['name']) ??
          _string(map['title']);
      if (nested is List && nested.isNotEmpty) {
        for (var i = 0; i < nested.length; i++) {
          addEntry(nested[i], groupName: name, index: i);
        }
        return;
      }
      addFile(map, groupName: name, index: index);
    }

    if (rawUploads is List) {
      for (var i = 0; i < rawUploads.length; i++) {
        addEntry(rawUploads[i], index: i);
      }
    } else if (rawUploads is Map) {
      final map = Map<String, dynamic>.from(rawUploads);
      final looksLikeFile = map.containsKey('filename') ||
          map.containsKey('file_name') ||
          map.containsKey('view_url') ||
          map.containsKey('url') ||
          map.containsKey('download_url');
      if (looksLikeFile) {
        addEntry(map, index: 0);
      } else {
        for (final entry in map.entries) {
          final value = entry.value;
          final groupName = entry.key.toString();
          if (value is List) {
            for (var i = 0; i < value.length; i++) {
              addEntry(value[i], groupName: groupName, index: i);
            }
          } else {
            addEntry(value, groupName: groupName);
          }
        }
      }
    }
    return items;
  }

  static KycDocumentRecord? findForKey(String key, List<dynamic> kycDocs) {
    KycDocumentRecord? fallback;
    for (final raw in kycDocs) {
      if (raw is! Map) continue;
      final record = fromMap(Map<String, dynamic>.from(raw));
      if (record == null) continue;
      if (record.isCustom && key.toLowerCase() != 'custom') continue;
      if (record.docKey == key) return record;
      if (key.toLowerCase() == 'custom' && record.isCustom) {
        fallback ??= record;
      }
    }
    return fallback;
  }

  WorkflowDocumentUpload toWorkflowUpload(
    String label, {
    bool canDownload = false,
  }) {
    final name = filename?.trim().isNotEmpty == true ? filename! : label;
    final allowed = canDownload ||
        raw['can_download'] == true ||
        raw['can_download'] == 1 ||
        raw['can_download']?.toString().toLowerCase() == 'true';
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
      raw: {
        ...raw,
        'can_download': allowed,
      },
    );
  }

  static List<KycDocumentRecord> _recordsFromList(dynamic rawList) {
    if (rawList is! List) return const [];
    final items = <KycDocumentRecord>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final record = fromMap(Map<String, dynamic>.from(raw));
      if (record != null) items.add(record);
    }
    return items;
  }

  static bool _usableLabel(String? value) {
    if (value == null) return false;
    final text = value.trim();
    if (text.isEmpty) return false;
    return text.toLowerCase() != 'custom';
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
