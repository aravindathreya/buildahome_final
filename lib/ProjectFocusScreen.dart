import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'MyTasksScreen.dart';
import 'ProjectSituationShell.dart';
import 'app_theme.dart';
import 'chat_v1/chat_v1_controller.dart';
import 'models/project_focus.dart';
import 'services/data_provider.dart';
import 'services/project_focus_service.dart';
import 'services/session_manager.dart';
import 'widgets/project_situation_switcher.dart';
import 'widgets/skeleton_loader.dart';

/// Current-situation dashboard for a project.
///
/// Source of truth: `GET /api/projects/{sales_sop_id}/focus`.
/// Does not compute workflow dependencies or blockers locally.
class ProjectFocusScreen extends StatefulWidget {
  final String? salesSopId;
  final bool embedded;

  const ProjectFocusScreen({
    super.key,
    this.salesSopId,
    this.embedded = false,
  });

  /// Sync entry from Quick Actions / menus.
  static Widget openQuick({
    String? erpProjectId,
    Map<String, dynamic>? project,
    Iterable<dynamic>? tasksHint,
  }) {
    return ProjectSituationShell.focus(
      salesSopId: _resolveSalesSopIdSync(
        erpProjectId: erpProjectId,
        project: project,
        tasksHint: tasksHint,
      ),
    );
  }

  static String? _resolveSalesSopIdSync({
    String? erpProjectId,
    Map<String, dynamic>? project,
    Iterable<dynamic>? tasksHint,
  }) {
    final dp = DataProvider();
    String? sopId =
        ChatV1Controller.instance.salesSopId ?? dp.clientSalesSopId;

    if ((sopId == null || sopId.isEmpty) && project != null) {
      for (final key in const [
        'sales_sop_id',
        'salesSopId',
        'sop_id',
        'sopId',
      ]) {
        final v = project[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          return v;
        }
      }
    }

    if ((sopId == null || sopId.isEmpty) && tasksHint != null) {
      for (final task in tasksHint) {
        if (task is! Map) continue;
        final v = (task['sales_sop_id'] ?? task['salesSopId'])
            ?.toString()
            .trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          return v;
        }
      }
    }

    if ((sopId == null || sopId.isEmpty) &&
        erpProjectId != null &&
        erpProjectId.isNotEmpty) {
      for (final p in dp.projects) {
        if (p is! Map) continue;
        if (p['id']?.toString() != erpProjectId) continue;
        final v = (p['sales_sop_id'] ?? p['salesSopId'])?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          return v;
        }
        break;
      }
    }

    return sopId;
  }

  @override
  State<ProjectFocusScreen> createState() => ProjectFocusScreenState();
}

class ProjectFocusScreenState extends State<ProjectFocusScreen>
    with AutomaticKeepAliveClientMixin {
  static Color get _ink => AppTheme.darkTextPrimary;
  static Color get _muted => AppTheme.darkTextSecondary;
  static Color get _pageBg => AppTheme.darkBackgroundPrimary;

  bool _loading = true;
  String? _error;
  String? _salesSopId;
  ProjectFocus? _focus;
  Map<String, dynamic>? _statusSummary;
  List<Map<String, dynamic>> _criticalTasks = [];
  bool _aiLoading = false;
  String? _aiError;

  @override
  bool get wantKeepAlive => true;

  bool get isRefreshing => _loading || _aiLoading;

  Future<void> refresh() => _onRefresh();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sopId = await _resolveSalesSopId();
      if (!mounted) return;
      if (sopId == null || sopId.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'Select a project first so Project Focus can load the current situation.';
        });
        return;
      }
      _salesSopId = sopId;
      await _fetch(sopId);
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

  Future<String?> _resolveSalesSopId() async {
    final hint = widget.salesSopId?.trim();
    if (hint != null && hint.isNotEmpty && hint.toLowerCase() != 'null') {
      return hint;
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('sales_sop_id')?.trim();
    if (cached != null &&
        cached.isNotEmpty &&
        cached.toLowerCase() != 'null') {
      return cached;
    }

    final projectId = prefs.getString('project_id');
    final token = prefs.getString('api_token');
    if (token == null || token.isEmpty) return null;
    return DataProvider().resolveSalesSopId(
      projectId: projectId,
      apiToken: token,
      useCache: true,
    );
  }

  Future<void> _fetch(String salesSopId) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final focus = await ProjectFocusService().fetchFocus(salesSopId);
      if (!mounted) return;
      setState(() {
        _focus = focus;
        _loading = false;
        _error = null;
        // Seed AI card from cache while fresh fetch runs.
        if (DataProvider().clientStatusSummaryLoaded) {
          _statusSummary = DataProvider().clientStatusSummary;
        }
        if (DataProvider().clientCriticalTimelineLoaded) {
          _criticalTasks = List<Map<String, dynamic>>.from(
            DataProvider().clientCriticalTimelineTasks,
          );
        }
      });
      // Load AI critical review after focus paints.
      _loadAiReview();
    } on SessionInvalidatedException {
      rethrow;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadAiReview() async {
    if (!mounted) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      await Future.wait([
        DataProvider().loadStatusSummary(force: true, criticalOnly: true),
        DataProvider().loadCriticalTimeline(force: true),
      ]);
      if (!mounted) return;
      setState(() {
        _statusSummary = DataProvider().clientStatusSummary;
        _criticalTasks = List<Map<String, dynamic>>.from(
          DataProvider().clientCriticalTimelineTasks,
        );
        _aiLoading = false;
        _aiError = null;
      });
    } on SessionInvalidatedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusSummary = DataProvider().clientStatusSummary;
        _criticalTasks = List<Map<String, dynamic>>.from(
          DataProvider().clientCriticalTimelineTasks,
        );
        _aiLoading = false;
        _aiError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _onRefresh() async {
    final sopId = _salesSopId ?? await _resolveSalesSopId();
    if (sopId == null || sopId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error =
            'Select a project first so Project Focus can load the current situation.';
      });
      return;
    }
    _salesSopId = sopId;
    try {
      await _fetch(sopId);
    } on SessionInvalidatedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openWorkflowTask({
    required int runId,
    required String name,
    String? status,
  }) async {
    final task = _taskPayloadForRun(runId: runId, name: name, status: status);
    final focusId = task['id']?.toString() ?? (-runId).toString();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyTasksScreen(
          tasks: [task],
          focusTaskId: focusId,
        ),
      ),
    );
    if (mounted) _onRefresh();
  }

  Map<String, dynamic> _taskPayloadForRun({
    required int runId,
    required String name,
    String? status,
  }) {
    final runIdStr = runId.toString();
    Map<String, dynamic>? cached;
    for (final list in [
      DataProvider().clientPendingTasks,
      DataProvider().clientTimelineTasks,
    ]) {
      for (final row in list) {
        final id = row['workflow_item_run_id']?.toString();
        final taskId = row['id']?.toString();
        if (id == runIdStr ||
            taskId == '-$runId' ||
            taskId == runIdStr) {
          cached = Map<String, dynamic>.from(row);
          break;
        }
      }
      if (cached != null) break;
    }

    final payload = cached ?? <String, dynamic>{};
    payload['id'] = payload['id'] ?? -runId;
    payload['workflow_item_run_id'] = runId;
    payload['is_workflow_task'] = true;
    // MyTasksScreen titles come from `note`.
    payload['note'] = name;
    payload['s_note'] = name;
    payload['task_name'] = name;
    payload['name'] = name;
    payload['title'] = name;
    if (status != null && status.isNotEmpty) {
      payload['status'] = payload['status'] ?? status;
      payload['workflow_status'] = payload['workflow_status'] ?? status;
    }
    return payload;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = _buildBody();
    if (widget.embedded) return body;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: AppTheme.darkBackgroundSecondary,
          foregroundColor: AppTheme.darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppTheme.darkTextPrimary),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            'Project Focus',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _onRefresh,
              icon: _loading && _focus != null
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkTextPrimary,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, color: AppTheme.darkTextPrimary),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _focus == null && _error == null) {
      return const SkeletonListLoader(
        showSummary: false,
        cardCount: 5,
        padding: EdgeInsets.fromLTRB(18, 12, 18, 28),
      );
    }

    if (_error != null && _focus == null) {
      return _buildErrorState();
    }

    final focus = _focus;
    if (focus == null) return _buildErrorState();

    final activity = focus.resolvedActivityState;
    final showBlockerDetails =
        activity == ProjectActivityState.blocked && focus.hasBlocker;
    final showAttention = focus.hasWorkflowAttention;

    return RefreshIndicator(
      color: AppTheme.accentBlue,
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!, onRetry: _bootstrap),
            const SizedBox(height: 12),
          ],
          // 1. Where the project is
          _buildWhereSection(focus),
          const SizedBox(height: 18),
          // 2. Combined project status + AI review
          _buildCombinedStatusAiCard(focus),
          if (showBlockerDetails) ...[
            const SizedBox(height: 14),
            _buildBlockerDetails(focus),
          ],
          // 3. Workflow attention — only when present
          if (showAttention) ...[
            const SizedBox(height: 22),
            _buildAttentionSection(focus),
          ],
        ],
      ),
    );
  }

  Widget _buildWhereSection(ProjectFocus focus) {
    final phases = _displayPhases(focus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Where the project is'),
        _PhaseHeroCard(phase: focus.currentPhase),
        if (phases.length > 1) ...[
          const SizedBox(height: 12),
          _PhaseRoadmap(phases: phases),
        ],
      ],
    );
  }

  _FocusStatusHeader _statusHeader(ProjectFocus focus) {
    final state = focus.resolvedActivityState;
    switch (state) {
      case ProjectActivityState.blocked:
        final blocker = focus.projectBlocker;
        final name = blocker?.task?.name ??
            focus.projectActivity?.label ??
            'Project is blocked';
        final waiting = blocker?.waitingCount ?? 0;
        return _FocusStatusHeader(
          title: 'PROJECT IS BLOCKED',
          color: const Color(0xFFF87171),
          icon: Icons.lock_rounded,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (waiting > 0) ...[
                const SizedBox(height: 4),
                Text(
                  waiting == 1
                      ? 'Waiting for 1 task'
                      : 'Waiting for $waiting tasks',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      case ProjectActivityState.waiting:
        return _FocusStatusHeader(
          title: 'PROJECT IS WAITING',
          color: const Color(0xFFFBBF24),
          icon: Icons.hourglass_top_rounded,
          body: Text(
            focus.projectActivity?.message ??
                focus.projectActivity?.label ??
                'Work is waiting on a dependency.',
            style: TextStyle(
              color: _ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        );
      case ProjectActivityState.workflowAttention:
        final item = focus.workflowAttention.isNotEmpty
            ? focus.workflowAttention.first
            : null;
        return _FocusStatusHeader(
          title: 'PROJECT NEEDS ATTENTION',
          color: const Color(0xFFC4B5FD),
          icon: Icons.warning_amber_rounded,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item?.name ??
                    focus.projectActivity?.label ??
                    'Workflow attention needed',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item?.message ??
                    focus.projectActivity?.message ??
                    'Expected task was not triggered.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      case ProjectActivityState.moving:
      case ProjectActivityState.unknown:
        return _FocusStatusHeader(
          title: 'PROJECT IS MOVING',
          color: const Color(0xFF34D399),
          icon: Icons.check_circle_rounded,
          body: Text(
            focus.projectActivity?.message ?? 'No current blocker',
            style: TextStyle(
              color: _ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
  }

  Widget _buildCombinedStatusAiCard(ProjectFocus focus) {
    final status = _statusHeader(focus);
    final summaryText = _extractStatusSummaryText(_statusSummary);
    final pending = _criticalTasks
        .where((t) =>
            timelineTaskTruthy(t['is_pending']) &&
            !timelineTaskTruthy(t['is_completed']) &&
            !timelineTaskTruthy(t['is_cancelled']) &&
            !timelineTaskTruthy(t['is_upcoming']) &&
            !timelineTaskTruthy(t['is_not_started']))
        .length;
    final completed = _criticalTasks
        .where((t) => timelineTaskTruthy(t['is_completed']))
        .length;
    final upcoming = _criticalTasks
        .where((t) =>
            timelineTaskTruthy(t['is_upcoming']) ||
            timelineTaskTruthy(t['is_not_started']))
        .length;
    final completedWindow = _taskNamesFromSummaryWindow(
      _statusSummary,
      const [
        'completed_tasks',
        'last_completed',
        'recently_completed',
        'recent_completed_tasks',
      ],
    );
    final pendingWindow = _taskNamesFromSummaryWindow(
      _statusSummary,
      const [
        'pending_tasks',
        'next_pending',
        'upcoming_tasks',
        'next_pending_tasks',
      ],
    );
    final showSkeleton = _aiLoading && summaryText == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.navy.withValues(alpha: 0.55),
            AppTheme.accentBlue.withValues(alpha: 0.28),
            AppTheme.darkBackgroundSecondary,
          ],
        ),
        border: Border.all(
          color: AppTheme.accentBlue.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(status.icon, color: status.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status.title,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusMotionIndicator(
                state: focus.resolvedActivityState,
                color: status.color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          status.body,
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: AppTheme.accentBlue.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 14),
          // AI review
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.accentBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project AI review',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      "What's done and what's yet to happen",
                      style: TextStyle(
                        color: AppTheme.accentBlue.withValues(alpha: 0.9),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (showSkeleton)
            const _AiReviewSkeleton()
          else if (summaryText != null && summaryText.isNotEmpty)
            Text(
              summaryText,
              style: TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            )
          else
            Text(
              _aiError ??
                  'Critical task summary is not available yet. Pull to refresh.',
              style: TextStyle(
                color: _muted,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          if (!showSkeleton && _criticalTasks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AiStatChip(
                  label: '$completed done',
                  color: const Color(0xFF34D399),
                ),
                _AiStatChip(
                  label: '$pending pending',
                  color: const Color(0xFFFBBF24),
                ),
                _AiStatChip(
                  label: '$upcoming upcoming',
                  color: const Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
          if (!showSkeleton &&
              (completedWindow.isNotEmpty || pendingWindow.isNotEmpty)) ...[
            const SizedBox(height: 14),
            if (completedWindow.isNotEmpty) ...[
              Text(
                'Recent completions',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                completedWindow.take(5).join(' · '),
                style: TextStyle(
                  color: AppTheme.accentBlue.withValues(alpha: 0.95),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            if (pendingWindow.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Next up',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pendingWindow.take(3).join(' · '),
                style: TextStyle(
                  color: _ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ],
          if (!showSkeleton && _aiError != null && summaryText != null) ...[
            const SizedBox(height: 8),
            Text(
              _aiError!,
              style: const TextStyle(
                color: Color(0xFFFCA5A5),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _extractStatusSummaryText(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    for (final key in const [
      'summary',
      'status_summary',
      'ai_summary',
      'review',
      'message',
    ]) {
      final value = payload[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    final nested = payload['data'];
    if (nested is Map) {
      return _extractStatusSummaryText(Map<String, dynamic>.from(nested));
    }
    return null;
  }

  List<String> _taskNamesFromSummaryWindow(
    Map<String, dynamic>? payload,
    List<String> keys,
  ) {
    if (payload == null) return const [];
    for (final key in keys) {
      final raw = payload[key];
      if (raw is! List) continue;
      final names = <String>[];
      for (final item in raw) {
        if (item is Map) {
          final name = (item['task_name'] ??
                  item['name'] ??
                  item['note'] ??
                  item['title'])
              ?.toString()
              .trim();
          if (name != null && name.isNotEmpty && name.toLowerCase() != 'null') {
            names.add(name);
          }
        } else {
          final name = item?.toString().trim();
          if (name != null && name.isNotEmpty) names.add(name);
        }
      }
      if (names.isNotEmpty) return names;
    }
    final windows = payload['task_windows'] ?? payload['windows'];
    if (windows is Map) {
      return _taskNamesFromSummaryWindow(
        Map<String, dynamic>.from(windows),
        keys,
      );
    }
    return const [];
  }

  Widget _buildAttentionSection(ProjectFocus focus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Workflow attention'),
        for (var i = 0; i < focus.workflowAttention.length; i++) ...[
          _AttentionCard(
            item: focus.workflowAttention[i],
            onOpen: focus.workflowAttention[i].canOpen
                ? () => _openWorkflowTask(
                      runId: focus.workflowAttention[i].workflowItemRunId!,
                      name: focus.workflowAttention[i].name,
                    )
                : null,
          ),
          if (i != focus.workflowAttention.length - 1)
            const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildBlockerDetails(ProjectFocus focus) {
    final waiting = focus.projectBlocker?.waitingFor ?? const [];
    if (waiting.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('What is holding the project?'),
        for (var i = 0; i < waiting.length; i++) ...[
          _PersonTaskCard(
            title: waiting[i].name,
            statusLabel: waiting[i].statusLabel,
            statusKey: waiting[i].status,
            assignee: waiting[i].waitingWith,
            role: waiting[i].role,
            category: waiting[i].category,
            onOpen: waiting[i].canOpen
                ? () => _openWorkflowTask(
                      runId: waiting[i].workflowItemRunId!,
                      name: waiting[i].name,
                      status: waiting[i].status,
                    )
                : null,
          ),
          if (i != waiting.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      color: AppTheme.accentBlue,
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.cloud_off_outlined, size: 46, color: _muted),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Could not load project focus',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull to refresh or try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton(
              onPressed: _bootstrap,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phase helpers ────────────────────────────────────────────────────────────

List<CurrentPhase> _displayPhases(ProjectFocus focus) {
  if (focus.phases.isNotEmpty) {
    final current = focus.currentPhase;
    final needle = _normalizePhaseKey(
      current?.key.isNotEmpty == true ? current!.key : (current?.label ?? ''),
    );
    if (needle.isEmpty) return focus.phases;
    return [
      for (final phase in focus.phases)
        CurrentPhase(
          key: phase.key,
          label: _normalizePhaseKey(phase.key) == needle
              ? (current?.label ?? phase.label)
              : phase.label,
          state: phase.state.isNotEmpty
              ? phase.state
              : (_normalizePhaseKey(phase.key) == needle
                  ? 'current'
                  : phase.state),
        ),
    ];
  }

  final current = focus.currentPhase;
  if (current == null) return const [];

  const catalog = <CurrentPhase>[
    CurrentPhase(key: 'site_setup', label: 'Site Setup'),
    CurrentPhase(key: 'excavation', label: 'Excavation'),
    CurrentPhase(key: 'foundation', label: 'Foundation'),
    CurrentPhase(key: 'plinth', label: 'Plinth'),
    CurrentPhase(key: 'ground_floor', label: 'Ground Floor'),
    CurrentPhase(key: 'first_floor', label: 'First Floor'),
    CurrentPhase(key: 'headroom', label: 'Headroom / SHR'),
    CurrentPhase(key: 'finishing', label: 'Finishing'),
    CurrentPhase(key: 'handover', label: 'Handover'),
  ];

  final needle = _normalizePhaseKey(
    current.key.isNotEmpty ? current.key : current.label,
  );
  var index = catalog.indexWhere((p) => _normalizePhaseKey(p.key) == needle);
  if (index < 0) {
    index = catalog.indexWhere((p) => _normalizePhaseKey(p.label) == needle);
  }
  if (index < 0) return [current];

  return [
    for (var i = 0; i < catalog.length; i++)
      CurrentPhase(
        key: catalog[i].key,
        label: i == index ? current.label : catalog[i].label,
        state: i < index
            ? 'completed'
            : (i == index ? 'current' : 'upcoming'),
      ),
  ];
}

String _normalizePhaseKey(String raw) {
  var value = raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  value = value.replaceAll(RegExp(r'_(stage|phase)$'), '');
  const aliases = {
    'gf': 'ground_floor',
    'ff': 'first_floor',
    'shr': 'headroom',
    'headroom_shr': 'headroom',
    'site': 'site_setup',
  };
  return aliases[value] ?? value;
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _FocusStatusHeader {
  final String title;
  final Color color;
  final IconData icon;
  final Widget body;

  const _FocusStatusHeader({
    required this.title,
    required this.color,
    required this.icon,
    required this.body,
  });
}

/// Right-aligned motion cue for project status (moving / blocked / waiting).
class _StatusMotionIndicator extends StatefulWidget {
  final ProjectActivityState state;
  final Color color;

  const _StatusMotionIndicator({
    required this.state,
    required this.color,
  });

  @override
  State<_StatusMotionIndicator> createState() => _StatusMotionIndicatorState();
}

class _StatusMotionIndicatorState extends State<_StatusMotionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.state),
    )..repeat(reverse: _reverses(widget.state));
  }

  @override
  void didUpdateWidget(covariant _StatusMotionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _controller
        ..duration = _durationFor(widget.state)
        ..repeat(reverse: _reverses(widget.state));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _durationFor(ProjectActivityState state) {
    switch (state) {
      case ProjectActivityState.moving:
      case ProjectActivityState.unknown:
        return const Duration(milliseconds: 1400);
      case ProjectActivityState.blocked:
        return const Duration(milliseconds: 900);
      case ProjectActivityState.waiting:
        return const Duration(milliseconds: 1600);
      case ProjectActivityState.workflowAttention:
        return const Duration(milliseconds: 1100);
    }
  }

  bool _reverses(ProjectActivityState state) {
    // Continuous spin for "moving"; pulse / shake for others.
    return state != ProjectActivityState.moving &&
        state != ProjectActivityState.unknown;
  }

  IconData get _icon {
    switch (widget.state) {
      case ProjectActivityState.moving:
      case ProjectActivityState.unknown:
        return Icons.sync_rounded;
      case ProjectActivityState.blocked:
        return Icons.lock_rounded;
      case ProjectActivityState.waiting:
        return Icons.hourglass_top_rounded;
      case ProjectActivityState.workflowAttention:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        Widget badge = child!;

        switch (widget.state) {
          case ProjectActivityState.moving:
          case ProjectActivityState.unknown:
            badge = Transform.rotate(
              angle: t * 6.28318530718,
              child: child,
            );
            break;
          case ProjectActivityState.blocked:
            final shake = (t - 0.5) * 6;
            badge = Transform.translate(
              offset: Offset(shake, 0),
              child: Opacity(
                opacity: 0.65 + (0.35 * (1 - (t - 0.5).abs() * 2)),
                child: child,
              ),
            );
            break;
          case ProjectActivityState.waiting:
          case ProjectActivityState.workflowAttention:
            final scale = 0.88 + (0.12 * t);
            badge = Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: 0.7 + (0.3 * t),
                child: child,
              ),
            );
            break;
        }

        return Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.35),
            ),
          ),
          child: badge,
        );
      },
      child: Icon(_icon, color: widget.color, size: 18),
    );
  }
}

class _AiReviewSkeleton extends StatelessWidget {
  const _AiReviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.navy.withValues(alpha: 0.35),
      highlightColor: AppTheme.accentBlue.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBar(height: 14),
          SizedBox(height: 10),
          SkeletonBar(height: 14),
          SizedBox(height: 10),
          SkeletonBar(width: 180, height: 14),
          SizedBox(height: 16),
          Row(
            children: [
              SkeletonBar(width: 72, height: 28, radius: 999),
              SizedBox(width: 8),
              SkeletonBar(width: 84, height: 28, radius: 999),
              SizedBox(width: 8),
              SkeletonBar(width: 96, height: 28, radius: 999),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiStatChip extends StatelessWidget {
  final String label;
  final Color color;

  const _AiStatChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: AppTheme.darkTextSecondary,
        ),
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const _FocusCard({
    required this.child,
    this.color,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

class _PhaseHeroCard extends StatelessWidget {
  final CurrentPhase? phase;
  const _PhaseHeroCard({this.phase});

  @override
  Widget build(BuildContext context) {
    final label = phase?.label.trim();
    return _FocusCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (label == null || label.isEmpty)
                      ? 'Phase unavailable'
                      : label.toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.darkTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Currently in this phase',
                  style: TextStyle(
                    color: AppTheme.darkTextSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.navy.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.apartment_rounded,
              color: Color(0xFFC4B5FD),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseRoadmap extends StatelessWidget {
  final List<CurrentPhase> phases;
  const _PhaseRoadmap({required this.phases});

  /// Parent Focus list pads 18px each side — keep in sync with that padding.
  static const double _parentHorizontalPadding = 18;

  /// How many cards fit in view: 3 full + half of the next (scroll affordance).
  static const double _visibleCardSlots = 3.5;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final viewportWidth =
        MediaQuery.sizeOf(context).width - (_parentHorizontalPadding * 2);
    // Separators between the visible slots (floor of 3.5 → 3 gaps).
    final gapCount = _visibleCardSlots.floor();
    final cardWidth =
        (viewportWidth - (_gap * gapCount)) / _visibleCardSlots;

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: phases.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final phase = phases[index];
          final current = phase.isCurrent;
          final completed = phase.isCompleted;
          final Color accent = current
              ? const Color(0xFFC4B5FD)
              : completed
                  ? const Color(0xFF34D399)
                  : AppTheme.darkTextSecondary;
          return Container(
            width: cardWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: current
                  ? AppTheme.navy.withValues(alpha: 0.4)
                  : AppTheme.darkBackgroundSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: current ? AppTheme.accentBlue : AppTheme.border,
                width: current ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  completed
                      ? Icons.check_circle_rounded
                      : current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(height: 6),
                Text(
                  phase.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PersonTaskCard extends StatelessWidget {
  final String title;
  final String statusLabel;
  final String statusKey;
  final String? assignee;
  final String? role;
  final String? category;
  final bool emphasizeStatus;
  final String actionLabel;
  final VoidCallback? onOpen;

  const _PersonTaskCard({
    required this.title,
    required this.statusLabel,
    required this.statusKey,
    this.assignee,
    this.role,
    this.category,
    this.emphasizeStatus = false,
    this.actionLabel = 'Open',
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final style = _FocusStatusStyle.from(statusKey, fallback: statusLabel);
    return _FocusCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (emphasizeStatus) ...[
            _StatusPill(label: style.label, color: style.color),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.darkTextPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              if (onOpen != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.darkTextSecondary,
                ),
            ],
          ),
          if (category != null && category!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              category!,
              style: TextStyle(
                color: AppTheme.darkTextSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!emphasizeStatus) ...[
            const SizedBox(height: 10),
            _StatusDot(label: style.label, color: style.color),
          ],
          if ((assignee != null && assignee!.isNotEmpty) ||
              (role != null && role!.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _OwnerLine(name: assignee, role: role),
          ],
          if (onOpen != null && actionLabel == 'Open Task') ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  final WorkflowAttentionItem item;
  final VoidCallback? onOpen;

  const _AttentionCard({required this.item, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return _FocusCard(
      color: const Color(0xFF241A33),
      borderColor: const Color(0xFF5B3A8C),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFC4B5FD), size: 18),
              SizedBox(width: 8),
              Text(
                'NEEDS ATTENTION',
                style: TextStyle(
                  color: Color(0xFFC4B5FD),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.message ?? 'Expected task was not triggered.',
            style: const TextStyle(
              color: Color(0xFFDDD6FE),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (onOpen != null) ...[
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'View dependency →',
                style: TextStyle(
                  color: Color(0xFFC4B5FD),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnerLine extends StatelessWidget {
  final String? name;
  final String? role;
  const _OwnerLine({this.name, this.role});

  @override
  Widget build(BuildContext context) {
    final hasName = name != null && name!.trim().isNotEmpty;
    final hasRole = role != null && role!.trim().isNotEmpty;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppTheme.navy.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.person_rounded,
              color: Color(0xFFC4B5FD), size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasName ? name! : (hasRole ? role! : 'Unassigned'),
                style: TextStyle(
                  color: AppTheme.darkTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (hasName && hasRole)
                Text(
                  role!,
                  style: TextStyle(
                    color: AppTheme.darkTextSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C1618),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFCA5A5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _FocusStatusStyle {
  final Color color;
  final String label;
  const _FocusStatusStyle(this.color, this.label);

  factory _FocusStatusStyle.from(String status, {String? fallback}) {
    switch (status.toLowerCase().replaceAll(' ', '_')) {
      case 'ready':
        return const _FocusStatusStyle(Color(0xFF34D399), 'Ready to start');
      case 'in_progress':
      case 'inprogress':
        return const _FocusStatusStyle(AppTheme.accentBlue, 'In progress');
      case 'waiting':
        return const _FocusStatusStyle(Color(0xFFFBBF24), 'Waiting');
      case 'not_started':
      case 'notstarted':
        return _FocusStatusStyle(AppTheme.darkTextSecondary, 'Not started');
      case 'blocked':
        return const _FocusStatusStyle(Color(0xFFF87171), 'Blocked');
      default:
        final text = (fallback != null && fallback.isNotEmpty)
            ? fallback
            : (status.isEmpty
                ? ''
                : status[0].toUpperCase() +
                    status.substring(1).replaceAll('_', ' '));
        return _FocusStatusStyle(AppTheme.darkTextSecondary, text);
    }
  }
}
