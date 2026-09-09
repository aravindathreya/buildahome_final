import 'workflow_document.dart';

/// Work-order list/detail payloads from `GET /API/work_orders`.
class WorkOrder {
  final int workOrderId;
  final String trade;
  final String woNumber;
  final int value;
  final String status;
  final String statusLabel;
  final bool locked;
  final String createdAt;
  final String comments;
  final WorkOrderContractor contractor;
  final bool hasPdf;
  final WorkOrderDocument? pdfDocument;
  final bool hasDifferenceOfCost;
  final WorkOrderDocument? differenceOfCostDocument;
  final WorkOrderTotals totals;
  final List<WorkOrderMilestone> milestones;
  final List<WorkOrderNote> notes;
  final String projectName;
  final String projectNumber;

  const WorkOrder({
    required this.workOrderId,
    required this.trade,
    required this.woNumber,
    required this.value,
    required this.status,
    required this.statusLabel,
    this.locked = false,
    this.createdAt = '',
    this.comments = '',
    this.contractor = const WorkOrderContractor(),
    this.hasPdf = false,
    this.pdfDocument,
    this.hasDifferenceOfCost = false,
    this.differenceOfCostDocument,
    this.totals = const WorkOrderTotals(),
    this.milestones = const [],
    this.notes = const [],
    this.projectName = '',
    this.projectNumber = '',
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    final contractorRaw = json['contractor'];
    WorkOrderContractor contractor;
    if (contractorRaw is Map) {
      contractor = WorkOrderContractor.fromJson(
        Map<String, dynamic>.from(contractorRaw),
      );
    } else if (contractorRaw != null &&
        contractorRaw.toString().trim().isNotEmpty) {
      contractor = WorkOrderContractor(name: _asString(contractorRaw));
    } else {
      contractor = WorkOrderContractor(
        name: _asString(json['contractor_name']),
        code: _asString(json['contractor_code'] ?? json['code']),
        pan: _asString(json['contractor_pan'] ?? json['pan']),
      );
    }

    final totalsRaw = json['totals'];
    final totals = totalsRaw is Map
        ? WorkOrderTotals.fromJson(Map<String, dynamic>.from(totalsRaw))
        : WorkOrderTotals(
            woValue: _asInt(json['wo_value'] ?? json['value']),
            totalBilled: _asInt(json['total_billed']),
            totalPaid: _asInt(json['total_paid']),
            balance: _asInt(json['balance']),
          );

    return WorkOrder(
      workOrderId: _asInt(json['work_order_id'] ?? json['id']),
      trade: _asString(json['trade'] ?? json['nature_of_work']),
      woNumber: _asString(json['wo_number']),
      value: _asInt(json['value'] ?? json['wo_value']),
      status: _asString(json['status']).toLowerCase(),
      statusLabel: _statusLabelFrom(
        json['status_label'],
        json['status'],
      ),
      locked: _truthy(json['locked']),
      createdAt: _asString(json['created_at'] ?? json['created_date']),
      comments: _asString(json['comments'] ?? json['comment']),
      contractor: contractor,
      hasPdf: _truthy(json['has_pdf']),
      pdfDocument: WorkOrderDocument.tryParse(
        json['pdf_document'] ?? json['pdf'],
      ),
      hasDifferenceOfCost: _truthy(json['has_difference_of_cost']),
      differenceOfCostDocument: WorkOrderDocument.tryParse(
        json['difference_of_cost_document'] ??
            json['difference_of_cost'] ??
            json['doc_pdf'],
      ),
      totals: totals.woValue == 0 && _asInt(json['value']) != 0
          ? totals.copyWith(woValue: _asInt(json['value']))
          : totals,
      milestones: _parseMilestones(json['milestones']),
      notes: _parseNotes(json['notes'] ?? json['work_order_notes']),
      projectName: _asString(json['project_name']),
      projectNumber: _asString(json['project_number']),
    );
  }

  String get displayStatusLabel {
    if (statusLabel.isNotEmpty) return statusLabel;
    return workOrderStatusLabel(status);
  }

  String displayWoNumber({bool prefixWoHash = false}) {
    final number = woNumber.trim().isNotEmpty
        ? woNumber.trim()
        : (workOrderId > 0 ? workOrderId.toString() : '');
    if (number.isEmpty) return '';
    if (prefixWoHash) return 'WO #$number';
    return number;
  }

  String displayWorkOrderNo() {
    if (woNumber.trim().isNotEmpty) return woNumber.trim();
    if (workOrderId > 0) return '#$workOrderId';
    return '';
  }

  WorkOrderStatusKind get statusKind => workOrderStatusKind(status);

  bool get canOpenPdf =>
      hasPdf && (pdfDocument?.resolvedUrl.isNotEmpty ?? false);

  bool get canOpenDifferenceOfCost =>
      hasDifferenceOfCost &&
      (differenceOfCostDocument?.resolvedUrl.isNotEmpty ?? false);

  WorkflowDocumentUpload? workflowPdf({
    required String label,
    WorkOrderDocument? document,
  }) {
    final url = document?.resolvedUrl ?? '';
    if (url.isEmpty) return null;
    final fileName = document?.filename.isNotEmpty == true
        ? document!.filename
        : label;
    return WorkflowDocumentUpload(
      id: 'wo-$workOrderId-${label.toLowerCase().replaceAll(' ', '-')}',
      documentKey: 'work-order-$workOrderId',
      name: fileName,
      url: url,
      contentType: 'application/pdf',
      isLatest: true,
      sectionLabel: label,
      categoryLabel: 'Work orders',
      status: displayStatusLabel,
      taskName: displayWorkOrderNo().isNotEmpty
          ? displayWorkOrderNo()
          : (trade.isNotEmpty ? trade : 'Work order'),
    );
  }
}

class WorkOrderContractor {
  final String name;
  final String code;
  final String pan;

  const WorkOrderContractor({
    this.name = '',
    this.code = '',
    this.pan = '',
  });

  factory WorkOrderContractor.fromJson(Map<String, dynamic> json) {
    return WorkOrderContractor(
      name: _asString(json['name'] ?? json['contractor_name']),
      code: _asString(json['code'] ?? json['contractor_code']),
      pan: _asString(json['pan'] ?? json['contractor_pan']),
    );
  }
}

class WorkOrderDocument {
  final String url;
  final String path;
  final String filename;

  const WorkOrderDocument({
    required this.url,
    this.path = '',
    this.filename = '',
  });

  factory WorkOrderDocument.fromJson(Map<String, dynamic> json) {
    return WorkOrderDocument(
      url: _asString(json['url']),
      path: _asString(json['path']),
      filename: _asString(json['filename'] ?? json['name'] ?? json['label']),
    );
  }

  static WorkOrderDocument? tryParse(dynamic raw) {
    if (raw is Map) {
      final doc = WorkOrderDocument.fromJson(Map<String, dynamic>.from(raw));
      if (doc.resolvedUrl.isEmpty) return null;
      return doc;
    }
    final text = _asString(raw);
    if (text.isEmpty) return null;
    return WorkOrderDocument(url: text);
  }

  String get resolvedUrl {
    final candidate = url.trim().isNotEmpty ? url.trim() : path.trim();
    if (candidate.isEmpty) return '';
    if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
      return candidate;
    }
    if (candidate.startsWith('/')) {
      return 'https://office.buildahome.in$candidate';
    }
    return 'https://office.buildahome.in/$candidate';
  }
}

class WorkOrderTotals {
  final int woValue;
  final int totalBilled;
  final int totalPaid;
  final int balance;

  const WorkOrderTotals({
    this.woValue = 0,
    this.totalBilled = 0,
    this.totalPaid = 0,
    this.balance = 0,
  });

  factory WorkOrderTotals.fromJson(Map<String, dynamic> json) {
    return WorkOrderTotals(
      woValue: _asInt(json['wo_value'] ?? json['value']),
      totalBilled: _asInt(json['total_billed'] ?? json['billed']),
      totalPaid: _asInt(json['total_paid'] ?? json['paid']),
      balance: _asInt(json['balance']),
    );
  }

  WorkOrderTotals copyWith({int? woValue}) {
    return WorkOrderTotals(
      woValue: woValue ?? this.woValue,
      totalBilled: totalBilled,
      totalPaid: totalPaid,
      balance: balance,
    );
  }
}

class WorkOrderMilestone {
  final String stage;
  final String percentage;
  final int billed;
  final int paid;
  final String approvedOn;
  final bool isDebitNote;
  final bool isClearingBalance;
  final String notes;

  const WorkOrderMilestone({
    required this.stage,
    this.percentage = '',
    this.billed = 0,
    this.paid = 0,
    this.approvedOn = '',
    this.isDebitNote = false,
    this.isClearingBalance = false,
    this.notes = '',
  });

  factory WorkOrderMilestone.fromJson(Map<String, dynamic> json) {
    return WorkOrderMilestone(
      stage: _asString(
        json['stage'] ?? json['name'] ?? json['milestone'] ?? json['title'],
      ),
      percentage: _percentageText(json['percentage'] ?? json['percent']),
      billed: _asInt(json['billed'] ?? json['total_billed'] ?? json['amount']),
      paid: _asInt(json['paid'] ?? json['total_paid'] ?? json['amount_paid']),
      approvedOn: _asString(
        json['approved_on'] ?? json['approved_date'] ?? json['approved_at'],
      ),
      isDebitNote: _truthy(json['is_debit_note'] ?? json['debit_note']),
      isClearingBalance:
          _truthy(json['is_clearing_balance'] ?? json['clearing_balance']),
      notes: _asString(json['notes'] ?? json['note']),
    );
  }

  String get displayStage {
    final base = stage.trim().isEmpty ? 'Stage' : stage.trim();
    if (isDebitNote) return 'Debit note · $base';
    return base;
  }

  bool get hasPercentage => percentage.trim().isNotEmpty;
}

class WorkOrderNote {
  final String text;
  final String postedBy;
  final String postedAt;

  const WorkOrderNote({
    required this.text,
    this.postedBy = '',
    this.postedAt = '',
  });

  factory WorkOrderNote.fromJson(Map<String, dynamic> json) {
    return WorkOrderNote(
      text: _asString(
        json['text'] ?? json['note'] ?? json['body'] ?? json['comment'],
      ),
      postedBy: _asString(
        json['posted_by'] ?? json['user'] ?? json['created_by'] ?? json['by'],
      ),
      postedAt: _asString(
        json['posted_at'] ?? json['created_at'] ?? json['date'],
      ),
    );
  }
}

class WorkOrderSummary {
  final int total;
  final int approved;
  final int unsigned;
  final int unapproved;

  const WorkOrderSummary({
    this.total = 0,
    this.approved = 0,
    this.unsigned = 0,
    this.unapproved = 0,
  });

  factory WorkOrderSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WorkOrderSummary();
    return WorkOrderSummary(
      total: _asInt(json['total']),
      approved: _asInt(json['approved']),
      unsigned: _asInt(json['unsigned']),
      unapproved: _asInt(json['unapproved']),
    );
  }
}

class WorkOrderListResult {
  final List<WorkOrder> items;
  final bool hasMore;
  final WorkOrderSummary summary;
  final int projectId;
  final int salesSopId;
  final String projectName;
  final String projectNumber;
  final String status;
  final String message;

  const WorkOrderListResult({
    required this.items,
    required this.hasMore,
    this.summary = const WorkOrderSummary(),
    this.projectId = 0,
    this.salesSopId = 0,
    this.projectName = '',
    this.projectNumber = '',
    this.status = 'all',
    this.message = '',
  });

  factory WorkOrderListResult.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] ?? json['work_orders'];
    final items = <WorkOrder>[];
    if (itemsRaw is List) {
      for (final row in itemsRaw) {
        if (row is Map) {
          items.add(WorkOrder.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    final summaryRaw = json['summary'];
    return WorkOrderListResult(
      items: items,
      hasMore: _truthy(json['has_more']),
      summary: summaryRaw is Map
          ? WorkOrderSummary.fromJson(Map<String, dynamic>.from(summaryRaw))
          : WorkOrderSummary(total: items.length),
      projectId: _asInt(json['project_id']),
      salesSopId: _asInt(json['sales_sop_id']),
      projectName: _asString(json['project_name']),
      projectNumber: _asString(json['project_number']),
      status: _asString(json['status']).isEmpty
          ? 'all'
          : _asString(json['status']),
      message: _asString(json['message']),
    );
  }

  String get projectSubtitle {
    final parts = <String>[];
    if (projectName.trim().isNotEmpty) parts.add(projectName.trim());
    if (projectNumber.trim().isNotEmpty) parts.add(projectNumber.trim());
    return parts.join(' · ');
  }
}

class WorkOrderListSection {
  final String trade;
  final List<WorkOrder> items;

  const WorkOrderListSection({required this.trade, required this.items});
}

/// Groups by trade when there are 4+ items. Otherwise a single flat section.
List<WorkOrderListSection> groupWorkOrdersForDisplay(List<WorkOrder> items) {
  if (items.length < 4) {
    return [WorkOrderListSection(trade: '', items: items)];
  }
  final order = <String>[];
  final map = <String, List<WorkOrder>>{};
  for (final item in items) {
    final key = item.trade.trim().isEmpty ? 'Other' : item.trade.trim();
    if (!map.containsKey(key)) {
      order.add(key);
      map[key] = [];
    }
    map[key]!.add(item);
  }
  return [
    for (final trade in order)
      WorkOrderListSection(trade: trade, items: map[trade]!),
  ];
}

enum WorkOrderStatusKind { approved, unapproved, unsigned, other }

WorkOrderStatusKind workOrderStatusKind(String status) {
  switch (status.trim().toLowerCase()) {
    case 'approved':
      return WorkOrderStatusKind.approved;
    case 'unapproved':
    case 'awaiting approval':
    case 'awaiting_approval':
      return WorkOrderStatusKind.unapproved;
    case 'unsigned':
      return WorkOrderStatusKind.unsigned;
    default:
      return WorkOrderStatusKind.other;
  }
}

String workOrderStatusLabel(String? status) {
  switch ((status ?? '').trim().toLowerCase()) {
    case 'approved':
      return 'Approved';
    case 'unapproved':
    case 'awaiting approval':
    case 'awaiting_approval':
      return 'Awaiting approval';
    case 'unsigned':
      return 'Unsigned';
    default:
      return _asString(status);
  }
}

String _statusLabelFrom(dynamic label, dynamic status) {
  final explicit = _asString(label);
  if (explicit.isNotEmpty) return explicit;
  return workOrderStatusLabel(_asString(status));
}

/// Indian grouping: `₹1,20,000`. Negative values keep the minus sign.
String formatIndianRupees(num amount) {
  final n = amount.round();
  final neg = n < 0;
  var s = n.abs().toString();
  if (s.length <= 3) return '${neg ? '-' : ''}₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${neg ? '-' : ''}₹${parts.join(',')},$last3';
}

List<WorkOrderMilestone> _parseMilestones(dynamic raw) {
  if (raw is! List) return const [];
  final out = <WorkOrderMilestone>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(
        WorkOrderMilestone.fromJson(Map<String, dynamic>.from(row)),
      );
    }
  }
  return out;
}

List<WorkOrderNote> _parseNotes(dynamic raw) {
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    return [WorkOrderNote(text: text)];
  }
  if (raw is! List) return const [];
  final out = <WorkOrderNote>[];
  for (final row in raw) {
    if (row is Map) {
      final note = WorkOrderNote.fromJson(Map<String, dynamic>.from(row));
      if (note.text.isNotEmpty) out.add(note);
    } else {
      final text = _asString(row);
      if (text.isNotEmpty) out.add(WorkOrderNote(text: text));
    }
  }
  return out;
}

String _percentageText(dynamic value) {
  if (value == null) return '';
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text.replaceAll('%', '').trim();
  }
  if (value is num) return value.toString();
  return _asString(value);
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
  if (value is String) {
    final cleaned =
        value.replaceAll(',', '').replaceAll('₹', '').replaceAll(' ', '').trim();
    if (cleaned.isEmpty) return 0;
    return int.tryParse(cleaned) ?? double.tryParse(cleaned)?.toInt() ?? 0;
  }
  return 0;
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
