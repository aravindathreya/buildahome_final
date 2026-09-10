import 'package:intl/intl.dart';

/// One uploaded payment-proof file from the client-portal upload response
/// or GET `payment_proof` snapshot.
class PaymentProofItem {
  static const notABillFallback = 'Not a bill';
  static const amountPlaceholder = '—';

  final String url;
  final String filename;
  final String label;
  final bool isPdf;
  final bool? isBill;
  final String rejectionCode;
  final String rejectionLabel;
  final num? receiptTotal;
  final String status;
  final String rejectReason;
  final String note;
  final int? index;
  final bool rejectedFlag;
  final bool? canDeleteFlag;

  const PaymentProofItem({
    required this.url,
    required this.filename,
    required this.label,
    required this.isPdf,
    required this.isBill,
    required this.rejectionCode,
    required this.rejectionLabel,
    required this.receiptTotal,
    required this.status,
    required this.rejectReason,
    required this.note,
    this.index,
    this.rejectedFlag = false,
    this.canDeleteFlag,
  });

  bool get isNotABill =>
      isBill == false || rejectionCode.toLowerCase() == 'not_a_bill';

  bool get isStatusRejected =>
      status.toLowerCase() == 'rejected' || rejectedFlag;

  /// Card uses reject treatment for finance reject and OpenAI not-a-bill.
  bool get isRejected => isStatusRejected || isNotABill || note.isNotEmpty;

  bool get isApproved {
    final s = status.toLowerCase();
    return s == 'approved' || s == 'accepted' || s == 'verified';
  }

  /// Clients may remove any proof that finance has not approved.
  bool get canRemove {
    if (canDeleteFlag == false) return false;
    if (canDeleteFlag == true) return true;
    return !isApproved;
  }

  String get rejectionDisplayText {
    if (note.isNotEmpty) return note;
    if (isRejected) return 'Rejected';
    return '';
  }

  /// Overlay badge only when the backend classified the file as not a bill.
  bool get showNotABillBadge => isBill == false;

  String get notABillBadgeText {
    if (rejectionLabel.isNotEmpty) return rejectionLabel;
    return notABillFallback;
  }

  /// Parsed bill amount under the thumbnail whenever the API sent one.
  String get displayAmount {
    if (receiptTotal == null) return amountPlaceholder;
    return formatReceiptAmount(receiptTotal!);
  }

  /// Rejected / not-a-bill amounts must not be summed into a payment total.
  bool get countsTowardPaymentTotal =>
      !isNotABill && !isStatusRejected && receiptTotal != null;

  factory PaymentProofItem.fromJson(
    Map<String, dynamic> json, {
    String Function(String url)? resolveUrl,
    String? fallbackLabel,
    int? fallbackIndex,
  }) {
    final flat = _flattenProofJson(json);
    final rawUrl = _firstString(flat, const [
          'url',
          'file_url',
          'screenshot_url',
          'payment_screenshot_url',
          'image_url',
          'src',
          'path',
        ]) ??
        '';
    final url = resolveUrl != null && rawUrl.isNotEmpty
        ? resolveUrl(rawUrl)
        : rawUrl;
    final filename = _firstString(flat, const [
          'filename',
          'file_name',
          'original_filename',
          'name',
        ]) ??
        '';
    final isPdf = flat['is_pdf'] == true || _looksLikePdf(url, filename);
    final label = _firstString(flat, const ['label']) ??
        fallbackLabel ??
        (filename.isNotEmpty ? filename : 'Payment proof');
    final rejectedFlag = _asBool(flat['is_rejected']) == true ||
        _asBool(flat['rejected']) == true;

    return PaymentProofItem(
      url: url,
      filename: filename,
      label: label,
      isPdf: isPdf,
      isBill: _asBool(flat['is_bill']),
      rejectionCode: (_asString(flat['rejection_code']) ?? '').trim(),
      rejectionLabel: (_asString(flat['rejection_label']) ?? '').trim(),
      receiptTotal: _receiptTotalOf(flat),
      status: (_asString(flat['status']) ?? '').trim(),
      rejectReason: (_rejectReasonOf(flat) ?? '').trim(),
      note: resolveDisplayNote(flat),
      index: _asInt(flat['index']) ??
          _asInt(flat['file_index']) ??
          _asInt(flat['screenshot_index']) ??
          _indexFromUrl(url) ??
          fallbackIndex,
      rejectedFlag: rejectedFlag,
      canDeleteFlag: _asBool(flat['can_delete']) ??
          _asBool(flat['can_remove']) ??
          _asBool(flat['deletable']),
    );
  }

  /// `note` is the one string under the image. Backend fills it as:
  /// finance reason, else not-a-bill label, else empty.
  ///
  /// If `note` is missing (old payload):
  /// - rejected + reject_reason → reject_reason
  /// - is_bill false / rejection_code not_a_bill → rejection_label or "Not a bill"
  static String resolveDisplayNote(Map<String, dynamic> json) {
    final flat = _flattenProofJson(json);
    final note = (_asString(flat['note']) ?? '').trim();
    if (note.isNotEmpty) return note;

    final status = (_asString(flat['status']) ?? '').trim().toLowerCase();
    final rejectedFlag = _asBool(flat['is_rejected']) == true ||
        _asBool(flat['rejected']) == true;
    final rejectReason = (_rejectReasonOf(flat) ?? '').trim();
    if ((status == 'rejected' || rejectedFlag) && rejectReason.isNotEmpty) {
      return rejectReason;
    }

    final isBill = _asBool(flat['is_bill']);
    final rejectionCode =
        (_asString(flat['rejection_code']) ?? '').trim().toLowerCase();
    if (isBill == false || rejectionCode == 'not_a_bill') {
      final label = (_asString(flat['rejection_label']) ?? '').trim();
      return label.isNotEmpty ? label : notABillFallback;
    }
    if (status == 'rejected' || rejectedFlag) {
      return rejectReason;
    }
    return '';
  }

  static List<PaymentProofItem> listFromPayload(
    Map<String, dynamic> payload, {
    String Function(String url)? resolveUrl,
  }) {
    final section = payload['section'] is Map
        ? Map<String, dynamic>.from(payload['section'] as Map)
        : <String, dynamic>{};

    final maps = _mergedFileMaps(section, payload, resolveUrl: resolveUrl);
    if (maps.isNotEmpty) {
      return [
        for (var i = 0; i < maps.length; i++)
          PaymentProofItem.fromJson(
            maps[i],
            resolveUrl: resolveUrl,
            fallbackLabel: maps.length == 1
                ? 'Payment proof'
                : 'Payment proof ${i + 1}',
            fallbackIndex: i + 1,
          ),
      ].where((item) => item.url.isNotEmpty).toList();
    }

    final urls = _urlList(section['payment_screenshot_urls']) +
        _urlList(payload['payment_screenshot_urls']) +
        _urlList(section['payment_screenshot_url']) +
        _urlList(payload['payment_screenshot_url']);
    final unique = <String>[];
    for (final url in urls) {
      final resolved = resolveUrl != null ? resolveUrl(url) : url;
      if (resolved.isNotEmpty && !unique.contains(resolved)) {
        unique.add(resolved);
      }
    }
    return [
      for (var i = 0; i < unique.length; i++)
        PaymentProofItem(
          url: unique[i],
          filename: '',
          label: unique.length == 1
              ? 'Payment proof'
              : 'Payment proof ${i + 1}',
          isPdf: _looksLikePdf(unique[i], ''),
          isBill: null,
          rejectionCode: '',
          rejectionLabel: '',
          receiptTotal: null,
          status: '',
          rejectReason: '',
          note: '',
          index: _indexFromUrl(unique[i]) ?? (i + 1),
          canDeleteFlag: null,
        ),
    ];
  }

  static bool payloadHasFileRecords(Map<String, dynamic> payload) {
    final section = payload['section'] is Map
        ? Map<String, dynamic>.from(payload['section'] as Map)
        : <String, dynamic>{};
    return _mergedFileMaps(section, payload).any(_hasClassificationFields);
  }

  static num billableTotal(Iterable<PaymentProofItem> items) {
    var sum = 0.0;
    for (final item in items) {
      if (!item.countsTowardPaymentTotal) continue;
      sum += item.receiptTotal!.toDouble();
    }
    return sum;
  }
}

String formatReceiptAmount(num amount) {
  final decimals = (amount % 1).abs() < 0.001 ? 0 : 2;
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: decimals,
  ).format(amount);
}

const _fileListKeys = [
  'payment_proof_items',
  'files',
  'uploaded_files',
  'items',
  'payment_screenshots',
  'screenshots',
  'proofs',
  'payment_screenshot_urls',
];

List<Map<String, dynamic>> _sourcesOf(
  Map<String, dynamic> section,
  Map<String, dynamic> payload,
) {
  final sources = <Map<String, dynamic>>[section, payload];
  if (section['data'] is Map) {
    sources.add(Map<String, dynamic>.from(section['data'] as Map));
  }
  if (payload['data'] is Map) {
    sources.add(Map<String, dynamic>.from(payload['data'] as Map));
  }
  return sources;
}

List<List<Map<String, dynamic>>> _allFileMapLists(
  Map<String, dynamic> section,
  Map<String, dynamic> payload,
) {
  final lists = <List<Map<String, dynamic>>>[];
  for (final key in _fileListKeys) {
    for (final source in _sourcesOf(section, payload)) {
      final parsed = _mapsFromMixedList(source[key]);
      if (parsed.isNotEmpty) lists.add(parsed);
    }
  }
  return lists;
}

/// Prefer the longest file list (full snapshot), then overlay classification
/// fields from any shorter upload `files` list onto matching url/filename.
List<Map<String, dynamic>> _mergedFileMaps(
  Map<String, dynamic> section,
  Map<String, dynamic> payload, {
  String Function(String url)? resolveUrl,
}) {
  final lists = _allFileMapLists(section, payload);
  if (lists.isEmpty) return const [];

  lists.sort((a, b) {
    final byLength = b.length.compareTo(a.length);
    if (byLength != 0) return byLength;
    final aClass = a.any(_hasClassificationFields);
    final bClass = b.any(_hasClassificationFields);
    if (aClass == bClass) return 0;
    return aClass ? -1 : 1;
  });
  final base = lists.first;
  final overlays = <String, Map<String, dynamic>>{};
  for (final list in lists) {
    for (final map in list) {
      if (!_hasClassificationFields(map)) continue;
      for (final key in _overlayKeys(map, resolveUrl: resolveUrl)) {
        overlays[key] = map;
      }
    }
  }
  if (overlays.isEmpty) return _withUnseenFiles(base, lists, resolveUrl: resolveUrl);

  final merged = [
    for (final map in base)
      _overlayClassification(map, overlays, resolveUrl: resolveUrl),
  ];
  return _withUnseenFiles(merged, lists, resolveUrl: resolveUrl);
}

List<Map<String, dynamic>> _withUnseenFiles(
  List<Map<String, dynamic>> base,
  List<List<Map<String, dynamic>>> lists, {
  String Function(String url)? resolveUrl,
}) {
  final seen = <String>{};
  for (final map in base) {
    seen.addAll(_overlayKeys(map, resolveUrl: resolveUrl));
  }
  final extra = <Map<String, dynamic>>[];
  for (final list in lists) {
    for (final map in list) {
      final keys = _overlayKeys(map, resolveUrl: resolveUrl).toList();
      if (keys.isEmpty || keys.any(seen.contains)) continue;
      extra.add(map);
      seen.addAll(keys);
    }
  }
  if (extra.isEmpty) return base;
  return [...base, ...extra];
}

Map<String, dynamic> _overlayClassification(
  Map<String, dynamic> map,
  Map<String, Map<String, dynamic>> overlays, {
  String Function(String url)? resolveUrl,
}) {
  for (final key in _overlayKeys(map, resolveUrl: resolveUrl)) {
    final overlay = overlays[key];
    if (overlay == null) continue;
    return {...map, ...overlay};
  }
  return map;
}

Iterable<String> _overlayKeys(
  Map<String, dynamic> json, {
  String Function(String url)? resolveUrl,
}) sync* {
  final rawUrl = _firstString(json, const [
        'url',
        'file_url',
        'screenshot_url',
        'payment_screenshot_url',
        'image_url',
        'src',
        'path',
      ]) ??
      '';
  if (rawUrl.isNotEmpty) {
    yield resolveUrl != null ? resolveUrl(rawUrl) : rawUrl;
    yield rawUrl;
  }
  final filename = _firstString(json, const [
        'filename',
        'file_name',
        'original_filename',
        'name',
      ]) ??
      '';
  if (filename.isNotEmpty) yield filename;
}

bool _hasClassificationFields(Map<String, dynamic> json) {
  return json.containsKey('is_bill') ||
      json.containsKey('note') ||
      json.containsKey('status') ||
      json.containsKey('rejection_code') ||
      json.containsKey('reject_reason') ||
      json.containsKey('rejection_label') ||
      json.containsKey('receipt_total') ||
      json.containsKey('parsed_amount') ||
      json.containsKey('extracted_amount') ||
      json.containsKey('amount') ||
      json.containsKey('is_rejected') ||
      json.containsKey('finance_reject_reason') ||
      json.containsKey('can_delete') ||
      json.containsKey('can_remove');
}

List<Map<String, dynamic>> _mapsFromMixedList(dynamic raw) {
  if (raw is Map) {
    return [Map<String, dynamic>.from(raw)];
  }
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    } else {
      final url = e?.toString().trim() ?? '';
      if (url.isNotEmpty) out.add({'url': url});
    }
  }
  return out;
}

List<String> _urlList(dynamic value) {
  if (value is List) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
  final single = value?.toString().trim() ?? '';
  return single.isEmpty ? const [] : [single];
}

bool _looksLikePdf(String url, String filename) {
  final lower = '${url.toLowerCase()} ${filename.toLowerCase()}';
  return lower.contains('.pdf') || lower.contains('application/pdf');
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _asString(json[key]);
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  return value.toString();
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) {
    if (value == 1) return true;
    if (value == 0) return false;
    return null;
  }
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return null;
}

bool _hasMeaningfulValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  return true;
}

Map<String, dynamic> _flattenProofJson(Map<String, dynamic> json) {
  final out = Map<String, dynamic>.from(json);
  for (final key in const [
    'openai',
    'classification',
    'analysis',
    'receipt',
    'parsed',
    'bill',
    'result',
  ]) {
    final nested = json[key];
    if (nested is! Map) continue;
    Map<String, dynamic>.from(nested).forEach((k, v) {
      if (!_hasMeaningfulValue(out[k])) out[k] = v;
    });
  }
  return out;
}

String? _rejectReasonOf(Map<String, dynamic> json) {
  return _firstString(json, const [
    'reject_reason',
    'finance_reject_reason',
    'rejection_reason',
    'reject_note',
    'rejection_note',
    'reason',
  ]);
}

num? _receiptTotalOf(Map<String, dynamic> json) {
  return _firstNum(json, const [
    'receipt_total',
    'parsed_amount',
    'extracted_amount',
    'extracted_total',
    'parsed_total',
    'bill_amount',
    'receipt_amount',
    'total_amount',
    'amount',
    'total',
  ]);
}

num? _firstNum(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _asNum(json[key]);
    if (value != null) return value;
  }
  return null;
}

int? _indexFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final raw = uri.queryParameters['index'];
  if (raw == null || raw.trim().isEmpty) return null;
  return int.tryParse(raw.trim());
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
  if (value is Map) {
    return _asNum(
      value['amount'] ?? value['total'] ?? value['value'] ?? value['receipt_total'],
    );
  }
  if (value is String) {
    var cleaned = value
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .replaceAll('/-', '')
        .replaceAll(RegExp(r'(rs\.?|inr)', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty) return null;
    final direct = num.tryParse(cleaned);
    if (direct != null) return direct;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(cleaned);
    if (match == null) return null;
    return num.tryParse(match.group(0)!);
  }
  return null;
}
