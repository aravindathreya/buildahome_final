import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'UploadPaymentProofScreen.dart';
import 'app_theme.dart';
import 'models/payment_proof_item.dart';
import 'services/client_portal_service.dart';
import 'services/data_provider.dart';
import 'widgets/dashboard_chrome.dart';
import 'widgets/themed_scaffold.dart';

enum PaymentCategory {
  tender,
  nonTender,
}

/// Snapshot of tender + non-tender payment data for a project.
class ProjectPaymentsSnapshot {
  final PaymentSummary tenderSummary;
  final PaymentSummary nonTenderSummary;
  final List<PaymentItem> tenderItems;
  final List<PaymentItem> nonTenderItems;

  const ProjectPaymentsSnapshot({
    required this.tenderSummary,
    required this.nonTenderSummary,
    required this.tenderItems,
    required this.nonTenderItems,
  });

  double get totalOutstanding =>
      tenderSummary.outstandingNumeric + nonTenderSummary.outstandingNumeric;

  /// Pending line items only (excludes paid / scheduled), tender then non-tender.
  List<PendingPaymentRow> get pendingPaymentRows {
    final rows = <PendingPaymentRow>[];
    for (final item in tenderItems) {
      if (!item.isPending) continue;
      rows.add(PendingPaymentRow(
        name: item.name,
        amount: item.resolvedAmount(tenderSummary),
        isTender: true,
        status: item.status,
      ));
    }
    for (final item in nonTenderItems) {
      if (!item.isPending) continue;
      rows.add(PendingPaymentRow(
        name: item.name,
        amount: item.resolvedAmount(nonTenderSummary),
        isTender: false,
        status: item.status,
      ));
    }
    return rows;
  }
}

class PaymentBillRef {
  final String taskId;
  final String name;
  final String description;
  final bool isTender;
  final String status;
  final double amount;

  const PaymentBillRef({
    required this.taskId,
    required this.name,
    required this.description,
    required this.isTender,
    required this.status,
    this.amount = 0,
  });

  /// Non-NT shows the stage name. NT shows the description from creation.
  String get appliedLabel {
    if (!isTender) {
      final note = description.trim();
      if (note.isNotEmpty && note.toLowerCase() != 'null') return note;
    }
    return name.trim();
  }
}

List<PaymentBillRef> paymentBillRefs(ProjectPaymentsSnapshot snapshot) {
  final out = <PaymentBillRef>[];
  for (final item in [...snapshot.tenderItems, ...snapshot.nonTenderItems]) {
    out.add(PaymentBillRef(
      taskId: item.taskId?.trim() ?? '',
      name: item.name,
      description: item.note?.trim() ?? '',
      isTender: item.isTender,
      status: item.status,
      amount: item.resolvedAmount(
        item.isTender ? snapshot.tenderSummary : snapshot.nonTenderSummary,
      ),
    ));
  }
  return out;
}

List<PaymentBillRef> paymentBillsForProof(
  PaymentProofItem item,
  List<PaymentBillRef> bills,
) {
  final hits = <PaymentBillRef>[];
  void add(PaymentBillRef? ref) {
    if (ref == null) return;
    if (hits.any((e) => e.taskId == ref.taskId && e.name == ref.name)) return;
    hits.add(ref);
  }

  PaymentBillRef? byId(String? id) {
    final wanted = id?.trim() ?? '';
    if (wanted.isEmpty) return null;
    for (final bill in bills) {
      if (bill.taskId == wanted) return bill;
    }
    return null;
  }

  PaymentBillRef? byName(String name, {bool? isTender}) {
    final key = _paymentMatchKey(name);
    if (key.isEmpty) return null;
    for (final bill in bills) {
      if (isTender != null && bill.isTender != isTender) continue;
      if (_paymentMatchKey(bill.name) == key) return bill;
    }
    return null;
  }

  add(byId(item.stageTaskId?.toString()));
  add(byName(item.stageName));
  for (final stage in item.billStages) {
    add(byId(stage.id?.toString()));
    add(byName(stage.stageName, isTender: !stage.isNt));
    add(byName(stage.sectionLabel, isTender: !stage.isNt));
  }
  return hits;
}

List<String> previousPaymentStageLabels(
  PaymentProofItem item,
  List<PaymentBillRef> bills,
) {
  if (item.isNotABill) return const [];
  if (item.appliedStageLabels.isNotEmpty) return item.appliedStageLabels;
  final matched = paymentBillsForProof(item, bills)
      .map((bill) => bill.appliedLabel.trim())
      .where((label) => label.isNotEmpty)
      .toSet()
      .toList();
  if (matched.isNotEmpty) return matched;
  final stage = item.stageName.trim();
  if (stage.isNotEmpty) return [stage];
  final text = item.clearedBillsText.trim();
  if (text.isEmpty) return const [];
  return text
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^(NT|Non-NT):\s*'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

class _RemainingBill {
  final PaymentBillRef bill;
  double left;

  _RemainingBill(this.bill, this.left);
}

/// Stages each previous-payment screenshot was applied to, in upload order.
/// When the proof names its stages, those are used. Otherwise the receipt
/// amount is walked across tender stages, then NT bills.
Map<String, List<String>> previousPaymentStagesByUrl({
  required List<PaymentProofItem> proofs,
  required List<PaymentBillRef> bills,
}) {
  final pools = <_RemainingBill>[
    for (final bill in bills)
      if (!isPaymentStatusScheduled(bill.status) && bill.amount > 0.5)
        _RemainingBill(bill, bill.amount),
  ];
  var cursor = 0;
  final ordered = [...proofs]..sort((a, b) {
      final byIndex = (a.index ?? 1 << 30).compareTo(b.index ?? 1 << 30);
      if (byIndex != 0) return byIndex;
      return a.url.compareTo(b.url);
    });
  final out = <String, List<String>>{};

  for (final proof in ordered) {
    if (proof.url.isEmpty || proof.isNotABill || proof.isStatusRejected) {
      continue;
    }
    final amount = proof.receiptTotal?.toDouble() ?? 0;
    final explicit = previousPaymentStageLabels(proof, bills);
    final hasExplicit = proof.appliedStageLabels.isNotEmpty ||
        proof.stageName.trim().isNotEmpty ||
        proof.clearedBillsText.trim().isNotEmpty;
    if (hasExplicit && explicit.isNotEmpty) {
      out[proof.url] = explicit;
      var left = amount;
      while (left > 0.5 && cursor < pools.length) {
        final pool = pools[cursor];
        if (left + 0.5 >= pool.left) {
          left -= pool.left;
          pool.left = 0;
          cursor++;
        } else {
          pool.left -= left;
          left = 0;
        }
      }
      continue;
    }

    if (amount <= 0.5 || cursor >= pools.length) continue;
    final labels = <String>[];
    var left = amount;
    while (left > 0.5 && cursor < pools.length) {
      final pool = pools[cursor];
      final label = pool.bill.appliedLabel.trim();
      if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
      if (left + 0.5 >= pool.left) {
        left -= pool.left;
        pool.left = 0;
        cursor++;
      } else {
        pool.left -= left;
        left = 0;
      }
    }
    if (labels.isNotEmpty) out[proof.url] = labels;
  }
  return out;
}

/// `paid` | `in review` | `pending`. Empty when the file is not a bill.
String previousPaymentDotStatus(
  PaymentProofItem item,
  List<PaymentBillRef> bills,
) {
  if (item.isNotABill || item.isStatusRejected) return '';
  final linked = paymentBillsForProof(item, bills);
  if (item.isFinanceSettled ||
      linked.any((bill) => isPaymentStatusPaid(bill.status))) {
    return 'paid';
  }
  if (linked.any((bill) => isPaymentStatusInReview(bill.status)) ||
      item.isBill == true ||
      item.isCorrectBill) {
    return 'in review';
  }
  return 'pending';
}

Color previousPaymentDotColor(String status) {
  if (isPaymentStatusPaid(status)) return const Color(0xFF22C55E);
  if (isPaymentStatusInReview(status)) return const Color(0xFF3B82F6);
  return const Color(0xFFEAB308);
}

class PendingPaymentRow {
  final String name;
  final double amount;
  final bool isTender;
  final String status;

  const PendingPaymentRow({
    required this.name,
    required this.amount,
    required this.isTender,
    required this.status,
  });
}

class AllocatedPendingPayments {
  final List<PendingPaymentRow> rows;

  /// Stage names fully covered by finance-approved proofs.
  final Set<String> clearedNameKeys;

  const AllocatedPendingPayments({
    required this.rows,
    required this.clearedNameKeys,
  });

  double get total => rows.fold<double>(0, (sum, row) => sum + row.amount);
}

/// Applies finance-approved proof totals onto pending stages in list order.
///
/// A 13 lakh proof against two 7 lakh stages clears the first and leaves
/// 1 lakh on the second. Tender and non-tender rows share one running total.
AllocatedPendingPayments allocateFinanceApprovedPayments({
  required List<PendingPaymentRow> rows,
  required List<PaymentProofItem> proofs,
}) {
  var pool = 0.0;
  for (final proof in proofs) {
    if (!proof.isFinanceSettled) continue;
    final amount = proof.receiptTotal?.toDouble() ?? 0;
    if (amount > 0) pool += amount;
  }

  if (pool <= 0.5) {
    return AllocatedPendingPayments(
      rows: rows,
      clearedNameKeys: const {},
    );
  }

  final remaining = <PendingPaymentRow>[];
  final cleared = <String>{};
  for (final row in rows) {
    if (pool <= 0.5 || row.amount <= 0) {
      if (row.amount > 0.5) remaining.add(row);
      continue;
    }
    if (pool + 0.5 >= row.amount) {
      pool -= row.amount;
      final key = _paymentMatchKey(row.name);
      if (key.isNotEmpty) cleared.add(key);
      continue;
    }
    remaining.add(PendingPaymentRow(
      name: row.name,
      amount: row.amount - pool,
      isTender: row.isTender,
      status: row.status,
    ));
    pool = 0;
  }

  return AllocatedPendingPayments(rows: remaining, clearedNameKeys: cleared);
}

bool paymentStageNameIsCleared(String name, Set<String> clearedNameKeys) {
  if (clearedNameKeys.isEmpty) return false;
  final key = _paymentMatchKey(name);
  if (key.isEmpty) return false;
  return clearedNameKeys.contains(key);
}

bool isPaymentStatusPaid(String status) {
  return status.toLowerCase().trim() == 'paid';
}

bool isPaymentStatusScheduled(String status) {
  final normalized = status.toLowerCase().trim();
  return normalized == 'not due' || normalized == 'wip';
}

bool isPaymentStatusInReview(String status) {
  final normalized = status.toLowerCase().trim().replaceAll('_', ' ');
  return normalized == 'in review';
}

bool isPaymentStatusPending(String status) {
  return !isPaymentStatusPaid(status) && !isPaymentStatusScheduled(status);
}

/// A real screenshot that finance has not approved yet.
bool paymentProofAwaitsFinanceReview(PaymentProofItem proof) {
  if (proof.isNotABill || proof.isStatusRejected || proof.isApproved) {
    return false;
  }
  return proof.url.trim().isNotEmpty || proof.filename.trim().isNotEmpty;
}

String _paymentMatchKey(String value) {
  var text = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  const prefix = 'completion of ';
  if (text.startsWith(prefix)) {
    text = text.substring(prefix.length).trim();
  }
  return text;
}

bool paymentHasUnapprovedScreenshot({
  required String paymentName,
  required bool isTender,
  String? taskId,
  required List<PaymentProofItem> proofs,
}) {
  final nameKey = _paymentMatchKey(paymentName);
  final id = taskId?.trim() ?? '';
  for (final proof in proofs) {
    if (!paymentProofAwaitsFinanceReview(proof)) continue;
    if (id.isNotEmpty && proof.stageTaskId?.toString() == id) return true;
    if (nameKey.isNotEmpty &&
        proof.stageName.isNotEmpty &&
        _paymentMatchKey(proof.stageName) == nameKey) {
      return true;
    }
    for (final stage in proof.billStages) {
      if (isTender && stage.isNt) continue;
      if (!isTender && !stage.isNt) continue;
      final stageKey = _paymentMatchKey(stage.stageName);
      final labelKey = _paymentMatchKey(stage.sectionLabel);
      if (nameKey.isNotEmpty &&
          (stageKey == nameKey || labelKey == nameKey)) {
        return true;
      }
    }
  }
  return false;
}

/// Paid stays paid. A linked screenshot that finance has not approved
/// shows as in review. Scheduled rows stay scheduled so the list can hide them.
String displayedPaymentStatus({
  required String paidStatus,
  required String name,
  required bool isTender,
  String? taskId,
  required List<PaymentProofItem> proofs,
}) {
  if (isPaymentStatusPaid(paidStatus)) return paidStatus;
  if (paymentHasUnapprovedScreenshot(
    paymentName: name,
    isTender: isTender,
    taskId: taskId,
    proofs: proofs,
  )) {
    return 'in review';
  }
  return paidStatus;
}

String? _paymentTaskId(Map item) {
  final raw = item['id'] ?? item['task_id'];
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  return text;
}

Future<List<PaymentProofItem>> _loadPaymentProofs() async {
  try {
    final payload = await ClientPortalService().getPaymentProof();
    return PaymentProofItem.listFromPayload(payload);
  } catch (e) {
    print('[Payments] payment proof load skipped: $e');
    return const [];
  }
}

double _paymentValueToDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(
          value.toString().replaceAll(RegExp('[^0-9\\.]'), '')) ??
      0;
}

/// Fetches payment summary plus tender and non-tender line items.
Future<ProjectPaymentsSnapshot> fetchProjectPaymentsSnapshot(
  String projectId, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final paymentUrl =
      'https://office1.buildahome.in/API/get_payment?project_id=$projectId';
  final tenderUrl =
      'https://office1.buildahome.in/API/get_all_tasks?project_id=$projectId&nt_toggle=0';
  final nonTenderUrl =
      'https://office1.buildahome.in/API/get_all_non_tender?project_id=$projectId';

  Future<http.Response?> safeGet(String url) async {
    try {
      return await http.get(Uri.parse(url)).timeout(timeout);
    } catch (e) {
      print('[Payments] fetchProjectPaymentsSnapshot request error: $e');
      return null;
    }
  }

  final results = await Future.wait<dynamic>([
    safeGet(paymentUrl),
    safeGet(tenderUrl),
    safeGet(nonTenderUrl),
    _loadPaymentProofs(),
  ]);

  final paymentResponse = results[0];
  if (paymentResponse == null || paymentResponse.statusCode != 200) {
    throw Exception('Unable to load payment summary right now.');
  }

  List<dynamic> tenderData = [];
  List<dynamic> nonTenderData = [];

  final tenderResponse = results[1];
  if (tenderResponse != null && tenderResponse.statusCode == 200) {
    final decoded = jsonDecode(tenderResponse.body);
    if (decoded is List) tenderData = decoded;
  }

  final nonTenderResponse = results[2];
  if (nonTenderResponse != null && nonTenderResponse.statusCode == 200) {
    final decoded = jsonDecode(nonTenderResponse.body);
    if (decoded is List) nonTenderData = decoded;
  }

  final proofs = results[3] as List<PaymentProofItem>;
  final paymentDetails = jsonDecode(paymentResponse.body);
  final summary = (paymentDetails is List && paymentDetails.isNotEmpty)
      ? Map<String, dynamic>.from(paymentDetails[0] as Map)
      : <String, dynamic>{};

  final tenderSummary = PaymentSummary(
    value: (summary['value'] ?? '0').toString(),
    totalPaid: (summary['total_paid'] ?? '0').toString(),
    outstanding: (summary['outstanding'] ?? '0').toString(),
  );

  final nonTenderSummary = PaymentSummary(
    value: (summary['nt_value'] ?? summary['value'] ?? '0').toString(),
    totalPaid: (summary['nt_total_paid'] ?? '0').toString(),
    outstanding: (summary['nt_outstanding'] ?? '0').toString(),
  );

  final tenderItems = tenderData
      .map<PaymentItem>((item) {
        final name = (item['task_name'] ?? 'Milestone').toString();
        final taskId = item is Map ? _paymentTaskId(Map<String, dynamic>.from(item)) : null;
        return PaymentItem(
            name: name,
            percentage: _paymentValueToDouble(item['payment']),
            status: displayedPaymentStatus(
              paidStatus: (item['paid'] ?? '').toString(),
              name: name,
              isTender: true,
              taskId: taskId,
              proofs: proofs,
            ),
            note: item['p_note']?.toString(),
            startDate: item['start_date']?.toString(),
            endDate: item['end_date']?.toString(),
            markedAsDueOn: item['marked_as_due_on']?.toString(),
            markedAsPaidOn: item['marked_as_paid_on']?.toString(),
            isTender: true,
            taskId: taskId,
          );
      })
      .toList();

  final nonTenderItems = nonTenderData
      .map<PaymentItem>((item) {
        final name = (item['task_name'] ?? 'Non tender item').toString();
        final taskId = item is Map ? _paymentTaskId(Map<String, dynamic>.from(item)) : null;
        return PaymentItem(
            name: name,
            percentage: _paymentValueToDouble(item['payment']),
            status: displayedPaymentStatus(
              paidStatus: (item['paid'] ?? '').toString(),
              name: name,
              isTender: false,
              taskId: taskId,
              proofs: proofs,
            ),
            note: item['p_note']?.toString(),
            startDate: item['start_date']?.toString(),
            endDate: item['end_date']?.toString(),
            markedAsDueOn: item['marked_as_due_on']?.toString(),
            markedAsPaidOn: item['marked_as_paid_on']?.toString(),
            isTender: false,
            amountOverride: _paymentValueToDouble(item['payment']),
            taskId: taskId,
          );
      })
      .toList();

  return ProjectPaymentsSnapshot(
    tenderSummary: tenderSummary,
    nonTenderSummary: nonTenderSummary,
    tenderItems: tenderItems,
    nonTenderItems: nonTenderItems,
  );
}

class PaymentTaskWidget extends StatelessWidget {
  final PaymentCategory initialCategory;

  const PaymentTaskWidget({this.initialCategory = PaymentCategory.tender});

  @override
  Widget build(BuildContext context) {
    return PaymentsDashboard(initialCategory: initialCategory);
  }
}

class PaymentsDashboard extends StatefulWidget {
  final PaymentCategory initialCategory;
  final String? initialSearch;

  const PaymentsDashboard({
    Key? key,
    required this.initialCategory,
    this.initialSearch,
  }) : super(key: key);

  @override
  _PaymentsDashboardState createState() => _PaymentsDashboardState();
}

class _PaymentsDashboardState extends State<PaymentsDashboard> {
  PaymentCategory selectedCategory = PaymentCategory.tender;
  bool isLoading = true;
  bool isRefreshing = false;
  String? errorMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);
  double _zoomLevel = 1.0; // Zoom level: 1.0 = 100%, base is smaller

  PaymentSummary tenderSummary = PaymentSummary.empty();
  PaymentSummary nonTenderSummary = PaymentSummary.empty();
  List<PaymentItem> tenderItems = [];
  List<PaymentItem> nonTenderItems = [];

  final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    print('[Payments] initState called');
    selectedCategory = widget.initialCategory;
    final seed = widget.initialSearch?.trim() ?? '';
    if (seed.isNotEmpty) {
      _searchController.text = seed;
      _searchQuery = seed;
    }
    _loadData();
  }

  @override
  void dispose() {
    print('\n');
    print('╔════════════════════════════════════════════════════════════════╗');
    print('║  🔙 ANDROID BACK BUTTON PRESSED - PAYMENTS WIDGET DISPOSED    ║');
    print('╠════════════════════════════════════════════════════════════════╣');
    print('║  Widget: PaymentTaskWidget                                     ║');
    print('║  Status: Widget is being disposed                              ║');
    print('║  Reason: Android/system back button was pressed                ║');
    print('╚════════════════════════════════════════════════════════════════╝');
    print('\n');
    _searchDebounce?.cancel();
    _searchController.dispose();
    _loadRequestId++;
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final int requestId = ++_loadRequestId;

    if (showLoader) {
      _safeSetState(() {
        isLoading = true;
        errorMessage = null;
      });
    } else {
      _safeSetState(() {
        isRefreshing = true;
        errorMessage = null;
      });
    }

    try {
      final projectId = await _ensureProjectId();
      if (projectId == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }

      // Check cache for non-Client users
      final dataProvider = DataProvider();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      
      Map<String, dynamic>? cachedPaymentData;
      List<dynamic>? cachedTenderData;
      
      if (role != null && role != 'Client' && dataProvider.cachedPayments != null) {
        cachedPaymentData = dataProvider.cachedPayments;
        // Tender data can be obtained from cached schedule
        cachedTenderData = dataProvider.cachedSchedule;
      }

      // Paint cached payments immediately, then refresh in the background.
      if (cachedPaymentData != null) {
        _processPaymentData(
          cachedPaymentData,
          cachedTenderData ?? [],
          [],
          requestId,
        );
        if (showLoader && mounted && !_shouldIgnoreLoad(requestId)) {
          _safeSetState(() {
            isLoading = false;
          });
        }
        unawaited(_fetchPaymentsFromApi(projectId, dataProvider, role, requestId));
        return;
      }

      // Fetch from API
      await _fetchPaymentsFromApi(projectId, dataProvider, role, requestId);
    } catch (e) {
      print('[Payments] Error while loading data: $e');
      if (_shouldIgnoreLoad(requestId)) return;

      _safeSetState(() {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (_shouldIgnoreLoad(requestId)) return;

      _safeSetState(() {
        isLoading = false;
        isRefreshing = false;
      });
    }
  }

  Future<void> _fetchPaymentsFromApi(String projectId, DataProvider dataProvider, String? userRole, int requestId) async {
    try {
      final paymentUrl = 'https://office1.buildahome.in/API/get_payment?project_id=$projectId';
      final tenderUrl = 'https://office1.buildahome.in/API/get_all_tasks?project_id=$projectId&nt_toggle=0';
      final nonTenderUrl = 'https://office1.buildahome.in/API/get_all_non_tender?project_id=$projectId';

      print('[Payments] Loading data for project $projectId');

      Future<http.Response?> safeGet(String label, String url) async {
        try {
          return await _fetchWithLogging(label, url);
        } catch (e) {
          print('[Payments] $label request error: $e');
          return null;
        }
      }

      final results = await Future.wait<dynamic>([
        safeGet('payment', paymentUrl),
        safeGet('tender', tenderUrl),
        safeGet('non-tender', nonTenderUrl),
        _loadPaymentProofs(),
      ]);

      if (_shouldIgnoreLoad(requestId)) return;

      final paymentResponse = results[0];
      if (paymentResponse == null || paymentResponse.statusCode != 200) {
        throw Exception('Unable to load payment summary right now.');
      }
      print('[Payments] Payment response: ${paymentResponse.body}');

      List<dynamic> tenderData = [];
      List<dynamic> nonTenderData = [];

      final tenderResponse = results[1];
      if (tenderResponse != null && tenderResponse.statusCode == 200) {
        final decoded = jsonDecode(tenderResponse.body);
        if (decoded is List) {
          tenderData = decoded;
        }
      } else if (tenderResponse != null) {
        print(
            '[Payments] Tender request failed with status ${tenderResponse.statusCode}');
      }

      final nonTenderResponse = results[2];
      if (nonTenderResponse != null && nonTenderResponse.statusCode == 200) {
        final decoded = jsonDecode(nonTenderResponse.body);
        if (decoded is List) {
          nonTenderData = decoded;
        }
      } else if (nonTenderResponse != null) {
        print(
            '[Payments] Non-tender request failed with status ${nonTenderResponse.statusCode}');
      }

      final proofs = results[3] as List<PaymentProofItem>;
      final paymentDetails = jsonDecode(paymentResponse.body);
      final summary = (paymentDetails is List && paymentDetails.isNotEmpty) ? paymentDetails[0] : {};

      // Update cache for non-Client users
      if (userRole != null && userRole != 'Client') {
        dataProvider.cachedPayments = summary;
        dataProvider.lastPaymentsLoad = DateTime.now();
      }

      _processPaymentData(
        summary,
        tenderData,
        nonTenderData,
        requestId,
        proofs: proofs,
      );
    } catch (e) {
      rethrow;
    }
  }

  void _processPaymentData(
    Map<String, dynamic> summary,
    List<dynamic> tenderData,
    List<dynamic> nonTenderData,
    int requestId, {
    List<PaymentProofItem> proofs = const [],
  }) {
    if (_shouldIgnoreLoad(requestId)) return;

    _safeSetState(() {
      tenderSummary = PaymentSummary(
        value: (summary['value'] ?? '0').toString(),
        totalPaid: (summary['total_paid'] ?? '0').toString(),
        outstanding: (summary['outstanding'] ?? '0').toString(),
      );

      nonTenderSummary = PaymentSummary(
        value: (summary['nt_value'] ?? summary['value'] ?? '0').toString(),
        totalPaid: (summary['nt_total_paid'] ?? '0').toString(),
        outstanding: (summary['nt_outstanding'] ?? '0').toString(),
      );

      tenderItems = tenderData
          .map<PaymentItem>((item) {
            final name = (item['task_name'] ?? 'Milestone').toString();
            final taskId = item is Map
                ? _paymentTaskId(Map<String, dynamic>.from(item))
                : null;
            return PaymentItem(
                name: name,
                percentage: _toDouble(item['payment']),
                status: displayedPaymentStatus(
                  paidStatus: (item['paid'] ?? '').toString(),
                  name: name,
                  isTender: true,
                  taskId: taskId,
                  proofs: proofs,
                ),
                note: item['p_note']?.toString(),
                startDate: item['start_date']?.toString(),
                endDate: item['end_date']?.toString(),
                markedAsDueOn: item['marked_as_due_on']?.toString(),
                markedAsPaidOn: item['marked_as_paid_on']?.toString(),
                isTender: true,
                taskId: taskId,
              );
          })
          .toList();

      nonTenderItems = nonTenderData
          .map<PaymentItem>((item) {
            final name = (item['task_name'] ?? 'Non tender item').toString();
            final taskId = item is Map
                ? _paymentTaskId(Map<String, dynamic>.from(item))
                : null;
            return PaymentItem(
                name: name,
                percentage: _toDouble(item['payment']),
                status: displayedPaymentStatus(
                  paidStatus: (item['paid'] ?? '').toString(),
                  name: name,
                  isTender: false,
                  taskId: taskId,
                  proofs: proofs,
                ),
                note: item['p_note']?.toString(),
                startDate: item['start_date']?.toString(),
                endDate: item['end_date']?.toString(),
                markedAsDueOn: item['marked_as_due_on']?.toString(),
                markedAsPaidOn: item['marked_as_paid_on']?.toString(),
                isTender: false,
                amountOverride: _toDouble(item['payment']),
                taskId: taskId,
              );
          })
          .toList();
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  bool _shouldIgnoreLoad(int requestId) {
    return !mounted || requestId != _loadRequestId;
  }

  Future<String?> _ensureProjectId({int retries = 5, Duration delay = const Duration(milliseconds: 300)}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? projectId = prefs.getString('project_id');
    int attempts = 0;

    while ((projectId == null || projectId.isEmpty) && attempts < retries) {
      await Future.delayed(delay);
      prefs = await SharedPreferences.getInstance();
      projectId = prefs.getString('project_id');
      attempts++;
    }

    if (projectId == null || projectId.isEmpty) {
      print('[Payments] Project ID unavailable after ${attempts + 1} attempts');
      return null;
    }

    return projectId;
  }

  Future<http.Response> _fetchWithLogging(String label, String url) async {
    try {
      print('[Payments] GET $label → $url');
      final response = await http.get(Uri.parse(url)).timeout(_requestTimeout);
      print('[Payments] $label response: ${response.statusCode}, bytes=${response.bodyBytes.length}');
      return response;
    } on TimeoutException catch (e) {
      print('[Payments] $label request timeout: $e');
      rethrow;
    } catch (e) {
      print('[Payments] $label request failed: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = selectedCategory == PaymentCategory.nonTender
        ? 'Upgrades and Additions Cost'
        : 'Payments';
    final isAdminChrome =
        DashboardChrome.of(context) == DashboardChromeStyle.admin;
    final tabLabelColor =
        isAdminChrome ? Colors.white : AppTheme.darkTextPrimary;
    final tabUnselectedColor = isAdminChrome
        ? Colors.white.withValues(alpha: 0.7)
        : AppTheme.mutedGrey;
    final tabIndicatorColor =
        isAdminChrome ? Colors.white : AppTheme.navy;

    return DefaultTabController(
      length: 2,
      child: ThemedScaffold(
        title: title,
        bottom: TabBar(
          labelColor: tabLabelColor,
          unselectedLabelColor: tabUnselectedColor,
          indicatorColor: tabIndicatorColor,
          tabs: const [
            Tab(text: 'Schedule'),
            Tab(text: 'Previous payment'),
          ],
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildBody(),
              ),
              // View-only previous proofs + bill association (no upload from Payments).
              const UploadPaymentProofScreen(
                embedded: true,
                allowUpload: false,
                showPendingPayments: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return _buildLoader('Loading payment details…');
    }

    if (errorMessage != null) {
      return _buildError();
    }

    final items = _filteredItems;
    final summary = _currentSummary;
    final isNonTender = selectedCategory == PaymentCategory.nonTender;
    final useNtSections = isNonTender && !_isSearching;

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoader: false),
      color: AppTheme.navy,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildFilterChips(),
                  const SizedBox(height: 16),
                  _buildSummaryCards(summary),
                  const SizedBox(height: 24),
                  _buildSearchField(),
                  const SizedBox(height: 20),
                  _buildPaymentListHeader(items, isSearching: _isSearching),
                ],
              ),
            ),
          ),
          if (items.isNotEmpty && useNtSections)
            ..._buildNtSectionedPaymentSlivers(items, summary)
          else if (items.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: _buildPaymentTableSliver(items, summary),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNtSectionedPaymentSlivers(
    List<PaymentItem> items,
    PaymentSummary summary,
  ) {
    final sections = <_NtPaymentSection>[
      _NtPaymentSection(
        title: 'Pending',
        emptyHint: 'No pending Upgrades and Additions Cost items',
        items: items.where((item) => item.isPending).toList(),
        accent: Colors.red[700]!,
      ),
      _NtPaymentSection(
        title: 'Paid',
        emptyHint: 'No paid Upgrades and Additions Cost items',
        items: items.where((item) => item.isPaid).toList(),
        accent: Colors.green[700]!,
      ),
    ];

    final slivers = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final isLast = i == sections.length - 1;
      final amount = section.items.fold<double>(
        0,
        (sum, item) => sum + item.resolvedAmount(summary),
      );

      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, i == 0 ? 0 : 8, 20, 8),
          sliver: SliverToBoxAdapter(
            child: _buildNtSectionHeader(
              title: section.title,
              count: section.items.length,
              amountText: _formatCurrency(amount),
              accent: section.accent,
            ),
          ),
        ),
      );

      if (section.items.isEmpty) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, isLast ? 24 : 12),
            sliver: SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundSecondary(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.08),
                  ),
                ),
                child: Text(
                  section.emptyHint,
                  style: TextStyle(
                    color: AppTheme.getTextSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, isLast ? 24 : 12),
            sliver: _buildPaymentTableSliver(section.items, summary),
          ),
        );
      }
    }
    return slivers;
  }

  Widget _buildNtSectionHeader({
    required String title,
    required int count,
    required String amountText,
    required Color accent,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$title · $count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
        ),
        Text(
          amountText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Track your project payments',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.darkTextPrimary,
            letterSpacing: -0.2,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Switch between project payments and Upgrades and Additions Cost using the filters below.',
          style: TextStyle(
            color: AppTheme.mutedGrey,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter by',
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.darkBackgroundPrimaryLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildChip('Project Payments', PaymentCategory.tender),
              ),
              Expanded(
                child: _buildChip(
                    'Upgrades and Additions Cost', PaymentCategory.nonTender),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 140), () {
          if (!mounted) return;
          if (_searchQuery == value) return;
          setState(() => _searchQuery = value);
        });
      },
      style: TextStyle(
        color: AppTheme.darkTextPrimary,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: 'Search payments, notes or status',
        hintStyle: const TextStyle(
          color: AppTheme.mutedGrey,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.mutedGrey),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.mutedGrey),
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: AppTheme.darkBackgroundPrimaryLight,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.navy, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.border),
        ),
      ),
    );
  }

  Widget _buildChip(String label, PaymentCategory category) {
    final bool isSelected = selectedCategory == category;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            selectedCategory = category;
          });
        },
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppTheme.mutedGrey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(PaymentSummary summary) {
    final bool isNonTender = selectedCategory == PaymentCategory.nonTender;

    if (isNonTender) {
      final pendingItems = _currentItems.where((item) => item.isPending).toList();
      final pendingAmount = pendingItems.fold<double>(
        0,
        (sum, item) => sum + item.resolvedAmount(summary),
      );

      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _SummaryCard(
            title: 'NT Value',
            subtitle: 'Total budgeted amount',
            value: _formatCurrency(summary.valueNumeric),
            icon: Icons.account_balance_wallet,
            gradient: const [
              Color(0xFFE3F2FD),
              Color(0xFFBBDEFB),
            ],
          ),
          _SummaryCard(
            title: 'Paid till date',
            subtitle: 'Approved & released',
            value: _formatCurrency(summary.totalPaidNumeric),
            icon: Icons.check_circle_outline,
            valueColor: Colors.green[700],
            gradient: const [
              Color(0xFFE8F5E9),
              Color(0xFFC8E6C9),
            ],
          ),
          _SummaryCard(
            title: 'Pending',
            subtitle: pendingItems.isEmpty
                ? 'No items due'
                : '${pendingItems.length} item${pendingItems.length == 1 ? '' : 's'} due now',
            value: _formatCurrency(pendingAmount),
            icon: Icons.pending_actions,
            valueColor: Colors.red[700],
            gradient: const [
              Color(0xFF3F1D24),
              Color(0xFF7F1D1D),
            ],
          ),
        ],
      );
    }

    // Tender: calculate total percentage for paid + pending milestones.
    final totalPercentage = _currentItems.fold<double>(0.0, (sum, item) {
      if (item.isPaid || item.isPending) {
        return sum + item.percentage;
      }
      return sum;
    });

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _SummaryCard(
          title: 'Contract Value',
          subtitle: 'Total budgeted amount',
          value: _formatCurrency(summary.valueNumeric),
          icon: Icons.account_balance_wallet,
          gradient: const [
            Color(0xFFE3F2FD),
            Color(0xFFBBDEFB),
          ],
        ),
        _SummaryCard(
          title: 'Paid till date',
          subtitle: 'Approved & released',
          value: _formatCurrency(summary.totalPaidNumeric),
          icon: Icons.check_circle_outline,
          valueColor: Colors.green[700],
          gradient: const [
            Color(0xFFE8F5E9),
            Color(0xFFC8E6C9),
          ],
        ),
        _SummaryCard(
          title: 'Outstanding',
          subtitle: 'Pending payment',
          value: _formatCurrency(summary.outstandingNumeric),
          icon: Icons.pending_actions,
          valueColor: Colors.red[700],
          gradient: const [
            Color(0xFF3F1D24),
            Color(0xFF7F1D1D),
          ],
        ),
        _SummaryCard(
          title: 'Total Percentage',
          subtitle: 'Total percentage billed',
          value: '${totalPercentage.toStringAsFixed(1)}%',
          icon: Icons.percent,
          valueColor: AppTheme.getPrimaryColor(context),
          gradient: [
            AppTheme.getPrimaryColor(context).withOpacity(0.15),
            AppTheme.getPrimaryColor(context).withOpacity(0.08),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentListHeader(List<PaymentItem> items, {bool isSearching = false}) {
    if (items.isEmpty) {
      return Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, color: AppTheme.getTextSecondary(context), size: 44),
            SizedBox(height: 12),
            Text(
              isSearching ? 'No payments match your search' : 'No payments yet',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            SizedBox(height: 4),
            Text(
              isSearching ? 'Try a different keyword or clear the search.' : 'Payments will appear here when they are due.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedCategory == PaymentCategory.tender
                  ? 'Milestone payments'
                  : 'Upgrades and Additions Cost',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            _buildZoomControls(),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.zoom_out, color: AppTheme.getTextSecondary(context), size: 20),
          onPressed: _zoomLevel > 0.8
              ? () {
                  setState(() {
                    _zoomLevel = (_zoomLevel - 0.1).clamp(0.8, 1.5);
                  });
                }
              : null,
          tooltip: 'Zoom out',
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
          ),
          child: Text(
            '${(_zoomLevel * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.zoom_in, color: AppTheme.getTextSecondary(context), size: 20),
          onPressed: _zoomLevel < 1.5
              ? () {
                  setState(() {
                    _zoomLevel = (_zoomLevel + 0.1).clamp(0.8, 1.5);
                  });
                }
              : null,
          tooltip: 'Zoom in',
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
        ),
      ],
    );
  }

  double _getScaledFontSize(double baseSize) {
    return baseSize * _zoomLevel;
  }

  Widget _buildPaymentTableSliver(List<PaymentItem> items, PaymentSummary summary) {
    final headerFontSize = _getScaledFontSize(11);
    final cellFontSize = _getScaledFontSize(11);
    final noteFontSize = _getScaledFontSize(10);
    final statusFontSize = _getScaledFontSize(10);
    final paddingVertical = 10 * _zoomLevel;
    final paddingHorizontal = 12 * _zoomLevel;
    final bool isNonTender = selectedCategory == PaymentCategory.nonTender;

    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.1)),
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Container(
            padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Stage',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (!isNonTender)
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Percentage',
                      style: TextStyle(
                        fontSize: headerFontSize,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextPrimary(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Value',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            );
            }

            final item = items[index - 1];
            final double amount = item.amountOverride ?? (summary.valueNumeric * (item.percentage / 100));
            final amountText = amount > 0 ? currencyFormatter.format(amount) : '—';
            final style = _statusStyle(item.status);

            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.05),
                    width: 1,
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: cellFontSize,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.getTextPrimary(context),
                            ),
                          ),
                          if (item.note != null && item.note!.trim().isNotEmpty) ...[
                            SizedBox(height: 2 * _zoomLevel),
                            Text(
                              item.note!.trim(),
                              style: TextStyle(
                                fontSize: noteFontSize,
                                color: AppTheme.getTextSecondary(context),
                              ),
                            ),
                          ],
                          ..._buildPaymentDateLines(
                            item,
                            isNonTender: isNonTender,
                            fontSize: noteFontSize - 1,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * _zoomLevel,
                            vertical: 4 * _zoomLevel,
                          ),
                          decoration: BoxDecoration(
                            color: style.background,
                            borderRadius: BorderRadius.circular(10 * _zoomLevel),
                          ),
                          child: Text(
                            style.label,
                            style: TextStyle(
                              color: style.foreground,
                              fontWeight: FontWeight.w600,
                              fontSize: statusFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!isNonTender)
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${item.percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: cellFontSize,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.getTextPrimary(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        amountText,
                        style: TextStyle(
                          fontSize: cellFontSize,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.getTextPrimary(context),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: items.length + 1,
        ),
      ),
    );
  }


  _StatusStyle _statusStyle(String status) {
    if (isPaymentStatusPaid(status)) {
      return _StatusStyle(
        label: 'Paid',
        background: Colors.green.withOpacity(0.15),
        foreground: Colors.green[800]!,
      );
    }
    if (isPaymentStatusInReview(status)) {
      return _StatusStyle(
        label: 'In review',
        background: const Color(0xFF312E81).withOpacity(0.45),
        foreground: const Color(0xFFC7D2FE),
      );
    }
    if (isPaymentStatusScheduled(status)) {
      return _StatusStyle(
        label: 'Scheduled',
        background: Colors.amber.withOpacity(0.2),
        foreground: Colors.amber[800]!,
      );
    }
    return _StatusStyle(
      label: 'Pending',
      background: Colors.red.withOpacity(0.15),
      foreground: Colors.red[700]!,
    );
  }

  Widget _buildLoader(String message) {
    final width = MediaQuery.of(context).size.width;
    final summaryWidth = (width - 60) / 2;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _skeletonBar(width: 200, height: 22),
        const SizedBox(height: 8),
        _skeletonBar(width: width * 0.7, height: 14),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(
            3,
            (_) => Container(
              width: summaryWidth,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundSecondary(context),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBar(width: 120, height: 14),
                  const SizedBox(height: 10),
                  _skeletonBar(width: 90, height: 22),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        ...List.generate(3, (_) => _buildSkeletonPaymentCard()),
      ],
    );
  }

  Widget _buildSkeletonPaymentCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _skeletonBar(width: 48, height: 48, radius: 16),
              const SizedBox(width: 12),
              Expanded(child: _skeletonBar(height: 18)),
            ],
          ),
          const SizedBox(height: 16),
          _skeletonBar(height: 12),
          const SizedBox(height: 6),
          _skeletonBar(width: 160, height: 12),
        ],
      ),
    );
  }

  Widget _skeletonBar({double? width, double height = 16, double radius = 10}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimaryLight(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            SizedBox(height: 8),
            Text(
              errorMessage ?? 'Please try again later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.getPrimaryColor(context),
                foregroundColor: Colors.white,
              ),
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  List<PaymentItem> get _currentItems => selectedCategory == PaymentCategory.tender ? tenderItems : nonTenderItems;

  PaymentSummary get _currentSummary => selectedCategory == PaymentCategory.tender ? tenderSummary : nonTenderSummary;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  List<PaymentItem> get _visibleItems {
    return _currentItems.where((item) => !item.isScheduled).toList();
  }

  List<PaymentItem> get _filteredItems {
    if (!_isSearching) return _visibleItems;
    final query = _searchQuery.trim().toLowerCase();
    final currentSummary = _currentSummary;
    return _visibleItems.where((item) {
      final note = item.note?.toLowerCase() ?? '';
      final status = item.status.toLowerCase();
      final statusLabel = _statusStyle(item.status).label.toLowerCase();
      final percentage = '${item.percentage.toStringAsFixed(1)}%'.toLowerCase();
      final amount = item.resolvedAmount(currentSummary);
      final amountText = amount > 0 ? currencyFormatter.format(amount).toLowerCase() : '';
      final raisedOn = (item.raisedOnDisplay ?? item.dueOnDisplay ?? '').toLowerCase();
      final paidOn = (item.paidOnDisplay ?? '').toLowerCase();
      return item.name.toLowerCase().contains(query) ||
          note.contains(query) ||
          status.contains(query) ||
          statusLabel.contains(query) ||
          percentage.contains(query) ||
          raisedOn.contains(query) ||
          paidOn.contains(query) ||
          amountText.contains(query.replaceAll(RegExp(r'[₹,\s]'), ''));
    }).toList();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(RegExp('[^0-9\\.]'), '')) ?? 0;
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return '₹ 0';
    return currencyFormatter.format(amount);
  }

  List<Widget> _buildPaymentDateLines(
    PaymentItem item, {
    required bool isNonTender,
    required double fontSize,
  }) {
    final raisedOn = isNonTender ? item.raisedOnDisplay : item.dueOnDisplay;
    final paidOn = item.paidOnDisplay;
    final raisedLabel = isNonTender ? 'Raised on' : 'Due on';
    final lines = <Widget>[];

    if (raisedOn != null) {
      lines.add(SizedBox(height: 4 * _zoomLevel));
      lines.add(
        Text(
          '$raisedLabel: $raisedOn',
          style: TextStyle(
            fontSize: fontSize,
            color: AppTheme.getTextSecondary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (paidOn != null) {
      lines.add(SizedBox(height: 4 * _zoomLevel));
      lines.add(
        Text(
          'Paid on: $paidOn',
          style: TextStyle(
            fontSize: fontSize,
            color: AppTheme.getTextSecondary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return lines;
  }
}

class PaymentSummary {
  final String value;
  final String totalPaid;
  final String outstanding;

  const PaymentSummary({
    required this.value,
    required this.totalPaid,
    required this.outstanding,
  });

  static PaymentSummary empty() => PaymentSummary(value: '0', totalPaid: '0', outstanding: '0');

  double get valueNumeric => _parse(value);

  double get totalPaidNumeric => _parse(totalPaid);

  double get outstandingNumeric => _parse(outstanding);

  static double _parse(String input) {
    return double.tryParse(input.replaceAll(RegExp('[^0-9\\.]'), '')) ?? 0;
  }
}

class PaymentItem {
  final String name;
  final double percentage;
  final String status;
  final bool isTender;
  final String? note;
  final String? startDate;
  final String? endDate;
  final String? markedAsDueOn;
  final String? markedAsPaidOn;
  final double? amountOverride;
  final String? taskId;

  const PaymentItem({
    required this.name,
    required this.percentage,
    required this.status,
    required this.isTender,
    this.note,
    this.startDate,
    this.endDate,
    this.markedAsDueOn,
    this.markedAsPaidOn,
    this.amountOverride,
    this.taskId,
  });

  bool get isPaid => isPaymentStatusPaid(status);

  bool get isScheduled => isPaymentStatusScheduled(status);

  bool get isPending => isPaymentStatusPending(status);

  /// Tender "due" timestamp, when present.
  String? get dueOnDisplay => _displayPaymentDate(markedAsDueOn);

  /// NT bills expose raised date via `start_date` (or `marked_as_due_on`).
  String? get raisedOnDisplay =>
      _displayPaymentDate(markedAsDueOn) ?? _displayPaymentDate(startDate);

  /// Paid timestamp when available; NT falls back to `end_date` for paid rows.
  String? get paidOnDisplay {
    final markedPaid = _displayPaymentDate(markedAsPaidOn);
    if (markedPaid != null) return markedPaid;
    if (!isTender && isPaid) return _displayPaymentDate(endDate);
    return null;
  }

  double resolvedAmount(PaymentSummary summary) {
    if (amountOverride != null) return amountOverride!;
    return summary.valueNumeric * (percentage / 100);
  }
}

bool _hasPaymentDate(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
}

String? _displayPaymentDate(String? value) {
  if (!_hasPaymentDate(value)) return null;
  final raw = value!.trim();

  // ISO / YYYY-MM-DD from NT start_date / end_date.
  final ymd = DateTime.tryParse(raw);
  if (ymd != null) {
    return DateFormat('dd MMM yyyy').format(ymd);
  }

  // Common API form: "Sat, 03 Oct 2026 16:08:47 GMT"
  final httpDate = raw.replaceFirst(RegExp(r'\s*GMT$', caseSensitive: false), '');
  try {
    final parsed = DateFormat('EEE, dd MMM yyyy HH:mm:ss').parse(httpDate, true);
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
  } catch (_) {}

  return raw;
}

Color _iconOnChip(Color background) {
  return background.computeLuminance() > 0.45
      ? const Color(0xFF1C1C1E)
      : Colors.white;
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final Color? valueColor;

  const _SummaryCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.gradient,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: (MediaQuery.of(context).size.width - 60) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: gradient.isNotEmpty
                      ? gradient.first
                      : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: _iconOnChip(
                    gradient.isNotEmpty
                        ? gradient.first
                        : const Color(0xFFEEF2FF),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkTextPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.getTextPrimary(context),
            ),
          ),
          SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color background;
  final Color foreground;

  _StatusStyle({
    required this.label,
    required this.background,
    required this.foreground,
  });
}

class _NtPaymentSection {
  final String title;
  final String emptyHint;
  final List<PaymentItem> items;
  final Color accent;

  const _NtPaymentSection({
    required this.title,
    required this.emptyHint,
    required this.items,
    required this.accent,
  });
}

class TaskItem extends StatefulWidget {
  final String _taskName;
  final _icon = Icons.home; // ignore: unused_field
  final _startDate; // ignore: unused_field
  final _endDate; // ignore: unused_field
  final _height = 0.0; // ignore: unused_field
  final _color = Colors.white;
  final _paymentPercentage;
  final status;
  final note;
  final projectValue;
  final markedAsDueOn;
  final markedAsPaidOn;

  TaskItem(this._taskName, this._startDate, this._endDate, this._paymentPercentage, this.status, this.note, this.projectValue, {this.markedAsDueOn, this.markedAsPaidOn});

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._color, this._height, this._paymentPercentage, this.status, this.note, this.projectValue, markedAsDueOn: markedAsDueOn, markedAsPaidOn: markedAsPaidOn);
  }
}

class TaskItemWidget extends State<TaskItem> with SingleTickerProviderStateMixin {
  String _taskName;
  var _icon = Icons.home; // ignore: unused_field
  var _startDate; // ignore: unused_field
  var _endDate; // ignore: unused_field
  var _color;
  var vis = false;
  var _paymentPercentage;
  var _textColor = Colors.black;
  var _height = 50.0; // ignore: unused_field
  var sprRadius = 1.0;
  var pad = 10.0;
  var valueStr;
  var value = 0;
  var status;
  var amt;
  var note;
  var gradient;
  var projectValue;
  var markedAsDueOn;
  var markedAsPaidOn;

  @override
  void initState() {
    super.initState();
    _setValue();
    _progress();
  }

  _setValue() async {
    if(this._paymentPercentage.toString().trim() == '') {
      this._paymentPercentage = '0';
    }
    setState(() {
      amt = ((int.parse(this._paymentPercentage)) / 100) * int.parse(this.projectValue);
    });
  }

  _progress() {
    if (this.status == 'not due') {
      this._color = Colors.white;
      this._textColor = Colors.black;
      this.gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.1, 0.9],
        colors: [
          Colors.white,
          Colors.white,
        ],
      );
    } else if (this.status == 'paid') {
      this._color = Colors.green;
      this._textColor = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.7],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xff009900),
          Color(0xff33cc00),
        ],
      );
    } else {
      this._color = Colors.deepOrange;
      this._textColor = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.7],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xFF7b0909),
          Color(0xFFd51010),
        ],
      );
    }
  }

  var view = Icons.expand_more;

  _expandCollapse() {
    setState(() {
      if (vis == false) {
        vis = true;
        view = Icons.expand_less;
        sprRadius = 1.0;
      } else if (vis == true) {
        vis = false;
        view = Icons.expand_more;
        sprRadius = 1.0;
      }
    });
  }

  TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._color, this._height, this._paymentPercentage, this.status, this.note, this.projectValue, {this.markedAsDueOn, this.markedAsPaidOn});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.95 + (0.05 * value),
              child: Opacity(
                opacity: value,
                child: Container(
                  margin: EdgeInsets.only(left: 15, top: 10, right: 15, bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppTheme.getBackgroundSecondary(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _expandCollapse,
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 300),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: this.gradient,
                        ),
                        child: Column(children: <Widget>[
                          Row(
                            children: <Widget>[
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: Duration(milliseconds: 400),
                                curve: Curves.elasticOut,
                                builder: (context, scaleValue, child) {
                                  return Transform.scale(
                                    scale: scaleValue,
                                    child: this._color == Colors.green
                                        ? Container(
                                            height: 50,
                                            width: 50,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.green[900],
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.green.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              'PAID',
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          )
                                        : this._color == Colors.white
                                            ? Container(
                                                height: 50,
                                                width: 50,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.yellow[700],
                                                  borderRadius: BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.yellow.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'WIP',
                                                  style: TextStyle(color: const Color.fromARGB(255, 0, 0, 0), fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              )
                                            : Container(
                                                height: 50,
                                                width: 50,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.red[700],
                                                  borderRadius: BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.red.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'DUE',
                                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                  );
                                },
                              ),
                              SizedBox(width: 15),
                              Expanded(
                                child: Text(
                                  this._taskName,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: this._textColor,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: this.vis ? 0.5 : 0.0,
                                duration: Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                child: Icon(
                                  Icons.expand_more,
                                  color: this._textColor,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          AnimatedSize(
                            duration: Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: this.vis
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      SizedBox(height: 12),
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: <Widget>[
                                            Text(
                                              this._paymentPercentage + "%",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: this._textColor,
                                              ),
                                            ),
                                            Text(
                                              "₹ " + ((amt != null) ? amt.toStringAsFixed(2) : ''),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: this._textColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (this.note.trim() != '')
                                        Container(
                                          margin: EdgeInsets.only(top: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            this.note.trim(),
                                            style: TextStyle(
                                              color: this._textColor,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      if (this.markedAsDueOn != null && this.markedAsDueOn.toString().isNotEmpty && this.markedAsDueOn.toString() != 'null')
                                        Container(
                                          margin: EdgeInsets.only(top: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.event_note, size: 14, color: this._textColor),
                                              SizedBox(width: 8),
                                              Text(
                                                "Due on: ${this.markedAsDueOn}",
                                                style: TextStyle(
                                                  color: this._textColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (this.markedAsPaidOn != null && this.markedAsPaidOn.toString().isNotEmpty && this.markedAsPaidOn.toString() != 'null')
                                        Container(
                                          margin: EdgeInsets.only(top: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.event_available, size: 14, color: this._textColor),
                                              SizedBox(width: 8),
                                              Text(
                                                "Paid on: ${this.markedAsPaidOn}",
                                                style: TextStyle(
                                                  color: this._textColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  )
                                : SizedBox.shrink(),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class PaymentTasksClass extends StatefulWidget {
  @override
  PaymentTasks createState() {
    return PaymentTasks();
  }
}

class PaymentTasks extends State<PaymentTasksClass> {
  var body;
  var tasks = [];
  var projectValue = "";
  var outstanding = "";
  var totalPaid = "";

  @override
  void initState() {
    super.initState();
    call();
    print('call');
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var url = 'https://office1.buildahome.in/API/get_all_tasks?project_id=$id&nt_toggle=0';
    var response = await http.get(Uri.parse(url));
    body = jsonDecode(response.body);

    var url1 = 'https://office1.buildahome.in/API/get_payment?project_id=$id';
    var response1 = await http.get(Uri.parse(url1));
    var details = jsonDecode(response1.body);
    outstanding = details[0]['outstanding'];
    totalPaid = double.parse(details[0]['total_paid'].toString().trim()).toString();
    projectValue = details[0]['value'];

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromARGB(255, 250, 250, 255),
            Color.fromARGB(255, 233, 233, 233),
          ],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 1),
            child: ListView(children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -20 * (1 - value)),
                      child: Container(
                        margin: EdgeInsets.only(top: 20, left: 20, bottom: 10),
                        child: Text(
                          "Project Payments",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkTextPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.navy,
                              Color.fromARGB(255, 20, 25, 80),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        width: 100,
                        margin: EdgeInsets.only(left: 20, right: 250, bottom: 20),
                      ),
                    ),
                  );
                },
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 30 * (1 - value)),
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 400),
                              curve: Curves.easeOutBack,
                              builder: (context, scaleValue, child) {
                                return Transform.scale(
                                  scale: scaleValue,
                                  child: Container(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.fromARGB(255, 240, 255, 242),
                                          Color.fromARGB(255, 220, 245, 225),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.account_balance_wallet, size: 18, color: AppTheme.darkTextPrimary),
                                            SizedBox(width: 6),
                                            Text(
                                              "Project Value",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color.fromARGB(255, 100, 100, 100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "₹ " + projectValue,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.darkTextPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 500),
                              curve: Curves.easeOutBack,
                              builder: (context, scaleValue, child) {
                                return Transform.scale(
                                  scale: scaleValue,
                                  child: Container(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.fromARGB(255, 255, 237, 237),
                                          Color.fromARGB(255, 255, 220, 220),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                                            SizedBox(width: 6),
                                            Text(
                                              "Paid till date",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color.fromARGB(255, 100, 100, 100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "₹ " + totalPaid,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 600),
                              curve: Curves.easeOutBack,
                              builder: (context, scaleValue, child) {
                                return Transform.scale(
                                  scale: scaleValue,
                                  child: Container(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.fromARGB(255, 246, 248, 225),
                                          Color.fromARGB(255, 240, 242, 200),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.pending_actions, size: 18, color: Colors.red[500]),
                                            SizedBox(width: 6),
                                            Text(
                                              "Current Outstanding",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color.fromARGB(255, 100, 100, 100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "₹ " + outstanding,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            new ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: body == null ? 0 : body.length,
                itemBuilder: (BuildContext ctxt, int index) {
                  return TaskItem(
                      body[index]['task_name'].toString(),
                      body[index]['start_date'].toString(),
                      body[index]['end_date'].toString(),
                      body[index]['payment'].toString(),
                      body[index]['paid'].toString(),
                      body[index]['p_note'].toString(),
                      projectValue,
                      markedAsDueOn: body[index]['marked_as_due_on']?.toString(),
                      markedAsPaidOn: body[index]['marked_as_paid_on']?.toString());
                }),
            ]),
          ),
        ],
      ),
    );
  }
}

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  AnimatedWidgetSlide({
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  _AnimatedWidgetSlideState createState() => _AnimatedWidgetSlideState();
}

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    switch (widget.direction) {
      case SlideDirection.leftToRight:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInSine,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, -1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
    }

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
