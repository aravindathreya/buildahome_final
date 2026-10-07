import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'FullScreenImage.dart';
import 'app_theme.dart';
import 'indent_list_helpers.dart';
import 'services/api_http.dart';

const String _indentProofApiBase = 'https://office.buildahome.in';

const _indentProofScreenKeys = [
  'open_tab',
  'native_screen',
  'wf_native_screen',
  'data-wf-native-screen',
  'data_wf_native_screen',
  'redirect_page',
];

const _indentIdKeys = [
  'indent_id',
  'indentId',
  'wf_indent_id',
  'data-wf-indent-id',
  'data_wf_indent_id',
];

bool isSiteEngineerRole(String? role) {
  final normalized = role?.trim().toLowerCase().replaceAll('-', ' ') ?? '';
  return normalized == 'site engineer';
}

bool isIndentProofReviewerRole(String? role) {
  final normalized = role?.trim().toLowerCase().replaceAll('-', ' ') ?? '';
  if (normalized.isEmpty) return false;
  if (isSiteEngineerRole(role)) return false;
  if (normalized.contains('assistant project coordinator') ||
      normalized == 'apcc') {
    return true;
  }
  if (normalized.contains('project coordinator') ||
      normalized.contains('project co ordinator')) {
    return true;
  }
  if (normalized.contains('project manager') || normalized == 'pm') {
    return true;
  }
  if (normalized.contains('project head') || normalized == 'ph') {
    return true;
  }
  if (normalized.contains('sr manager')) return true;
  if (normalized.contains('coo')) return true;
  if (normalized == 'admin' || normalized.contains('super admin')) {
    return true;
  }
  return false;
}

bool showIndentProofTabForRole(String? role) =>
    isSiteEngineerRole(role) || isIndentProofReviewerRole(role);

bool shouldHideIndentProofReviewTask(Map task, String? role) {
  if (!isSiteEngineerRole(role)) return false;
  final actions = _workflowActionsFromTaskMap(task);
  for (final action in actions) {
    final id = action['id']?.toString() ?? '';
    if (id == 'indent_po_review_comment' || id == 'indent_po_proof_approve') {
      return true;
    }
  }
  return _hasIndentProofScreenOrFlag(task);
}

List<Map<String, dynamic>> _workflowActionsFromTaskMap(Map task) {
  dynamic actions = task['workflow_actions'] ?? task['workflow_task_actions'];
  if (actions is String && actions.trim().isNotEmpty) {
    try {
      actions = jsonDecode(actions);
    } catch (_) {}
  }
  if (actions is! List) return const [];
  return actions
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

bool isIndentProofDeeplinkTask(Map task, {Map<String, dynamic>? action}) {
  final indentId = indentProofIndentId(task, action: action);
  if (indentId == null || indentId.isEmpty) return false;

  if (action != null && _hasIndentProofScreenOrFlag(action)) return true;
  if (_hasIndentProofScreenOrFlag(task)) return true;

  for (final key in const [
    'workflow_actions',
    'workflow_task_actions',
    'actions',
    'data',
    'config',
    'action_config',
    'task_action_config',
    'settings',
  ]) {
    final nested = task[key];
    if (nested is Map &&
        _hasIndentProofScreenOrFlag(Map<String, dynamic>.from(nested))) {
      return true;
    }
    if (nested is List) {
      for (final item in nested) {
        if (item is Map &&
            _hasIndentProofScreenOrFlag(Map<String, dynamic>.from(item))) {
          return true;
        }
      }
    }
  }
  return false;
}

String? indentProofIndentId(Map task, {Map<String, dynamic>? action}) {
  if (action != null) {
    final fromAction = _indentIdFrom(action);
    if (fromAction != null) return fromAction;
  }

  final fromTask = _indentIdFrom(task);
  if (fromTask != null) return fromTask;

  for (final key in const [
    'workflow_actions',
    'workflow_task_actions',
    'actions',
    'data',
    'config',
    'action_config',
    'task_action_config',
    'settings',
  ]) {
    final nested = task[key];
    if (nested is Map) {
      final id = _indentIdFrom(Map<String, dynamic>.from(nested));
      if (id != null) return id;
    }
    if (nested is List) {
      for (final item in nested) {
        if (item is! Map) continue;
        final id = _indentIdFrom(Map<String, dynamic>.from(item));
        if (id != null) return id;
      }
    }
  }
  return null;
}

bool _hasIndentProofScreenOrFlag(Map map) {
  if (_indentProofTruthy(map['indent_proof_deeplink'])) return true;
  for (final key in _indentProofScreenKeys) {
    if (_isIndentProofScreenValue(map[key])) return true;
  }

  for (final configKey in const [
    'config',
    'action_config',
    'task_action_config',
    'settings',
    'data',
  ]) {
    final config = map[configKey];
    if (config is! Map) continue;
    final nested = Map<String, dynamic>.from(config);
    if (_indentProofTruthy(nested['indent_proof_deeplink'])) return true;
    for (final key in _indentProofScreenKeys) {
      if (_isIndentProofScreenValue(nested[key])) return true;
    }
  }

  final redirectUrl = map['redirect_url']?.toString() ?? '';
  final uri = Uri.tryParse(redirectUrl);
  if (uri != null) {
    final path = '${uri.host}${uri.path}'.toLowerCase();
    if (path.contains('indent_proof') || path.contains('indent-proof')) {
      return true;
    }
    if (_isIndentProofScreenValue(uri.queryParameters['open_tab']) ||
        _isIndentProofScreenValue(uri.queryParameters['native_screen'])) {
      return true;
    }
  }
  return false;
}

bool _isIndentProofScreenValue(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return normalized == 'indent_proof' || normalized == 'indent-proof';
}

String? _indentIdFrom(Map map) {
  for (final key in _indentIdKeys) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }

  for (final configKey in const [
    'config',
    'action_config',
    'task_action_config',
    'settings',
    'data',
  ]) {
    final config = map[configKey];
    if (config is! Map) continue;
    for (final key in _indentIdKeys) {
      final value = config[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }
  }

  final redirectUrl = map['redirect_url']?.toString() ?? '';
  final uri = Uri.tryParse(redirectUrl);
  if (uri != null) {
    for (final key in _indentIdKeys) {
      final value = uri.queryParameters[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

bool _indentProofTruthy(dynamic value) {
  if (value == true) return true;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes';
  }
  return false;
}

class IndentProofTab extends StatefulWidget {
  final String? initialIndentId;
  final String? initialProjectId;
  final String? initialProjectName;

  const IndentProofTab({
    Key? key,
    this.initialIndentId,
    this.initialProjectId,
    this.initialProjectName,
  }) : super(key: key);

  @override
  State<IndentProofTab> createState() => IndentProofTabState();
}

class IndentProofTabState extends State<IndentProofTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  bool _openedInitial = false;
  final _pager = IndentPagedListController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pager.lockedProjectId = widget.initialProjectId;
    _scrollController.addListener(_onScroll);
    _load(openInitial: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_pager.loadingMore || !_pager.hasMore) return;
    if (_pager.serverPaged) {
      _pager.loadingMore = true;
      await _load(openInitial: false, reset: false);
      return;
    }
    setState(() {
      _pager.showMoreClient();
      _items = _pager.visible.whereType<Map>().map((item) {
        return Map<String, dynamic>.from(item);
      }).toList();
    });
  }

  void _onProjectSearch(String value) {
    _pager.search = value;
    setState(() {
      _pager.rebuildVisible(resetClientPage: true);
      _syncVisibleItems();
    });
  }

  void _syncVisibleItems() {
    _items = _pager.visible.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Future<void> reload() => _load(openInitial: false);

  Future<void> _load({required bool openInitial, bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _fetchIndentProofs(
        projectId: _pager.isLocked ? widget.initialProjectId : null,
        search: _pager.isLocked ? null : _pager.search,
        offset: reset ? 0 : _pager.offset,
        limit: kIndentListPageSize,
      );
      if (!mounted) return;
      setState(() {
        _pager.acceptPage(page, reset: reset);
        _syncVisibleItems();
        _loading = false;
        _pager.loadingMore = false;
      });
      final initialId = widget.initialIndentId?.trim() ?? '';
      if (openInitial &&
          initialId.isNotEmpty &&
          !_openedInitial &&
          mounted) {
        _openedInitial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Map<String, dynamic>? match;
          for (final row in _items) {
            if ((_display(row, ['indent_id', 'id']) ?? '') == initialId) {
              match = row;
              break;
            }
          }
          if (match == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This indent is no longer available.'),
              ),
            );
            return;
          }
          _openDetail(match);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pager.loadingMore = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final indentId = _display(item, ['indent_id', 'id']) ?? '';
    if (indentId.isEmpty) return;
    final proof = _proofMap(item);
    Map<String, dynamic> pending = {};
    final rawPending = item['pending_delivery'] ?? proof['pending_delivery'];
    if (rawPending is Map) {
      pending = Map<String, dynamic>.from(rawPending);
    }
    String? pick(List<String> keys, [Map<String, dynamic>? extra]) {
      final fromItem = _display(item, keys);
      if (fromItem != null && fromItem.trim().isNotEmpty) return fromItem.trim();
      final fromProof = _display(proof, keys);
      if (fromProof != null && fromProof.trim().isNotEmpty) return fromProof.trim();
      if (extra != null) {
        final fromExtra = _display(extra, keys);
        if (fromExtra != null && fromExtra.trim().isNotEmpty) return fromExtra.trim();
      }
      return null;
    }

    final vendorId = pick(['vendor_id'], pending);
    final deliveryId = pick(
          ['review_delivery_id', 'delivery_id', 'last_delivery_id'],
          pending,
        ) ??
        (pending['id']?.toString().trim().isNotEmpty == true
            ? pending['id'].toString().trim()
            : null);
    final itemRunId = pick([
      'review_item_run_id',
      'workflow_item_run_id',
      'item_run_id',
    ], pending);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IndentProofDetailScreen(
          indentId: indentId,
          forReview: true,
          vendorId: vendorId,
          deliveryId: deliveryId,
          itemRunId: itemRunId,
        ),
      ),
    );
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IndentProjectListHeader(
          title: 'Indent proof',
          count: _pager.filteredCount,
          lockedProjectName: widget.initialProjectName,
          searchController: _pager.isLocked ? null : _searchController,
          onSearchChanged: _onProjectSearch,
          onSearchCleared: () {
            _searchController.clear();
            _onProjectSearch('');
          },
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _IndentProofMessage(
                      icon: Icons.error_outline,
                      title: 'Could not load indent proofs',
                      message: _error!,
                      actionLabel: 'Retry',
                      onAction: () => _load(openInitial: false),
                    )
                  : _items.isEmpty
                      ? _IndentProofMessage(
                          icon: Icons.fact_check_outlined,
                          title: 'No indent proofs',
                          message: _pager.search.trim().isEmpty
                              ? 'Indents with pending PC/APC review or outstanding/partial delivery proof will appear here.'
                              : 'No indent proofs for this project.',
                        )
                      : RefreshIndicator(
                          onRefresh: reload,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(15, 8, 15, 24),
                            itemCount:
                                _items.length + (_pager.hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _items.length) {
                                return const IndentListLoadMoreTile();
                              }
                              final item = _items[index];
                              final indentId = _display(item, [
                                    'indent_id',
                                    'id',
                                  ]) ??
                                  '';
                              return _IndentProofListCard(
                                item: item,
                                onTap: indentId.isEmpty
                                    ? null
                                    : () => _openDetail(item),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class IndentProofDetailScreen extends StatefulWidget {
  final String indentId;
  /// When true, fetch pending under-review batch (for_review=1) and allow qty decrease.
  final bool forReview;
  /// Scope review to this vendor / delivery / item_run (split-vendor cards).
  final String? vendorId;
  final String? deliveryId;
  final String? itemRunId;

  const IndentProofDetailScreen({
    Key? key,
    required this.indentId,
    this.forReview = false,
    this.vendorId,
    this.deliveryId,
    this.itemRunId,
  }) : super(key: key);

  @override
  State<IndentProofDetailScreen> createState() =>
      _IndentProofDetailScreenState();
}

class _IndentProofDetailScreenState extends State<IndentProofDetailScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _detail = {};

  final _quantityController = TextEditingController();
  final _measurementController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _weightController = TextEditingController();
  final _reviewCommentController = TextEditingController();

  String? _siteComment;
  String _originalQuantity = '';
  String _originalMeasurement = '';
  String _reviewDeliveryId = '';
  final List<_ReviewMaterialQty> _reviewMaterials = [];

  bool get _isProofApproved {
    final proof = _proofMap(_detail);
    if (_indentProofTruthy(proof['approved']) ||
        _indentProofTruthy(_detail['approved']) ||
        _indentProofTruthy(proof['is_approved']) ||
        _indentProofTruthy(_detail['is_approved']) ||
        _indentProofTruthy(proof['proof_approved']) ||
        _indentProofTruthy(_detail['proof_approved'])) {
      return true;
    }
    // Open review for THIS delivery/vendor is never "approved" just because a
    // sibling vendor's review completed on the same indent.
    if (widget.forReview) {
      final pending = proof['pending_delivery'] ?? _detail['pending_delivery'];
      final hasPending = pending is Map && pending.isNotEmpty;
      final hasPendingList = (_detail['pending_deliveries'] is List &&
              (_detail['pending_deliveries'] as List).isNotEmpty) ||
          (proof['pending_deliveries'] is List &&
              (proof['pending_deliveries'] as List).isNotEmpty);
      if (hasPending || hasPendingList) {
        return false;
      }
    }
    final status = (
          _display(proof, [
                'task_status',
                'proof_status',
                'workflow_status',
                'status',
              ]) ??
              _display(_detail, [
                'task_status',
                'proof_status',
                'workflow_status',
                'status',
              ]) ??
              ''
        )
            .toLowerCase()
            .replaceAll(' ', '_')
            .replaceAll('-', '_');
    return status == 'approved' ||
        status == 'completed' ||
        status == 'done' ||
        status == 'finished';
  }

  bool get _canEdit =>
      !_isProofApproved &&
      _indentProofTruthy(_detail['can_edit'] ?? _proofMap(_detail)['can_edit']);

  bool get _canApprove => _canEdit && !_isProofApproved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _measurementController.dispose();
    _vehicleController.dispose();
    _weightController.dispose();
    _reviewCommentController.dispose();
    for (final m in _reviewMaterials) {
      m.controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _proof => _proofMap(_detail);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _fetchIndentProofDetail(
        widget.indentId,
        forReview: widget.forReview,
        vendorId: widget.vendorId,
        deliveryId: widget.deliveryId,
        itemRunId: widget.itemRunId,
      );
      if (!mounted) return;
      _applyDetail(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _applyDetail(Map<String, dynamic> detail) {
    final proof = _proofMap(detail);
    for (final m in _reviewMaterials) {
      m.controller.dispose();
    }
    _reviewMaterials.clear();
    _reviewDeliveryId = (
          _display(detail, ['review_delivery_id']) ??
          _display(proof, ['review_delivery_id']) ??
          ''
        )
            .trim();
    final pending = detail['pending_delivery'] is Map
        ? Map<String, dynamic>.from(detail['pending_delivery'] as Map)
        : (proof['pending_delivery'] is Map
            ? Map<String, dynamic>.from(proof['pending_delivery'] as Map)
            : <String, dynamic>{});
    if (_reviewDeliveryId.isEmpty) {
      _reviewDeliveryId = pending['id']?.toString().trim() ?? '';
    }
    final reviewMats = <Map<String, dynamic>>[];
    final rawReview = detail['review_materials'] ??
        proof['review_materials'] ??
        pending['materials'];
    if (rawReview is List) {
      for (final row in rawReview) {
        if (row is Map) {
          reviewMats.add(Map<String, dynamic>.from(row));
        }
      }
    }
    for (final mat in reviewMats) {
      String firstNonEmpty(List<dynamic> values) {
        for (final v in values) {
          final t = (v ?? '').toString().trim();
          if (t.isNotEmpty && t.toLowerCase() != 'null') return t;
        }
        return '';
      }
      // Show the uploaded qty by default; reviewer only lowers it if needed.
      final submitted = firstNonEmpty([
        mat['submitted'],
        mat['quantity_received'],
        mat['received'],
      ]);
      final initial = firstNonEmpty([
        mat['approved_qty'],
        submitted,
      ]);
      final key = (mat['material_key'] ?? '').toString().trim().isNotEmpty
          ? mat['material_key'].toString().trim()
          : '${mat['material']}_${mat['unit']}';
      _reviewMaterials.add(
        _ReviewMaterialQty(
          materialKey: key,
          name: (mat['material'] ?? '').toString().trim(),
          unit: (mat['unit'] ?? '').toString().trim(),
          submitted: submitted,
          controller: TextEditingController(text: initial),
        ),
      );
    }
    final qtyFromPending = pending['quantity_label']?.toString().trim() ?? '';
    _quantityController.text = qtyFromPending.isNotEmpty
        ? qtyFromPending
        : (_display(proof, [
              'quantity',
              'proof_quantity',
              'site_quantity',
            ]) ??
            _display(detail, ['proof_quantity', 'site_quantity']) ??
            '');
    // Prefer THIS pending batch fields over merged proof (sibling deliveries).
    final pendingMeasurement = (pending['measurement'] ?? '').toString().trim();
    final pendingVehicle = (pending['vehicle_number'] ?? '').toString().trim();
    final pendingWeight = (pending['weight'] ?? '').toString().trim();
    final pendingSiteComment = (pending['site_comment'] ?? '').toString().trim();
    _measurementController.text = pendingMeasurement.isNotEmpty
        ? pendingMeasurement
        : (_display(proof, [
              'measurement',
              'proof_measurement',
            ]) ??
            '');
    _vehicleController.text = pendingVehicle.isNotEmpty
        ? pendingVehicle
        : (_display(proof, [
              'vehicle_number',
              'vehicle',
              'vehicle_no',
            ]) ??
            '');
    _weightController.text = pendingWeight.isNotEmpty
        ? pendingWeight
        : (_display(proof, [
              'weight',
              'proof_weight',
            ]) ??
            '');
    _reviewCommentController.text = _display(proof, [
          'review_comment',
        ]) ??
        _commentFromMap(proof['comments'], 'review_comment') ??
        '';
    // Site engineer comment: prefer THIS pending batch, then scoped proof.
    _siteComment = pendingSiteComment.isNotEmpty
        ? pendingSiteComment
        : (_display(proof, ['site_comment']) ??
            _commentFromMap(proof['comments'], 'site_comment'));
    _originalQuantity = _quantityController.text.trim();
    _originalMeasurement = _measurementController.text.trim();
    setState(() {
      _detail = detail;
      _loading = false;
      _error = null;
    });
  }

  String? _validateReducedFields() {
    for (final m in _reviewMaterials) {
      final err = _validateNotIncreased(
        fieldLabel: m.name.isEmpty ? 'Quantity' : m.name,
        original: m.submitted,
        edited: m.controller.text.trim(),
      );
      if (err != null) return err;
      final v = double.tryParse(m.controller.text.trim().replaceAll(',', ''));
      if (v == null) {
        return 'Enter a valid quantity for ${m.name.isEmpty ? 'material' : m.name}';
      }
      if (v < 0) return 'Quantity cannot be negative';
    }
    if (_reviewMaterials.isEmpty) {
      final quantityError = _validateNotIncreased(
        fieldLabel: 'Quantity',
        original: _originalQuantity,
        edited: _quantityController.text.trim(),
      );
      if (quantityError != null) return quantityError;
    }
    // Measurement may be changed freely by PC/APC â€” no reduce-only rule.
    return null;
  }

  Map<String, String> _approvedQtyPayload() {
    final out = <String, String>{};
    for (final m in _reviewMaterials) {
      if (m.materialKey.isEmpty) continue;
      out[m.materialKey] = m.controller.text.trim();
    }
    return out;
  }

  Future<void> _save({required bool approve}) async {
    if (_saving) return;
    final validationError = _validateReducedFields();
    if (validationError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final message = await _updateIndentProof(
        indentId: widget.indentId,
        quantity: _quantityController.text.trim(),
        measurement: _measurementController.text.trim(),
        vehicleNumber: _vehicleController.text.trim(),
        weight: _weightController.text.trim(),
        reviewComment: _reviewCommentController.text.trim(),
        approve: approve,
        deliveryId: _reviewDeliveryId,
        vendorId: (widget.vendorId ?? '').trim(),
        itemRunId: (widget.itemRunId ?? '').trim(),
        approvedQuantities: _approvedQtyPayload(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isNotEmpty
                ? message
                : (approve ? 'Indent proof approved' : 'Indent proof saved'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      if (approve) {
        Navigator.of(context).pop(true);
        return;
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmApprove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve indent proof'),
        content: const Text(
          'Save any edits and approve this site proof?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _save(approve: true);
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _display(_detail, ['status_label']) ??
        _display(_detail, ['status', 'indent_status']) ??
        '-';
    final primary = AppTheme.getPrimaryColor(context);

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        title: const Text('Indent proof'),
        backgroundColor: AppTheme.darkBackgroundSecondary,
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _IndentProofMessage(
                  icon: Icons.error_outline,
                  title: 'Could not load indent',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _compactMaterialHeader(context, statusLabel, primary),
                          const SizedBox(height: 14),
                          _sectionCard(
                            context,
                            title: 'Received details',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_reviewMaterials.isNotEmpty) ...[
                                  Text(
                                    'Received quantity',
                                    style: TextStyle(
                                      color: AppTheme.getTextPrimary(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ..._reviewMaterials.map(_reviewQtyEditor),
                                  const SizedBox(height: 4),
                                  if (_canEdit)
                                    _editField(
                                      controller: _measurementController,
                                      label: 'Measurement',
                                    )
                                  else
                                    _infoRow(
                                      'Measurement',
                                      _measurementController.text.trim().isEmpty
                                          ? '-'
                                          : _measurementController.text.trim(),
                                    ),
                                  const SizedBox(height: 8),
                                ] else if (_canEdit) ...[
                                  _editField(
                                    controller: _quantityController,
                                    label: 'Quantity',
                                    helperText: _originalQuantity.isEmpty
                                        ? 'Lower only if less was received'
                                        : 'Uploaded: $_originalQuantity â€” lower only if less was received',
                                  ),
                                  _editField(
                                    controller: _measurementController,
                                    label: 'Measurement',
                                  ),
                                ] else ...[
                                  _infoRow(
                                    'Quantity',
                                    _quantityController.text.trim().isEmpty
                                        ? '-'
                                        : _quantityController.text.trim(),
                                  ),
                                  _infoRow(
                                    'Measurement',
                                    _measurementController.text.trim().isEmpty
                                        ? '-'
                                        : _measurementController.text.trim(),
                                  ),
                                ],
                                if (_canEdit) ...[
                                  _editField(
                                    controller: _vehicleController,
                                    label: 'Vehicle number',
                                  ),
                                  _editField(
                                    controller: _weightController,
                                    label: 'Weight',
                                  ),
                                ] else ...[
                                  _infoRow(
                                    'Vehicle number',
                                    _vehicleController.text.trim().isEmpty
                                        ? '-'
                                        : _vehicleController.text.trim(),
                                  ),
                                  _infoRow(
                                    'Weight',
                                    _weightController.text.trim().isEmpty
                                        ? '-'
                                        : _weightController.text.trim(),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _infoRow(
                                  'Site comment',
                                  (_siteComment ?? '').trim().isEmpty
                                      ? '-'
                                      : _siteComment!.trim(),
                                ),
                                ..._pendingProofListWidgets(context),
                                ..._proofSectionsWidgets(context, _proof),
                                const SizedBox(height: 12),
                                _mediaSection(
                                  context,
                                  title: 'Images',
                                  urls: _imageUrls(_proof, _detail),
                                ),
                                const SizedBox(height: 12),
                                _mediaSection(
                                  context,
                                  title: 'Video',
                                  urls: _videoUrls(_proof, _detail),
                                  isVideo: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionCard(
                            context,
                            title: 'Review comment',
                            child: _canEdit
                                ? _editField(
                                    controller: _reviewCommentController,
                                    label: 'Your review comment',
                                  )
                                : _infoRow(
                                    'Review comment',
                                    _reviewCommentController.text.trim().isEmpty
                                        ? '-'
                                        : _reviewCommentController.text.trim(),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (_canApprove)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      _saving ? null : () => _save(approve: false),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Save'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _saving ? null : _confirmApprove,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColorConst,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_isProofApproved)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14532D),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF166534)),
                            ),
                            child: const Text(
                              'This indent proof is already approved.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF6EE7B7),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _compactMaterialHeader(
    BuildContext context,
    String statusLabel,
    Color primary,
  ) {
    final lines = <String>[];
    if (_reviewMaterials.isNotEmpty) {
      for (final m in _reviewMaterials) {
        final qty = m.controller.text.trim().isNotEmpty
            ? m.controller.text.trim()
            : m.submitted;
        final unit = m.unit.isEmpty ? '' : ' ${m.unit}';
        final name = m.name.isEmpty ? 'Material' : m.name;
        lines.add('$name Â· $qty$unit'.trim());
      }
    } else {
      final mats = _detail['upload_materials'] ??
          _detail['materials'] ??
          _proof['materials'];
      if (mats is List && mats.isNotEmpty) {
        for (final raw in mats) {
          if (raw is! Map) continue;
          final mat = Map<String, dynamic>.from(raw);
          final name = (mat['material'] ?? '').toString().trim();
          final recv = (mat['previously_received_quantity'] ??
                  mat['received'] ??
                  mat['submitted'] ??
                  '')
              .toString()
              .trim();
          final ordered =
              (mat['ordered_quantity'] ?? mat['ordered'] ?? '').toString().trim();
          final unit = (mat['unit'] ?? '').toString().trim();
          final qty = ordered.isNotEmpty
              ? '$recv of $ordered${unit.isEmpty ? '' : ' $unit'}'
              : '$recv${unit.isEmpty ? '' : ' $unit'}';
          lines.add('${name.isEmpty ? 'Material' : name} Â· $qty');
        }
      } else {
        final name = _display(_detail, ['material', 'item']) ?? 'Material';
        final qty = _joinQuantity(
          _display(_detail, ['quantity']),
          _display(_detail, ['unit']),
        );
        lines.add('$name Â· $qty');
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Indent #${widget.indentId}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
              ),
              if (statusLabel.trim().isNotEmpty && statusLabel != '-')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: primary.withValues(alpha: 0.12)),
          const SizedBox(height: 10),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewQtyEditor(_ReviewMaterialQty m) {
    final name = m.name.trim().isEmpty ? 'Material' : m.name.trim();
    final unit = m.unit.trim();
    final uploaded = m.submitted.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Unit: $unit',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (uploaded.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Uploaded quantity: $uploaded${unit.isEmpty ? '' : ' $unit'}',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _editField(
            controller: m.controller,
            label: 'Quantity',
            helperText: 'Lower only if less was received',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    );
  }



  List<Widget> _pendingProofListWidgets(BuildContext context) {
    // Review opens one delivery/batch at a time — bottom Save + Approve is enough.
    // Do not show per-proof "Proof N" cards or "Approve Proof N" buttons.
    if (widget.forReview ||
        _scopedReviewDelivery(_proof, _detail) != null) {
      return const <Widget>[];
    }
    final proof = _proof;
    final raw = _detail['pending_deliveries'] ?? proof['pending_deliveries'];
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) items.add(Map<String, dynamic>.from(row));
      }
    }
    if (items.isEmpty) {
      final one = _detail['pending_delivery'] ?? proof['pending_delivery'];
      if (one is Map) items.add(Map<String, dynamic>.from(one));
    }
    if (items.isEmpty) return const <Widget>[];
    final primary = AppTheme.getPrimaryColor(context);
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final p = items[i];
      final label = (p['proof_label'] ?? p['label'] ?? ('Proof ${i + 1}')).toString();
      final qty = (p['quantity_label'] ?? p['quantity'] ?? '').toString();
      final when = (p['submitted_at'] ?? '').toString();
      final did = (p['id'] ?? '').toString();
      widgets.add(const SizedBox(height: 10));
      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.darkBackgroundSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
              if (qty.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(qty, style: TextStyle(color: AppTheme.getTextSecondary(context))),
              ],
              if (when.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(when, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
              ],
              if (_canApprove && did.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () {
                            _reviewDeliveryId = did;
                            _confirmApprove();
                          },
                    child: Text('Approve ' + label),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _proofSectionsWidgets(
    BuildContext context,
    Map<String, dynamic> proof,
  ) {
    // Review screens already show batch-scoped Images/Video â€” skip merged
    // action sections that pile media from every proof on the indent.
    if (widget.forReview &&
        _scopedReviewDelivery(proof, _detail) != null) {
      return const [];
    }
    final sections = proof['sections'];
    if (sections is! List || sections.isEmpty) return const [];

    final widgets = <Widget>[];
    const skipIds = {
      'indent_po_quantity',
      'indent_po_measurement',
      'indent_po_vehicle',
      'indent_po_weight',
      'indent_po_site_comment',
      'indent_po_review_comment',
    };

    for (final item in sections) {
      if (item is! Map) continue;
      final section = Map<String, dynamic>.from(item);
      final actionId = section['action_id']?.toString() ?? '';
      if (skipIds.contains(actionId)) continue;

      final label = section['label']?.toString().trim() ?? '';
      final comment = section['comment']?.toString().trim() ?? '';
      final files = section['files'];
      final fileMaps = files is List
          ? files.whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList()
          : <Map<String, dynamic>>[];

      if (comment.isEmpty && fileMaps.isEmpty) continue;

      widgets.add(const SizedBox(height: 12));
      if (label.isNotEmpty) {
        widgets.add(
          Text(
            label,
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        widgets.add(const SizedBox(height: 6));
      }
      if (comment.isNotEmpty) {
        widgets.add(_infoRow('Comment', comment));
      }
      if (fileMaps.isNotEmpty) {
        widgets.add(const SizedBox(height: 8));
        widgets.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fileMaps.map((file) {
              final url = _mediaUrlFromMap(file);
              if (url == null) return const SizedBox.shrink();
              final isVideo = _looksLikeVideo(url);
              return InkWell(
                onTap: () => _openMedia(context, url: url, isVideo: isVideo),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: isVideo
                      ? Container(
                          width: 84,
                          height: 84,
                          color: const Color(0xFFE2E8F0),
                          child: const Icon(Icons.play_circle_outline),
                        )
                      : Image.network(
                          url,
                          width: 84,
                          height: 84,
                          cacheWidth: 168,
                          cacheHeight: 168,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 84,
                            height: 84,
                            color: const Color(0xFFE2E8F0),
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _editField({
    required TextEditingController controller,
    required String label,
    String? helperText,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperMaxLines: 2,
          filled: true,
          fillColor: AppTheme.getBackgroundPrimary(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

String? _validateNotIncreased({
  required String fieldLabel,
  required String original,
  required String edited,
}) {
  if (original.isEmpty) return null;
  if (edited.isEmpty) {
    return '$fieldLabel cannot be empty. Use a value less than or equal to $original.';
  }
  if (edited == original) return null;

  final originalNumber = _firstNumberFrom(original);
  final editedNumber = _firstNumberFrom(edited);
  if (originalNumber == null) {
    // Non-numeric original: only allow keeping the same value.
    return '$fieldLabel can only be reduced from the site value ($original).';
  }
  if (editedNumber == null) {
    return 'Enter a numeric $fieldLabel less than or equal to $original.';
  }
  if (editedNumber > originalNumber) {
    return '$fieldLabel cannot be increased. Enter a value less than or equal to $original.';
  }
  return null;
}

double? _firstNumberFrom(String value) {
  final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(value.trim());
  if (match == null) return null;
  final normalized = match.group(0)!.replaceAll(',', '.');
  return double.tryParse(normalized);
}

class _IndentProofListCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  const _IndentProofListCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final proof = _proofMap(item);
    final primary = AppTheme.getPrimaryColor(context);
    final indentId = _display(item, ['indent_id', 'id']) ?? '';
    final proofLabel = _display(item, ['proof_label']) ?? '';
    final project = _display(item, ['project_name', 'project']) ?? 'Project';
    final vendor = _display(item, ['vendor_name', 'vendor']) ?? '';
    final po = _display(item, ['po_number', 'po', 'purchase_order']) ?? '';
    final statusLabel = _display(item, ['status_label']) ??
        _display(item, ['status', 'indent_status']) ??
        '';
    final reviewChip = _display(item, ['review_status_chip']) ??
        (_indentProofTruthy(item['has_pending_review'] ?? proof['has_pending_review'])
            ? 'pending review'
            : '');
    final progressLabel = _display(item, ['delivery_progress_label']) ??
        (_indentProofTruthy(item['is_complete'] ?? proof['upload_is_complete'])
            ? 'Full'
            : (_indentProofTruthy(item['is_partial'] ?? proof['upload_is_partial'])
                ? 'Partial'
                : 'Not received'));
    final batchCount = int.tryParse(
          (item['all_deliveries_count'] ??
                  proof['all_deliveries_count'] ??
                  item['deliveries_count'] ??
                  proof['deliveries_count'] ??
                  '0')
              .toString(),
        ) ??
        0;
    final submittedBy = _display(item, [
          'latest_submitted_by_name',
          'submitted_by_name',
        ]) ??
        _display(proof, ['latest_submitted_by_name', 'submitted_by_name']) ??
        _nestedDeliveryField(item, proof, 'submitted_by_name') ??
        '';
    final submittedAt = _display(item, [
          'latest_submitted_at',
          'submitted_at',
        ]) ??
        _display(proof, ['latest_submitted_at', 'submitted_at']) ??
        _nestedDeliveryField(item, proof, 'submitted_at') ??
        '';
    final materialLines = _listCardMaterialLines(item, proof);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: primary.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.fact_check_outlined, color: primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      indentId.isEmpty
                          ? (proofLabel.isEmpty ? 'Indent' : proofLabel)
                          : (proofLabel.isEmpty ? 'Indent #$indentId' : 'Indent #$indentId Â· $proofLabel'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                  ),
                  if (reviewChip.isNotEmpty) _statusChip(context, reviewChip),
                  if (reviewChip.isEmpty && statusLabel.isNotEmpty)
                    _statusChip(context, statusLabel),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: primary.withValues(alpha: 0.1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardMiniRow(
                    context,
                    Icons.apartment_outlined,
                    project,
                    bold: true,
                  ),
                  const SizedBox(height: 10),
                  ...materialLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _cardMiniRow(
                        context,
                        Icons.inventory_2_outlined,
                        line,
                      ),
                    ),
                  ),
                  if (vendor.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _cardMiniRow(context, Icons.storefront_outlined, 'Vendor: $vendor'),
                  ],
                  if (po.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _cardMiniRow(context, Icons.receipt_long_outlined, 'PO: $po'),
                  ],
                  if (submittedBy.isNotEmpty || submittedAt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _cardMiniRow(
                      context,
                      Icons.person_outline,
                      [
                        if (submittedBy.isNotEmpty) 'Submitted by $submittedBy',
                        if (submittedAt.isNotEmpty) submittedAt,
                      ].join(' Â· '),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusChip(
                        context,
                        batchCount > 0
                            ? '$progressLabel Â· $batchCount batch${batchCount == 1 ? '' : 'es'}'
                            : progressLabel,
                      ),
                      if (reviewChip.isNotEmpty && statusLabel.isNotEmpty)
                        _statusChip(context, statusLabel),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardMiniRow(
    BuildContext context,
    IconData icon,
    String text, {
    bool bold = false,
  }) {
    final primary = AppTheme.getPrimaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context, String label) {
    final colors = _statusChipColors(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors[0],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors[1],
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}


List<Color> _statusChipColors(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('pending')) {
    return const [Color(0xFF3D3420), Color(0xFFEAB308)];
  }
  if (lower.contains('approved') || lower.contains('full') || lower.contains('complete')) {
    return const [Color(0xFF14532D), Color(0xFF6EE7B7)];
  }
  if (lower.contains('partial')) {
    return const [Color(0xFF1E3A5F), Color(0xFF93C5FD)];
  }
  if (lower.contains('reject') || lower.contains('cancel')) {
    return const [Color(0xFF3F1D1D), Color(0xFFFCA5A5)];
  }
  return const [Color(0xFF2A2A2D), Color(0xFFA1A1AA)];
}

String? _nestedDeliveryField(
  Map<String, dynamic> item,
  Map<String, dynamic> proof,
  String key,
) {
  for (final src in [item, proof]) {
    for (final nestKey in const ['pending_delivery', 'last_delivery']) {
      final nest = src[nestKey];
      if (nest is Map) {
        final v = nest[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
  }
  return null;
}

List<String> _listCardMaterialLines(
  Map<String, dynamic> item,
  Map<String, dynamic> proof,
) {
  final lines = <String>[];
  final mats = item['upload_materials'] ??
      proof['upload_materials'] ??
      item['materials'] ??
      proof['materials'];
  if (mats is List && mats.isNotEmpty) {
    for (final raw in mats) {
      if (raw is! Map) continue;
      final mat = Map<String, dynamic>.from(raw);
      final name = (mat['material'] ?? '').toString().trim();
      final recv = (mat['previously_received_quantity'] ??
              mat['received'] ??
              '0')
          .toString()
          .trim();
      final ordered =
          (mat['ordered_quantity'] ?? mat['ordered'] ?? '').toString().trim();
      final unit = (mat['unit'] ?? '').toString().trim();
      final qty = ordered.isNotEmpty
          ? '$recv of $ordered${unit.isEmpty ? '' : ' $unit'}'
          : '$recv${unit.isEmpty ? '' : ' $unit'}';
      lines.add('${name.isEmpty ? 'Material' : name}: $qty');
    }
  }
  if (lines.isEmpty) {
    final material = _display(item, ['material', 'item']) ?? 'Material';
    final quantity = _joinQuantity(
      _display(item, ['quantity', 'qty']),
      _display(item, ['unit']),
    );
    lines.add('$material: $quantity');
  }
  return lines;
}


class _IndentProofMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _IndentProofMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _sectionCard(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.15),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.trim().isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _mediaSection(
  BuildContext context, {
  required String title,
  required List<String> urls,
  bool isVideo = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        ),
      ),
      const SizedBox(height: 8),
      if (urls.isEmpty)
        const Text('-', style: TextStyle(fontWeight: FontWeight.w700))
      else if (isVideo)
        ...urls.map(
          (url) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Play video'),
            onTap: () => _openMedia(context, url: url, isVideo: true),
          ),
        )
      else
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final url = urls[index];
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FullScreenImage(
                      url,
                      imageUrls: urls,
                      initialIndex: index,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    width: 84,
                    height: 84,
                    cacheWidth: 168,
                    cacheHeight: 168,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 84,
                      height: 84,
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}

Future<void> _openMedia(
  BuildContext context, {
  required bool isVideo,
  required String url,
}) async {
  if (!isVideo) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FullScreenImage(url)),
    );
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.inAppWebView);
}

Map<String, dynamic> _proofMap(Map<String, dynamic> detail) {
  for (final key in const ['site_proof', 'proof', 'indent_proof']) {
    final nested = detail[key];
    if (nested is Map) return Map<String, dynamic>.from(nested);
  }
  return detail;
}

String? _display(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return null;
}

String? _commentFromMap(dynamic comments, String key) {
  if (comments is Map) {
    final value = comments[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return null;
}

String? _mediaUrlFromMap(Map<String, dynamic> map) {
  return _absoluteUrl(
    _display(map, ['url', 'href', 'file_url', 'path', 'file_path']) ?? '',
  );
}

String _joinQuantity(String? quantity, String? unit) {
  if ((quantity ?? '').isEmpty) return '-';
  if ((unit ?? '').isEmpty) return quantity!;
  return '$quantity $unit';
}

String? _commentsText(Map<String, dynamic> map) {
  final direct = _display(map, [
    'comments',
    'comment',
    'upload_comment',
    'proof_comment',
  ]);
  if (direct != null) return direct;
  final list = map['comments'];
  if (list is List) {
    final parts = list
        .map((item) {
          if (item is Map) {
            return (item['comment'] ?? item['text'] ?? item['message'] ?? '')
                .toString()
                .trim();
          }
          return item.toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) return parts.join('\n');
  }
  return null;
}

Map<String, dynamic>? _scopedReviewDelivery(
  Map<String, dynamic> proof,
  Map<String, dynamic> detail,
) {
  final pending = detail['pending_delivery'] is Map
      ? Map<String, dynamic>.from(detail['pending_delivery'] as Map)
      : (proof['pending_delivery'] is Map
          ? Map<String, dynamic>.from(proof['pending_delivery'] as Map)
          : null);
  if (pending != null && pending.isNotEmpty) return pending;

  final wantId = (
        detail['review_delivery_id'] ??
        proof['review_delivery_id'] ??
        ''
      )
          .toString()
          .trim();
  if (wantId.isEmpty) return null;

  for (final key in const ['deliveries', 'pending_deliveries']) {
    for (final source in [detail[key], proof[key]]) {
      if (source is! List) continue;
      for (final row in source) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        if ((map['id'] ?? '').toString().trim() == wantId) return map;
      }
    }
  }
  return null;
}

List<String> _imageUrls(Map<String, dynamic> proof, Map<String, dynamic> detail) {
  final scoped = _scopedReviewDelivery(proof, detail);
  if (scoped != null) {
    final scopedUrls = _collectMediaUrls([
      scoped['images'],
      scoped['photos'],
      scoped['image'],
      scoped['photo'],
    ], videos: false);
    if (scopedUrls.isNotEmpty) return scopedUrls;
  }
  // When a scoped delivery exists but has no images, do not fall back to
  // all-indent media (that re-piles sibling proofs).
  if (scoped != null) return const <String>[];
  return _collectMediaUrls([
    proof['images'],
    proof['photos'],
    proof['image'],
    proof['photo'],
    detail['images'],
    detail['photos'],
    detail['proof_images'],
  ], videos: false);
}

List<String> _videoUrls(Map<String, dynamic> proof, Map<String, dynamic> detail) {
  final scoped = _scopedReviewDelivery(proof, detail);
  if (scoped != null) {
    final scopedUrls = _collectMediaUrls([
      scoped['video'],
      scoped['videos'],
      scoped['site_video'],
    ], videos: true);
    if (scopedUrls.isNotEmpty) return scopedUrls;
  }
  if (scoped != null) return const <String>[];
  return _collectMediaUrls([
    proof['video'],
    proof['videos'],
    proof['site_video'],
    detail['video'],
    detail['videos'],
    detail['proof_video'],
  ], videos: true);
}

List<String> _collectMediaUrls(List<dynamic> sources, {required bool videos}) {
  final urls = <String>[];
  for (final source in sources) {
    _collectMediaFrom(source, urls, videos: videos);
  }
  final seen = <String>{};
  return urls.where((url) => seen.add(url)).toList();
}

void _collectMediaFrom(
  dynamic value,
  List<String> urls, {
  required bool videos,
}) {
  if (value == null) return;
  if (value is String) {
    final url = _absoluteUrl(value);
    if (url != null && _looksLikeVideo(url) == videos) urls.add(url);
    return;
  }
  if (value is List) {
    for (final item in value) {
      _collectMediaFrom(item, urls, videos: videos);
    }
    return;
  }
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final url = _display(map, [
      'url',
      'href',
      'file_url',
      'image_url',
      'video_url',
      'path',
      'file_path',
    ]);
    if (url != null) {
      final absolute = _absoluteUrl(url);
      if (absolute != null) {
        final isVideo = _looksLikeVideo(absolute) ||
            _looksLikeVideo(map['content_type']?.toString() ?? '') ||
            _looksLikeVideo(map['mime_type']?.toString() ?? '');
        if (isVideo == videos) urls.add(absolute);
      }
      return;
    }
    for (final nestedKey in const ['files', 'images', 'videos', 'photos']) {
      _collectMediaFrom(map[nestedKey], urls, videos: videos);
    }
  }
}

bool _looksLikeVideo(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('video') ||
      normalized.endsWith('.mp4') ||
      normalized.endsWith('.mov') ||
      normalized.endsWith('.webm') ||
      normalized.endsWith('.m4v');
}

String? _absoluteUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'null') return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) return '$_indentProofApiBase$trimmed';
  return '$_indentProofApiBase/$trimmed';
}

Future<_IndentProofCredentials> _indentProofCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
  final apiToken = prefs.getString('api_token') ?? '';
  if (userId.isEmpty) {
    throw Exception('Missing credentials. Please log in again.');
  }
  return _IndentProofCredentials(userId: userId, apiToken: apiToken);
}

class _IndentProofCredentials {
  final String userId;
  final String apiToken;

  const _IndentProofCredentials({
    required this.userId,
    required this.apiToken,
  });
}

dynamic _decodeBody(http.Response response) {
  if (response.body.trim().isEmpty) return null;
  try {
    return jsonDecode(response.body);
  } catch (_) {
    return null;
  }
}

String _apiFailureMessage(dynamic decoded, String fallback) {
  if (decoded is! Map) return fallback;
  final message = (decoded['message']?.toString() ?? '').trim();
  final reason = (
        decoded['reason'] ??
        decoded['error'] ??
        decoded['detail'] ??
        decoded['error_message'] ??
        ''
      )
          .toString()
          .trim();
  final bareFailure = message.isEmpty ||
      message.toLowerCase() == 'failure' ||
      message.toLowerCase() == 'error' ||
      message.toLowerCase() == 'failed';
  if (reason.isNotEmpty && bareFailure) return reason;
  if (message.isNotEmpty &&
      reason.isNotEmpty &&
      message.toLowerCase() != reason.toLowerCase()) {
    return '$message: $reason';
  }
  if (message.isNotEmpty && !bareFailure) return message;
  if (reason.isNotEmpty) return reason;
  if (message.isNotEmpty) return message;
  return fallback;
}

void _throwIfFailed(http.Response response, dynamic decoded, String fallback) {
  final status = response.statusCode;
  if (status >= 200 && status < 300) {
    if (decoded is Map && decoded['success'] == false) {
      throw Exception(_apiFailureMessage(decoded, fallback));
    }
    return;
  }
  if (decoded is Map) {
    final msg = _apiFailureMessage(decoded, '$fallback (HTTP $status)');
    // Always include status so Retry subtitle is actionable even for bare "failure".
    if (!msg.contains('HTTP $status') && !msg.contains('($status)')) {
      throw Exception('$msg (HTTP $status)');
    }
    throw Exception(msg);
  }
  final bodySnippet = response.body.trim();
  final clipped = bodySnippet.length > 160
      ? '${bodySnippet.substring(0, 160)}â€¦'
      : bodySnippet;
  if (clipped.isNotEmpty) {
    throw Exception('$fallback (HTTP $status): $clipped');
  }
  throw Exception('$fallback (HTTP $status)');
}

List<Map<String, dynamic>> _asObjectList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  return const [];
}

Future<IndentListPageResult> _fetchIndentProofs({
  String? projectId,
  String? search,
  int offset = 0,
  int limit = kIndentListPageSize,
}) async {
  final credentials = await _indentProofCredentials();
  final uri = Uri.parse('$_indentProofApiBase/API/get_indent_proofs').replace(
    queryParameters: {
      'user_id': credentials.userId,
      if (credentials.apiToken.isNotEmpty) 'api_token': credentials.apiToken,
      if ((projectId ?? '').trim().isNotEmpty) 'project_id': projectId!.trim(),
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    },
  );
  final response = await ApiHttp.get(
    uri,
    headers: credentials.apiToken.isEmpty
        ? null
        : {'X-Api-Token': credentials.apiToken},
  ).timeout(const Duration(seconds: 25));
  final decoded = _decodeBody(response);
  _throwIfFailed(response, decoded, 'Failed to load indent proofs');
  return parseIndentListResponse(decoded);
}

Future<Map<String, dynamic>> _fetchIndentProofDetail(
  String indentId, {
  bool forReview = false,
  String? vendorId,
  String? deliveryId,
  String? itemRunId,
}) async {
  final credentials = await _indentProofCredentials();
  final uri =
      Uri.parse('$_indentProofApiBase/API/get_indent_proof_detail').replace(
    queryParameters: {
      'user_id': credentials.userId,
      'indent_id': indentId,
      if (forReview) 'for_review': '1',
      if ((vendorId ?? '').trim().isNotEmpty) 'vendor_id': vendorId!.trim(),
      if ((deliveryId ?? '').trim().isNotEmpty) 'delivery_id': deliveryId!.trim(),
      if ((itemRunId ?? '').trim().isNotEmpty) 'item_run_id': itemRunId!.trim(),
      if (credentials.apiToken.isNotEmpty) 'api_token': credentials.apiToken,
    },
  );
  final response = await ApiHttp.get(
    uri,
    headers: credentials.apiToken.isEmpty
        ? null
        : {'X-Api-Token': credentials.apiToken},
  ).timeout(const Duration(seconds: 25));
  final decoded = _decodeBody(response);
  _throwIfFailed(response, decoded, 'Failed to load indent proof');

  if (decoded is Map) {
    for (final key in const ['data', 'indent', 'proof', 'detail']) {
      final nested = decoded[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return Map<String, dynamic>.from(decoded);
  }
  throw Exception('Indent proof detail was empty.');
}

Future<String> _updateIndentProof({
  required String indentId,
  required String quantity,
  required String measurement,
  required String vehicleNumber,
  required String weight,
  required String reviewComment,
  required bool approve,
  String deliveryId = '',
  String vendorId = '',
  String itemRunId = '',
  Map<String, String> approvedQuantities = const {},
}) async {
  final credentials = await _indentProofCredentials();
  final body = <String, String>{
    'user_id': credentials.userId,
    'indent_id': indentId,
    if (credentials.apiToken.isNotEmpty) 'api_token': credentials.apiToken,
    if (quantity.isNotEmpty) 'quantity': quantity,
    if (measurement.isNotEmpty) 'measurement': measurement,
    if (vehicleNumber.isNotEmpty) 'vehicle_number': vehicleNumber,
    if (weight.isNotEmpty) 'weight': weight,
    if (reviewComment.isNotEmpty) 'review_comment': reviewComment,
    if (deliveryId.isNotEmpty) 'delivery_id': deliveryId,
    if (vendorId.isNotEmpty) 'vendor_id': vendorId,
    if (itemRunId.isNotEmpty) 'item_run_id': itemRunId,
    if (approvedQuantities.isNotEmpty)
      'approved_quantities': jsonEncode(approvedQuantities),
    if (approve) 'complete': '1',
    if (approve) 'approve': '1',
  };
  final response = await ApiHttp.post(
    Uri.parse('$_indentProofApiBase/API/update_indent_proof'),
    headers: credentials.apiToken.isEmpty
        ? null
        : {'X-Api-Token': credentials.apiToken},
    body: body,
  ).timeout(const Duration(seconds: 25));
  final decoded = _decodeBody(response);
  _throwIfFailed(response, decoded, 'Failed to update indent proof');
  if (decoded is Map && decoded['message'] != null) {
    return decoded['message'].toString();
  }
  return '';
}


class _ReviewMaterialQty {
  final String materialKey;
  final String name;
  final String unit;
  final String submitted;
  final TextEditingController controller;

  _ReviewMaterialQty({
    required this.materialKey,
    required this.name,
    required this.unit,
    required this.submitted,
    required this.controller,
  });
}
