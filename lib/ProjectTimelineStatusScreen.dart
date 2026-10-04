import 'package:flutter/material.dart';

import 'ProjectFocusScreen.dart';
import 'ProjectTimelineScreen.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/project_situation_switcher.dart';
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

/// Client-facing project activity: recently closed, ongoing, and upcoming tasks.
class ProjectTimelineStatusScreen extends StatefulWidget {
  const ProjectTimelineStatusScreen({super.key});

  @override
  State<ProjectTimelineStatusScreen> createState() =>
      _ProjectTimelineStatusScreenState();
}

class _ProjectTimelineStatusScreenState
    extends State<ProjectTimelineStatusScreen> {
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _hydrateFromProvider();
    _loadStatus();
  }

  void _hydrateFromProvider() {
    final provider = DataProvider();
    if (!provider.clientTimelineLoaded) return;
    setState(() {
      _tasks = List<Map<String, dynamic>>.from(provider.clientTimelineTasks);
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
      await DataProvider().loadProjectTimeline(force: true);
      if (!mounted) return;
      setState(() {
        _tasks =
            List<Map<String, dynamic>>.from(DataProvider().clientTimelineTasks);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tasks =
            List<Map<String, dynamic>>.from(DataProvider().clientTimelineTasks);
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

  List<Map<String, dynamic>> get _ongoingPending {
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

  List<Map<String, dynamic>> get _upcomingNext {
    final upcoming = _tasks
        .where((task) =>
            (_statusTruthy(task['is_upcoming']) ||
                _statusTruthy(task['is_not_started'])) &&
            !_statusTruthy(task['is_completed']) &&
            !_statusTruthy(task['is_cancelled']))
        .toList();
    upcoming.sort((a, b) => _orderIdx(a).compareTo(_orderIdx(b)));
    return upcoming.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppTheme.darkTextPrimary),
        actionsIconTheme: IconThemeData(color: AppTheme.darkTextPrimary),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.darkTextPrimary, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Project Status',
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        bottom: ProjectSituationSwitcher(
          selected: ProjectSituationTab.status,
          onChanged: (tab) {
            if (tab == ProjectSituationTab.status) return;
            final Widget page;
            switch (tab) {
              case ProjectSituationTab.focus:
                page = ProjectFocusScreen.openQuick();
                break;
              case ProjectSituationTab.status:
                return;
              case ProjectSituationTab.timeline:
                page = const ProjectTimelineScreen();
                break;
            }
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => page),
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadStatus(),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.navy),
                  )
                : Icon(Icons.refresh_rounded,
                    color: AppTheme.darkTextPrimary),
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

    final recentlyClosed = _recentlyClosed;
    final ongoing = _ongoingPending;
    final upcoming = _upcomingNext;

    if (recentlyClosed.isEmpty && ongoing.isEmpty && upcoming.isEmpty) {
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
            subtitle: 'Last 5 completed tasks',
            tasks: recentlyClosed,
            emptyLabel: 'No recently closed tasks yet.',
            accent: const Color(0xFF059669),
          ),
          const SizedBox(height: 22),
          _buildSection(
            title: 'Ongoing',
            subtitle: 'Pending tasks in progress',
            tasks: ongoing,
            emptyLabel: 'No ongoing pending tasks right now.',
            accent: const Color(0xFFD97706),
          ),
          const SizedBox(height: 22),
          _buildSection(
            title: 'Upcoming',
            subtitle: 'Next 5 tasks',
            tasks: upcoming,
            emptyLabel: 'No upcoming tasks yet.',
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
              'No project activity yet',
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recently closed, ongoing, and upcoming tasks will appear here.',
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
    final taskName = _value('task_name') ??
        _value('note') ??
        _value('name') ??
        'Task';
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
              color: accent.withOpacity(0.14),
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
