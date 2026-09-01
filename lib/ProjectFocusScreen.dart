import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'MyTasksScreen.dart';
import 'ProjectTimelineScreen.dart';
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

  const ProjectFocusScreen({super.key, this.salesSopId});

  /// Sync entry from Quick Actions / menus.
  static ProjectFocusScreen openQuick({
    String? erpProjectId,
    Map<String, dynamic>? project,
    Iterable<dynamic>? tasksHint,
  }) {
    return ProjectFocusScreen(
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
  State<ProjectFocusScreen> createState() => _ProjectFocusScreenState();
}

class _ProjectFocusScreenState extends State<ProjectFocusScreen> {
  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _pageBg = Color(0xFFF7F8FB);

  bool _loading = true;
  String? _error;
  String? _salesSopId;
  ProjectFocus? _focus;

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
      });
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

  void _openTimeline() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ProjectTimelineScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.navy,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.navy),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text(
            'Project Focus',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          bottom: ProjectSituationSwitcher(
            selected: ProjectSituationTab.focus,
            onChanged: (tab) {
              if (tab == ProjectSituationTab.timeline) {
                _openTimeline();
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _onRefresh,
              icon: _loading && _focus != null
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.navy,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, color: AppTheme.navy),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(child: _buildBody()),
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
          // 2. Project state
          _buildProjectStateCard(focus),
          if (showBlockerDetails) ...[
            const SizedBox(height: 14),
            _buildBlockerDetails(focus),
          ],
          // 3. What can you do now? (user-first)
          const SizedBox(height: 22),
          _buildMyActionsSection(focus),
          // 4. What's happening now? (other people's work)
          const SizedBox(height: 22),
          _buildActiveWorkSection(focus),
          // 5. Your next involvement
          const SizedBox(height: 22),
          _buildInvolvementSection(focus),
          // 6. What happens after this?
          if (focus.activeFlow.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildActiveFlowSection(focus),
          ],
          // 7. Workflow attention — only when present
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

  Widget _buildProjectStateCard(ProjectFocus focus) {
    final state = focus.resolvedActivityState;
    switch (state) {
      case ProjectActivityState.blocked:
        final blocker = focus.projectBlocker;
        final name = blocker?.task?.name ??
            focus.projectActivity?.label ??
            'Project is blocked';
        final waiting = blocker?.waitingCount ?? 0;
        return _StatusBanner(
          title: 'PROJECT IS BLOCKED',
          color: const Color(0xFFDC2626),
          background: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          icon: Icons.lock_rounded,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (waiting > 0) ...[
                const SizedBox(height: 6),
                Text(
                  waiting == 1
                      ? 'Waiting for 1 task'
                      : 'Waiting for $waiting tasks',
                  style: const TextStyle(
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
        return _StatusBanner(
          title: 'PROJECT IS WAITING',
          color: const Color(0xFFB45309),
          background: const Color(0xFFFFF7ED),
          border: const Color(0xFFFED7AA),
          icon: Icons.hourglass_top_rounded,
          body: Text(
            focus.projectActivity?.message ??
                focus.projectActivity?.label ??
                'Work is waiting on a dependency.',
            style: const TextStyle(
              color: Color(0xFF9A3412),
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
        return _StatusBanner(
          title: 'PROJECT NEEDS ATTENTION',
          color: const Color(0xFF7C3AED),
          background: const Color(0xFFF5F3FF),
          border: const Color(0xFFDDD6FE),
          icon: Icons.warning_amber_rounded,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item?.name ??
                    focus.projectActivity?.label ??
                    'Workflow attention needed',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item?.message ??
                    focus.projectActivity?.message ??
                    'Expected task was not triggered.',
                style: const TextStyle(
                  color: Color(0xFF5B21B6),
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
        return _StatusBanner(
          title: 'PROJECT IS MOVING',
          color: const Color(0xFF059669),
          background: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          icon: Icons.check_circle_rounded,
          body: Text(
            focus.projectActivity?.message ?? 'No current blocker',
            style: const TextStyle(
              color: Color(0xFF047857),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
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

  Widget _buildActiveWorkSection(ProjectFocus focus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel("What's happening now"),
        if (!focus.hasActiveWork)
          const _FocusCard(
            child: Text(
              'No active work reported right now.',
              style: TextStyle(
                color: _muted,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (var i = 0; i < focus.activeWork.length; i++) ...[
            _PersonTaskCard(
              title: focus.activeWork[i].name,
              statusLabel: focus.activeWork[i].statusLabel,
              statusKey: focus.activeWork[i].status,
              assignee: focus.activeWork[i].assignee,
              role: focus.activeWork[i].role,
              category: focus.activeWork[i].category,
              emphasizeStatus: true,
              onOpen: focus.activeWork[i].canOpen
                  ? () => _openWorkflowTask(
                        runId: focus.activeWork[i].workflowItemRunId!,
                        name: focus.activeWork[i].name,
                        status: focus.activeWork[i].status,
                      )
                  : null,
            ),
            if (i != focus.activeWork.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildActiveFlowSection(ProjectFocus focus) {
    final branches = focus.activeFlow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('What happens after this?'),
        for (var b = 0; b < branches.length; b++) ...[
          if (branches[b].label != null && branches.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                branches[b].label!,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          _FlowChain(items: branches[b].items.take(5).toList()),
          if (b != branches.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildInvolvementSection(ProjectFocus focus) {
    final involvement = focus.myNextInvolvement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Your next involvement'),
        if (involvement == null)
          _NoInvolvementCard(focus: focus)
        else
          _InvolvementCard(
            involvement: involvement,
            onOpen: involvement.canOpen
                ? () => _openWorkflowTask(
                      runId: involvement.workflowItemRunId!,
                      name: involvement.name ?? 'Your next task',
                      status: involvement.status,
                    )
                : null,
          ),
      ],
    );
  }

  Widget _buildMyActionsSection(ProjectFocus focus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('What can you do now?'),
        if (!focus.hasMyActions)
          const _FocusCard(
            color: Color(0xFFEFF6FF),
            borderColor: Color(0xFFBFDBFE),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFF2563EB), size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nothing assigned to you right now',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'The project is progressing with other team members.',
                        style: TextStyle(
                          color: Color(0xFF1E40AF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < focus.myNextActions.length; i++) ...[
            _PersonTaskCard(
              title: focus.myNextActions[i].name,
              statusLabel: focus.myNextActions[i].statusLabel,
              statusKey: focus.myNextActions[i].status,
              category: focus.myNextActions[i].category,
              emphasizeStatus: true,
              actionLabel: 'Open Task',
              onOpen: focus.myNextActions[i].canOpen
                  ? () => _openWorkflowTask(
                        runId: focus.myNextActions[i].workflowItemRunId!,
                        name: focus.myNextActions[i].name,
                        status: focus.myNextActions[i].status,
                      )
                  : null,
            ),
            if (i != focus.myNextActions.length - 1) const SizedBox(height: 10),
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
          const Icon(Icons.cloud_off_outlined, size: 46, color: _muted),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Could not load project focus',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: Color(0xFF6B7280),
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
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? const Color(0xFFE8ECF1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Currently in this phase',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
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
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.apartment_rounded,
              color: AppTheme.accentBlue,
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: phases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final phase = phases[index];
          final current = phase.isCurrent;
          final completed = phase.isCompleted;
          final Color accent = current
              ? AppTheme.accentBlue
              : completed
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF9CA3AF);
          return Container(
            width: 84,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: current ? const Color(0xFFEFF4FF) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: current
                    ? const Color(0xFFBFDBFE)
                    : const Color(0xFFE8ECF1),
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
                    color: current
                        ? AppTheme.navy
                        : completed
                            ? const Color(0xFF111827)
                            : const Color(0xFF9CA3AF),
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

class _StatusBanner extends StatelessWidget {
  final String title;
  final Color color;
  final Color background;
  final Color border;
  final IconData icon;
  final Widget body;

  const _StatusBanner({
    required this.title,
    required this.color,
    required this.background,
    required this.border,
    required this.icon,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return _FocusCard(
      color: background,
      borderColor: border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
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
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              if (onOpen != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9CA3AF),
                ),
            ],
          ),
          if (category != null && category!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              category!,
              style: const TextStyle(
                color: Color(0xFF6B7280),
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
                  backgroundColor: AppTheme.accentBlue,
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
      color: const Color(0xFFF5F3FF),
      borderColor: const Color(0xFFDDD6FE),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFF7C3AED), size: 18),
              SizedBox(width: 8),
              Text(
                'NEEDS ATTENTION',
                style: TextStyle(
                  color: Color(0xFF7C3AED),
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
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.message ?? 'Expected task was not triggered.',
            style: const TextStyle(
              color: Color(0xFF5B21B6),
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
                  color: Color(0xFF7C3AED),
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

class _NoInvolvementCard extends StatelessWidget {
  final ProjectFocus focus;
  const _NoInvolvementCard({required this.focus});

  @override
  Widget build(BuildContext context) {
    final current = focus.activeWork.isNotEmpty ? focus.activeWork.first : null;
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing is assigned to you right now.',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (current != null) ...[
            const SizedBox(height: 12),
            const Text(
              'The project is currently progressing with:',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (current.assignee != null && current.assignee!.isNotEmpty)
              Text(
                current.assignee!,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            Text(
              current.name,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InvolvementCard extends StatelessWidget {
  final MyNextInvolvement involvement;
  final VoidCallback? onOpen;

  const _InvolvementCard({required this.involvement, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return _FocusCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your next task',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            involvement.name ?? 'Upcoming involvement',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (involvement.statusLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StatusDot(
              label: involvement.statusLabel,
              color: _FocusStatusStyle.from(involvement.status).color,
            ),
          ],
          if (involvement.waitingFor.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Waiting for',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final dep in involvement.waitingFor.take(4)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ',
                        style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w800)),
                    Expanded(
                      child: Text(
                        dep.name,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (involvement.message != null &&
              involvement.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              involvement.message!,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowChain extends StatelessWidget {
  final List<ActiveFlowItem> items;
  const _FlowChain({required this.items});

  @override
  Widget build(BuildContext context) {
    return _FocusCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _FlowStep(item: items[i], isFirst: i == 0),
            if (i != items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 16,
                  color: Color(0xFF9CA3AF),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FlowStep extends StatelessWidget {
  final ActiveFlowItem item;
  final bool isFirst;
  const _FlowStep({required this.item, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    final style = _FocusStatusStyle.from(item.status, fallback: item.statusLabel);
    final meta = [
      if (item.assignee != null && item.assignee!.isNotEmpty) item.assignee!,
      if (item.role != null && item.role!.isNotEmpty) item.role!,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: isFirst ? AppTheme.accentBlue : const Color(0xFFD1D5DB),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: TextStyle(
                  color: const Color(0xFF111827),
                  fontSize: 14.5,
                  fontWeight: isFirst ? FontWeight.w800 : FontWeight.w700,
                  height: 1.3,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (item.statusLabel.isNotEmpty || item.status.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  style.label,
                  style: TextStyle(
                    color: style.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.person_rounded,
              color: AppTheme.navy, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasName ? name! : (hasRole ? role! : 'Unassigned'),
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (hasName && hasRole)
                Text(
                  role!,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
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
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
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
        return const _FocusStatusStyle(Color(0xFF16A34A), 'Ready to start');
      case 'in_progress':
      case 'inprogress':
        return const _FocusStatusStyle(Color(0xFF2563EB), 'In progress');
      case 'waiting':
        return const _FocusStatusStyle(Color(0xFFB45309), 'Waiting');
      case 'not_started':
      case 'notstarted':
        return const _FocusStatusStyle(Color(0xFF9CA3AF), 'Not started');
      case 'blocked':
        return const _FocusStatusStyle(Color(0xFFDC2626), 'Blocked');
      default:
        final text = (fallback != null && fallback.isNotEmpty)
            ? fallback
            : (status.isEmpty
                ? ''
                : status[0].toUpperCase() +
                    status.substring(1).replaceAll('_', ' '));
        return _FocusStatusStyle(const Color(0xFF6B7280), text);
    }
  }
}
