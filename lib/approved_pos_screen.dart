import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'client_portal/client_portal_document_ui.dart';
import 'indent_proof.dart';
import 'models/approved_po.dart';
import 'models/workflow_document.dart';
import 'MyTasksScreen.dart';
import 'services/approved_po_service.dart';
import 'services/session_manager.dart';
import 'widgets/skeleton_loader.dart';
import 'widgets/themed_scaffold.dart';
import 'site_proof_multi/multi_material_site_proof_flow.dart';
import 'widgets/indent_site_proof_summary_card.dart';
import 'widgets/workflow_document_viewer.dart';

class ApprovedPosScreenLayout extends StatelessWidget {
  final String? initialProjectId;
  final String? initialProjectName;
  final String? initialSearch;

  const ApprovedPosScreenLayout({
    super.key,
    this.initialProjectId,
    this.initialProjectName,
    this.initialSearch,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Approved POs',
      body: SafeArea(
        child: ApprovedPosScreen(
          initialProjectId: initialProjectId,
          initialProjectName: initialProjectName,
          initialSearch: initialSearch,
        ),
      ),
    );
  }
}

class ApprovedPosScreen extends StatefulWidget {
  final String? initialProjectId;
  final String? initialProjectName;
  final String? initialSearch;

  const ApprovedPosScreen({
    super.key,
    this.initialProjectId,
    this.initialProjectName,
    this.initialSearch,
  });

  @override
  State<ApprovedPosScreen> createState() => _ApprovedPosScreenState();
}

enum _PoDeliveryFilter { delivered, notDelivered }

class _ApprovedPosScreenState extends State<ApprovedPosScreen> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<ApprovedPo> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _offset = 0;
  String _search = '';
  _PoDeliveryFilter _filter = _PoDeliveryFilter.notDelivered;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialSearch?.trim() ?? '';
    if (seed.isNotEmpty) {
      _searchController.text = seed;
      _search = seed;
    }
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _projectId {
    final id = widget.initialProjectId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
    });
    try {
      final result = await ApprovedPoService().fetchList(
        projectId: _projectId,
        search: _search,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _hasMore = result.hasMore;
        _offset = result.items.length;
        _loading = false;
      });
      await _fillActiveTabIfEmpty();
    } on SessionInvalidatedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result = await ApprovedPoService().fetchList(
        projectId: _projectId,
        search: _search,
        offset: _offset,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...result.items];
        _hasMore = result.hasMore;
        _offset += result.items.length;
        _loadingMore = false;
      });
    } on SessionInvalidatedException {
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (_scrollController.position.pixels >= max - 200) {
      _loadMore();
    }
  }

  void _onSearchSubmitted(String value) {
    _search = value.trim();
    _loadInitial();
  }

  List<ApprovedPo> _itemsFor(_PoDeliveryFilter filter) {
    if (filter == _PoDeliveryFilter.delivered) {
      return _items.where((item) => item.isDeliveredReceipt).toList();
    }
    return _items.where((item) => !item.isDeliveredReceipt).toList();
  }

  List<ApprovedPo> get _visibleItems => _itemsFor(_filter);

  /// Keep paging when the open tab is empty but later pages may still match.
  Future<void> _fillActiveTabIfEmpty() async {
    var hops = 0;
    while (mounted &&
        !_loading &&
        _itemsFor(_filter).isEmpty &&
        _hasMore &&
        hops < 8) {
      hops++;
      await _loadMore();
    }
  }

  void _onFilterSelected(_PoDeliveryFilter next) {
    if (_filter == next) return;
    setState(() => _filter = next);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _fillActiveTabIfEmpty();
  }

  Future<void> _openDetail(ApprovedPo item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApprovedPoDetailScreen(
          indentId: item.indentId,
          listItem: item,
        ),
      ),
    );
    if (!mounted) return;
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.getBackgroundPrimary(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.initialProjectName != null &&
                    widget.initialProjectName!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFC7D2FE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.folder_outlined,
                                size: 14,
                                color: Color(0xFF4338CA),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.initialProjectName!.trim(),
                                style: const TextStyle(
                                  color: Color(0xFF4338CA),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ClientPortalSearchBar(
                  controller: _searchController,
                  hint: 'Search PO, indent, material…',
                  onClear: () {
                    _searchController.clear();
                    _onSearchSubmitted('');
                  },
                ),
                const SizedBox(height: 12),
                _DeliveryFilterBar(
                  selected: _filter,
                  deliveredCount: _itemsFor(_PoDeliveryFilter.delivered).length,
                  notDeliveredCount:
                      _itemsFor(_PoDeliveryFilter.notDelivered).length,
                  onChanged: _onFilterSelected,
                ),
                if (!_loading && _visibleItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ClientPortalSectionHeading(
                          label: _filter == _PoDeliveryFilter.delivered
                              ? 'Delivered'
                              : 'Not delivered',
                        ),
                      ),
                      Text(
                        '${_visibleItems.length}${_hasMore ? '+' : ''}',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const SkeletonListLoader(
        showSummary: false,
        cardCount: 4,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
      );
    }

    if (_error != null && _items.isEmpty) {
      return _InlineMessage(
        icon: Icons.error_outline_rounded,
        title: 'Could not load',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _loadInitial,
      );
    }

    final visible = _visibleItems;
    final deliveredTab = _filter == _PoDeliveryFilter.delivered;

    if (_items.isEmpty || (visible.isEmpty && !_loadingMore)) {
      final title = _items.isEmpty
          ? 'No approved POs'
          : (deliveredTab ? 'No delivered POs' : 'Nothing left to deliver');
      final message = _items.isEmpty
          ? (_projectId != null
              ? 'No approved POs for this project'
              : 'No approved POs found')
          : (deliveredTab
              ? 'POs show here after site proof is uploaded and fully approved.'
              : 'Approved POs still waiting on delivery show here, including partially delivered ones.');
      return RefreshIndicator(
        color: AppTheme.accentBlue,
        onRefresh: _loadInitial,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: _InlineMessage(
                icon: Icons.receipt_long_outlined,
                title: title,
                message: message,
                actionLabel: 'Refresh',
                onAction: _loadInitial,
              ),
            ),
          ],
        ),
      );
    }

    if (visible.isEmpty && _loadingMore) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentBlue,
      onRefresh: _loadInitial,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        itemCount: visible.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visible.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = visible[index];
          return _ApprovedPoListCard(
            item: item,
            onTap: () => _openDetail(item),
          );
        },
      ),
    );
  }
}

class _DeliveryFilterBar extends StatelessWidget {
  final _PoDeliveryFilter selected;
  final int deliveredCount;
  final int notDeliveredCount;
  final ValueChanged<_PoDeliveryFilter> onChanged;

  const _DeliveryFilterBar({
    required this.selected,
    required this.deliveredCount,
    required this.notDeliveredCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DeliveryFilterChip(
              label: 'Not delivered',
              count: notDeliveredCount,
              selected: selected == _PoDeliveryFilter.notDelivered,
              onTap: () => onChanged(_PoDeliveryFilter.notDelivered),
            ),
          ),
          Expanded(
            child: _DeliveryFilterChip(
              label: 'Delivered',
              count: deliveredCount,
              selected: selected == _PoDeliveryFilter.delivered,
              onTap: () => onChanged(_PoDeliveryFilter.delivered),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _DeliveryFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.mutedGrey;
    return Material(
      color: selected ? AppTheme.accentBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Center(
          child: Text(
            count > 0 ? '$label ($count)' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedPoListCard extends StatelessWidget {
  final ApprovedPo item;
  final VoidCallback onTap;

  const _ApprovedPoListCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = item.displayPoNumber();
    final isPendingPo = title == 'PO pending';
    final materialLine = item.displayMaterialLine();
    final metaParts = <String>[];
    if (item.vendorName.isNotEmpty) metaParts.add(item.vendorName);
    if (item.projectName.isNotEmpty) metaParts.add(item.projectName);
    final metaLine = metaParts.join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ClientPortalDocTheme.cardBackground,
        borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: ClientPortalDocTheme.cardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPendingPo
                        ? const Color(0xFF3D3420)
                        : const Color(0xFF1E3A5F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPendingPo
                        ? Icons.hourglass_empty_rounded
                        : Icons.receipt_long_rounded,
                    color: isPendingPo
                        ? const Color(0xFFEAB308)
                        : const Color(0xFF93C5FD),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: AppTheme.darkTextPrimary,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (item.indentId > 0)
                            Text(
                              '#${item.indentId}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.getTextSecondary(context),
                              ),
                            ),
                        ],
                      ),
                      if (materialLine.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          materialLine,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkTextPrimary,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (item.receivedMaterialId.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Material ID: ',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4338CA),
                            letterSpacing: 0.2,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (metaLine.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          metaLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.getTextSecondary(context),
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (item.createdAt.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.createdAt,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.getTextSecondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (item.statusLabel.isNotEmpty)
                            _ApprovedPoChip(
                              label: item.statusLabel,
                              bg: const Color(0xFF14532D),
                              fg: const Color(0xFF6EE7B7),
                            ),
                          if (item.isPartial ||
                              item.receiptStatus == 'partial')
                            _ApprovedPoChip(
                              label: item.receiptLabel.trim().isNotEmpty
                                  ? item.receiptLabel.trim()
                                  : 'Partially completed',
                              bg: const Color(0xFF3D3420),
                              fg: const Color(0xFFEAB308),
                              icon: Icons.timelapse_rounded,
                            ),
                          if (item.isComplete ||
                              item.receiptStatus == 'complete')
                            _ApprovedPoChip(
                              label: item.receiptLabel.trim().isNotEmpty
                                  ? item.receiptLabel.trim()
                                  : 'Fully received',
                              bg: const Color(0xFF14532D),
                              fg: const Color(0xFF6EE7B7),
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          if (item.canViewMaskedDocument)
                            _ApprovedPoChip(
                              label: 'PDF ready',
                              bg: const Color(0xFF1E3A5F),
                              fg: const Color(0xFF93C5FD),
                              icon: Icons.picture_as_pdf_rounded,
                            ),
                          if (item.awaitingMaskedDocument)
                            _ApprovedPoChip(
                              label: 'PDF pending',
                              bg: const Color(0xFF3D3420),
                              fg: const Color(0xFFEAB308),
                              icon: Icons.hourglass_top_rounded,
                            ),
                          if (item.isBilled)
                            _ApprovedPoChip(
                              label: 'Billed',
                              bg: const Color(0xFF14532D),
                              fg: const Color(0xFF6EE7B7),
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          if (item.createdByName.isNotEmpty)
                            _ApprovedPoChip(
                              label: item.createdByName,
                              bg: AppTheme.darkBackgroundPrimaryLight,
                              fg: AppTheme.mutedGrey,
                              icon: Icons.person_outline_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.getTextSecondary(context),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApprovedPoChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;

  const _ApprovedPoChip({
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ApprovedPoDetailScreen extends StatefulWidget {
  final int indentId;
  final ApprovedPo? listItem;

  const ApprovedPoDetailScreen({
    super.key,
    required this.indentId,
    this.listItem,
  });

  @override
  State<ApprovedPoDetailScreen> createState() => _ApprovedPoDetailScreenState();
}

class _ApprovedPoDetailScreenState extends State<ApprovedPoDetailScreen> {
  ApprovedPo? _item;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _siteProofTask;
  bool _siteProofTaskLoading = false;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _item = widget.listItem;
    _loadRole();
    _loadDetail();
    final listItem = widget.listItem;
    if (listItem != null) {
      _refreshSiteProofTask(listItem);
    }
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _userRole = prefs.getString('role'));
  }

  Future<void> _refreshSiteProofTask(ApprovedPo item) async {
    setState(() => _siteProofTaskLoading = true);
    // Prefer an open site-proof task (remaining vendor/batch) over a completed sibling.
    var task = await findIndentSiteProofTask(
      indentId: item.indentId.toString(),
      projectId: item.projectId > 0 ? item.projectId.toString() : null,
      fetchIfMissing: true,
      includeCompleted: false,
    );
    task ??= await findIndentSiteProofTask(
      indentId: item.indentId.toString(),
      projectId: item.projectId > 0 ? item.projectId.toString() : null,
      fetchIfMissing: true,
      includeCompleted: true,
    );
    if (!mounted) return;
    setState(() {
      _siteProofTask = task;
      _siteProofTaskLoading = false;
    });
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ApprovedPoService().fetchDetail(widget.indentId);
      if (!mounted) return;
      setState(() {
        _item = detail;
        _loading = false;
      });
      await _refreshSiteProofTask(detail);
    } on SessionInvalidatedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openMaskedDocument(ApprovedPo item) async {
    final doc = item.workflowDocument();
    if (doc == null) return;
    await openWorkflowDocument(context, doc, clientMode: false);
  }

  Future<void> _openSiteProofUpload(ApprovedPo item) async {
    final siteTask = _siteProofTask;
    final vendorId = siteTask == null
        ? null
        : indentSiteProofTaskVendorId(siteTask);
    final runId = siteTask == null
        ? ''
        : resolvedWorkflowItemRunIdFromTask(
            Map<String, dynamic>.from(siteTask),
          );
    await openIndentSiteProofForIndent(
      context,
      indentId: item.indentId.toString(),
      projectId: item.projectId > 0 ? item.projectId.toString() : null,
      vendorId: vendorId,
      itemRunId: runId.isEmpty ? null : runId,
      preferredTask: siteTask == null
          ? null
          : Map<String, dynamic>.from(siteTask),
      onRefresh: () async {
        await _loadDetail();
      },
    );
    if (!mounted) return;
    final current = _item;
    if (current != null) await _refreshSiteProofTask(current);
  }

  Future<void> _openSiteProofReview(ApprovedPo item) async {
    final siteTask = _siteProofTask;
    final vendorId =
        siteTask == null ? null : indentSiteProofTaskVendorId(siteTask);
    final deliveryId =
        siteTask == null ? null : indentProofReviewDeliveryId(siteTask);
    final runId = siteTask == null
        ? ''
        : resolvedWorkflowItemRunIdFromTask(
            Map<String, dynamic>.from(siteTask),
          );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IndentProofDetailScreen(
          indentId: item.indentId.toString(),
          forReview: true,
          vendorId: vendorId,
          deliveryId: deliveryId,
          itemRunId: runId.isEmpty ? null : runId,
        ),
      ),
    );
    if (!mounted) return;
    await _loadDetail();
  }

  bool _indentIsApproved(ApprovedPo item) {
    final text = '${item.status} ${item.statusLabel}'.toLowerCase();
    if (text.contains('unapprov') || text.contains('reject')) return false;
    if (text.contains('approv')) return true;
    return true;
  }

  bool _siteProofSubmitted(Map<String, dynamic>? task) {
    if (task == null) return false;
    if (isTaskCompletedStatus(task)) return true;
    final steps = indentPoSiteProofActions(workflowActionsFromTask(task));
    final requiredSteps = steps.where((action) {
      final id = action['id']?.toString() ?? '';
      return id != 'indent_po_site_comment' &&
          id != 'indent_po_review_comment';
    }).toList();
    if (requiredSteps.isEmpty) return false;
    return requiredSteps
        .every((action) => indentPoSiteProofStepDone(task, action));
  }

  bool _shouldShowSiteProofUpload(ApprovedPo item) {
    if (_siteProofTaskLoading) return false;
    if (!_indentIsApproved(item)) return false;

    // Multi-material: keep upload available until remaining qty is fully received.
    // A prior partial delivery must NOT permanently hide "Start/Add remaining".
    if (item.usesMultiMaterialSiteProof) {
      return item.hasOutstandingSiteProofMaterials;
    }

    final task = _siteProofTask;
    if (task == null) return false;
    if (_siteProofSubmitted(task)) return false;
    return indentPoSiteProofActions(workflowActionsFromTask(task)).isNotEmpty;
  }

  bool _shouldShowSiteProofSection(ApprovedPo item) {
    if (_siteProofTaskLoading) return false;
    if (!_indentIsApproved(item)) return false;
    if (item.usesMultiMaterialSiteProof &&
        item.hasOutstandingSiteProofMaterials) {
      return true;
    }
    if (_siteProofTask == null) return false;
    if (_shouldShowSiteProofUpload(item)) return true;
    return isIndentProofReviewerRole(_userRole);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final title = item != null
        ? (item.poNumber.trim().isNotEmpty
            ? item.poNumber.trim()
            : 'Indent #${item.indentId}')
        : 'Approved PO';

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _item == null) {
      return const SkeletonListLoader(
        showSummary: false,
        cardCount: 3,
        padding: EdgeInsets.all(20),
      );
    }

    if (_error != null && _item == null) {
      return _InlineMessage(
        icon: Icons.error_outline_rounded,
        title: 'Could not load',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _loadDetail,
      );
    }

    final item = _item!;
    final materials = item.materials.isNotEmpty
        ? item.materials
        : [
            ApprovedPoMaterialLine(
              material: item.material,
              quantity: item.quantity,
              unit: item.unit,
            ),
          ];
    final workflowDoc = item.workflowDocument();

    return RefreshIndicator(
      color: ClientPortalDocTheme.accentBlue,
      onRefresh: _loadDetail,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _ApprovedPoHeroCard(item: item),
          const SizedBox(height: 16),
          const ClientPortalSectionHeading(label: 'Details'),
          _ApprovedPoInfoTable(item: item),
          const SizedBox(height: 16),
          const ClientPortalSectionHeading(label: 'Materials'),
          _ApprovedPoMaterialsCard(materials: materials),
          const SizedBox(height: 20),
          const ClientPortalSectionHeading(label: 'PO document'),
          if (workflowDoc != null)
            _ApprovedPoDocumentCard(
              document: workflowDoc,
              onOpen: () => _openMaskedDocument(item),
            )
          else if (item.awaitingMaskedDocument)
            const _ApprovedPoPendingDocumentCard()
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: ClientPortalDocTheme.cardDecoration(
                bg: AppTheme.darkBackgroundPrimaryLight,
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.darkBackgroundSecondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: AppTheme.mutedGrey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No PO document for this indent yet.',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_shouldShowSiteProofSection(item)) ...[
            const SizedBox(height: 20),
            const ClientPortalSectionHeading(label: 'Site proof'),
            _ApprovedPoSiteProofCard(
              item: item,
              siteProofTask: _siteProofTask,
              loadingTask: _siteProofTaskLoading,
              showUpload: _shouldShowSiteProofUpload(item),
              showReviewOption: isIndentProofReviewerRole(_userRole) &&
                  _siteProofTask != null,
              onUpload: () => _openSiteProofUpload(item),
              onReview: () => _openSiteProofReview(item),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedPoHeroCard extends StatelessWidget {
  final ApprovedPo item;

  const _ApprovedPoHeroCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFDC2626),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayPoNumber(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkTextPrimary,
                    fontSize: 16,
                    height: 1.25,
                  ),
                ),
                if (item.projectName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.projectName,
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (item.displayMaterialLine().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.displayMaterialLine(),
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.statusLabel.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: const TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (item.isPartial || item.receiptStatus == 'partial') ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D3420),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.receiptLabel.trim().isNotEmpty
                        ? item.receiptLabel.trim()
                        : 'Partially completed',
                    style: const TextStyle(
                      color: Color(0xFFEAB308),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              if (item.isComplete || item.receiptStatus == 'complete') ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.receiptLabel.trim().isNotEmpty
                        ? item.receiptLabel.trim()
                        : 'Fully received',
                    style: const TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              if (item.isBilled) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Billed',
                    style: TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovedPoInfoTable extends StatelessWidget {
  final ApprovedPo item;

  const _ApprovedPoInfoTable({required this.item});

  @override
  Widget build(BuildContext context) {
    final rows = <_ApprovedPoInfoRow>[
      if (item.vendorName.isNotEmpty)
        _ApprovedPoInfoRow(Icons.storefront_outlined, 'Vendor', item.vendorName),
      if (item.createdByName.isNotEmpty)
        _ApprovedPoInfoRow(
            Icons.person_outline, 'Created by', item.createdByName),
      if (item.createdAt.isNotEmpty)
        _ApprovedPoInfoRow(
            Icons.calendar_today_outlined, 'Date', item.createdAt),
      if (item.purpose.isNotEmpty)
        _ApprovedPoInfoRow(Icons.flag_outlined, 'Purpose', item.purpose),
      if (item.comments.isNotEmpty)
        _ApprovedPoInfoRow(Icons.comment_outlined, 'Comments', item.comments),
      if (item.indentId > 0)
        _ApprovedPoInfoRow(Icons.tag_outlined, 'Indent ID', '#${item.indentId}'),
      if (item.receivedMaterialId.trim().isNotEmpty)
        _ApprovedPoInfoRow(
          Icons.qr_code_2_outlined,
          'Material ID',
          item.receivedMaterialId.trim(),
        ),
    ];

    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final row = entry.value;
          final isLast = entry.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isLast ? Colors.transparent : AppTheme.border,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(row.icon, size: 18, color: AppTheme.mutedGrey),
                const SizedBox(width: 10),
                SizedBox(
                  width: 100,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: TextStyle(
                      color: AppTheme.darkTextPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ApprovedPoInfoRow {
  final IconData icon;
  final String label;
  final String value;

  const _ApprovedPoInfoRow(this.icon, this.label, this.value);
}

class _ApprovedPoMaterialsCard extends StatelessWidget {
  final List<ApprovedPoMaterialLine> materials;

  const _ApprovedPoMaterialsCard({required this.materials});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              _materialHeader('Material'),
              _materialHeader('Qty'),
              _materialHeader('Unit'),
            ],
          ),
          for (final line in materials)
            TableRow(
              children: [
                _materialCell(line.material),
                _materialCell(line.quantity),
                _materialCell(line.unit),
              ],
            ),
        ],
      ),
    );
  }

  Widget _materialHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTheme.mutedGrey,
        ),
      ),
    );
  }

  Widget _materialCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text.trim().isEmpty ? '—' : text,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.darkTextPrimary,
        ),
      ),
    );
  }
}

class _ApprovedPoSiteProofCard extends StatelessWidget {
  final ApprovedPo item;
  final Map<String, dynamic>? siteProofTask;
  final bool loadingTask;
  final bool showUpload;
  final bool showReviewOption;
  final VoidCallback onUpload;
  final VoidCallback onReview;

  const _ApprovedPoSiteProofCard({
    required this.item,
    required this.siteProofTask,
    required this.loadingTask,
    required this.showUpload,
    required this.showReviewOption,
    required this.onUpload,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final doneCount = siteProofTask != null
        ? indentPoSiteProofDoneCount(siteProofTask!)
        : 0;
    final started = doneCount > 0;

    final itemText = item.displayMaterialLine().trim();
    final vendor = item.vendorName.trim();

    String? subtitle;
    if (loadingTask) {
      subtitle = 'Checking site-proof task…';
    } else if (!showUpload) {
      subtitle = 'Site proof has been submitted for this indent.';
    } else if (item.usesMultiMaterialSiteProof &&
        (item.isPartial ||
            item.receiptStatus == 'partial' ||
            item.hasOutstandingSiteProofMaterials)) {
      if (item.isPartial || item.receiptStatus == 'partial') {
        subtitle =
            'Partially completed — submit another delivery for remaining quantities.';
      } else {
        subtitle =
            'You can submit another delivery for remaining material quantities.';
      }
    }

    final buttonLabel = !showUpload
        ? ''
        : (item.usesMultiMaterialSiteProof && started
            ? 'Add remaining delivery'
            : (started ? 'Continue site proof' : 'Start site proof'));

    Widget? reviewBtn;
    if (showReviewOption) {
      reviewBtn = SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onReview,
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Review site proof'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.darkTextPrimary,
            minimumSize: const Size.fromHeight(44),
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return IndentSiteProofSummaryCard(
      title: showUpload
          ? 'Upload site proof for approved PO'
          : 'Site proof',
      indentId: item.indentId > 0 ? '${item.indentId}' : null,
      itemText: itemText.isEmpty ? null : itemText,
      vendorName: vendor.isEmpty ? null : vendor,
      subtitle: subtitle,
      buttonLabel: buttonLabel.isEmpty ? 'Start site proof' : buttonLabel,
      onPressed: showUpload ? (loadingTask ? null : onUpload) : null,
      trailingButton: reviewBtn,
    );
  }
}

class _ApprovedPoDocumentCard extends StatelessWidget {
  final WorkflowDocumentUpload document;
  final VoidCallback onOpen;

  const _ApprovedPoDocumentCard({
    required this.document,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Color(0xFFDC2626),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.darkTextPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Masked PO PDF. Amounts and rates are hidden.',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColorConst,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedPoPendingDocumentCard extends StatelessWidget {
  const _ApprovedPoPendingDocumentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3420),
        borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
        border: Border.all(color: const Color(0xFF854D0E)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF4A3B1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFFEAB308),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Masked PO PDF pending',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A PO file exists for this indent, but the masked mobile copy '
                  'has not been generated yet. Pull to refresh after it is ready.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppTheme.getTextSecondary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InlineMessage({
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
            Icon(icon, size: 44, color: const Color(0xFF9CA3AF)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
