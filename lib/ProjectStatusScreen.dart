import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_v1/chat_v1_controller.dart';
import 'notifcations.dart';
import 'services/api_http.dart';
import 'services/data_provider.dart';
import 'services/notification_service.dart';

/// My Work Queue — pending + upcoming tasks for the selected sales_sop.
/// API / auth / ordering unchanged; UI-only redesign.
class ProjectStatusScreen extends StatefulWidget {
  final String? salesSopId;

  const ProjectStatusScreen({super.key, this.salesSopId});

  /// Sync entry from menus — resolve sales_sop_id without awaiting network.
  static ProjectStatusScreen openQuick({
    String? erpProjectId,
    Map<String, dynamic>? project,
    Iterable<dynamic>? tasksHint,
  }) {
    return ProjectStatusScreen(
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
  State<ProjectStatusScreen> createState() => _ProjectStatusScreenState();
}

class _ProjectStatusScreenState extends State<ProjectStatusScreen>
    with SingleTickerProviderStateMixin {
  static const _baseUrl = 'https://office.buildahome.in';
  static const _navy = Color(0xFF0B1B4D);
  static const _pageBg = Color(0xFFF5F6FA);
  static const _muted = Color(0xFF6B7280);

  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  String? _salesSopId;
  String? _currentUserId;
  int _pendingCount = 0;
  int _upcomingCount = 0;
  _WorkTask? _current;
  List<_WorkTask> _tasks = const [];
  List<_WorkTask> _upcoming = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    NotificationService.instance.ensureHydrated();
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              'Select a project first so My Work Queue can load your tasks.';
        });
        return;
      }
      _salesSopId = sopId;
      await _fetch(sopId);
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

  Future<void> _fetch(String salesSopId, {bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in');
    }

    final projectId = prefs.getString('project_id')?.trim() ?? '';
    final userId = (prefs.getString('userId') ?? prefs.getString('user_id'))
            ?.trim() ??
        '';
    final role = prefs.getString('role')?.trim() ?? '';
    final authHeaders = <String, String>{
      'Accept': 'application/json',
      'X-Api-Token': token,
      'Authorization': 'Bearer $token',
    };

    print(
      '[ProjectStatus] auth role=$role userId=$userId '
      'sales_sop_id=$salesSopId project_id=$projectId',
    );

    final pendingFuture = _fetchPendingBody(
      salesSopId: salesSopId,
      token: token,
      projectId: projectId,
      userId: userId,
      authHeaders: authHeaders,
    );
    final upcomingFuture = _fetchUpcomingTasks(
      salesSopId: salesSopId,
      token: token,
      projectId: projectId,
      userId: userId,
      authHeaders: authHeaders,
    );

    final pending = await pendingFuture;
    final upcomingResult = await upcomingFuture;

    final decoded = pending.body;
    if (decoded == null) {
      final status = pending.statusCode;
      throw Exception(
        pending.lastMessage ??
            (status != null
                ? 'Could not load project status ($status)'
                : 'Could not load project status'),
      );
    }

    final tasksRaw = decoded['pending_tasks'];
    final tasks = <_WorkTask>[];
    if (tasksRaw is List) {
      for (final row in tasksRaw) {
        if (row is Map) {
          tasks.add(_WorkTask.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    if (tasks.isEmpty) {
      final alt = decoded['pending_timeline_tasks'];
      if (alt is List) {
        for (final row in alt) {
          if (row is Map) {
            tasks.add(_WorkTask.fromJson(Map<String, dynamic>.from(row)));
          }
        }
      }
    }
    tasks.sort((a, b) => a.orderIdx.compareTo(b.orderIdx));

    _WorkTask? current;
    final currentRaw = decoded['current_pending_task'];
    if (currentRaw is Map) {
      current = _WorkTask.fromJson(Map<String, dynamic>.from(currentRaw));
    } else if (tasks.isNotEmpty) {
      current = tasks.first;
    }

    final count = _asInt(decoded['pending_task_count']) ?? tasks.length;

    if (!mounted) return;
    setState(() {
      _currentUserId = userId;
      _pendingCount = count;
      _current = current;
      _tasks = tasks;
      _upcoming = upcomingResult.tasks;
      _upcomingCount = upcomingResult.count;
      _loading = false;
      _error = null;
    });
  }

  Future<_PendingFetchResult> _fetchPendingBody({
    required String salesSopId,
    required String token,
    required String projectId,
    required String userId,
    required Map<String, String> authHeaders,
  }) async {
    final attempts = <Uri>[
      Uri.parse('$_baseUrl/API/sales_sop_pending_tasks/$salesSopId').replace(
        queryParameters: {
          'api_token': token,
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
      Uri.parse('$_baseUrl/API/sales_sop_pending_tasks').replace(
        queryParameters: {
          'api_token': token,
          'sales_sop_id': salesSopId,
          if (projectId.isNotEmpty) 'project_id': projectId,
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
    ];

    int? lastStatus;
    Map<String, dynamic>? decoded;
    String? lastMessage;

    for (final uri in attempts) {
      print('[ProjectStatus] GET $uri');
      try {
        final res = await ApiHttp.get(uri, headers: authHeaders)
            .timeout(const Duration(seconds: 20));
        lastStatus = res.statusCode;
        print('[ProjectStatus] status=${res.statusCode} body=${res.body}');

        Map<String, dynamic>? body;
        try {
          final raw = jsonDecode(res.body);
          if (raw is Map) body = Map<String, dynamic>.from(raw);
        } catch (_) {
          body = null;
        }

        if (res.statusCode == 401) {
          lastMessage = body?['message']?.toString() ?? 'Unauthorized';
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastMessage = body?['message']?.toString() ??
              'Could not load project status (${res.statusCode})';
          continue;
        }
        if (body == null) {
          lastMessage = 'Unexpected response from server';
          continue;
        }
        if (body['success'] == false) {
          lastMessage =
              body['message']?.toString() ?? 'Could not load project status';
          continue;
        }

        decoded = body;
        break;
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
        print('[ProjectStatus] attempt failed: $e');
      }
    }

    return _PendingFetchResult(
      body: decoded,
      statusCode: lastStatus,
      lastMessage: lastMessage,
    );
  }

  Future<_UpcomingFetchResult> _fetchUpcomingTasks({
    required String salesSopId,
    required String token,
    required String projectId,
    required String userId,
    required Map<String, String> authHeaders,
  }) async {
    final attempts = <Uri>[
      Uri.parse('$_baseUrl/API/sales_sop_upcoming_my_tasks/$salesSopId').replace(
        queryParameters: {
          'api_token': token,
          'limit': '10',
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
      Uri.parse('$_baseUrl/API/sales_sop_upcoming_my_tasks').replace(
        queryParameters: {
          'api_token': token,
          'sales_sop_id': salesSopId,
          'limit': '10',
          if (projectId.isNotEmpty) 'project_id': projectId,
          if (userId.isNotEmpty) 'user_id': userId,
        },
      ),
    ];

    for (final uri in attempts) {
      print('[ProjectStatus] Upcoming GET $uri');
      try {
        final res = await ApiHttp.get(uri, headers: authHeaders)
            .timeout(const Duration(seconds: 20));
        print(
          '[ProjectStatus] Upcoming status=${res.statusCode} body=${res.body}',
        );

        Map<String, dynamic>? body;
        try {
          final raw = jsonDecode(res.body);
          if (raw is Map) body = Map<String, dynamic>.from(raw);
        } catch (_) {
          body = null;
        }

        if (res.statusCode < 200 ||
            res.statusCode >= 300 ||
            body == null ||
            body['success'] == false) {
          continue;
        }

        final tasks = <_WorkTask>[];
        final rawList = body['upcoming_tasks'];
        if (rawList is List) {
          for (final row in rawList) {
            if (row is Map) {
              tasks.add(_WorkTask.fromJson(Map<String, dynamic>.from(row)));
            }
          }
        }
        tasks.sort((a, b) => a.orderIdx.compareTo(b.orderIdx));
        final count = _asInt(body['upcoming_task_count']) ?? tasks.length;
        return _UpcomingFetchResult(tasks: tasks, count: count);
      } catch (e) {
        print('[ProjectStatus] Upcoming attempt failed: $e');
      }
    }

    return const _UpcomingFetchResult(tasks: [], count: 0);
  }

  Future<void> _onRefresh() async {
    final sopId = _salesSopId ?? await _resolveSalesSopId();
    if (sopId == null || sopId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error =
            'Select a project first so My Work Queue can load your tasks.';
      });
      return;
    }
    _salesSopId = sopId;
    try {
      await _fetch(sopId, showLoader: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  /// Pending tasks that need action now (never mixes upcoming).
  List<_WorkTask> get _pendingNowTasks {
    final list = <_WorkTask>[];
    final seen = <String>{};

    void addTask(_WorkTask t) {
      final key = t.dedupeKey;
      if (seen.contains(key)) return;
      seen.add(key);
      list.add(t);
    }

    for (final t in _tasks) {
      if (t.isAssignedToUser(_currentUserId) || !_tasksHaveAssigneeIds) {
        addTask(t);
      }
    }

    // If API filtered nothing (no assignee ids on payload), keep original order.
    if (list.isEmpty && _tasks.isNotEmpty && _tasksHaveAssigneeIds) {
      // Assigned-to-other pending only — still empty for "my" queue.
      return const [];
    }
    if (list.isEmpty && _tasks.isNotEmpty) {
      for (final t in _tasks) {
        addTask(t);
      }
    }

    if (list.isEmpty &&
        _current != null &&
        (_current!.isAssignedToUser(_currentUserId) ||
            !_current!.hasAssigneeUserId)) {
      addTask(_current!);
    }

    list.sort((a, b) => a.orderIdx.compareTo(b.orderIdx));
    return list;
  }

  bool get _tasksHaveAssigneeIds =>
      _tasks.any((t) => t.hasAssigneeUserId) ||
      (_current?.hasAssigneeUserId ?? false);

  /// Upcoming only — excludes anything already shown in Pending Now.
  List<_WorkTask> get _upcomingOnlyTasks {
    final pendingKeys = _pendingNowTasks.map((t) => t.dedupeKey).toSet();
    final out = <_WorkTask>[];
    for (final t in _upcoming) {
      if (pendingKeys.contains(t.dedupeKey)) continue;
      out.add(t);
      if (out.length >= 10) break;
    }
    return out;
  }

  int get _pendingBadgeCount => _pendingNowTasks.length;

  int get _upcomingBadgeCount => _upcomingOnlyTasks.length;

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const Notifications()),
    );
  }

  void _openTaskDetails(_WorkTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskDetailsSheet(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: _navy,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _pageBg,
        body: Column(
          children: [
            _MyWorkQueueHeader(
              controller: _tabController,
              pendingCount: _pendingBadgeCount,
              upcomingCount: _upcomingBadgeCount,
              onBack: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              onNotifications: _openNotifications,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading &&
        _tasks.isEmpty &&
        _current == null &&
        _upcoming.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null &&
        _tasks.isEmpty &&
        _current == null &&
        _upcoming.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.cloud_off_outlined, size: 42, color: _muted),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: _bootstrap,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ErrorBanner(message: _error!, onRetry: _bootstrap),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PendingNowTab(
                tasks: _pendingNowTasks,
                onRefresh: _onRefresh,
                onOpenDetails: _openTaskDetails,
              ),
              _UpcomingTab(
                tasks: _upcomingOnlyTasks,
                onRefresh: _onRefresh,
                onOpenDetails: _openTaskDetails,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Header + tabs ────────────────────────────────────────────────────────────

class _MyWorkQueueHeader extends StatelessWidget {
  final TabController controller;
  final int pendingCount;
  final int upcomingCount;
  final VoidCallback onBack;
  final VoidCallback onNotifications;

  const _MyWorkQueueHeader({
    required this.controller,
    required this.pendingCount,
    required this.upcomingCount,
    required this.onBack,
    required this.onNotifications,
  });

  static const _navy = Color(0xFF0B1B4D);
  static const _navyDeep = Color(0xFF071536);

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_navy, _navyDeep],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topInset),
          // Top navigation row
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: onNotifications,
                    icon: ValueListenableBuilder<int>(
                      valueListenable:
                          NotificationService.instance.unreadCountNotifier,
                      builder: (context, unread, _) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            if (unread > 0)
                              Positioned(
                                right: 1,
                                top: 1,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _navy,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Title + subtitle
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Text(
              'My Work Queue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.15,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 5, 20, 0),
            child: Text(
              'Stay on top of your tasks and upcoming work',
              style: TextStyle(
                color: Color(0xFFB8C0D4),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          // Segmented tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: _WorkQueueTabBar(
              controller: controller,
              pendingCount: pendingCount,
              upcomingCount: upcomingCount,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkQueueTabBar extends StatelessWidget {
  final TabController controller;
  final int pendingCount;
  final int upcomingCount;

  const _WorkQueueTabBar({
    required this.controller,
    required this.pendingCount,
    required this.upcomingCount,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _TabChip(
                  label: 'Pending Now',
                  count: pendingCount,
                  icon: Icons.checklist_rtl_rounded,
                  selected: controller.index == 0,
                  onTap: () => controller.animateTo(0),
                ),
              ),
              Expanded(
                child: _TabChip(
                  label: 'Upcoming (Next 10)',
                  count: upcomingCount,
                  icon: Icons.calendar_today_rounded,
                  selected: controller.index == 1,
                  onTap: () => controller.animateTo(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      elevation: selected ? 1 : 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? const Color(0xFF0B1B4D)
                    : Colors.white.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF0B1B4D)
                        : Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE8EEFF)
                      : Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF4338CA)
                        : Colors.white.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingNowTab extends StatelessWidget {
  final List<_WorkTask> tasks;
  final Future<void> Function() onRefresh;
  final ValueChanged<_WorkTask> onOpenDetails;

  const _PendingNowTab({
    required this.tasks,
    required this.onRefresh,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
          children: const [
            Icon(Icons.check_circle_outline,
                size: 44, color: Color(0xFF16A34A)),
            SizedBox(height: 14),
            Text(
              'You’re all caught up',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'No pending tasks require your action.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: tasks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: _SectionHeader(
                title: 'Pending Tasks',
                subtitle: 'Tasks currently waiting for your action',
              ),
            );
          }
          final task = tasks[index - 1];
          final isPrimary = index == 1;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == tasks.length ? 0 : 8,
            ),
            child: isPrimary
                ? _PrimaryPendingCard(
                    task: task,
                    onOpenDetails: () => onOpenDetails(task),
                  )
                : _CompactTaskRow(
                    task: task,
                    onTap: () => onOpenDetails(task),
                  ),
          );
        },
      ),
    );
  }
}

class _UpcomingTab extends StatelessWidget {
  final List<_WorkTask> tasks;
  final Future<void> Function() onRefresh;
  final ValueChanged<_WorkTask> onOpenDetails;

  const _UpcomingTab({
    required this.tasks,
    required this.onRefresh,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
          children: const [
            Icon(Icons.event_available_outlined,
                size: 44, color: Color(0xFF6366F1)),
            SizedBox(height: 14),
            Text(
              'No upcoming tasks',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'There are no tasks scheduled after your current workflow.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          const _SectionHeader(
            title: 'Upcoming Tasks',
            subtitle: 'Next 10 tasks coming your way',
          ),
          const SizedBox(height: 10),
          ...tasks.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CompactTaskRow(
                task: t,
                upcoming: true,
                onTap: () => onOpenDetails(t),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Cards ────────────────────────────────────────────────────────────────────

/// First pending task — compact emphasis, not a hero card.
class _PrimaryPendingCard extends StatelessWidget {
  final _WorkTask task;
  final VoidCallback onOpenDetails;

  const _PrimaryPendingCard({
    required this.task,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC7D2FE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Action needed',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _StatusPill(
                    label: task.statusDisplay.isNotEmpty
                        ? task.statusDisplay
                        : 'Pending',
                    bg: const Color(0xFFFEF3C7),
                    fg: const Color(0xFFB45309),
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.taskName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (task.isWorkflowTask)
                    const _StatusPill(
                      label: 'Workflow',
                      bg: Color(0xFFEEF2FF),
                      fg: Color(0xFF4338CA),
                      compact: true,
                    )
                  else if (task.typeLabel.isNotEmpty)
                    _StatusPill(
                      label: task.typeLabel,
                      bg: const Color(0xFFEFF6FF),
                      fg: const Color(0xFF1D4ED8),
                      compact: true,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.isUnassigned
                    ? 'Assigned to: Pending assignment'
                    : 'Assigned to: ${task.assignedToName}'
                        '${task.assignedToRole.isNotEmpty && task.assignedToRole != '—' ? ' · ${task.assignedToRole}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (task.dueLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  task.dueLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onOpenDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0B1B4D),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Task Details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact row used for secondary pending + all upcoming tasks.
class _CompactTaskRow extends StatelessWidget {
  final _WorkTask task;
  final VoidCallback onTap;
  final bool upcoming;

  const _CompactTaskRow({
    required this.task,
    required this.onTap,
    this.upcoming = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconBg = task.isWorkflowTask
        ? const Color(0xFFEEF2FF)
        : const Color(0xFFEFF6FF);
    final iconColor = task.isWorkflowTask
        ? const Color(0xFF4F46E5)
        : const Color(0xFF2563EB);
    final statusLabel = upcoming
        ? (task.displayStatus.isNotEmpty ? task.displayStatus : 'Not Started')
        : (task.statusDisplay.isNotEmpty ? task.statusDisplay : 'Pending');
    final statusBg =
        upcoming ? const Color(0xFFE0E7FF) : const Color(0xFFFEF3C7);
    final statusFg =
        upcoming ? const Color(0xFF4338CA) : const Color(0xFFB45309);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  task.isWorkflowTask
                      ? Icons.account_tree_outlined
                      : Icons.task_alt_rounded,
                  color: iconColor,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.taskName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusPill(
                          label: statusLabel,
                          bg: statusBg,
                          fg: statusFg,
                          compact: true,
                        ),
                        if (task.isWorkflowTask)
                          const _StatusPill(
                            label: 'Workflow',
                            bg: Color(0xFFEEF2FF),
                            fg: Color(0xFF4338CA),
                            compact: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      task.isUnassigned
                          ? 'Assigned to: Pending assignment'
                          : 'Assigned to: ${task.assignedToName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (upcoming && task.dueShortLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        task.dueShortLabel!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF4F46E5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9CA3AF),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool compact;

  const _StatusPill({
    required this.label,
    required this.bg,
    required this.fg,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: compact ? 10.5 : 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TaskDetailsSheet extends StatelessWidget {
  final _WorkTask task;
  const _TaskDetailsSheet({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 48),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Task details',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                task.taskName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _StatusPill(
                    label: task.displayStatus.isNotEmpty
                        ? task.displayStatus
                        : (task.statusDisplay.isNotEmpty
                            ? task.statusDisplay
                            : 'Pending'),
                    bg: const Color(0xFFFEF3C7),
                    fg: const Color(0xFFB45309),
                    compact: true,
                  ),
                  if (task.isWorkflowTask)
                    const _StatusPill(
                      label: 'Workflow',
                      bg: Color(0xFFEEF2FF),
                      fg: Color(0xFF4338CA),
                      compact: true,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SheetMeta(
                label: 'Assigned to',
                value: task.isUnassigned
                    ? 'Pending assignment'
                    : task.assignedToName,
                sub: task.isUnassigned ||
                        task.assignedToRole.isEmpty ||
                        task.assignedToRole == '—'
                    ? null
                    : task.assignedToRole,
              ),
              if (task.referenceLabel != null) ...[
                const SizedBox(height: 12),
                _SheetMeta(label: 'Reference', value: task.referenceLabel!),
              ],
              if (task.dueLabel != null) ...[
                const SizedBox(height: 12),
                _SheetMeta(label: 'Due', value: task.dueLabel!),
              ],
              if (task.category != null && task.category!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SheetMeta(
                  label: 'Category',
                  value: task.category!.replaceAll('_', ' '),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0B1B4D),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetMeta extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _SheetMeta({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        if (sub != null && sub!.isNotEmpty)
          Text(
            sub!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
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
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ── Models / fetch results ───────────────────────────────────────────────────

class _PendingFetchResult {
  final Map<String, dynamic>? body;
  final int? statusCode;
  final String? lastMessage;

  const _PendingFetchResult({
    this.body,
    this.statusCode,
    this.lastMessage,
  });
}

class _UpcomingFetchResult {
  final List<_WorkTask> tasks;
  final int count;

  const _UpcomingFetchResult({
    required this.tasks,
    required this.count,
  });
}

class _WorkTask {
  final int orderIdx;
  final String taskName;
  final String assignedToName;
  final String assignedToRole;
  final String? assignedToUserId;
  final String status;
  final String timelineStatus;
  final bool isWorkflowTask;
  final bool isNotStarted;
  final bool isUpcoming;
  final String? category;
  final String? source;
  final String? erpTaskId;
  final String? reference;
  final String? flowLabel;
  final String? dueDisplay;
  final int? dueInDays;
  final DateTime? dueAt;

  const _WorkTask({
    required this.orderIdx,
    required this.taskName,
    required this.assignedToName,
    required this.assignedToRole,
    this.assignedToUserId,
    required this.status,
    required this.timelineStatus,
    required this.isWorkflowTask,
    this.isNotStarted = false,
    this.isUpcoming = false,
    this.category,
    this.source,
    this.erpTaskId,
    this.reference,
    this.flowLabel,
    this.dueDisplay,
    this.dueInDays,
    this.dueAt,
  });

  factory _WorkTask.fromJson(Map<String, dynamic> json) {
    final dueRaw = json['due_date'] ??
        json['due_at'] ??
        json['due_on'] ??
        json['deadline'];
    DateTime? dueAt;
    if (dueRaw != null) {
      dueAt = DateTime.tryParse(dueRaw.toString());
    }

    final ref = _firstString(json, const [
      'reference',
      'reference_label',
      's_no',
      'serial_no',
      'sequence_label',
      'sequence_no',
    ]);
    final flow = _firstString(json, const [
      'flow_name',
      'workflow_name',
      'workflow_title',
      'flow',
      'source_label',
    ]);

    String? reference;
    if (ref != null && flow != null) {
      reference = 'S. No: $ref / $flow';
    } else if (ref != null) {
      reference = ref.startsWith('S.') ? ref : 'S. No: $ref';
    } else if (flow != null) {
      reference = flow;
    }

    final dueDisplay = _firstString(json, const [
      'due_date_display',
      'due_at_display',
      'due_display',
      'due_label',
    ]);

    int? dueInDays = _parseInt(json['due_in_days']);
    if (dueInDays == null && dueAt != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(dueAt.year, dueAt.month, dueAt.day);
      dueInDays = dueDay.difference(today).inDays;
    }

    return _WorkTask(
      orderIdx: _parseInt(json['order_idx']) ?? 0,
      taskName: (json['task_name'] ?? 'Untitled task').toString().trim(),
      assignedToName:
          (json['assigned_to_name'] ?? 'Pending assignment').toString().trim(),
      assignedToRole: (json['assigned_to_role'] ?? '—').toString().trim(),
      assignedToUserId: _firstString(json, const [
        'assigned_to_user_id',
        'assigned_user_id',
      ]),
      status: (json['status'] ?? '').toString().trim(),
      timelineStatus: (json['timeline_status'] ?? '').toString().trim(),
      isWorkflowTask: json['is_workflow_task'] == true,
      isNotStarted: json['is_not_started'] == true,
      isUpcoming: json['is_upcoming'] == true,
      category: json['category']?.toString().trim(),
      source: json['source']?.toString().trim(),
      erpTaskId: _firstString(json, const ['erp_task_id', 'task_id']),
      reference: reference,
      flowLabel: flow,
      dueDisplay: dueDisplay,
      dueInDays: dueInDays,
      dueAt: dueAt,
    );
  }

  static String? _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key]?.toString().trim();
      if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return null;
  }

  bool get hasAssigneeUserId {
    final id = assignedToUserId?.trim() ?? '';
    return id.isNotEmpty && id.toLowerCase() != 'null';
  }

  bool isAssignedToUser(String? userId) {
    if (userId == null || userId.isEmpty) return true;
    if (!hasAssigneeUserId) return true;
    return assignedToUserId == userId;
  }

  bool get isUnassigned {
    final name = assignedToName.toLowerCase();
    return name.isEmpty ||
        name == 'pending assignment' ||
        name == '—' ||
        name == '-';
  }

  String get displayStatus {
    if (timelineStatus.isNotEmpty) return timelineStatus;
    if (status.isNotEmpty) return status;
    if (isNotStarted) return 'Not Started';
    return '';
  }

  String get statusDisplay {
    final s = status.toLowerCase().replaceAll(' ', '_');
    if (s == 'in_progress' || s == 'inprogress') return 'In progress';
    if (s == 'not_started') return 'Not Started';
    if (s == 'pending' || s.isEmpty) return 'Pending';
    if (status.isEmpty) return 'Pending';
    return status[0].toUpperCase() + status.substring(1);
  }

  String get typeLabel {
    if (isWorkflowTask) return 'Workflow';
    if (category != null && category!.isNotEmpty) {
      return category!.replaceAll('_', ' ');
    }
    if (source == 'sales_sop') return 'Sales SOP';
    if (source != null && source!.isNotEmpty) return source!;
    return '';
  }

  String? get referenceLabel => reference;

  String? get dueLabel {
    if (dueDisplay != null && dueDisplay!.isNotEmpty) return dueDisplay;
    if (dueAt != null) {
      final h = dueAt!.hour.toString().padLeft(2, '0');
      final m = dueAt!.minute.toString().padLeft(2, '0');
      final hasTime = dueAt!.hour != 0 || dueAt!.minute != 0;
      final days = dueInDays;
      if (days == 0) {
        return hasTime ? 'Due today, $h:$m' : 'Due today';
      }
      if (days == 1) {
        return hasTime ? 'Due tomorrow, $h:$m' : 'Due tomorrow';
      }
      if (days != null && days > 1) {
        return 'Due in $days days';
      }
      if (days != null && days < 0) {
        return 'Overdue';
      }
    }
    if (dueInDays != null) {
      if (dueInDays == 0) return 'Due today';
      if (dueInDays == 1) return 'Due in 1 day';
      if (dueInDays! > 1) return 'Due in $dueInDays days';
      if (dueInDays! < 0) return 'Overdue';
    }
    return null;
  }

  String? get dueShortLabel {
    if (dueInDays != null) {
      if (dueInDays == 0) return 'Due today';
      if (dueInDays == 1) return 'Due in 1 day';
      if (dueInDays! > 1) return 'Due in $dueInDays days';
      if (dueInDays! < 0) return 'Overdue';
    }
    return dueLabel;
  }

  String get dedupeKey {
    if (erpTaskId != null &&
        erpTaskId!.isNotEmpty &&
        !erpTaskId!.startsWith('-')) {
      return 'erp:$erpTaskId';
    }
    return 'ord:$orderIdx|${taskName.toLowerCase()}';
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}
