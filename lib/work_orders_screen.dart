import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'client_portal/client_portal_document_ui.dart';
import 'models/work_order.dart';
import 'models/workflow_document.dart';
import 'services/session_manager.dart';
import 'services/work_order_service.dart';
import 'widgets/skeleton_loader.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/workflow_document_viewer.dart';

class WorkOrdersScreenLayout extends StatelessWidget {
  final String? salesSopId;
  final String? projectId;
  final String? initialProjectName;

  const WorkOrdersScreenLayout({
    super.key,
    this.salesSopId,
    this.projectId,
    this.initialProjectName,
  });

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Work orders',
      body: SafeArea(
        child: WorkOrdersScreen(
          salesSopId: salesSopId,
          projectId: projectId,
          initialProjectName: initialProjectName,
        ),
      ),
    );
  }
}

class WorkOrdersScreen extends StatefulWidget {
  final String? salesSopId;
  final String? projectId;
  final String? initialProjectName;

  const WorkOrdersScreen({
    super.key,
    this.salesSopId,
    this.projectId,
    this.initialProjectName,
  });

  @override
  State<WorkOrdersScreen> createState() => _WorkOrdersScreenState();
}

class _WorkOrdersScreenState extends State<WorkOrdersScreen> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<WorkOrder> _items = [];
  WorkOrderSummary _summary = const WorkOrderSummary();
  String _projectSubtitle = '';
  String _status = 'all';
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
    _projectSubtitle = widget.initialProjectName?.trim() ?? '';
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
    });
    try {
      final result = await WorkOrderService().fetchList(
        salesSopId: widget.salesSopId,
        projectId: widget.projectId,
        status: _status,
        search: _search,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _summary = result.summary;
        _hasMore = result.hasMore;
        _offset = result.items.length;
        if (result.projectSubtitle.isNotEmpty) {
          _projectSubtitle = result.projectSubtitle;
        }
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
      final result = await WorkOrderService().fetchList(
        salesSopId: widget.salesSopId,
        projectId: widget.projectId,
        status: _status,
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next == _search) return;
      _search = next;
      _loadInitial();
    });
    setState(() {});
  }

  void _selectStatus(String status) {
    if (_status == status) return;
    setState(() => _status = status);
    _loadInitial();
  }

  Future<void> _openDetail(WorkOrder item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkOrderDetailScreen(
          workOrderId: item.workOrderId,
          listItem: item,
        ),
      ),
    );
  }

  Future<void> _openPdf(WorkOrder item) async {
    final doc = item.workflowPdf(
      label: 'Work order PDF',
      document: item.pdfDocument,
    );
    if (doc == null) return;
    await openWorkflowDocument(context, doc, clientMode: false);
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
                if (_projectSubtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _projectSubtitle,
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                _StatusChips(
                  selected: _status,
                  summary: _summary,
                  onSelected: _selectStatus,
                ),
                const SizedBox(height: 12),
                ClientPortalSearchBar(
                  controller: _searchController,
                  hint: 'Search trade, contractor, WO number',
                  onChanged: _onSearchChanged,
                  onClear: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
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
                icon: Icons.engineering_outlined,
                title: 'No work orders',
                message: 'No work orders for this project',
                actionLabel: 'Refresh',
                onAction: _loadInitial,
              ),
            ),
          ],
        ),
      );
    }

    final sections = groupWorkOrdersForDisplay(_items);
    final showHeaders =
        sections.length > 1 || (sections.length == 1 && sections.first.trade.isNotEmpty);
    final entries = _flatten(sections, showHeaders);

    return RefreshIndicator(
      color: AppTheme.accentBlue,
      onRefresh: _loadInitial,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        itemCount: entries.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= entries.length) {
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
          final entry = entries[index];
          if (entry.header != null) {
            return Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? 4 : 14,
                bottom: 8,
              ),
              child: ClientPortalSectionHeading(label: entry.header!),
            );
          }
          final item = entry.item!;
          return _WorkOrderListCard(
            item: item,
            onTap: () => _openDetail(item),
            onPdfTap: item.canOpenPdf ? () => _openPdf(item) : null,
          );
        },
      ),
    );
  }

  List<_ListEntry> _flatten(
    List<WorkOrderListSection> sections,
    bool showHeaders,
  ) {
    final out = <_ListEntry>[];
    for (final section in sections) {
      if (showHeaders && section.trade.isNotEmpty) {
        out.add(_ListEntry.header(section.trade));
      }
      for (final item in section.items) {
        out.add(_ListEntry.item(item));
      }
    }
    return out;
  }
}

class _ListEntry {
  final String? header;
  final WorkOrder? item;

  const _ListEntry._({this.header, this.item});
  factory _ListEntry.header(String trade) => _ListEntry._(header: trade);
  factory _ListEntry.item(WorkOrder item) => _ListEntry._(item: item);
}

class _StatusChips extends StatelessWidget {
  final String selected;
  final WorkOrderSummary summary;
  final ValueChanged<String> onSelected;

  const _StatusChips({
    required this.selected,
    required this.summary,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      _ChipSpec('all', 'All', summary.total),
      _ChipSpec('approved', 'Approved', summary.approved),
      _ChipSpec('unsigned', 'Unsigned', summary.unsigned),
      _ChipSpec('unapproved', 'Awaiting approval', summary.unapproved),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _FilterChip(
              label: chips[i].count > 0
                  ? '${chips[i].label} (${chips[i].count})'
                  : chips[i].label,
              selected: selected == chips[i].status,
              onTap: () => onSelected(chips[i].status),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipSpec {
  final String status;
  final String label;
  final int count;
  const _ChipSpec(this.status, this.label, this.count);
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1B254B) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? const Color(0xFF1B254B) : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkOrderListCard extends StatelessWidget {
  final WorkOrder item;
  final VoidCallback onTap;
  final VoidCallback? onPdfTap;

  const _WorkOrderListCard({
    required this.item,
    required this.onTap,
    this.onPdfTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(item.statusKind);
    final woLine = item.displayWoNumber(prefixWoHash: true);

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.trade.isNotEmpty ? item.trade : 'Work order',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppTheme.navy,
                          height: 1.25,
                        ),
                      ),
                      if (item.contractor.name.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.contractor.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.getTextSecondary(context),
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (woLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          woLine,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.getTextSecondary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatIndianRupees(item.value),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.displayStatusLabel,
                        style: TextStyle(
                          color: colors.fg,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onPdfTap != null) ...[
                      const SizedBox(height: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: 'View PDF',
                        onPressed: onPdfTap,
                        icon: const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Color(0xFFDC2626),
                          size: 22,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WorkOrderDetailScreen extends StatefulWidget {
  final int workOrderId;
  final WorkOrder? listItem;

  const WorkOrderDetailScreen({
    super.key,
    required this.workOrderId,
    this.listItem,
  });

  @override
  State<WorkOrderDetailScreen> createState() => _WorkOrderDetailScreenState();
}

class _WorkOrderDetailScreenState extends State<WorkOrderDetailScreen> {
  WorkOrder? _item;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _item = widget.listItem;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await WorkOrderService().fetchDetail(widget.workOrderId);
      if (!mounted) return;
      setState(() {
        _item = detail;
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

  Future<void> _openDocument(WorkflowDocumentUpload? doc) async {
    if (doc == null) return;
    await openWorkflowDocument(context, doc, clientMode: false);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final title = item != null && item.trade.isNotEmpty
        ? item.trade
        : 'Work order';
    final subtitle = item?.contractor.name ?? '';

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppTheme.navy,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: AppTheme.getTextSecondary(context),
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _item == null) {
      return const SkeletonListLoader(
        showSummary: true,
        cardCount: 3,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
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
    final woPdf = item.canOpenPdf
        ? item.workflowPdf(
            label: 'Work order PDF',
            document: item.pdfDocument,
          )
        : null;
    final docPdf = item.canOpenDifferenceOfCost
        ? item.workflowPdf(
            label: 'Difference of cost',
            document: item.differenceOfCostDocument,
          )
        : null;
    final showDocuments = woPdf != null || docPdf != null;
    final notes = item.notes.where((n) => n.text.isNotEmpty).toList();

    return RefreshIndicator(
      color: ClientPortalDocTheme.accentBlue,
      onRefresh: _loadDetail,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _StatusBanner(item: item),
          const SizedBox(height: 16),
          const ClientPortalSectionHeading(label: 'Summary'),
          _SummaryTable(item: item),
          if (showDocuments) ...[
            const SizedBox(height: 16),
            const ClientPortalSectionHeading(label: 'Documents'),
            if (woPdf != null)
              _DocumentButton(
                label: 'View work order PDF',
                onTap: () => _openDocument(woPdf),
              ),
            if (woPdf != null && docPdf != null) const SizedBox(height: 10),
            if (docPdf != null)
              _DocumentButton(
                label: 'Difference of cost',
                icon: Icons.compare_arrows_outlined,
                onTap: () => _openDocument(docPdf),
              ),
          ],
          if (item.milestones.isNotEmpty) ...[
            const SizedBox(height: 16),
            const ClientPortalSectionHeading(label: 'Milestones'),
            _MilestonesCard(milestones: item.milestones),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const ClientPortalSectionHeading(label: 'Work order notes'),
            _NotesCard(notes: notes),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final WorkOrder item;

  const _StatusBanner({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(item.statusKind);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: ClientPortalDocTheme.cardDecoration(bg: colors.bg),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: colors.fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.displayStatusLabel,
              style: TextStyle(
                color: colors.fg,
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
              ),
            ),
          ),
          if (item.locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 12, color: Color(0xFF4B5563)),
                  SizedBox(width: 4),
                  Text(
                    'Locked',
                    style: TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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

class _SummaryTable extends StatelessWidget {
  final WorkOrder item;

  const _SummaryTable({required this.item});

  @override
  Widget build(BuildContext context) {
    final woNo = item.displayWorkOrderNo();
    final balance = item.totals.balance;
    final rows = <_InfoRow>[
      if (woNo.isNotEmpty)
        _InfoRow('Work order no.', woNo),
      if (item.contractor.name.isNotEmpty)
        _InfoRow('Contractor', item.contractor.name),
      if (item.contractor.code.isNotEmpty)
        _InfoRow('Contractor code', item.contractor.code),
      if (item.contractor.pan.isNotEmpty)
        _InfoRow('Contractor PAN', item.contractor.pan),
      if (item.trade.isNotEmpty)
        _InfoRow('Nature of work', item.trade),
      _InfoRow('WO value', formatIndianRupees(item.totals.woValue)),
      _InfoRow('Total billed', formatIndianRupees(item.totals.totalBilled)),
      _InfoRow('Total paid', formatIndianRupees(item.totals.totalPaid)),
      _InfoRow(
        'Balance',
        formatIndianRupees(balance),
        valueColor: balance < 0 ? const Color(0xFFDC2626) : null,
      ),
      if (item.createdAt.isNotEmpty) _InfoRow('Created date', item.createdAt),
      if (item.comments.isNotEmpty) _InfoRow('Comments', item.comments),
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
                SizedBox(
                  width: 120,
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
                      color: row.valueColor ?? AppTheme.navy,
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

class _InfoRow {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow(this.label, this.value, {this.valueColor});
}

class _DocumentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DocumentButton({
    required this.label,
    required this.onTap,
    this.icon = Icons.picture_as_pdf_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ClientPortalDocTheme.cardRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: ClientPortalDocTheme.cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFDC2626), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AppTheme.getTextSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MilestonesCard extends StatelessWidget {
  final List<WorkOrderMilestone> milestones;

  const _MilestonesCard({required this.milestones});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _ColHead('Stage'),
                ),
                Expanded(child: _ColHead('%', alignEnd: true)),
                Expanded(
                  flex: 2,
                  child: _ColHead('Billed', alignEnd: true),
                ),
                Expanded(
                  flex: 2,
                  child: _ColHead('Paid', alignEnd: true),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          for (var i = 0; i < milestones.length; i++) ...[
            _MilestoneRow(milestone: milestones[i]),
            if (i != milestones.length - 1)
              const Divider(height: 1, color: AppTheme.border),
          ],
        ],
      ),
    );
  }
}

class _ColHead extends StatelessWidget {
  final String label;
  final bool alignEnd;

  const _ColHead(this.label, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: AppTheme.mutedGrey,
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final WorkOrderMilestone milestone;

  const _MilestoneRow({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final muted = milestone.isClearingBalance;
    final color = muted ? const Color(0xFF9CA3AF) : AppTheme.navy;
    final secondary = muted
        ? const Color(0xFFD1D5DB)
        : AppTheme.getTextSecondary(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  milestone.displayStage,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: color,
                    height: 1.3,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  milestone.hasPercentage ? milestone.percentage : '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatIndianRupees(milestone.billed),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatIndianRupees(milestone.paid),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (milestone.approvedOn.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Approved on ${milestone.approvedOn}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ],
          if (milestone.isDebitNote && milestone.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              milestone.notes,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: secondary,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final List<WorkOrderNote> notes;

  const _NotesCard({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ClientPortalDocTheme.cardDecoration(),
      child: Column(
        children: notes.asMap().entries.map((entry) {
          final note = entry.value;
          final isLast = entry.key == notes.length - 1;
          final meta = [
            if (note.postedBy.isNotEmpty) note.postedBy,
            if (note.postedAt.isNotEmpty) note.postedAt,
          ].join(' on ');
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isLast ? Colors.transparent : AppTheme.border,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navy,
                    height: 1.4,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusColors {
  final Color bg;
  final Color fg;
  const _StatusColors(this.bg, this.fg);
}

_StatusColors _statusColors(WorkOrderStatusKind kind) {
  switch (kind) {
    case WorkOrderStatusKind.approved:
      return const _StatusColors(Color(0xFFDCFCE7), Color(0xFF166534));
    case WorkOrderStatusKind.unapproved:
      return const _StatusColors(Color(0xFFFEF3C7), Color(0xFFB45309));
    case WorkOrderStatusKind.unsigned:
      return const _StatusColors(Color(0xFFF3F4F6), Color(0xFF4B5563));
    case WorkOrderStatusKind.other:
      return const _StatusColors(Color(0xFFEEF2FF), Color(0xFF4338CA));
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
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
