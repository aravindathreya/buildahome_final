import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/skeleton_loader.dart';

const Color _pageBackground = Color(0xFFF8F9FC);
const Color _cardSurface = Colors.white;
const Color _ink = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);

enum _TimelineFilter { all, completed, pending, upcoming }

class ProjectTimelineScreen extends StatefulWidget {
  const ProjectTimelineScreen({super.key});

  @override
  State<ProjectTimelineScreen> createState() => _ProjectTimelineScreenState();
}

class _ProjectTimelineScreenState extends State<ProjectTimelineScreen> {
  List<Map<String, dynamic>> _tasks = [];
  int _timelineTaskCount = 0;
  int _pendingCount = 0;
  int _completedCount = 0;
  int _upcomingCount = 0;
  _TimelineFilter _filter = _TimelineFilter.all;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _hydrateFromProvider();
    _loadTimeline();
  }

  void _hydrateFromProvider() {
    final provider = DataProvider();
    if (!provider.clientTimelineLoaded) return;
    setState(() {
      _applyProviderData(provider);
      _isLoading = false;
    });
  }

  void _applyProviderData(DataProvider provider) {
    _tasks = List<Map<String, dynamic>>.from(provider.clientTimelineTasks);
    _timelineTaskCount = provider.clientTimelineTaskCount;
    _pendingCount = provider.clientTimelinePendingCount;
    _completedCount = provider.clientTimelineCompletedCount;
    _upcomingCount = provider.clientTimelineUpcomingCount;
  }

  Future<void> _loadTimeline({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await DataProvider().loadProjectTimeline(force: true);
      if (!mounted) return;
      setState(() {
        _applyProviderData(DataProvider());
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _filteredTasks {
    switch (_filter) {
      case _TimelineFilter.completed:
        return _tasks.where((task) => task['is_completed'] == true).toList();
      case _TimelineFilter.pending:
        return _tasks.where((task) => task['is_pending'] == true).toList();
      case _TimelineFilter.upcoming:
        return _tasks.where((task) => task['is_upcoming'] == true).toList();
      case _TimelineFilter.all:
        return _tasks;
    }
  }

  int _countForFilter(_TimelineFilter filter) {
    switch (filter) {
      case _TimelineFilter.completed:
        return _completedCount;
      case _TimelineFilter.pending:
        return _pendingCount;
      case _TimelineFilter.upcoming:
        return _upcomingCount;
      case _TimelineFilter.all:
        return _timelineTaskCount;
    }
  }

  void _openTaskDetail(Map<String, dynamic> task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TimelineTaskDetailSheet(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.navy),
        actionsIconTheme: const IconThemeData(color: AppTheme.navy),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.navy, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Project Timeline',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadTimeline(),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.navy),
                  )
                : const Icon(Icons.refresh_rounded, color: AppTheme.navy),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _tasks.isEmpty && _errorMessage == null) {
      return const SkeletonListLoader(showSummary: false, cardCount: 5);
    }

    if (_errorMessage != null && _tasks.isEmpty) {
      return _buildErrorState();
    }

    if (_timelineTaskCount == 0 && _tasks.isEmpty) {
      return _buildEmptyTimelineState();
    }

    final filtered = _filteredTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBanner(),
        _buildFilterChips(),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.getPrimaryColor(context),
            onRefresh: () => _loadTimeline(showLoader: false),
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.18),
                      _buildFilterEmptyState(),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _TimelineTaskCard(
                      task: filtered[index],
                      onTap: () => _openTaskDetail(filtered[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.timeline_rounded,
                color: AppTheme.getPrimaryColor(context), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$_pendingCount pending · $_completedCount completed · $_upcomingCount upcoming',
              style: const TextStyle(
                color: _ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = <MapEntry<_TimelineFilter, String>>[
      MapEntry(_TimelineFilter.all, 'All'),
      MapEntry(_TimelineFilter.completed, 'Completed'),
      MapEntry(_TimelineFilter.pending, 'Pending'),
      MapEntry(_TimelineFilter.upcoming, 'Upcoming'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index].key;
          final label = filters[index].value;
          final selected = _filter == filter;
          final count = _countForFilter(filter);
          return ChoiceChip(
            label: Text('$label ($count)'),
            selected: selected,
            onSelected: (_) => setState(() => _filter = filter),
            labelStyle: TextStyle(
              color: selected ? Colors.white : _ink,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            selectedColor: AppTheme.getPrimaryColor(context),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected
                  ? AppTheme.getPrimaryColor(context)
                  : const Color(0xFFE5E7EB),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyTimelineState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_outlined,
                size: 56, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 20),
            const Text(
              'No timeline tasks yet',
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Project timeline tasks will appear here once they are created.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : () => _loadTimeline(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterEmptyState() {
    String label;
    switch (_filter) {
      case _TimelineFilter.completed:
        label = 'No completed tasks in this filter.';
        break;
      case _TimelineFilter.pending:
        label = 'No pending tasks in this filter.';
        break;
      case _TimelineFilter.upcoming:
        label = 'No upcoming tasks in this filter.';
        break;
      case _TimelineFilter.all:
        label = 'No tasks to show.';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.filter_list_off_rounded, size: 40, color: _muted),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final message = _errorMessage ?? 'Please try again.';
    final isAuthError = message.toLowerCase().contains('unauthorized') ||
        message.toLowerCase().contains('log in');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAuthError ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isAuthError
                  ? 'Session expired'
                  : 'Could not load project timeline',
              style: const TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isAuthError ? null : () => _loadTimeline(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.getPrimaryColor(context),
                foregroundColor: Colors.white,
              ),
              child: Text(isAuthError ? 'Please log in again' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;

  const _TimelineTaskCard({
    required this.task,
    required this.onTap,
  });

  String? _value(String key) {
    final text = task[key]?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final orderIdx = int.tryParse(task['order_idx']?.toString() ?? '');
    final taskName = _value('task_name') ?? 'Task';
    final assigneeName = _value('assigned_to_name') ?? '—';
    final assigneeRole =
        _value('assigned_role') ?? _value('assigned_to_role') ?? '—';
    final timelineStatus = _value('timeline_status') ??
        _value('status') ??
        'Pending';
    final completedAt = _value('completed_at_display');
    final isWorkflow = task['is_workflow_task'] == true;
    final workflowName = _value('workflow_name');
    final triggerLabel = _value('workflow_trigger_label');
    final isCompleted = task['is_completed'] == true;
    final isCancelled = task['is_cancelled'] == true;
    final isRedoPending = task['is_redo_pending'] == true;
    final isBlocked = task['is_flow_blocked'] == true;
    final isUpcoming = task['is_upcoming'] == true || task['is_not_started'] == true;
    final statusColor = _timelineStatusColor(
      timelineStatus,
      isCompleted: isCompleted,
      isCancelled: isCancelled,
      isRedoPending: isRedoPending,
      isUpcoming: isUpcoming,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCompleted
                  ? const Color(0xFFD1FAE5)
                  : const Color(0xFFF3F4F6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (orderIdx != null)
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(Icons.check_rounded,
                                color: statusColor, size: 18)
                            : Text(
                                '$orderIdx',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isWorkflow)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Workflow',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        Text(
                          taskName,
                          style: TextStyle(
                            color: isCancelled || isUpcoming ? _muted : _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: statusColor.withOpacity(0.25)),
                        ),
                        child: Text(
                          timelineStatus,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (isCompleted &&
                          completedAt != null &&
                          completedAt != '—' &&
                          completedAt.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          completedAt,
                          style: const TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$assigneeName · $assigneeRole',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isWorkflow && workflowName != null) ...[
                const SizedBox(height: 6),
                Text(
                  workflowName,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (triggerLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  triggerLabel,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (isBlocked) ...[
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Icon(Icons.lock_outline_rounded,
                        size: 15, color: Color(0xFFE11D48)),
                    SizedBox(width: 6),
                    Text(
                      'Blocked until manually released',
                      style: TextStyle(
                        color: Color(0xFFBE123C),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _timelineStatusColor(
  String status, {
  required bool isCompleted,
  required bool isCancelled,
  required bool isRedoPending,
  required bool isUpcoming,
}) {
  if (isCancelled) return const Color(0xFFDC2626);
  if (isCompleted) return const Color(0xFF059669);
  if (isRedoPending) return const Color(0xFFCA8A04);
  final normalized = status.toLowerCase();
  if (normalized.contains('progress')) return const Color(0xFF2563EB);
  if (normalized.contains('upcoming') ||
      normalized.contains('not started') ||
      isUpcoming) {
    return const Color(0xFF9CA3AF);
  }
  if (normalized.contains('cancel')) return const Color(0xFFDC2626);
  if (normalized.contains('redo')) return const Color(0xFFCA8A04);
  return const Color(0xFFD97706);
}

class _TimelineTaskDetailSheet extends StatelessWidget {
  final Map<String, dynamic> task;

  const _TimelineTaskDetailSheet({
    required this.task,
  });

  String? _value(String key) {
    final text = task[key]?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final taskName = _value('task_name') ?? 'Task';
    final timelineStatus = _value('timeline_status') ?? _value('status') ?? '—';
    final assigneeName = _value('assigned_to_name') ?? '—';
    final assigneeRole =
        _value('assigned_role') ?? _value('assigned_to_role') ?? '—';
    final completedAt = _value('completed_at_display');
    final isWorkflow = task['is_workflow_task'] == true;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundPrimary(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    Text(
                      taskName,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _detailLine('Status', timelineStatus),
                    _detailLine('Assigned to', assigneeName),
                    _detailLine('Role', assigneeRole),
                    if (completedAt != null && completedAt != '—')
                      _detailLine('Completed', completedAt),
                    if (isWorkflow) ...[
                      if (_value('workflow_name') != null)
                        _detailLine('Workflow', _value('workflow_name')!),
                      if (_value('workflow_trigger_label') != null)
                        _detailLine('Trigger', _value('workflow_trigger_label')!),
                      if (_value('workflow_status') != null)
                        _detailLine('Workflow status', _value('workflow_status')!),
                    ],
                    if (!isWorkflow && _value('erp_task_id') != null)
                      _detailLine('ERP task id', _value('erp_task_id')!),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
