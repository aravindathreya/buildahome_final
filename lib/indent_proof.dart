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
          if (mounted) _openDetail(initialId);
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

  Future<void> _openDetail(String indentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IndentProofDetailScreen(indentId: indentId),
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
                              ? 'Approved site-proof indents assigned to you will appear here.'
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
                                    : () => _openDetail(indentId),
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

  const IndentProofDetailScreen({
    Key? key,
    required this.indentId,
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
    super.dispose();
  }

  Map<String, dynamic> get _proof => _proofMap(_detail);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _fetchIndentProofDetail(widget.indentId);
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
    _quantityController.text = _display(proof, [
          'quantity',
          'proof_quantity',
          'site_quantity',
        ]) ??
        _display(detail, ['proof_quantity', 'site_quantity']) ??
        '';
    _measurementController.text = _display(proof, [
          'measurement',
          'proof_measurement',
        ]) ??
        '';
    _vehicleController.text = _display(proof, [
          'vehicle_number',
          'vehicle',
          'vehicle_no',
        ]) ??
        '';
    _weightController.text = _display(proof, [
          'weight',
          'proof_weight',
        ]) ??
        '';
    _reviewCommentController.text = _display(proof, [
          'review_comment',
        ]) ??
        _commentFromMap(proof['comments'], 'review_comment') ??
        '';
    _siteComment = _display(proof, ['site_comment']) ??
        _commentFromMap(proof['comments'], 'site_comment');
    _originalQuantity = _quantityController.text.trim();
    _originalMeasurement = _measurementController.text.trim();
    setState(() {
      _detail = detail;
      _loading = false;
      _error = null;
    });
  }

  String? _validateReducedFields() {
    final quantityError = _validateNotIncreased(
      fieldLabel: 'Quantity',
      original: _originalQuantity,
      edited: _quantityController.text.trim(),
    );
    if (quantityError != null) return quantityError;
    return _validateNotIncreased(
      fieldLabel: 'Measurement',
      original: _originalMeasurement,
      edited: _measurementController.text.trim(),
    );
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
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        title: const Text('Indent proof'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.navy,
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
                          _sectionCard(
                            context,
                            title: 'Indent ${widget.indentId}',
                            child: Column(
                              children: [
                                _infoRow('Indent ID', widget.indentId),
                                _infoRow(
                                  'Project',
                                  _display(_detail, [
                                        'project_name',
                                        'project',
                                      ]) ??
                                      '—',
                                ),
                                _infoRow(
                                  'Material',
                                  _display(_detail, ['material', 'item']) ?? '—',
                                ),
                                _infoRow(
                                  'Quantity',
                                  _joinQuantity(
                                    _display(_detail, ['quantity']),
                                    _display(_detail, ['unit']),
                                  ),
                                ),
                                _infoRow(
                                  'Purpose',
                                  _display(_detail, ['purpose', 'reason']) ??
                                      '—',
                                ),
                                _infoRow(
                                  'Status',
                                  _display(_detail, ['status', 'indent_status']) ??
                                      '—',
                                ),
                                _infoRow(
                                  'PO',
                                  _display(_detail, [
                                        'po_number',
                                        'po',
                                        'purchase_order',
                                        'po_id',
                                      ]) ??
                                      '—',
                                ),
                                _infoRow(
                                  'Created by',
                                  _display(_detail, [
                                        'created_by_name',
                                        'created_by',
                                        'user_name',
                                      ]) ??
                                      '—',
                                ),
                                _infoRow(
                                  'Timestamp',
                                  _display(_detail, [
                                        'timestamp',
                                        'created_at',
                                        'created_on',
                                      ]) ??
                                      '—',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionCard(
                            context,
                            title: 'Site proof',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _infoRow(
                                  'Task status',
                                  _display(_proof, [
                                        'task_status',
                                        'proof_status',
                                        'workflow_status',
                                        'status',
                                      ]) ??
                                      _display(_detail, [
                                        'task_status',
                                        'proof_status',
                                        'workflow_status',
                                      ]) ??
                                      '—',
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Received details',
                                  style: TextStyle(
                                    color: AppTheme.getTextPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_canEdit) ...[
                                  _editField(
                                    controller: _quantityController,
                                    label: 'Quantity',
                                    helperText: _originalQuantity.isEmpty
                                        ? null
                                        : 'Can only reduce from $_originalQuantity',
                                  ),
                                  _editField(
                                    controller: _measurementController,
                                    label: 'Measurement',
                                    helperText: _originalMeasurement.isEmpty
                                        ? null
                                        : 'Can only reduce from $_originalMeasurement',
                                  ),
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
                                    'Quantity',
                                    _quantityController.text.trim().isEmpty
                                        ? '—'
                                        : _quantityController.text.trim(),
                                  ),
                                  _infoRow(
                                    'Measurement',
                                    _measurementController.text.trim().isEmpty
                                        ? '—'
                                        : _measurementController.text.trim(),
                                  ),
                                  _infoRow(
                                    'Vehicle number',
                                    _vehicleController.text.trim().isEmpty
                                        ? '—'
                                        : _vehicleController.text.trim(),
                                  ),
                                  _infoRow(
                                    'Weight',
                                    _weightController.text.trim().isEmpty
                                        ? '—'
                                        : _weightController.text.trim(),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _infoRow(
                                  'Site comment',
                                  (_siteComment ?? '').trim().isEmpty
                                      ? '—'
                                      : _siteComment!.trim(),
                                ),
                                if (_canEdit) ...[
                                  const SizedBox(height: 12),
                                  _editField(
                                    controller: _reviewCommentController,
                                    label: 'Review comment',
                                  ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    'Review comment',
                                    _reviewCommentController.text.trim().isEmpty
                                        ? '—'
                                        : _reviewCommentController.text.trim(),
                                  ),
                                ],
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
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Text(
                              'This indent proof is already approved.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF166534),
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

  List<Widget> _proofSectionsWidgets(
    BuildContext context,
    Map<String, dynamic> proof,
  ) {
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: !_saving,
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
    final project = _display(item, ['project_name', 'project']) ?? 'Indent';
    final material = _display(item, ['material', 'item']) ?? '—';
    final quantity = _joinQuantity(
      _display(item, ['quantity', 'qty']),
      _display(item, ['unit']),
    );
    final status = _display(item, ['status', 'indent_status']) ?? '';
    final proofStatus = _display(proof, [
          'task_status',
          'proof_status',
          'workflow_status',
        ]) ??
        _display(item, ['task_status', 'proof_status']) ??
        '';
    final indentId = _display(item, ['indent_id', 'id']) ?? '';
    final createdBy = _display(item, [
          'created_by_name',
          'created_by_user',
          'created_by',
          'user_name',
        ]) ??
        '';
    final timestamp = _display(item, [
          'timestamp',
          'created_at',
          'created_on',
        ]) ??
        '';
    final primary = AppTheme.getPrimaryColor(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              AppTheme.getBackgroundPrimaryLight(context),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.fact_check_outlined,
                      color: primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.getTextPrimary(context),
                          ),
                        ),
                        if (createdBy.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Created by $createdBy',
                            style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (indentId.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '#$indentId',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardInfoRow(context, Icons.build_outlined, 'Material', material),
                  if (quantity != '—') ...[
                    const SizedBox(height: 14),
                    _cardInfoRow(
                      context,
                      Icons.numbers_rounded,
                      'Quantity',
                      quantity,
                    ),
                  ],
                  if (status.isNotEmpty || proofStatus.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (status.isNotEmpty)
                          _statusChip(context, status),
                        if (proofStatus.isNotEmpty)
                          _statusChip(context, proofStatus),
                      ],
                    ),
                  ],
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: AppTheme.getTextSecondary(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timestamp,
                            style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final primary = AppTheme.getPrimaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.getTextSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ],
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
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<Color> _statusChipColors(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('approv') ||
        normalized.contains('complete') ||
        normalized.contains('done')) {
      return const [Color(0xFFDCFCE7), Color(0xFF166534)];
    }
    if (normalized.contains('reject') || normalized.contains('fail')) {
      return const [Color(0xFFFEE2E2), Color(0xFFB91C1C)];
    }
    if (normalized.contains('pending') ||
        normalized.contains('review') ||
        normalized.contains('open')) {
      return const [Color(0xFFFFF7ED), Color(0xFFC2410C)];
    }
    return const [Color(0xFFEFF6FF), Color(0xFF1D4ED8)];
  }
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
            value.trim().isEmpty ? '—' : value,
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
        const Text('—', style: TextStyle(fontWeight: FontWeight.w700))
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
  if ((quantity ?? '').isEmpty) return '—';
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

List<String> _imageUrls(Map<String, dynamic> proof, Map<String, dynamic> detail) {
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

void _throwIfFailed(http.Response response, dynamic decoded, String fallback) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    if (decoded is Map && decoded['success'] == false) {
      throw Exception(decoded['message']?.toString() ?? fallback);
    }
    return;
  }
  if (decoded is Map && decoded['message'] != null) {
    throw Exception(decoded['message'].toString());
  }
  throw Exception('$fallback (${response.statusCode})');
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

Future<Map<String, dynamic>> _fetchIndentProofDetail(String indentId) async {
  final credentials = await _indentProofCredentials();
  final uri =
      Uri.parse('$_indentProofApiBase/API/get_indent_proof_detail').replace(
    queryParameters: {
      'user_id': credentials.userId,
      'indent_id': indentId,
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
