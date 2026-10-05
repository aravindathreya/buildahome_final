import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/skeleton_loader.dart';
import 'widgets/tentative_handover_card.dart';

Color get _cardSurface => AppTheme.darkBackgroundSecondary;
Color get _ink => AppTheme.darkTextPrimary;
Color get _muted => AppTheme.darkTextSecondary;

bool _timelineTruthy(dynamic value) {
  if (value == true || value == 1) return true;
  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

dynamic _timelineField(Map<String, dynamic> task, String key) {
  if (task[key] != null) return task[key];
  for (final nestKey in const [
    'main_critical',
    'meta',
    'context',
    'context_json',
  ]) {
    final nest = task[nestKey];
    if (nest is Map && nest[key] != null) return nest[key];
  }
  return null;
}

String? _timelineDurationLabel(Map<String, dynamic> task) {
  String? clean(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  final direct = clean(_timelineField(task, 'assigned_duration_label'));
  if (direct != null) return direct;

  final amount = clean(_timelineField(task, 'main_critical_duration'));
  final unit = clean(_timelineField(task, 'main_critical_duration_unit'));
  if (amount != null && unit != null) return '$amount $unit';

  final days = clean(_timelineField(task, 'assigned_days'));
  if (days != null) {
    final parsed = double.tryParse(days);
    if (parsed == null) return '$days days';
    if (parsed == parsed.roundToDouble()) return '${parsed.toInt()} days';
    return '$parsed days';
  }
  return null;
}

int? _indexOfOngoingTimelineTask(List<Map<String, dynamic>> tasks) {
  bool looksInProgress(Map<String, dynamic> task) {
    final status =
        '${task['timeline_status'] ?? ''} ${task['status'] ?? ''}'.toLowerCase();
    return status.contains('progress') || status.contains('ongoing');
  }

  // Prefer explicit pending (not upcoming / not started).
  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    final ongoing = _timelineTruthy(task['is_pending']) &&
        !_timelineTruthy(task['is_completed']) &&
        !_timelineTruthy(task['is_cancelled']) &&
        !_timelineTruthy(task['is_upcoming']) &&
        !_timelineTruthy(task['is_not_started']);
    if (ongoing) return i;
  }
  // Status text fallback (e.g. "In progress").
  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    if (!_timelineTruthy(task['is_completed']) &&
        !_timelineTruthy(task['is_cancelled']) &&
        looksInProgress(task)) {
      return i;
    }
  }
  // First incomplete non-cancelled task.
  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    if (!_timelineTruthy(task['is_completed']) &&
        !_timelineTruthy(task['is_cancelled'])) {
      return i;
    }
  }
  return null;
}

/// Critical-path timeline (tab 3). Use [ProjectScheduleScreen] for full schedule.
class ProjectTimelineScreen extends StatefulWidget {
  final bool criticalOnly;
  final bool embedded;

  const ProjectTimelineScreen({
    super.key,
    this.embedded = false,
  }) : criticalOnly = true;

  const ProjectTimelineScreen.fullSchedule({
    super.key,
    this.embedded = false,
  }) : criticalOnly = false;

  /// Menu / dashboard entry — opens the swipeable situation shell.
  /// Prefer [ProjectSituationShell.timeline] / [.schedule] from call sites.
  static Widget open({bool schedule = false}) {
    // Deferred import avoided — call sites use ProjectSituationShell directly.
    return schedule
        ? const ProjectTimelineScreen.fullSchedule(embedded: true)
        : const ProjectTimelineScreen(embedded: true);
  }

  @override
  State<ProjectTimelineScreen> createState() => ProjectTimelineScreenState();
}

class ProjectTimelineScreenState extends State<ProjectTimelineScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _ongoingKey = GlobalKey();

  List<Map<String, dynamic>> _tasks = [];
  int _pendingCount = 0;
  int _completedCount = 0;
  int _upcomingCount = 0;
  int? _remainingDays;
  int? _ongoingIndex;
  bool _isLoading = true;
  bool _ongoingInView = true;
  bool _didAutoScroll = false;
  String? _errorMessage;

  bool get _criticalOnly => widget.criticalOnly;

  @override
  bool get wantKeepAlive => true;

  bool get isRefreshing => _isLoading;

  Future<void> refresh() => _loadTimeline();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _hydrateFromProvider();
    _loadTimeline();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _hydrateFromProvider() {
    final provider = DataProvider();
    _remainingDays = provider.clientRemainingDays;
    final loaded = _criticalOnly
        ? provider.clientCriticalTimelineLoaded
        : provider.clientTimelineLoaded;
    if (!loaded) return;
    setState(() {
      _applyProviderData(provider);
      _isLoading = false;
    });
  }

  void _applyProviderData(DataProvider provider) {
    final tasks = _criticalOnly
        ? List<Map<String, dynamic>>.from(provider.clientCriticalTimelineTasks)
        : List<Map<String, dynamic>>.from(provider.clientTimelineTasks);
    _tasks = tasks;
    _pendingCount = tasks.where((t) => t['is_pending'] == true).length;
    _completedCount = tasks.where((t) => t['is_completed'] == true).length;
    _upcomingCount = tasks.where((t) => t['is_upcoming'] == true).length;
    _remainingDays = provider.clientRemainingDays;
    _ongoingIndex = _indexOfOngoingTimelineTask(tasks);
  }

  Future<void> _loadTimeline({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _didAutoScroll = false;
      });
    }

    try {
      await Future.wait([
        if (_criticalOnly)
          DataProvider().loadCriticalTimeline(force: true)
        else
          DataProvider().loadProjectTimeline(force: true),
        DataProvider().refreshProjectPercentage(),
      ]);
      if (!mounted) return;
      setState(() {
        _applyProviderData(DataProvider());
        _isLoading = false;
        _errorMessage = null;
        // Until the ongoing row is measured, assume it may be off-screen so the
        // jump control can appear if auto-scroll needs a second try.
        if (_ongoingIndex != null && _ongoingIndex! > 1) {
          _ongoingInView = false;
        }
      });
      _scheduleAutoScroll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyProviderData(DataProvider());
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _scheduleAutoScroll() {
    if (_didAutoScroll || _ongoingIndex == null || _tasks.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _didAutoScroll) return;
      // Wait for the ListView to attach its ScrollPosition.
      for (var i = 0; i < 20 && mounted && !_scrollController.hasClients; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 32));
      }
      if (!mounted || !_scrollController.hasClients) return;
      await _jumpToOngoing(animated: true);
      if (!mounted) return;
      _didAutoScroll = true;
      _updateOngoingVisibility();
    });
  }

  void _onScroll() => _updateOngoingVisibility();

  void _updateOngoingVisibility() {
    if (_ongoingIndex == null) {
      if (!_ongoingInView) setState(() => _ongoingInView = true);
      return;
    }

    // Lazy ListView: off-screen rows are not built, so the GlobalKey has no
    // context until we scroll near them. Treat that as "not in view".
    final ctx = _ongoingKey.currentContext;
    if (ctx == null) {
      if (_ongoingInView) setState(() => _ongoingInView = false);
      return;
    }

    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      if (_ongoingInView) setState(() => _ongoingInView = false);
      return;
    }

    final listBox = context.findRenderObject();
    if (listBox is! RenderBox || !listBox.hasSize) return;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final listTopLeft = listBox.localToGlobal(Offset.zero);
    final relativeTop = topLeft.dy - listTopLeft.dy;
    final relativeBottom = relativeTop + renderObject.size.height;
    final viewHeight = listBox.size.height;

    // Consider "in view" when a meaningful portion of the card is visible.
    final inView = relativeBottom > 48 && relativeTop < viewHeight - 48;

    if (inView != _ongoingInView) {
      setState(() => _ongoingInView = inView);
    }
  }

  /// Lazy lists don't build off-screen children, so [Scrollable.ensureVisible]
  /// alone fails when the ongoing row has never been painted. Jump by offset
  /// first, then refine with ensureVisible once the row exists.
  Future<void> _jumpToOngoing({bool animated = true}) async {
    final index = _ongoingIndex;
    if (index == null || _tasks.isEmpty) return;

    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToOngoing(animated: animated);
      });
      return;
    }

    final position = _scrollController.position;
    // Card + separator estimate; refined below once the row is built.
    const estimatedItemExtent = 156.0;
    const separator = 12.0;
    final rawTarget = index * (estimatedItemExtent + separator);
    final target = rawTarget.clamp(0.0, position.maxScrollExtent);

    if (animated) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }

    // Give the lazy list a frame to build the target row.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;

    final ctx = _ongoingKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: animated
            ? const Duration(milliseconds: 240)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        alignment: 0.22,
      );
    } else if (_scrollController.hasClients) {
      // Estimation was short/long — nudge further and retry once.
      final nudged = (target + 220)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(nudged);
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (!mounted) return;
      final retryCtx = _ongoingKey.currentContext;
      if (retryCtx != null) {
        await Scrollable.ensureVisible(
          retryCtx,
          duration: Duration.zero,
          alignment: 0.22,
        );
      }
    }

    if (!mounted) return;
    setState(() => _ongoingInView = true);
    _updateOngoingVisibility();
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
    super.build(context);

    final body = _buildBody();
    final showJump = !_ongoingInView && _ongoingIndex != null;

    if (!widget.embedded) {
      return Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        appBar: AppBar(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          foregroundColor: AppTheme.darkTextPrimary,
          elevation: 0,
          title: Text(
            _criticalOnly ? 'Project Timeline' : 'Schedule',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              body,
              if (showJump) _jumpButton(),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        body,
        if (showJump) _jumpButton(),
      ],
    );
  }

  Widget _jumpButton() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: FloatingActionButton.extended(
        onPressed: () => _jumpToOngoing(),
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.my_location_rounded, size: 18),
        label: const Text(
          'Jump to current',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _tasks.isEmpty && _errorMessage == null) {
      return const SkeletonListLoader(showSummary: false, cardCount: 5);
    }

    if (_errorMessage != null && _tasks.isEmpty) {
      return _buildErrorState();
    }

    if (_tasks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_remainingDays != null)
            TentativeHandoverCard(
              remainingDays: _remainingDays!,
              margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              compact: true,
            ),
          Expanded(child: _buildEmptyTimelineState()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBanner(),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.getPrimaryColor(context),
            onRefresh: () => _loadTimeline(showLoader: false),
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 88),
              itemCount: _tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = _tasks[index];
                final isOngoing = index == _ongoingIndex;
                return KeyedSubtree(
                  key: isOngoing ? _ongoingKey : ValueKey('task_$index'),
                  child: _TimelineTaskCard(
                    task: task,
                    highlight: isOngoing,
                    onTap: () => _openTaskDetail(task),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBanner() {
    final remaining = _remainingDays;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _criticalOnly
                      ? Icons.bolt_rounded
                      : Icons.calendar_month_rounded,
                  color: AppTheme.getPrimaryColor(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _criticalOnly
                          ? 'Critical path'
                          : 'Full project schedule',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_pendingCount pending · $_completedCount completed · $_upcomingCount upcoming',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (remaining != null) ...[
            const SizedBox(height: 14),
            TentativeHandoverCard(
              remainingDays: remaining,
              compact: true,
            ),
          ],
        ],
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
            Text(
              _criticalOnly
                  ? 'No critical tasks from server'
                  : 'No schedule tasks yet',
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _criticalOnly
                  ? 'The critical timeline API returned 0 tasks. Full schedule may still have work — Main Critical flags are missing on the server for this project.'
                  : 'Project schedule tasks will appear here once they are created.',
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

  Widget _buildErrorState() {
    final message = _errorMessage ?? 'Please try again.';
    final isAuthError = message.toLowerCase().contains('unauthorized') ||
        message.toLowerCase().contains('log in again');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAuthError
                  ? Icons.lock_outline_rounded
                  : Icons.error_outline_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isAuthError
                  ? 'Could not authorize this request'
                  : (_criticalOnly
                      ? 'Could not load critical timeline'
                      : 'Could not load schedule'),
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _loadTimeline(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.getPrimaryColor(context),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
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
  final bool highlight;

  const _TimelineTaskCard({
    required this.task,
    required this.onTap,
    this.highlight = false,
  });

  String? _value(String key) {
    final text = task[key]?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final isClient =
        (DataProvider().currentRole ?? '').trim().toLowerCase() == 'client';
    final orderIdx = int.tryParse(task['order_idx']?.toString() ?? '');
    final taskName = _value('task_name') ?? 'Task';
    final assigneeName = _value('assigned_to_name') ?? '—';
    final assigneeRole =
        _value('assigned_role') ?? _value('assigned_to_role') ?? '—';
    final timelineStatus =
        _value('timeline_status') ?? _value('status') ?? 'Pending';
    final completedAt = _value('completed_at_display');
    final isWorkflow = _timelineTruthy(task['is_workflow_task']);
    final triggerLabel = _value('workflow_trigger_label');
    final isMainCritical =
        _timelineTruthy(_timelineField(task, 'is_main_critical'));
    final durationLabel = _timelineDurationLabel(task);
    final showDuration = durationLabel != null &&
        (isMainCritical ||
            _timelineField(task, 'assigned_days') != null ||
            _timelineField(task, 'main_critical_duration') != null ||
            _timelineField(task, 'assigned_duration_label') != null);
    final isCompleted = task['is_completed'] == true;
    final isCancelled = task['is_cancelled'] == true;
    final isRedoPending = task['is_redo_pending'] == true;
    final isBlocked = task['is_flow_blocked'] == true;
    final isUpcoming =
        task['is_upcoming'] == true || task['is_not_started'] == true;
    final showWorkflowMeta = !isClient && isWorkflow;
    final showAssignee = !isClient;
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
              color: highlight
                  ? AppTheme.accentBlue
                  : isCompleted
                      ? const Color(0xFF14532D)
                      : AppTheme.border,
              width: highlight ? 1.6 : 1,
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
              if (highlight) ...[
                Row(
                  children: [
                    Icon(Icons.play_circle_filled_rounded,
                        size: 14, color: AppTheme.accentBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Current ongoing',
                      style: TextStyle(
                        color: AppTheme.accentBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
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
                        if (showWorkflowMeta)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2A45),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Workflow',
                              style: TextStyle(
                                color: AppTheme.accentBlue,
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
              if (showDuration) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B2A14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF92400E)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: Color(0xFFFBBF24),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Complete in $durationLabel',
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (showAssignee) ...[
                const SizedBox(height: 12),
                Text(
                  '$assigneeName · $assigneeRole',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (showWorkflowMeta && triggerLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  triggerLabel,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (isBlocked) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
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
  if (normalized.contains('progress')) return AppTheme.accentBlue;
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
    final isClient =
        (DataProvider().currentRole ?? '').trim().toLowerCase() == 'client';
    final taskName = _value('task_name') ?? 'Task';
    final timelineStatus = _value('timeline_status') ?? _value('status') ?? '—';
    final assigneeName = _value('assigned_to_name') ?? '—';
    final assigneeRole =
        _value('assigned_role') ?? _value('assigned_to_role') ?? '—';
    final completedAt = _value('completed_at_display');
    final isWorkflow = _timelineTruthy(task['is_workflow_task']);
    final durationLabel = _timelineDurationLabel(task);
    final showDuration = durationLabel != null &&
        (_timelineTruthy(_timelineField(task, 'is_main_critical')) ||
            _timelineField(task, 'assigned_days') != null ||
            _timelineField(task, 'main_critical_duration') != null ||
            _timelineField(task, 'assigned_duration_label') != null);

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
                      style: TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _detailLine('Status', timelineStatus),
                    if (!isClient) ...[
                      _detailLine('Assigned to', assigneeName),
                      _detailLine('Role', assigneeRole),
                    ],
                    if (showDuration)
                      _detailLine('Duration', 'Complete in $durationLabel'),
                    if (completedAt != null && completedAt != '—')
                      _detailLine('Completed', completedAt),
                    if (!isClient && isWorkflow) ...[
                      if (_value('workflow_name') != null)
                        _detailLine('Workflow', _value('workflow_name')!),
                      if (_value('workflow_trigger_label') != null)
                        _detailLine(
                            'Trigger', _value('workflow_trigger_label')!),
                      if (_value('workflow_status') != null)
                        _detailLine(
                            'Workflow status', _value('workflow_status')!),
                    ],
                    if (!isClient &&
                        !isWorkflow &&
                        _value('erp_task_id') != null)
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
              style: TextStyle(
                color: _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
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
