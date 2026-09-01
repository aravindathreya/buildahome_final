import '../models/workflow_document.dart';

/// Approved PO list/detail payloads from `GET /API/approved_pos`.
class ApprovedPo {
  final int indentId;
  final int projectId;
  final String projectName;
  final String projectNumber;
  final String poNumber;
  final String material;
  final String quantity;
  final String unit;
  final String purpose;
  final String createdByName;
  final String createdAt;
  final int billed;
  final String status;
  final String statusLabel;
  final String vendorName;
  final bool hasPoDocument;
  final MaskedPoDocument? maskedPoDocument;
  final int? createdByUserId;
  final String comments;
  final List<ApprovedPoMaterialLine> materials;

  const ApprovedPo({
    required this.indentId,
    required this.projectId,
    required this.projectName,
    required this.projectNumber,
    required this.poNumber,
    required this.material,
    required this.quantity,
    required this.unit,
    required this.purpose,
    required this.createdByName,
    required this.createdAt,
    required this.billed,
    required this.status,
    required this.statusLabel,
    required this.vendorName,
    required this.hasPoDocument,
    this.maskedPoDocument,
    this.createdByUserId,
    this.comments = '',
    this.materials = const [],
  });

  factory ApprovedPo.fromJson(Map<String, dynamic> json) {
    final maskedRaw = json['masked_po_document'];
    MaskedPoDocument? masked;
    if (maskedRaw is Map) {
      final candidate = MaskedPoDocument.fromJson(
        Map<String, dynamic>.from(maskedRaw),
      );
      if (candidate.isMasked) masked = candidate;
    }

    final materialsRaw = json['materials'];
    final materials = <ApprovedPoMaterialLine>[];
    if (materialsRaw is List) {
      for (final row in materialsRaw) {
        if (row is Map) {
          materials.add(
            ApprovedPoMaterialLine.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }

    return ApprovedPo(
      indentId: _asInt(json['indent_id']),
      projectId: _asInt(json['project_id']),
      projectName: _asString(json['project_name']),
      projectNumber: _asString(json['project_number']),
      poNumber: _asString(json['po_number']),
      material: _asString(json['material']),
      quantity: _asString(json['quantity']),
      unit: _asString(json['unit']),
      purpose: _asString(json['purpose']),
      createdByName: _asString(json['created_by_name']),
      createdAt: _asString(json['created_at']),
      billed: _asInt(json['billed']),
      status: _asString(json['status']),
      statusLabel: _asString(json['status_label']),
      vendorName: _asString(json['vendor_name']),
      hasPoDocument: _truthy(json['has_po_document']),
      maskedPoDocument: masked,
      createdByUserId: json['created_by_user_id'] == null
          ? null
          : _asInt(json['created_by_user_id']),
      comments: _asString(json['comments']),
      materials: materials,
    );
  }

  String displayPoNumber() {
    final trimmed = poNumber.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'PO pending';
  }

  String displayMaterialLine() {
    final parts = <String>[];
    if (material.trim().isNotEmpty) parts.add(material.trim());
    if (quantity.trim().isNotEmpty) parts.add(quantity.trim());
    if (unit.trim().isNotEmpty) parts.add(unit.trim());
    return parts.join(' ');
  }

  bool get isBilled => billed == 1;

  bool get canViewMaskedDocument => maskedPoDocument != null;

  /// PO file exists on server but masked mobile copy is not linked yet.
  bool get awaitingMaskedDocument =>
      !canViewMaskedDocument && hasPoDocument;

  /// Workflow document row for Documents V1–style inline preview.
  WorkflowDocumentUpload? workflowDocument() {
    final doc = maskedPoDocument;
    if (doc == null || !doc.isMasked || doc.url.trim().isEmpty) return null;

    final fileTitle = doc.filename.trim().isNotEmpty
        ? doc.filename.trim()
        : (doc.label.trim().isNotEmpty ? doc.label.trim() : displayPoNumber());

    return WorkflowDocumentUpload(
      id: doc.key.isNotEmpty ? doc.key : 'indent-$indentId',
      documentKey: doc.key.isNotEmpty ? doc.key : 'po-$indentId',
      name: fileTitle,
      url: doc.url,
      contentType:
          doc.mimeType.trim().isNotEmpty ? doc.mimeType.trim() : 'application/pdf',
      uploadedAt: createdAt.isNotEmpty ? createdAt : null,
      uploadedBy: createdByName.isNotEmpty ? createdByName : null,
      isLatest: true,
      sectionLabel: 'Approved PO',
      categoryLabel: 'Purchase Orders',
      status: statusLabel.isNotEmpty ? statusLabel : 'Approved',
      taskName: displayPoNumber(),
    );
  }
}

class ApprovedPoMaterialLine {
  final String material;
  final String quantity;
  final String unit;

  const ApprovedPoMaterialLine({
    required this.material,
    required this.quantity,
    required this.unit,
  });

  factory ApprovedPoMaterialLine.fromJson(Map<String, dynamic> json) {
    return ApprovedPoMaterialLine(
      material: _asString(json['material']),
      quantity: _asString(json['quantity']),
      unit: _asString(json['unit']),
    );
  }
}

/// Masked PO PDF metadata. Only documents whose key/filename/label contain
/// `MASKED` are accepted by the app.
class MaskedPoDocument {
  final String key;
  final String filename;
  final String label;
  final String mimeType;
  final String path;
  final String url;

  const MaskedPoDocument({
    required this.key,
    required this.filename,
    required this.label,
    required this.mimeType,
    required this.path,
    required this.url,
  });

  factory MaskedPoDocument.fromJson(Map<String, dynamic> json) {
    return MaskedPoDocument(
      key: _asString(json['key']),
      filename: _asString(json['filename']),
      label: _asString(json['label']),
      mimeType: _asString(json['mime_type']),
      path: _asString(json['path']),
      url: _asString(json['url']),
    );
  }

  bool get isMasked {
    return _containsMasked(key) ||
        _containsMasked(filename) ||
        _containsMasked(label) ||
        _containsMasked(path);
  }

  static bool _containsMasked(String value) {
    return value.toUpperCase().contains('MASKED');
  }
}

class ApprovedPoListResult {
  final List<ApprovedPo> items;
  final bool hasMore;
  final String message;

  const ApprovedPoListResult({
    required this.items,
    required this.hasMore,
    required this.message,
  });
}

class ApprovedPoException implements Exception {
  final String message;
  final int? statusCode;

  const ApprovedPoException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

String _asString(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
