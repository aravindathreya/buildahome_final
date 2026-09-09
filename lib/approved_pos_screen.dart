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
import 'widgets/workflow_document_viewer.dart';

class ApprovedPosScreenLayout extends StatelessWidget {
  final String? initialProjectId;
  final String? initialProjectName;

  const ApprovedPosScreenLayout({
    super.key,
    this.initialProjectId,
    this.initialProjectName,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Approved POs',
      body: SafeArea(
        child: ApprovedPosScreen(
          initialProjectId: initialProjectId,
          initialProjectName: initialProjectName,
        ),
      ),
    );
  }
}

class ApprovedPosScreen extends StatefulWidget {
  final String? initialProjectId;
  final String? initialProjectName;

  const ApprovedPosScreen({
    super.key,
    this.initialProjectId,
    this.initialProjectName,
  });

  @override
  State<ApprovedPosScreen> createState() => _ApprovedPosScreenState();
}

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

  @override
  void initState() {
    super.initState();
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

  Future<void> _openDetail(ApprovedPo item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApprovedPoDetailScreen(
          indentId: item.indentId,
          listItem: item,
        ),
      ),
    );
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
                if (!_loading && _items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: ClientPortalSectionHeading(
                          label: 'Approved purchase orders',
                        ),
                      ),
                      Text(
                        '${_items.length}${_hasMore ? '+' : ''}',
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

    if (_items.isEmpty) {
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
                title: 'No approved POs',
                message: _projectId != null
                    ? 'No approved POs for this project'
                    : 'No approved POs found',
                actionLabel: 'Refresh',
                onAction: _loadInitial,
              ),
            ),
          ],
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
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
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
          final item = _items[index];
          return _ApprovedPoListCard(
            item: item,
            onTap: () => _openDetail(item),
          );
        },
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
                        ? const Color(0xFFFFF7ED)
                        : const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPendingPo
                        ? Icons.hourglass_empty_rounded
                        : Icons.receipt_long_rounded,
                    color: isPendingPo
                        ? const Color(0xFFB45309)
                        : const Color(0xFF4338CA),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: AppTheme.navy,
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
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
                              bg: const Color(0xFFDCFCE7),
                              fg: const Color(0xFF166534),
                            ),
                          if (item.canViewMaskedDocument)
                            _ApprovedPoChip(
                              label: 'PDF ready',
                              bg: const Color(0xFFEFF6FF),
                              fg: const Color(0xFF2563EB),
                              icon: Icons.picture_as_pdf_rounded,
                            ),
                          if (item.awaitingMaskedDocument)
                            _ApprovedPoChip(
                              label: 'PDF pending',
                              bg: const Color(0xFFFFF7ED),
                              fg: const Color(0xFFB45309),
                              icon: Icons.hourglass_top_rounded,
                            ),
                          if (item.isBilled)
                            _ApprovedPoChip(
                              label: 'Billed',
                              bg: const Color(0xFFECFDF5),
                              fg: const Color(0xFF047857),
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          if (item.createdByName.isNotEmpty)
                            _ApprovedPoChip(
                              label: item.createdByName,
                              bg: const Color(0xFFF3F4F6),
                              fg: const Color(0xFF4B5563),
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
    final task = await findIndentSiteProofTask(
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
    await openIndentSiteProofForIndent(
      context,
      indentId: item.indentId.toString(),
      projectId: item.projectId > 0 ? item.projectId.toString() : null,
      onRefresh: () async {
        await _loadDetail();
      },
    );
    if (!mounted) return;
    final current = _item;
    if (current != null) await _refreshSiteProofTask(current);
  }

  Future<void> _openSiteProofReview(ApprovedPo item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IndentProofDetailScreen(
          indentId: item.indentId.toString(),
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
    final task = _siteProofTask;
    if (task == null) return false;
    if (_siteProofSubmitted(task)) return false;
    return indentPoSiteProofActions(workflowActionsFromTask(task)).isNotEmpty;
  }

  bool _shouldShowSiteProofSection(ApprovedPo item) {
    if (_siteProofTaskLoading) return false;
    if (!_indentIsApproved(item)) return false;
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
        foregroundColor: AppTheme.navy,
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
                bg: const Color(0xFFF9FAFB),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: Color(0xFF9CA3AF),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
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
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: const TextStyle(
                      color: Color(0xFF166534),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (item.isBilled) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Billed',
                    style: TextStyle(
                      color: Color(0xFF166534),
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
                    style: const TextStyle(
                      color: AppTheme.navy,
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
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.navy,
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
    final steps = siteProofTask != null
        ? indentPoSiteProofActions(workflowActionsFromTask(siteProofTask!))
        : const <Map<String, dynamic>>[];
    final doneCount = siteProofTask != null
        ? indentPoSiteProofDoneCount(siteProofTask!)
        : 0;
    final started = doneCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.pin_drop_outlined,
                  color: Color(0xFF2563EB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showUpload
                          ? 'Upload site proof for approved PO'
                          : 'Site proof',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loadingTask
                          ? 'Checking site-proof task…'
                          : showUpload
                              ? (steps.isEmpty
                                  ? 'Complete the on-site steps in order.'
                                  : '$doneCount of ${steps.length} steps complete. '
                                      'Go to the project site, then finish each step.')
                              : 'Site proof has been submitted for this indent.',
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
          if (showUpload) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: loadingTask ? null : onUpload,
                icon: const Icon(Icons.pin_drop_outlined, size: 18),
                label: Text(started ? 'Continue site proof' : 'Start site proof'),
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
          if (showReviewOption) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Review site proof'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.navy,
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: AppTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.navy,
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
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFFB45309),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masked PO PDF pending',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.navy,
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
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
