import 'package:intl/intl.dart';

/// One NT or non-NT bill stage a payment proof amount is allocated against.
class PaymentProofBillStage {
  final int? id;
  final String stageName;
  final String kind; // `nt` | `non_nt`
  final num? amount;
  final String amountDisplay;
  final bool partial;
  final num? billAmount;
  final String billNumber;

  const PaymentProofBillStage({
    this.id,
    required this.stageName,
    required this.kind,
    this.amount,
    this.amountDisplay = '',
    this.partial = false,
    this.billAmount,
    this.billNumber = '',
  });

  bool get isNt => kind == 'nt';

  String get sectionKey {
    final idPart = id?.toString() ?? '';
    final namePart = stageName.trim().toLowerCase();
    final billPart = billNumber.trim().toLowerCase();
    return '$kind|$idPart|$namePart|$billPart';
  }

  String get sectionLabel {
    final name = stageName.trim();
    if (name.isEmpty && billNumber.isEmpty) {
      return isNt ? 'NT bill' : 'Non-NT bill';
    }
    if (name.isEmpty) return billNumber;
    if (billNumber.isEmpty || billNumber == name) return name;
    return '$name $billNumber';
  }

  factory PaymentProofBillStage.fromJson(Map<String, dynamic> json) {
    final kind = normalizeBillStageKind(json['kind']);
    final stageName = (_asString(json['stage_name']) ??
            _asString(json['name']) ??
            _asString(json['task_name']) ??
            '')
        .trim();
    final amount = _asNum(json['amount']);
    final amountDisplay = (_asString(json['amount_display']) ?? '').trim();
    return PaymentProofBillStage(
      id: _asInt(json['id']),
      stageName: stageName,
      kind: kind.isEmpty ? 'non_nt' : kind,
      amount: amount,
      amountDisplay: amountDisplay.isNotEmpty
          ? amountDisplay
          : (amount == null ? '' : formatBillStageAmount(amount)),
      partial: json['partial'] == true,
      billAmount: _asNum(json['bill_amount']),
      billNumber: (_asString(json['bill_number']) ?? '').trim(),
    );
  }

  static List<PaymentProofBillStage> listFromProofJson(
    Map<String, dynamic> json,
  ) {
    final out = <PaymentProofBillStage>[];
    final seen = <String>{};

    void addAll(dynamic raw, {String? forceKind}) {
      if (raw is! List) return;
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        if (forceKind != null &&
            (map['kind'] == null || map['kind'].toString().trim().isEmpty)) {
          map['kind'] = forceKind;
        }
        final stage = PaymentProofBillStage.fromJson(map);
        if (stage.stageName.isEmpty &&
            stage.billNumber.isEmpty &&
            stage.id == null) {
          continue;
        }
        if (seen.add(stage.sectionKey)) out.add(stage);
      }
    }

    // Explicit NT / non-NT lists first (new API shape).
    addAll(json['nt_bills'], forceKind: 'nt');
    addAll(json['non_nt_bills'], forceKind: 'non_nt');
    addAll(json['cleared_bills']);
    addAll(json['finance_applied_bills']);
    return out;
  }
}

String normalizeBillStageKind(dynamic value) {
  final kind =
      (value ?? '').toString().trim().toLowerCase().replaceAll(' ', '_');
  if (kind == 'nt' || kind == 'non_tender' || kind == 'non-tender') {
    return 'nt';
  }
  if (kind == 'non_nt' ||
      kind == 'non-nt' ||
      kind == 'raised' ||
      kind == 'stage' ||
      kind == 'staged' ||
      kind == 'stage_bill' ||
      kind == 'staged_bill') {
    return 'non_nt';
  }
  return '';
}

String formatBillStageAmount(num amount) {
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  ).format(amount);
}

String? _asString(dynamic value) {
  if (value == null) return null;
  return value.toString();
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

num? _asNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) {
    final cleaned = value
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .replaceAll('/-', '')
        .trim();
    return num.tryParse(cleaned);
  }
  return null;
}
