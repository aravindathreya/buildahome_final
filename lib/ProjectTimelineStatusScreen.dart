import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/skeleton_loader.dart';

Color get _ink => AppTheme.darkTextPrimary;
Color get _muted => AppTheme.darkTextSecondary;
Color get _cardSurface => AppTheme.darkBackgroundSecondary;

bool _statusTruthy(dynamic value) {
  if (value == true || value == 1) return true;
  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

DateTime? _parseTaskDate(Map<String, dynamic> task, List<String> keys) {
  for (final key in keys) {
    final raw = task[key]?.toString().trim();
    if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') continue;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
  }
  return null;
}

int _orderIdx(Map<String, dynamic> task) {
  return int.tryParse(task['order_idx']?.toString() ?? '') ?? 0;
}

/// Critical-path status: last 5 completed, pending, upcoming.
/// Site Engineer all-tasks status: last 5 closed, ongoing, next 5 future.
class ProjectTimelineStatusScreen extends StatefulWidget {
  final bool embedded;

  const ProjectTimelineStatusScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<ProjectTimelineStatusScreen> createState() =>
      ProjectTimelineStatusScreenState();
}

class ProjectTimelineStatusScreenState
    extends State<ProjectTimelineStatusScreen>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _role;

  bool get _isSiteEngineer {
    final role = (_role ?? DataProvider().currentRole ?? '').trim().toLowerCase();
    return role == 'site engineer';
  }

  /// Site Engineer Status uses the full (all-tasks) schedule, not critical-only.
  bool get _useAllTasksForSiteEngineer => _isSiteEngineer;

  @override
  bool get wantKeepAlive => true;

  bool get isRefreshing => _isLoading;

  Future<void> refresh() => _loadStatus();

  @override
  void initState() {
    super.initState();
    _role = DataProvider().currentRole;
    _hydrateFromProvider();
    _loadStatus();
  }

  Future<void> _ensureRole() async {
    if (_role != null && _role!.trim().isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role') ?? DataProvider().currentRole;
    if (role != null && role.trim().isNotEmpty) {
      DataProvider().currentRole = role;
      _role = role;
    }
  }

  void _hydrateFromProvider() {
    final provider = DataProvider();
    if (_useAllTasksForSiteEngineer) {
      if (!provider.clientTimelineLoaded) return;
      setState(() {
        _tasks = List<Map<String, dynamic>>.from(provider.clientTimelineTasks);
        _isLoading = false;
      });
      return;
    }
    if (!provider.clientCriticalTimelineLoaded) return;
    setState(() {
      _tasks =
          List<Map<String, dynamic>>.from(provider.clientCriticalTimelineTasks);
      _isLoading = false;
    });
  }

  Future<void> _loadStatus({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await _ensureRole();
      if (_useAllTasksForSiteEngineer) {
        await DataProvider().loadProjectTimeline(force: true);
      } else {
        await DataProvider().loadCriticalTimeline(force: true);
      }
      if (!mounted) return;
      setState(() {
        _tasks = _useAllTasksForSiteEngineer
            ? List<Map<String, dynamic>>.from(
                DataProvider().clientTimelineTasks)
            : List<Map<String, dynamic>>.from(
                DataProvider().clientCriticalTimelineTasks);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tasks = _useAllTasksForSiteEngineer
            ? List<Map<String, dynamic>>.from(
                DataProvider().clientTimelineTasks)
            : List<Map<String, dynamic>>.from(
                DataProvider().clientCriticalTimelineTasks);
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _recentlyClosed {
    final closed = _tasks
        .where((task) =>
            _statusTruthy(task['is_completed']) &&
            !_statusTruthy(task['is_cancelled']))
        .toList();
    closed.sort((a, b) {
      final aDate = _parseTaskDate(a, const [
        'completed_at',
        'updated_at',
        'closed_at',
      ]);
      final bDate = _parseTaskDate(b, const [
        'completed_at',
        'updated_at',
        'closed_at',
      ]);
      if (aDate != null && bDate != null) return bDate.compareTo(aDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return _orderIdx(b).compareTo(_orderIdx(a));
    });
    return closed.take(5).toList();
  }

  List<Map<String, dynamic>> get _allPending {
    final pending = _tasks
        .where((task) =>
            _statusTruthy(task['is_pending']) &&
            !_statusTruthy(task['is_completed']) &&
            !_statusTruthy(task['is_cancelled']) &&
            !_statusTruthy(task['is_upcoming']) &&
            !_statusTruthy(task['is_not_started']))
        .toList();
    pending.sort((a, b) => _orderIdx(a).compareTo(_orderIdx(b)));
    return pending;
  }

  List<Map<String, dynamic>> get _allUpcoming {
    final upcoming = _tasks
        .where((task) =>
            (_statusTruthy(task['is_upcoming']) ||
                _statusTruthy(task['is_not_started'])) &&
            !_statusTruthy(task['is_completed']) &&
            !_statusTruthy(task['is_cancelled']))
        .toList();
    upcoming.sort((a, b) => _orderIdx(a).compareTo(_orderIdx(b)));
    return _useAllTasksForSiteEngineer
        ? upcoming.take(5).toList()
        : upcoming;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = _buildBody();
    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Project Status',
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadStatus(),
            icon: Icon(Icons.refresh_rounded, color: AppTheme.darkTextPrimary),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _tasks.isEmpty && _errorMessage == null) {
      return const SkeletonListLoader(showSummary: false, cardCount: 5);
    }

    if (_errorMessage != null && _tasks.isEmpty) {
      return _buildErrorState();
    }

    final recentlyClosed = _recentlyClosed;
    final pending = _allPending;
    final upcoming = _allUpcoming;
    final siteEngineerAllTasks = _useAllTasksForSiteEngineer;

    if (recentlyClosed.isEmpty && pending.isEmpty && upcoming.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: AppTheme.getPrimaryColor(context),
      onRefresh: () => _loadStatus(showLoader: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _buildSection(
            title: 'Recently closed',
            subtitle: siteEngineerAllTasks
                ? 'Last 5 completed tasks'
                : 'Top 5 completed critical tasks',
            tasks: recentlyClosed,
            emptyLabel: siteEngineerAllTasks
                ? 'No recently closed tasks yet.'
                : 'No recently closed critical tasks yet.',
            accent: const Color(0xFF059669),
          ),
          const SizedBox(height: 22),
          _buildSection(
            title: siteEngineerAllTasks ? 'Ongoing' : 'Pending',
            subtitle: siteEngineerAllTasks
                ? 'Current in-progress tasks'
                : 'All pending critical tasks',
            tasks: pending,
            emptyLabel: siteEngineerAllTasks
                ? 'No ongoing tasks right now.'
                : 'No pending critical tasks right now.',
            accent: const Color(0xFFD97706),
          ),
          const SizedBox(height: 22),
          _buildSection(
            title: siteEngineerAllTasks ? 'Future' : 'Upcoming',
            subtitle: siteEngineerAllTasks
                ? 'Next 5 upcoming tasks'
                : 'All upcoming critical tasks',
            tasks: upcoming,
            emptyLabel: siteEngineerAllTasks
                ? 'No future tasks yet.'
                : 'No upcoming critical tasks yet.',
            accent: const Color(0xFF9CA3AF),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> tasks,
    required String emptyLabel,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${tasks.length}',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              emptyLabel,
              style: TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          ...tasks.map((task) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StatusTaskRow(task: task, accent: accent),
              )),
      ],
    );
  }

  Widget _buildEmptyState() {
    final siteEngineerAllTasks = _useAllTasksForSiteEngineer;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_outlined,
                size: 56, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 20),
            Text(
              siteEngineerAllTasks
                  ? 'No schedule tasks yet'
                  : 'No critical tasks from server',
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              siteEngineerAllTasks
                  ? 'Project schedule tasks will appear here once they are created.'
                  : 'The critical timeline API returned successfully but with 0 tasks. '
                      'This is a server/data issue — Main Critical tasks are not flagged for this project yet.',
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
              onPressed: _isLoading ? null : () => _loadStatus(),
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
                  : 'Could not load project status',
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
              onPressed: () => _loadStatus(),
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

class _StatusTaskRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final Color accent;

  const _StatusTaskRow({
    required this.task,
    required this.accent,
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
    final taskName =
        _value('task_name') ?? _value('note') ?? _value('name') ?? 'Task';
    final status = _value('timeline_status') ?? _value('status') ?? '—';
    final completedAt = _value('completed_at_display');
    final assignee = _value('assigned_to_name');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: orderIdx != null
                  ? Text(
                      '$orderIdx',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : Icon(Icons.circle, size: 8, color: accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  taskName,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (completedAt != null && completedAt != '—') ...[
                  const SizedBox(height: 2),
                  Text(
                    'Completed $completedAt',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (!isClient && assignee != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    assignee,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
