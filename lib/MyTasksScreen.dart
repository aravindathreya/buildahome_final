import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'FullScreenImage.dart';
import 'NotesAndComments.dart';
import 'TasksScreen.dart';
import 'services/api_http.dart';
import 'services/data_provider.dart';
import 'services/session_manager.dart';
import 'widgets/dashboard_chrome.dart';
import 'widgets/modern_task_card.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/skeleton_loader.dart';

const String _workflowApiBaseUrl = 'https://office.buildahome.in';
const Color _premiumBackground = Color(0xFFF7F8FB);
const Color _premiumSurface = Colors.white;
const Color _premiumInk = Color(0xFF1B254B);
const Color _premiumMuted = Color(0xFF8A94A6);

const Set<String> kCompletedTaskStatuses = {
  'completed',
  'done',
  'finished',
  'skipped',
  'approved',
};

String normalizeTaskStatusValue(Map task) {
  final isWorkflow = task['is_workflow_task'] == true ||
      task['workflow_item_run_id'] != null;
  if (isWorkflow) {
    final workflowStatus =
        task['workflow_status']?.toString().trim().toLowerCase();
    if (workflowStatus != null && workflowStatus.isNotEmpty) {
      return workflowStatus.replaceAll(' ', '_');
    }
  }

  return (task['status']?.toString().trim().toLowerCase() ?? 'pending')
      .replaceAll(' ', '_');
}

String workflowStatusDisplayLabel(Map task) {
  final apiLabel = task['workflow_status_label']?.toString().trim();
  if (apiLabel != null && apiLabel.isNotEmpty) return apiLabel;

  switch (normalizeTaskStatusValue(task)) {
    case 'in_progress':
      return 'In progress';
    case 'waiting_approval':
      return 'In review';
    case 'completed':
      return 'Completed';
    case 'rejected':
      return 'Rejected';
    case 'ready':
      return 'Ready';
    case 'scheduled':
      return 'Scheduled';
    default:
      final status = task['status']?.toString().trim();
      if (status != null && status.isNotEmpty) return status;
      return 'Pending';
  }
}

bool isWorkflowReviewerTask(Map task) {
  return task['can_approve_workflow_task'] == true ||
      task['is_workflow_approval_task'] == true;
}

bool shouldShowWorkflowApprovalButtons(Map task) {
  if (task['can_approve_workflow_task'] != true) return false;
  final status = normalizeTaskStatusValue(task);
  return task['pending_manager_approval'] == true ||
      status == 'waiting_approval';
}

bool _isAssigneeInteractiveWorkflowAction(String type) {
  return type == 'upload' || type == 'complete_button';
}

Map<String, dynamic>? workflowDelayGate(Map task) {
  final gate = task['workflow_delay_gate'];
  if (gate is Map) return Map<String, dynamic>.from(gate);
  return null;
}

DateTime? parseWorkflowAvailableAt(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } catch (_) {
    return null;
  }
}

int workflowDelayRemainingSeconds(Map<String, dynamic>? gate) {
  if (gate == null) return 0;

  final availableAt = parseWorkflowAvailableAt(
    gate['available_at_iso'] ?? gate['available_at'],
  );
  if (availableAt != null) {
    final diff = availableAt.difference(DateTime.now().toUtc()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  final fromApi = gate['seconds_remaining'];
  if (fromApi is num) return fromApi.floor().clamp(0, 999999999);
  return 0;
}

String formatWorkflowCountdown(int totalSeconds) {
  if (totalSeconds <= 0) return '0d 0h 0m';
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  return '${days}d ${hours}h ${minutes}m';
}

bool isWorkflowDelayGated(Map task) {
  final gate = workflowDelayGate(task);
  if (gate == null) return false;
  if (gate['is_delay_gated'] == true) return true;

  final availableAt = parseWorkflowAvailableAt(
    gate['available_at_iso'] ?? gate['available_at'],
  );
  if (availableAt != null && availableAt.isAfter(DateTime.now().toUtc())) {
    return true;
  }

  return workflowDelayRemainingSeconds(gate) > 0;
}

bool canUpdateWorkflowTask(Map task) {
  if (isWorkflowDelayGated(task)) return false;
  if (task['can_update_workflow_task'] == false) return false;
  if (task['can_update'] == false) return false;
  return true;
}

Map<String, dynamic> resolveWorkflowDelayGateData({
  Map<String, dynamic>? gate,
  Map<String, dynamic>? action,
}) {
  if (gate != null && gate.isNotEmpty) return gate;
  if (action == null) return const {};

  return {
    'is_delay_gated': true,
    'available_at': action['available_at'],
    'available_at_iso': action['available_at'],
    'available_at_display': action['available_at_display'],
    'seconds_remaining': action['seconds_remaining'],
    'countdown_label': action['label'],
    'message': action['message'],
    'heading': action['heading'],
  };
}

List<Map<String, dynamic>> filterVisibleWorkflowActions(
  Map<String, dynamic> task,
  List<Map<String, dynamic>> actions,
) {
  if (shouldShowWorkflowApprovalButtons(task)) return [];

  final status = normalizeTaskStatusValue(task);
  final delayGated = isWorkflowDelayGated(task);
  final canUpdate = canUpdateWorkflowTask(task);
  final isWaitingApproval = status == 'waiting_approval' ||
      task['pending_manager_approval'] == true;
  final isCompleted = kCompletedTaskStatuses.contains(status);

  if (delayGated) {
    return actions
        .where((action) => action['type']?.toString() != 'delay_timer')
        .toList();
  }

  if (isWaitingApproval) {
    return actions
        .where(
          (action) => !_isAssigneeInteractiveWorkflowAction(
            action['type']?.toString() ?? '',
          ),
        )
        .toList();
  }

  if (isCompleted || !canUpdate) {
    return actions
        .where(
          (action) => !_isAssigneeInteractiveWorkflowAction(
            action['type']?.toString() ?? '',
          ),
        )
        .toList();
  }

  return actions;
}

Future<Map<String, dynamic>> mergeWorkflowTaskDetail(
  Map<String, dynamic> task,
) async {
  final runId = task['workflow_item_run_id']?.toString().trim() ?? '';
  if (runId.isEmpty || task['is_workflow_task'] != true) return task;

  try {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        prefs.getString('userId') ?? prefs.getString('user_id') ?? '';
    final apiToken = prefs.getString('api_token') ?? '';
    if (userId.isEmpty || apiToken.isEmpty) return task;

    final uri = Uri.parse(
      '$_workflowApiBaseUrl/API/workflow/item-runs/$runId/actions',
    ).replace(
      queryParameters: {
        'user_id': userId,
        'api_token': apiToken,
      },
    );

    final response = await ApiHttp.get(
          uri,
          headers: {'X-Api-Token': apiToken},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) return task;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] == false) return task;

    final merged = Map<String, dynamic>.from(task);
    for (final key in const [
      'workflow_status',
      'workflow_status_label',
      'can_update',
      'can_update_workflow_task',
      'workflow_delay_gate',
      'can_approve_workflow_task',
      'pending_manager_approval',
      'is_workflow_approval_task',
      'workflow_actions',
      'workflow_task_actions',
      'workflow_action_responses',
      'workflow_prior_picture_choice_lists',
    ]) {
      if (decoded[key] != null) {
        merged[key] = decoded[key];
      }
    }

    if (decoded['status'] != null) {
      merged['workflow_status'] = decoded['status'];
      merged['status'] = decoded['status'];
    }
    if (decoded['item_run_id'] != null) {
      merged['workflow_item_run_id'] = decoded['item_run_id'];
    }

    return merged;
  } catch (e) {
    if (e is SessionInvalidatedException) rethrow;
    print('[WorkflowTaskDetail] fetch failed: $e');
    return task;
  }
}

bool isTaskCompletedStatus(Map task) {
  return kCompletedTaskStatuses.contains(normalizeTaskStatusValue(task));
}

bool isTaskAssignedToUser(Map task, String userId) {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) return false;

  for (final key in ['assigned_to', 'assigned_to_id', 'assignee_id']) {
    final value = task[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value == normalizedUserId) {
      return true;
    }
  }
  return false;
}

bool isTaskForProject(Map task, String projectId) {
  final normalizedProjectId = projectId.trim();
  if (normalizedProjectId.isEmpty) return true;

  for (final key in [
    'project_id',
    'projectId',
    'erp_project_id',
    'sales_sop_project_id',
    'sop_project_id',
  ]) {
    final value = task[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value == normalizedProjectId) {
      return true;
    }
  }
  return false;
}

List<dynamic> filterTasksForProjectAndAssignee(
  List<dynamic> tasks, {
  required String userId,
  String? projectId,
}) {
  return tasks.where((task) {
    if (task is! Map) return false;
    final isAssignee = isTaskAssignedToUser(task, userId);
    final isReviewer = isWorkflowReviewerTask(task);
    if (!isAssignee && !isReviewer) return false;
    if (projectId != null &&
        projectId.isNotEmpty &&
        !isTaskForProject(task, projectId)) {
      return false;
    }
    return true;
  }).toList();
}

List<Map<String, dynamic>> filterActiveRecentTasks(List<dynamic> tasks) {
  return tasks
      .whereType<Map>()
      .where((task) => !isTaskCompletedStatus(task))
      .map((task) => Map<String, dynamic>.from(task))
      .toList();
}

class MyTasksScreen extends StatefulWidget {
  final List<dynamic> tasks;
  final Future<List<dynamic>> Function()? onRefresh;
  final int initialTabIndex;
  final String? focusTaskId;

  const MyTasksScreen({
    Key? key,
    required this.tasks,
    this.onRefresh,
    this.initialTabIndex = 0,
    this.focusTaskId,
  }) : super(key: key);

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late List<dynamic> _tasks;
  bool _isRefreshing = false;
  String? _tasksSignature;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchVisible = false;
  String? _currentUserId;
  String? _selectedProjectId;
  String? _selectedProjectName;
  bool _showAssignedToMeOnly = false;
  bool _showCreatedByMeOnly = false;

  static const Set<String> _pendingStatuses = {
    'pending',
    'scheduled',
    'in_progress',
    'ready',
    'waiting_approval',
    'rejected',
  };
  static const Set<String> _completedStatuses = kCompletedTaskStatuses;

  bool get _hasActiveFilters =>
      _selectedProjectId != null ||
      _showAssignedToMeOnly ||
      _showCreatedByMeOnly;

  String _tasksListSignature(List<dynamic> tasks) {
    return tasks.whereType<Map>().map((task) {
      return [
        task['id'],
        task['status'],
        task['workflow_status'],
        task['note'],
        task['updated_at'],
        task['can_update_workflow_task'],
        task['can_approve_workflow_task'],
        jsonEncode(task['workflow_task_actions'] ?? const []),
        jsonEncode(task['workflow_actions'] ?? const []),
        jsonEncode(task['workflow_delay_gate'] ?? const {}),
      ].join('|');
    }).join('||');
  }

  @override
  void initState() {
    super.initState();
    final focusId = widget.focusTaskId?.toString().trim() ?? '';
    var initialIndex = widget.initialTabIndex.clamp(0, 1);
    if (focusId.isNotEmpty) {
      final focusedTask = widget.tasks.whereType<Map>().cast<Map>().firstWhere(
            (task) => task['id']?.toString() == focusId,
            orElse: () => <String, dynamic>{},
          );
      if (focusedTask.isNotEmpty) {
        initialIndex =
            _completedStatuses.contains(_taskStatus(focusedTask)) ? 1 : 0;
      }
    }
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tasks = List<dynamic>.from(widget.tasks);
    _tasksSignature = _tasksListSignature(_tasks);
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadCurrentUserId();
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentUserId =
          prefs.getString('userId') ?? prefs.getString('user_id');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _applyTaskFilters(
    Iterable<Map> source,
  ) {
    final query = _searchController.text.toLowerCase().trim();
    return source
        .where((task) {
          if (_selectedProjectId != null) {
            final taskProjectId = task['project_id']?.toString() ?? '';
            if (taskProjectId != _selectedProjectId) return false;
          }

          if (_showAssignedToMeOnly && _currentUserId != null) {
            final assignedTo = task['assigned_to']?.toString() ?? '';
            if (assignedTo != _currentUserId) return false;
          }

          if (_showCreatedByMeOnly && _currentUserId != null) {
            final userId = task['user_id']?.toString() ??
                task['created_by']?.toString() ??
                '';
            if (userId != _currentUserId) return false;
          }

          if (query.isNotEmpty) {
            final haystack = [
              task['note'],
              task['s_note'],
              task['project_name'],
              task['assigned_to_name'],
              task['assignee_name'],
              task['id'],
              task['status'],
              task['workflow_status'],
            ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
            if (!haystack.contains(query)) return false;
          }

          return true;
        })
        .map((task) => Map<String, dynamic>.from(task))
        .toList();
  }

  List<Map<String, dynamic>> get _pendingTasks => _applyTaskFilters(
        _tasks
            .whereType<Map>()
            .where((task) => _pendingStatuses.contains(_taskStatus(task))),
      );

  List<Map<String, dynamic>> get _completedTasks => _applyTaskFilters(
        _tasks
            .whereType<Map>()
            .where((task) => _completedStatuses.contains(_taskStatus(task))),
      );

  String _taskStatus(Map task) => normalizeTaskStatusValue(task);

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
      if (!_isSearchVisible) {
        _searchController.clear();
        _searchFocusNode.unfocus();
      }
    });
    if (_isSearchVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  Future<void> _showFilterSheet() async {
    await DataProvider().reloadData(force: false);
    if (!mounted) return;
    final projects = List<dynamic>.from(DataProvider().projects);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget filterChip({
              required String label,
              required IconData icon,
              required bool selected,
              required VoidCallback onTap,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? kTaskNavy.withValues(alpha: 0.12)
                        : const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? kTaskNavy
                          : kTaskBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: selected ? kTaskNavy : _premiumMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? kTaskNavy : _premiumMuted,
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: kTaskNavy,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Filter tasks',
                            style: TextStyle(
                              color: _premiumInk,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (_hasActiveFilters)
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                _selectedProjectId = null;
                                _selectedProjectName = null;
                                _showAssignedToMeOnly = false;
                                _showCreatedByMeOnly = false;
                              });
                              setState(() {});
                            },
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: _premiumMuted),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          filterChip(
                            label: 'Assigned to me',
                            icon: Icons.person_outline_rounded,
                            selected: _showAssignedToMeOnly,
                            onTap: () {
                              setSheetState(() {
                                _showAssignedToMeOnly = !_showAssignedToMeOnly;
                              });
                              setState(() {});
                            },
                          ),
                          filterChip(
                            label: 'Created by me',
                            icon: Icons.edit_outlined,
                            selected: _showCreatedByMeOnly,
                            onTap: () {
                              setSheetState(() {
                                _showCreatedByMeOnly = !_showCreatedByMeOnly;
                              });
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Project',
                        style: TextStyle(
                          color: _premiumInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      itemCount: projects.length + 1,
                      itemBuilder: (context, index) {
                        final isAll = index == 0;
                        final project =
                            isAll ? null : projects[index - 1] as Map?;
                        final projectId =
                            isAll ? null : project?['id']?.toString();
                        final projectName = isAll
                            ? 'All projects'
                            : (project?['name']?.toString() ??
                                'Unnamed project');
                        final isSelected = isAll
                            ? _selectedProjectId == null
                            : _selectedProjectId == projectId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? kTaskNavy.withValues(alpha: 0.08)
                                : const Color(0xFFF7F8FB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? kTaskNavy : kTaskBorder,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setSheetState(() {
                                  _selectedProjectId = projectId;
                                  _selectedProjectName =
                                      isAll ? null : projectName;
                                });
                                setState(() {});
                                Navigator.pop(context);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      isAll
                                          ? Icons.clear_all_rounded
                                          : Icons.folder_special_outlined,
                                      size: 20,
                                      color: kTaskNavy,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        projectName,
                                        style: const TextStyle(
                                          color: _premiumInk,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
                                        color: kTaskNavy,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _refreshTasks() async {
    if (widget.onRefresh == null || _isRefreshing) return;

    _isRefreshing = true;

    try {
      final updatedTasks = await widget.onRefresh!();
      if (!mounted) return;
      final nextTasks = List<dynamic>.from(updatedTasks);
      final nextSignature = _tasksListSignature(nextTasks);
      if (nextSignature != _tasksSignature) {
        setState(() {
          _tasks = nextTasks;
          _tasksSignature = nextSignature;
          _isRefreshing = false;
        });
      } else {
        _isRefreshing = false;
      }
    } catch (_) {
      if (mounted) {
        _isRefreshing = false;
      }
    }
  }

  Future<void> _openCreateTask() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TasksLayout(
          initialTasks: _tasks,
          initialTabIndex: 0,
          onTaskUpdated: () {
            _refreshTasks();
          },
          loadTasksCallback: widget.onRefresh,
        ),
      ),
    );
    await _refreshTasks();
  }

  @override
  Widget build(BuildContext context) {
    final pendingTasks = _pendingTasks;
    final completedTasks = _completedTasks;

    final isAdminChrome =
        DashboardChrome.of(context) == DashboardChromeStyle.admin;
    final appBarFg = isAdminChrome ? Colors.white : _premiumInk;

    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    final emptyPendingMessage = hasSearchQuery || _hasActiveFilters
        ? 'No pending tasks match your search or filters.'
        : 'Pending tasks for this project will appear here.';
    final emptyCompletedMessage = hasSearchQuery || _hasActiveFilters
        ? 'No completed tasks match your search or filters.'
        : 'Completed tasks will appear here once they are finished.';

    return ThemedScaffold(
      title: 'My tasks',
      backgroundColor: _premiumBackground,
      actions: [
        IconButton(
          tooltip: _isSearchVisible ? 'Close search' : 'Search',
          onPressed: _toggleSearch,
          icon: Icon(
            _isSearchVisible ? Icons.close_rounded : Icons.search_rounded,
            color: appBarFg,
            size: 22,
          ),
        ),
        IconButton(
          tooltip: 'Filter',
          onPressed: _showFilterSheet,
          icon: Badge(
            isLabelVisible: _hasActiveFilters,
            smallSize: 8,
            backgroundColor: const Color(0xFF2563EB),
            child: Icon(Icons.tune_rounded, color: appBarFg, size: 22),
          ),
        ),
        if (widget.onRefresh != null)
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isRefreshing ? null : _refreshTasks,
            icon: _isRefreshing
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(appBarFg),
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: appBarFg, size: 22),
          ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_isSearchVisible ? 126 : 66),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: Column(
            children: [
              if (_isSearchVisible) ...[
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: _premiumInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by task, project, or assignee',
                    hintStyle: const TextStyle(
                      color: _premiumMuted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _premiumMuted,
                      size: 20,
                    ),
                    suffixIcon: hasSearchQuery
                        ? IconButton(
                            tooltip: 'Clear',
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(
                              Icons.cancel_rounded,
                              color: _premiumMuted,
                              size: 18,
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F4F8),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  labelPadding: EdgeInsets.zero,
                  indicator: BoxDecoration(
                    color: kTaskNavy,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: _premiumMuted,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: [
                    SizedBox(
                      height: 40,
                      child: Center(
                          child: Text('Pending (${pendingTasks.length})')),
                    ),
                    SizedBox(
                      height: 40,
                      child: Center(
                          child:
                              Text('Completed (${completedTasks.length})')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_hasActiveFilters || hasSearchQuery)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasSearchQuery)
                      _ActiveFilterChip(
                        label: 'Search: ${_searchController.text.trim()}',
                        onClear: () => _searchController.clear(),
                      ),
                    if (_selectedProjectName != null)
                      _ActiveFilterChip(
                        label: _selectedProjectName!,
                        onClear: () {
                          setState(() {
                            _selectedProjectId = null;
                            _selectedProjectName = null;
                          });
                        },
                      ),
                    if (_showAssignedToMeOnly)
                      _ActiveFilterChip(
                        label: 'Assigned to me',
                        onClear: () {
                          setState(() => _showAssignedToMeOnly = false);
                        },
                      ),
                    if (_showCreatedByMeOnly)
                      _ActiveFilterChip(
                        label: 'Created by me',
                        onClear: () {
                          setState(() => _showCreatedByMeOnly = false);
                        },
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Row(
              children: [
                Expanded(
                  child: TaskSummaryStatCard(
                    value: '${pendingTasks.length}',
                    label: 'Pending tasks',
                    icon: Icons.assignment_outlined,
                    iconColor: const Color(0xFFEAB308),
                    iconBg: const Color(0xFFFFF1D6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TaskSummaryStatCard(
                    value: '${completedTasks.length}',
                    label: 'Completed tasks',
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: const Color(0xFF16A34A),
                    iconBg: const Color(0xFFDCFCE7),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final isPending = _tabController.index == 0;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        isPending ? 'All pending tasks' : 'All completed tasks',
                        style: const TextStyle(
                          color: _premiumInk,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Material(
                      color: kTaskNavy,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _openCreateTask,
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'New task',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TaskList(
                  tasks: pendingTasks,
                  emptyTitle: 'No pending tasks',
                  emptyMessage: emptyPendingMessage,
                  emptyIcon: Icons.pending_actions,
                  onWorkflowActionCompleted: _refreshTasks,
                  onCreateTask: _openCreateTask,
                  focusTaskId: widget.focusTaskId,
                ),
                _TaskList(
                  tasks: completedTasks,
                  emptyTitle: 'No completed tasks',
                  emptyMessage: emptyCompletedMessage,
                  emptyIcon: Icons.task_alt,
                  onWorkflowActionCompleted: _refreshTasks,
                  showWorkflowActions: false,
                  onCreateTask: _openCreateTask,
                  focusTaskId: widget.focusTaskId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const _ActiveFilterChip({
    required this.label,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final Future<void> Function() onWorkflowActionCompleted;
  final bool showWorkflowActions;
  final VoidCallback? onCreateTask;
  final String? focusTaskId;

  const _TaskList({
    required this.tasks,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onWorkflowActionCompleted,
    this.showWorkflowActions = true,
    this.onCreateTask,
    this.focusTaskId,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _EmptyTasksState(
            title: emptyTitle,
            message: emptyMessage,
            icon: emptyIcon,
          ),
          TaskHelpBanner(
            onChat: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotesAndComments()),
              );
            },
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
      itemCount: tasks.length + 1,
      itemBuilder: (context, index) {
        if (index == tasks.length) {
          return TaskHelpBanner(
            onChat: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotesAndComments()),
              );
            },
          );
        }
        final task = tasks[index];
        final focusId = focusTaskId?.toString().trim() ?? '';
        return _TaskCard(
          task: task,
          accentIndex: index,
          onWorkflowActionCompleted: onWorkflowActionCompleted,
          showWorkflowActions: showWorkflowActions,
          isSelected:
              focusId.isNotEmpty && task['id']?.toString() == focusId,
        );
      },
    );
  }
}

class _TaskCard extends StatefulWidget {
  final Map<String, dynamic> task;
  final Future<void> Function() onWorkflowActionCompleted;
  final bool showWorkflowActions;
  final int accentIndex;
  final bool isSelected;

  const _TaskCard({
    required this.task,
    required this.onWorkflowActionCompleted,
    this.showWorkflowActions = true,
    this.accentIndex = 0,
    this.isSelected = false,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  late Map<String, dynamic> _task;
  bool _isLoadingWorkflowDetail = false;
  bool _isRefreshingAfterDelay = false;
  bool _statusExpanded = false;
  bool _isUpdatingStatus = false;
  bool _isDeleting = false;
  bool _isSwipeCompleting = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _task = Map<String, dynamic>.from(widget.task);
    _loadCurrentUserId();
    _loadWorkflowDetail();
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentUserId =
          prefs.getString('userId') ?? prefs.getString('user_id');
    });
  }

  String _taskIdentity(Map task) {
    return [
      task['id'],
      task['status'],
      task['workflow_status'],
      task['updated_at'],
      task['can_update_workflow_task'],
      task['can_approve_workflow_task'],
      jsonEncode(task['workflow_task_actions'] ?? const []),
      jsonEncode(task['workflow_actions'] ?? const []),
      jsonEncode(task['workflow_delay_gate'] ?? const {}),
    ].join('|');
  }

  @override
  void didUpdateWidget(covariant _TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-merge workflow detail when task data actually changed.
    if (_taskIdentity(oldWidget.task) != _taskIdentity(widget.task)) {
      _task = Map<String, dynamic>.from(widget.task);
      _loadWorkflowDetail();
    }
  }

  Future<void> _loadWorkflowDetail() async {
    if (_task['is_workflow_task'] != true) return;

    setState(() {
      _isLoadingWorkflowDetail = true;
    });

    final merged = await mergeWorkflowTaskDetail(_task);
    if (!mounted) return;

    setState(() {
      _task = merged;
      _isLoadingWorkflowDetail = false;
    });
  }

  Future<void> _handleWorkflowActionCompleted() async {
    await widget.onWorkflowActionCompleted();
    await _loadWorkflowDetail();
  }

  Future<void> _handleDelayExpired() async {
    if (_isRefreshingAfterDelay || !mounted) return;
    setState(() => _isRefreshingAfterDelay = true);
    try {
      await widget.onWorkflowActionCompleted();
      await _loadWorkflowDetail();
    } finally {
      if (mounted) {
        setState(() => _isRefreshingAfterDelay = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final note = (task['note'] ?? task['s_note'] ?? '').toString().trim();
    final taskId = task['id']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final createdAt = task['created_at']?.toString() ?? '';
    final status = normalizeTaskStatusValue(task);
    final statusLabel = workflowStatusDisplayLabel(task);
    final delayGated = isWorkflowDelayGated(task);
    final delayGateData = workflowDelayGate(task);
    final statusColor = delayGated
        ? const Color(0xFF6366F1)
        : _statusColor(status);
    final workflowActions =
        filterVisibleWorkflowActions(task, _workflowActions);
    final title = _taskTitle(note, taskId, _workflowActions);
    final uploadedPhotos = _uploadedPhotos;
    final showApprovalButtons = shouldShowWorkflowApprovalButtons(task);
    final completeAction = _findSwipeCompleteAction(workflowActions);

    final taskUserId =
        (task['user_id'] ?? task['created_by'])?.toString() ?? '';
    final isCreatedByMe =
        _currentUserId != null && taskUserId == _currentUserId;
    final showStatusEditor = !_isWorkflowTask && _statusExpanded;

    final footerChildren = <Widget>[
      if (showStatusEditor) _buildStatusDropdown(taskId, status),
      if (delayGated && delayGateData != null) ...[
        if (showStatusEditor) const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 15, color: statusColor),
            const SizedBox(width: 6),
            WorkflowDelayCountdownText(
              gateData: delayGateData,
              onExpired: _handleDelayExpired,
              style: TextStyle(
                color: statusColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _WorkflowDelayGateCard(
          gateData: delayGateData,
          onExpired: _handleDelayExpired,
        ),
      ],
      if (uploadedPhotos.isNotEmpty) ...[
        if (showStatusEditor || (delayGated && delayGateData != null))
          const SizedBox(height: 10),
        _UploadedPhotosSection(photos: uploadedPhotos),
      ],
      if (_isLoadingWorkflowDetail) ...[
        const SizedBox(height: 10),
        const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
      if (showApprovalButtons) ...[
        const SizedBox(height: 10),
        _WorkflowManagerApprovalSection(
          task: task,
          onActionCompleted: _handleWorkflowActionCompleted,
        ),
      ],
      if (widget.showWorkflowActions &&
          _isWorkflowTask &&
          workflowActions.isNotEmpty) ...[
        const SizedBox(height: 10),
        _WorkflowActionsSection(
          task: task,
          actions: workflowActions,
          onActionCompleted: _handleWorkflowActionCompleted,
          onDelayExpired: _handleDelayExpired,
        ),
      ],
    ];

    return ModernTaskCard(
      title: title,
      projectName: projectName,
      assigneeName: assignedToName,
      dateLabel: createdAt.isNotEmpty ? _formatDate(createdAt) : null,
      status: status,
      statusLabel: statusLabel,
      accentIndex: widget.accentIndex,
      isSelected: widget.isSelected,
      onSwipeComplete: completeAction == null
          ? null
          : () => _handleSwipeComplete(completeAction),
      swipeCompleteLabel: completeAction == null
          ? 'Swipe to complete'
          : _swipeCompleteLabel(completeAction),
      menu: _isWorkflowTask
          ? null
          : PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              iconSize: 20,
              icon: const Icon(Icons.more_horiz_rounded,
                  color: kTaskMuted, size: 20),
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteTask(int.tryParse(taskId) ?? 0);
                } else if (value == 'change_status') {
                  setState(() {
                    _statusExpanded = !_statusExpanded;
                  });
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'change_status',
                  child: Text('Change status'),
                ),
                if (isCreatedByMe)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete task',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
      footer: footerChildren.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: footerChildren,
            ),
    );
  }

  Map<String, dynamic>? _findSwipeCompleteAction(
    List<Map<String, dynamic>> actions,
  ) {
    if (!widget.showWorkflowActions || !_isWorkflowTask) return null;
    if (!canUpdateWorkflowTask(_task)) return null;

    for (final action in actions) {
      if (action['type']?.toString() != 'complete_button') continue;
      if (action['blocked'] == true) continue;
      return action;
    }
    return null;
  }

  String _swipeCompleteLabel(Map<String, dynamic> action) {
    final label = action['label']?.toString().trim() ?? '';
    if (label.isEmpty) return 'Swipe to complete';
    return 'Swipe to ${toSentenceCaseLabel(label).toLowerCase()}';
  }

  String _resolvedWorkflowItemRunIdFor(
    Map<String, dynamic> task,
    Map<String, dynamic> action,
  ) {
    final fromTask = task['workflow_item_run_id']?.toString().trim() ?? '';
    if (fromTask.isNotEmpty) return fromTask;

    final taskId = int.tryParse(task['id']?.toString() ?? '');
    if (taskId != null && taskId < 0) return taskId.abs().toString();

    return action['workflow_item_run_id']?.toString().trim() ?? '';
  }

  Future<bool> _handleSwipeComplete(Map<String, dynamic> action) async {
    if (_isSwipeCompleting) return false;

    final runId = _resolvedWorkflowItemRunIdFor(_task, action);
    final actionId = action['id'];
    if (runId.isEmpty || actionId == null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing workflow item run id.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    setState(() => _isSwipeCompleting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? prefs.getString('user_id');
      final apiToken = prefs.getString('api_token');
      if (userId == null ||
          userId.isEmpty ||
          apiToken == null ||
          apiToken.isEmpty) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final response = await http
          .post(
            Uri.parse(
              '$_workflowApiBaseUrl/API/workflow/item-runs/$runId/complete',
            ),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': apiToken,
            },
            body: jsonEncode({
              'user_id': userId,
              'api_token': apiToken,
              'action_id': actionId,
            }),
          )
          .timeout(const Duration(seconds: 30));

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {}

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'Server error: ${response.statusCode}';
        throw Exception(message);
      }
      if (decoded is Map && decoded['success'] == false) {
        throw Exception(decoded['message'] ?? 'Action failed');
      }

      if (!mounted) return true;
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Workflow task updated';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
      await _handleWorkflowActionCompleted();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSwipeCompleting = false);
    }
  }

  bool get _isWorkflowTask => _task['is_workflow_task'] == true;

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    return TaskStatusChipSet(
      currentStatus: currentStatus,
      enabled: !_isUpdatingStatus,
      onStatusSelected: (newStatus) => _updateTaskStatus(taskId, newStatus),
    );
  }

  Future<void> _deleteTask(int taskId) async {
    if (_isDeleting || taskId <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task'),
        content: const Text(
          'Are you sure you want to delete this task? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiToken = prefs.getString('api_token');
      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final response = await http
          .post(
            Uri.parse('https://office.buildahome.in/API/delete_task'),
            body: {
              'task_id': taskId.toString(),
              'api_token': apiToken,
            },
          )
          .timeout(const Duration(seconds: 20));

      final decoded = response.statusCode == 200 ? jsonDecode(response.body) : null;
      if (decoded is! Map || decoded['success'] != true) {
        throw Exception(
          decoded is Map
              ? (decoded['message'] ?? 'Failed to delete task')
              : 'Unable to delete task (code ${response.statusCode})',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await widget.onWorkflowActionCompleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _updateTaskStatus(int taskId, String newStatus) async {
    if (_isUpdatingStatus || taskId <= 0) return;

    setState(() => _isUpdatingStatus = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiToken = prefs.getString('api_token');
      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final response = await http
          .post(
            Uri.parse('https://office.buildahome.in/API/update_task_status'),
            body: {
              'task_id': taskId.toString(),
              'status': newStatus,
              'api_token': apiToken,
            },
          )
          .timeout(const Duration(seconds: 20));

      final decoded = response.statusCode == 200 ? jsonDecode(response.body) : null;
      if (decoded is! Map || decoded['success'] != true) {
        throw Exception(
          decoded is Map
              ? (decoded['message'] ?? 'Failed to update status')
              : 'Unable to update status (code ${response.statusCode})',
        );
      }

      if (!mounted) return;
      setState(() {
        _task = Map<String, dynamic>.from(_task)..['status'] = newStatus;
        _statusExpanded = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status updated'),
          backgroundColor: Colors.green,
        ),
      );
      await widget.onWorkflowActionCompleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  List<Map<String, dynamic>> get _workflowActions {
    // Prefer workflow_actions from GET .../item-runs/{id}/actions (merged in
    // mergeWorkflowTaskDetail) over list payload workflow_task_actions, which
    // may carry stale site_location coordinates for near-site upload.
    final fromDetailApi = _mapListFlexible(_task['workflow_actions']);
    if (fromDetailApi.isNotEmpty) return fromDetailApi;

    final fromListPayload = _mapListFlexible(_task['workflow_task_actions']);
    if (fromListPayload.isNotEmpty) return fromListPayload;

    return <Map<String, dynamic>>[];
  }

  String _taskTitle(
    String note,
    String taskId,
    List<Map<String, dynamic>> workflowActions,
  ) {
    final baseTitle = note.isNotEmpty ? _toSentenceCase(note) : 'Task #$taskId';
    final followupItem = _checklistFollowupItemLabel(workflowActions);

    if (followupItem == null || followupItem.isEmpty) return baseTitle;
    if (baseTitle.toLowerCase().contains(followupItem.toLowerCase())) {
      return baseTitle;
    }

    return '$baseTitle — $followupItem';
  }

  String? _checklistFollowupItemLabel(
    List<Map<String, dynamic>> workflowActions,
  ) {
    for (final action in workflowActions) {
      if (action['type']?.toString() != 'user_checklist_followup') continue;

      final directItems = _mapListFlexible(action['items']);
      if (directItems.isNotEmpty) {
        final label =
            _firstString(directItems.first, ['label', 'name', 'title']);
        if (label != null) return label;
      }

      final priorChecklist = _configMap(action['prior_checklist']);
      final priorItems = _mapListFlexible(priorChecklist?['items']);
      if (priorItems.isNotEmpty) {
        final label =
            _firstString(priorItems.first, ['label', 'name', 'title']);
        if (label != null) return label;
      }
    }

    return null;
  }

  List<String> get _uploadedPhotos => _taskUploadedPhotoUrls(_task);

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'done':
      case 'finished':
      case 'skipped':
        return const Color(0xFF047857);
      case 'in_progress':
      case 'ready':
        return AppTheme.accentBlue;
      case 'waiting_approval':
      case 'scheduled':
        return AppTheme.navySoft;
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFFB45309);
    }
  }

  String _formatDate(String value) {
    try {
      final parsed = DateTime.parse(value);
      return DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
    } catch (_) {
      return value;
    }
  }

  String _toSentenceCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

String _resolvedWorkflowItemRunIdFromTask(Map<String, dynamic> task) {
  final directId = task['workflow_item_run_id']?.toString().trim() ?? '';
  if (directId.isNotEmpty) return directId;

  final taskId = int.tryParse(task['id']?.toString() ?? '');
  if (taskId != null && taskId < 0) return taskId.abs().toString();

  return '';
}

class WorkflowDelayCountdownText extends StatefulWidget {
  final Map<String, dynamic> gateData;
  final TextStyle style;
  final VoidCallback? onExpired;

  const WorkflowDelayCountdownText({
    super.key,
    required this.gateData,
    required this.style,
    this.onExpired,
  });

  @override
  State<WorkflowDelayCountdownText> createState() =>
      _WorkflowDelayCountdownTextState();
}

class _WorkflowDelayCountdownTextState extends State<WorkflowDelayCountdownText> {
  Timer? _timer;
  late int _remainingSeconds;
  bool _expiredHandled = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = workflowDelayRemainingSeconds(widget.gateData);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant WorkflowDelayCountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateData != widget.gateData) {
      _remainingSeconds = workflowDelayRemainingSeconds(widget.gateData);
      _expiredHandled = false;
    }
  }

  void _tick() {
    if (!mounted) return;
    final next = workflowDelayRemainingSeconds(widget.gateData);
    setState(() => _remainingSeconds = next);
    if (next <= 0 && !_expiredHandled) {
      _expiredHandled = true;
      widget.onExpired?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.gateData['countdown_label']?.toString().trim();
    final label = _remainingSeconds > 0
        ? formatWorkflowCountdown(_remainingSeconds)
        : (fallback != null && fallback.isNotEmpty ? fallback : '0d 0h 0m');

    return Text(label, style: widget.style);
  }
}

class _WorkflowDelayGateCard extends StatelessWidget {
  final Map<String, dynamic> gateData;
  final bool compact;
  final VoidCallback? onExpired;

  const _WorkflowDelayGateCard({
    required this.gateData,
    this.compact = false,
    this.onExpired,
  });

  @override
  Widget build(BuildContext context) {
    final heading = gateData['heading']?.toString().trim();
    final title = heading != null && heading.isNotEmpty
        ? heading
        : 'Waiting to start';
    final message = gateData['message']?.toString().trim() ?? '';
    final unlocksAt = gateData['available_at_display']?.toString().trim() ?? '';
    final accent = const Color(0xFF6366F1);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 40 : 44,
            height: compact ? 40 : 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: accent,
              size: compact ? 20 : 22,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkflowDelayCountdownText(
                  gateData: gateData,
                  onExpired: onExpired,
                  style: TextStyle(
                    color: _premiumInk,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (!compact && title.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      color: _premiumMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (message.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Text(
                    message,
                    style: TextStyle(
                      color: _premiumMuted,
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
                if (unlocksAt.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Text(
                    'Unlocks at $unlocksAt',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

class _WorkflowManagerApprovalSection extends StatefulWidget {
  final Map<String, dynamic> task;
  final Future<void> Function() onActionCompleted;

  const _WorkflowManagerApprovalSection({
    required this.task,
    required this.onActionCompleted,
  });

  @override
  State<_WorkflowManagerApprovalSection> createState() =>
      _WorkflowManagerApprovalSectionState();
}

class _WorkflowManagerApprovalSectionState
    extends State<_WorkflowManagerApprovalSection> {
  bool _isApproving = false;
  bool _isRejecting = false;

  Future<void> _showSnackBar(String message, {bool isError = false}) async {
    if (!mounted) return;
    final cleaned = message.replaceAll('Exception: ', '').trim();
    if (cleaned.isEmpty) return;
    if (cleaned == SessionManager.logoutMessage ||
        cleaned.toLowerCase().contains('invalid api token') ||
        cleaned.toLowerCase().contains('signed in on another device') ||
        cleaned.toLowerCase().contains('two devices')) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cleaned),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _submitDecision({
    required bool approve,
    String note = '',
  }) async {
    final runId = _resolvedWorkflowItemRunIdFromTask(widget.task);
    if (runId.isEmpty) {
      await _showSnackBar('Missing workflow item run id.', isError: true);
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId =
          prefs.getString('userId') ?? prefs.getString('user_id') ?? '';
      final apiToken = prefs.getString('api_token') ?? '';
      if (userId.isEmpty || apiToken.isEmpty) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final endpoint = approve
          ? '/API/workflow/item-runs/$runId/approve'
          : '/API/workflow/item-runs/$runId/reject';
      final payload = <String, dynamic>{
        'user_id': userId,
        'api_token': apiToken,
      };
      if (approve) {
        if (note.trim().isNotEmpty) payload['comments'] = note.trim();
      } else if (note.trim().isNotEmpty) {
        payload['reason'] = note.trim();
      }

      final response = await ApiHttp.post(
            Uri.parse('$_workflowApiBaseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': apiToken,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {}

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map && decoded['success'] == false) {
          throw Exception(decoded['message'] ?? 'Action failed');
        }
        final message = decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : approve
                ? 'Task approved and completed.'
                : 'Task rejected.';
        await _showSnackBar(message);
        await widget.onActionCompleted();
        return true;
      }

      if (decoded is Map && decoded['message'] != null) {
        throw Exception(decoded['message']);
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      await _showSnackBar(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
      return false;
    }
  }

  Future<void> _handleApprove() async {
    if (_isApproving || _isRejecting) return;

    final confirmed = await _confirmAction(
      title: 'Approve task',
      message: 'Approve this task and mark it as completed?',
      confirmLabel: 'Approve',
      confirmColor: AppTheme.primaryColorConst,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isApproving = true;
    });

    await _submitDecision(approve: true);

    if (mounted) {
      setState(() {
        _isApproving = false;
      });
    }
  }

  Future<void> _handleReject() async {
    if (_isApproving || _isRejecting) return;

    final reasonController = TextEditingController();
    final rejected = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reject task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The assignee may need to redo this work.'),
            SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Color(0xFFEF4444)),
            child: Text('Reject'),
          ),
        ],
      ),
    );

    if (rejected != true || !mounted) {
      reasonController.dispose();
      return;
    }

    setState(() {
      _isRejecting = true;
    });

    await _submitDecision(approve: false, note: reasonController.text.trim());
    reasonController.dispose();

    if (mounted) {
      setState(() {
        _isRejecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fact_check_outlined, size: 18, color: _premiumInk),
            SizedBox(width: 8),
            Text(
              'Manager review',
              style: TextStyle(
                color: _premiumInk,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isApproving || _isRejecting ? null : _handleApprove,
                  icon: _isApproving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(_isApproving ? 'Approving...' : 'Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColorConst,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isApproving || _isRejecting ? null : _handleReject,
                  icon: _isRejecting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.close_rounded, size: 18),
                  label: Text(_isRejecting ? 'Rejecting...' : 'Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFB91C1C)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkflowActionsSection extends StatelessWidget {
  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> actions;
  final Future<void> Function() onActionCompleted;
  final VoidCallback? onDelayExpired;

  const _WorkflowActionsSection({
    required this.task,
    required this.actions,
    required this.onActionCompleted,
    this.onDelayExpired,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_motion_outlined,
              size: 18,
              color: _premiumInk,
            ),
            SizedBox(width: 8),
            Text(
              'Actions',
              style: TextStyle(
                color: _premiumInk,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions
              .map(
                (action) => WorkflowActionButton(
                  task: task,
                  action: action,
                  onActionCompleted: onActionCompleted,
                  onDelayExpired: onDelayExpired,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _UploadedPhotosSection extends StatelessWidget {
  final List<String> photos;

  const _UploadedPhotosSection({required this.photos});

  void _openPhotoViewer(BuildContext context, int initialIndex) {
    if (photos.isEmpty) return;
    final resolved = photos.map(_resolveTaskPhotoUrl).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImage(
          resolved[initialIndex.clamp(0, resolved.length - 1)],
          imageUrls: resolved,
          initialIndex: initialIndex.clamp(0, resolved.length - 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visiblePhotos = photos.take(3).toList();
    final remainingCount = photos.length - visiblePhotos.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library_outlined, size: 18, color: _premiumInk),
            SizedBox(width: 8),
            Text(
              'Uploaded Photos (${photos.length})',
              style: TextStyle(
                color: _premiumInk,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            if (photos.isNotEmpty) ...[
              Spacer(),
              TextButton(
                onPressed: () => _openPhotoViewer(context, 0),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View all',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 12),
        if (photos.isEmpty)
          Text(
            'No uploads yet',
            style: TextStyle(
              color: _premiumMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          SizedBox(
            height: 58,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ...visiblePhotos.asMap().entries.map(
                      (entry) => Positioned(
                        left: entry.key * 44.0,
                        child: _UploadThumbnail(
                          url: entry.value,
                          onTap: () => _openPhotoViewer(context, entry.key),
                        ),
                      ),
                    ),
                if (remainingCount > 0)
                  Positioned(
                    left: visiblePhotos.length * 44.0,
                    child: GestureDetector(
                      onTap: () => _openPhotoViewer(context, 3),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _premiumInk,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '+$remainingCount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String _resolveTaskPhotoUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.startsWith('/')) return '$_workflowApiBaseUrl$trimmed';
  return trimmed;
}

class _UploadThumbnail extends StatelessWidget {
  final String url;
  final VoidCallback? onTap;

  const _UploadThumbnail({
    required this.url,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: _premiumBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildImage(),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final resolvedUrl = _resolveTaskPhotoUrl(url);
    final uri = Uri.tryParse(resolvedUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Image.network(
        resolvedUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }

    final file = File(url);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }

    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Center(
      child: Icon(Icons.image_outlined, color: _premiumMuted, size: 22),
    );
  }
}

class WorkflowActionButton extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic> action;
  final Future<void> Function() onActionCompleted;
  final VoidCallback? onDelayExpired;
  final bool expand;

  const WorkflowActionButton({
    Key? key,
    required this.task,
    required this.action,
    required this.onActionCompleted,
    this.onDelayExpired,
    this.expand = false,
  }) : super(key: key);

  @override
  State<WorkflowActionButton> createState() => _WorkflowActionButtonState();
}

class _WorkflowActionButtonState extends State<WorkflowActionButton> {
  bool _isSubmitting = false;
  bool _loggedViewPriorResponseConfig = false;
  bool _loggedChecklistFollowupConfig = false;
  bool _loggedSlotConfirmationConfig = false;

  Map<String, dynamic> get action => widget.action;
  Map<String, dynamic> get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final type = _actionType;

    if (type == 'delay_timer') {
      final gateData = resolveWorkflowDelayGateData(
        gate: workflowDelayGate(task),
        action: action,
      );
      return SizedBox(
        width: widget.expand ? double.infinity : null,
        child: _WorkflowDelayGateCard(
          gateData: gateData,
          compact: true,
          onExpired: widget.onDelayExpired,
        ),
      );
    }

    final taskBlocked = !canUpdateWorkflowTask(task);
    final blocked = action['blocked'] == true || taskBlocked;
    final buttonData = _buttonData(type);

    if (buttonData == null) {
      return _ActionChipButton(
        label: _label('Unsupported'),
        icon: Icons.block,
        color: Colors.grey,
        isOutlined: true,
        expand: widget.expand,
        onPressed: null,
        blockedMessage: 'Unsupported action type: $type',
      );
    }

    return _ActionChipButton(
      label: type == 'user_checklist_followup'
          ? 'Checklist follow-up'
          : _label(buttonData.defaultLabel),
      icon: buttonData.icon,
      color: buttonData.color,
      isOutlined: buttonData.outlined,
      isLoading: _isSubmitting,
      expand: widget.expand,
      onPressed: blocked || _isSubmitting ? null : () => _handleTap(type),
      blockedMessage: blocked ? _blockedMessageForAction(taskBlocked) : null,
    );
  }

  String _blockedMessageForAction(bool taskBlocked) {
    if (action['blocked_message']?.toString().trim().isNotEmpty == true) {
      return action['blocked_message'].toString().trim();
    }
    if (taskBlocked) {
      final gateMessage = workflowDelayGate(task)?['message']?.toString().trim();
      if (gateMessage != null && gateMessage.isNotEmpty) return gateMessage;
    }
    return 'This action is blocked.';
  }

  String get _actionType => action['type']?.toString() ?? '';
  String get _workflowItemRunId =>
      task['workflow_item_run_id']?.toString() ?? '';
  String get _resolvedWorkflowItemRunId {
    if (_workflowItemRunId.trim().isNotEmpty) return _workflowItemRunId;

    final taskId = int.tryParse(task['id']?.toString() ?? '');
    if (taskId != null && taskId < 0) return taskId.abs().toString();

    final actionItemRunId =
        action['workflow_item_run_id']?.toString().trim() ?? '';
    if (actionItemRunId.isNotEmpty) return actionItemRunId;

    return '';
  }

  String _label(String fallback) {
    final label = action['label']?.toString().trim() ?? '';
    return toSentenceCaseLabel(label.isEmpty ? fallback : label);
  }

  dynamic _slotActionValue(String key, {Map<String, dynamic>? source}) {
    final actionMap = source ?? action;
    final directValue = actionMap[key];
    if (!_isBlankConfigValue(directValue)) return directValue;

    for (final configKey in const [
      'config',
      'action_config',
      'task_action_config',
      'settings',
    ]) {
      final config = _configMap(actionMap[configKey]);
      if (config == null) continue;
      final value = config[key];
      if (!_isBlankConfigValue(value)) return value;
    }

    return null;
  }

  Future<Map<String, dynamic>> _resolveFreshUploadAction() async {
    final loaded = await _loadFreshWorkflowActionContext();
    return loaded.action;
  }

  Future<_FreshWorkflowActionContext> _loadFreshWorkflowActionContext() async {
    final actionId = action['id']?.toString() ?? '';
    final runId = _resolvedWorkflowItemRunId;
    if (runId.isEmpty) {
      return _FreshWorkflowActionContext(action: action);
    }

    try {
      final credentials = await _credentials();
      final uri = Uri.parse(
        '$_workflowApiBaseUrl/API/workflow/item-runs/$runId/actions',
      ).replace(
        queryParameters: {
          'user_id': credentials.userId,
          'api_token': credentials.apiToken,
        },
      );

      final response = await ApiHttp.get(
            uri,
            headers: {'X-Api-Token': credentials.apiToken},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        print(
          '[WorkflowActions] refresh_failed '
          'item_run_id=$runId status=${response.statusCode}',
        );
        return _FreshWorkflowActionContext(action: action);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] == false) {
        return _FreshWorkflowActionContext(action: action);
      }

      bool? canUpdate;
      if (decoded.containsKey('can_update') ||
          decoded.containsKey('can_update_workflow_task') ||
          decoded.containsKey('workflow_delay_gate')) {
        final probeTask = Map<String, dynamic>.from(task);
        if (decoded['can_update'] != null) {
          probeTask['can_update'] = decoded['can_update'];
        }
        if (decoded['can_update_workflow_task'] != null) {
          probeTask['can_update_workflow_task'] =
              decoded['can_update_workflow_task'];
        }
        if (decoded['workflow_delay_gate'] != null) {
          probeTask['workflow_delay_gate'] = decoded['workflow_delay_gate'];
        }
        canUpdate = canUpdateWorkflowTask(probeTask);
      }

      for (final listKey in const [
        'workflow_actions',
        'workflow_task_actions',
        'actions',
      ]) {
        final actions = _mapListFlexible(decoded[listKey]);
        for (final item in actions) {
          if (item['id']?.toString() == actionId) {
            print(
              '[WorkflowActions] refresh_ok '
              'item_run_id=$runId source=$listKey action_id=$actionId '
              'submit_endpoint=${item['submit_endpoint']} '
              'can_update=$canUpdate',
            );
            return _FreshWorkflowActionContext(
              action: Map<String, dynamic>.from(item),
              canUpdate: canUpdate,
            );
          }
        }
      }
    } catch (e) {
      print('[WorkflowActions] refresh_failed item_run_id=$runId error=$e');
    }

    return _FreshWorkflowActionContext(action: action);
  }

  _WorkflowButtonData? _buttonData(String type) {
    // Muted, navy-family tones that match AppTheme (avoid neon fills).
    const success = Color(0xFF047857);
    const warn = Color(0xFFB45309);
    const info = AppTheme.accentBlue;
    const primary = AppTheme.primaryColorConst;
    const secondary = AppTheme.navySoft;
    const tertiary = Color(0xFF334155);

    switch (type) {
      case 'upload':
        return _WorkflowButtonData(
          defaultLabel: 'Upload file',
          icon: Icons.upload_file,
          color: warn,
        );
      case 'complete_button':
        return _WorkflowButtonData(
          defaultLabel: 'Complete task',
          icon: Icons.check_circle,
          color: success,
        );
      case 'update_status':
        return _WorkflowButtonData(
          defaultLabel: 'Update status',
          icon: Icons.sync,
          color: info,
        );
      case 'yes_no':
        return _WorkflowButtonData(
          defaultLabel: 'Yes / no',
          icon: Icons.rule,
          color: secondary,
        );
      case 'checklist':
        return _WorkflowButtonData(
          defaultLabel: 'Checklist',
          icon: Icons.checklist,
          color: primary,
        );
      case 'user_checklist':
        return _WorkflowButtonData(
          defaultLabel: 'User checklist',
          icon: Icons.playlist_add_check,
          color: secondary,
        );
      case 'user_checklist_followup':
        return _WorkflowButtonData(
          defaultLabel: 'Checklist follow-up',
          icon: Icons.assignment_turned_in_outlined,
          color: info,
        );
      case 'slot_selection':
        return _WorkflowButtonData(
          defaultLabel: 'Select slots',
          icon: Icons.event_available_outlined,
          color: info,
        );
      case 'slot_confirmation':
        return _WorkflowButtonData(
          defaultLabel: 'Confirm slot',
          icon: Icons.event_available_outlined,
          color: success,
        );
      case 'kyp_material_shift':
        return _WorkflowButtonData(
          defaultLabel: 'Shift material',
          icon: Icons.move_up_outlined,
          color: tertiary,
        );
      case 'redirect_button':
        return _WorkflowButtonData(
          defaultLabel: 'Open',
          icon: Icons.open_in_new,
          color: primary,
        );
      case 'view_prior_response':
      case 'yes_no_summary':
      case 'user_checklist_summary':
      case 'text_list_summary':
      case 'material_shift_summary':
        return _WorkflowButtonData(
          defaultLabel: 'View response',
          icon: Icons.visibility_outlined,
          color: AppTheme.mutedGrey,
          outlined: true,
        );
      case 'text_list':
        return _WorkflowButtonData(
          defaultLabel: 'Material request',
          icon: Icons.format_list_bulleted,
          color: info,
        );
      case 'picture_choice_list':
        return _WorkflowButtonData(
          defaultLabel: 'Send options to client',
          icon: Icons.palette_outlined,
          color: secondary,
        );
      case 'picture_choice_pick':
        return _WorkflowButtonData(
          defaultLabel: 'Submit choice',
          icon: Icons.color_lens_outlined,
          color: primary,
        );
      default:
        return null;
    }
  }

  Future<void> _handleTap(String type) async {
    if (!canUpdateWorkflowTask(task) || action['blocked'] == true) {
      _showSnackBar(_blockedMessageForAction(true), isError: true);
      return;
    }

    if (_resolvedWorkflowItemRunId.isEmpty) {
      _showSnackBar('Missing workflow item run id.', isError: true);
      return;
    }

    switch (type) {
      case 'upload':
        await _showUploadSheet();
        break;
      case 'complete_button':
        await _submitComplete();
        break;
      case 'update_status':
        await _showStatusSheet();
        break;
      case 'yes_no':
        await _showYesNoSheet();
        break;
      case 'checklist':
        await _showChecklistSheet();
        break;
      case 'user_checklist':
        await _showUserChecklistSheet();
        break;
      case 'user_checklist_followup':
        await _showUserChecklistFollowupSheet();
        break;
      case 'slot_selection':
        await _showSlotSelectionSheet();
        break;
      case 'slot_confirmation':
        await _showSlotConfirmationSheet();
        break;
      case 'kyp_material_shift':
        await _showKypMaterialShiftSheet();
        break;
      case 'redirect_button':
        await _openRedirect();
        break;
      case 'view_prior_response':
      case 'yes_no_summary':
      case 'user_checklist_summary':
      case 'text_list_summary':
      case 'material_shift_summary':
        await _showResponseSheet();
        break;
      case 'text_list':
        await _showTextListSheet();
        break;
      case 'picture_choice_list':
        await _showPictureChoiceListSheet();
        break;
      case 'picture_choice_pick':
        await _showPictureChoicePickSheet();
        break;
    }
  }

  Future<_WorkflowCredentials> _credentials() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? prefs.getString('user_id');
    final apiToken = prefs.getString('api_token');

    if (userId == null ||
        userId.isEmpty ||
        apiToken == null ||
        apiToken.isEmpty) {
      throw Exception('Missing credentials. Please log in again.');
    }

    return _WorkflowCredentials(userId: userId, apiToken: apiToken);
  }

  Future<bool> _submitJson({
    required String endpoint,
    required Map<String, dynamic> payload,
    String successMessage = 'Action completed successfully',
    bool refreshOnSuccess = true,
  }) async {
    if (!canUpdateWorkflowTask(task) || action['blocked'] == true) {
      _showSnackBar(_blockedMessageForAction(true), isError: true);
      return false;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final credentials = await _credentials();
      final response = await ApiHttp.post(
            Uri.parse('$_workflowApiBaseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': credentials.apiToken,
            },
            body: jsonEncode({
              'user_id': credentials.userId,
              'api_token': credentials.apiToken,
              ...payload,
            }),
          )
          .timeout(Duration(seconds: 30));
      print(
        '[WorkflowSubmit] endpoint=$endpoint '
        'payload=$payload '
        'status=${response.statusCode} '
        'body=${response.body}',
      );

      final message = _successMessageOrThrow(response, successMessage);
      _showSnackBar(message);
      if (refreshOnSuccess) {
        await widget.onActionCompleted();
      }
      return true;
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<bool> _submitComplete({
    String? decision,
    String? note,
    bool refreshOnSuccess = true,
  }) async {
    final payload = <String, dynamic>{
      'action_id': action['id'],
    };
    if (decision != null) payload['decision'] = decision;
    if (note != null) payload['note'] = note;

    return _submitJson(
      endpoint: '/API/workflow/item-runs/$_resolvedWorkflowItemRunId/complete',
      payload: payload,
      successMessage: 'Workflow task updated',
      refreshOnSuccess: refreshOnSuccess,
    );
  }

  Future<bool> _submitViewPriorResponseApproval({
    required String comment,
  }) async {
    return _submitJson(
      endpoint: '/API/workflow/item-runs/$_resolvedWorkflowItemRunId/complete',
      payload: {
        'action_id': action['id']?.toString() ?? '',
        'workflow_action_id': action['id']?.toString() ?? '',
        'decision': 'approved',
        'note': comment,
        'comment': comment,
      },
      successMessage: 'Approved successfully',
      refreshOnSuccess: false,
    );
  }

  String _workflowActionSubmitEndpoint(String fallbackActionPath) {
    final configured = action['submit_endpoint']?.toString().trim() ?? '';
    if (configured.isNotEmpty) return configured;
    return '/API/workflow/item-runs/$_resolvedWorkflowItemRunId/'
        '$fallbackActionPath';
  }

  void _logIndentsCreated(http.Response response, String tag) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['indents_created'] is List) {
        final indents = decoded['indents_created'] as List;
        print('[$tag] indents_created=${indents.length} indents=$indents');
      }
    } catch (_) {}
  }

  Future<bool> _submitTextList({
    required Map<String, dynamic> textListAction,
    required List<Map<String, dynamic>> customLines,
    required Map<String, Map<String, String>> lineQuantities,
  }) async {
    final endpoint = _submitEndpointForAction(textListAction, 'text-list');
    final actionId = textListAction['id']?.toString() ?? '';

    try {
      final credentials = await _credentials();
      final payload = <String, dynamic>{
        'user_id': credentials.userId,
        'api_token': credentials.apiToken,
        'action_id': actionId,
      };
      if (customLines.isNotEmpty) {
        payload['custom_lines'] = customLines;
      }
      if (lineQuantities.isNotEmpty) {
        payload['line_quantities'] = lineQuantities;
      }

      final response = await ApiHttp.post(
            Uri.parse(_absoluteWorkflowUrl(endpoint)),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': credentials.apiToken,
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: 30));
      print(
        '[WorkflowTextList] endpoint=$endpoint '
        'payload=$payload '
        'status=${response.statusCode} '
        'response=${response.body}',
      );
      _logIndentsCreated(response, 'WorkflowTextList');

      final message = _workflowSuccessMessage(
        response,
        'Material request submitted',
      );
      _showSnackBar(message);
      return true;
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return false;
    }
  }

  List<Map<String, dynamic>> get _checklistFollowupItems {
    final directItems = _mapListFlexible(action['items']);
    if (directItems.isNotEmpty) return directItems;

    final priorChecklist = _configMap(action['prior_checklist']);
    final priorItems = _mapListFlexible(priorChecklist?['items']);
    if (priorItems.isNotEmpty) return priorItems;

    return <Map<String, dynamic>>[];
  }

  Future<void> _showUserChecklistFollowupSheet() async {
    final items = _checklistFollowupItems;
    final responseMode =
        action['response_mode']?.toString().trim().toLowerCase() ?? '';
    final requireComment = action['require_comment_per_item'] == true;
    final requireDocument = action['require_document_per_item'] == true;
    final allowComment = action['allow_comment_per_item'] == true;
    final showDocument =
        requireDocument || responseMode == 'document' || responseMode == 'both';
    final showComment = requireComment ||
        allowComment ||
        responseMode == 'comment' ||
        responseMode == 'both' ||
        responseMode.isEmpty ||
        showDocument;
    final uploadSources = _resolveWorkflowUploadSources(
      action,
      allowedFormats: _stringList(action['allowed_formats']),
    );
    final allowedFormats = uploadSources.allAllowedFormats.isNotEmpty
        ? uploadSources.allAllowedFormats
        : _stringList(action['allowed_formats']);
    final submitLabel =
        action['submit_button_label']?.toString().trim().isNotEmpty == true
            ? action['submit_button_label'].toString().trim()
            : 'Submit responses';

    _logChecklistFollowupConfig();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: 'Checklist follow-up',
        icon: Icons.assignment_turned_in_outlined,
        child: _UserChecklistFollowupSheet(
          items: items,
          allowedFormats: allowedFormats,
          uploadSources: uploadSources,
          requireComment: requireComment,
          requireDocument: requireDocument,
          showComment: showComment,
          showDocument: showDocument,
          submitLabel: submitLabel,
          onSubmit: _submitUserChecklistFollowup,
        ),
      ),
    );

    if (submitted == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  Future<void> _showSlotConfirmationSheet() async {
    final slots = _mapListFlexible(action['slots']);
    final priorSelection = _configMap(action['prior_slot_selection']);
    final priorSlots = _mapListFlexible(priorSelection?['slots']);
    final availableSlots = slots.isNotEmpty ? slots : priorSlots;
    final allowNote = action['allow_note'] == true;
    final requireNote = action['require_note'] == true;
    final submitLabel =
        action['submit_button_label']?.toString().trim().isNotEmpty == true
            ? action['submit_button_label'].toString().trim()
            : 'Confirm slot';
    final title = action['heading']?.toString().trim().isNotEmpty == true
        ? action['heading'].toString().trim()
        : _label('Confirm slot');

    _logSlotConfirmationConfig();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: title,
        icon: Icons.event_available_outlined,
        child: _SlotConfirmationSheet(
          slots: availableSlots,
          priorSelection: priorSelection,
          allowNote: allowNote,
          requireNote: requireNote,
          submitLabel: submitLabel,
          onSubmit: _submitSlotConfirmation,
          onSelectedForDebug: (slotIndex) {
            print(
              '[SlotConfirmation] selected_accepted_slot_index=$slotIndex',
            );
          },
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  void _logSlotConfirmationConfig() {
    if (_loggedSlotConfirmationConfig) return;
    _loggedSlotConfirmationConfig = true;
    print(
      '[SlotConfirmation] task_id=${task['id']} '
      'action_id=${action['id']} '
      'type=${action['type']} '
      'slots=${action['slots']} '
      'prior_slot_selection=${action['prior_slot_selection']}',
    );
  }

  Future<bool> _submitSlotConfirmation({
    required int acceptedSlotIndex,
    required String comment,
  }) async {
    final priorSelection = _configMap(action['prior_slot_selection']);
    final directSlots = _mapListFlexible(action['slots']);
    final priorSlots = _mapListFlexible(priorSelection?['slots']);
    final availableSlots = directSlots.isNotEmpty ? directSlots : priorSlots;
    final acceptedSlot = _slotByIndex(availableSlots, acceptedSlotIndex);
    final payload = <String, dynamic>{
      'action_id': action['id']?.toString() ?? '',
      'accepted_slot_index': acceptedSlotIndex,
      'note': comment,
      'comment': comment,
    };
    if (acceptedSlot != null) {
      payload['accepted_slot'] = acceptedSlot;
    }
    if (priorSelection != null) {
      for (final key in const [
        'source_item_run_id',
        'source_action_id',
        'source_node_key',
      ]) {
        final value = priorSelection[key];
        if (!_isBlankConfigValue(value)) {
          payload[key] = value;
        }
      }
    }

    return _submitJson(
      endpoint:
          '/API/workflow/item-runs/$_resolvedWorkflowItemRunId/slot-confirmation',
      payload: payload,
      successMessage: 'Slot confirmed',
      refreshOnSuccess: false,
    );
  }

  Future<_KypMaterialShiftSubmitResult?> _submitKypMaterialShift({
    required String fromProjectId,
    required List<Map<String, dynamic>> materials,
    String? shiftingDate,
    String? differenceCost,
  }) async {
    final submitEndpoint = _workflowActionSubmitEndpoint('material-shift');

    try {
      final credentials = await _credentials();
      final payload = <String, dynamic>{
        'user_id': int.tryParse(credentials.userId) ?? credentials.userId,
        'api_token': credentials.apiToken,
        'action_id': action['id']?.toString() ?? '',
        'from_project_id':
            int.tryParse(fromProjectId) ?? fromProjectId,
        'materials': materials,
        'difference_cost':
            double.tryParse(differenceCost?.trim() ?? '') ?? 0,
      };
      if (shiftingDate != null && shiftingDate.trim().isNotEmpty) {
        payload['shifting_date'] = shiftingDate.trim();
      }
      final indentPurpose =
          _actionConfigValue('indent_purpose')?.toString().trim() ?? '';
      if (indentPurpose.isNotEmpty) {
        payload['indent_purpose'] = indentPurpose;
      }

      final response = await ApiHttp.post(
            Uri.parse(_absoluteWorkflowUrl(submitEndpoint)),
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': credentials.apiToken,
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: 30));
      print(
        '[KypMaterialShift] endpoint=$submitEndpoint '
        'payload=$payload '
        'status=${response.statusCode} '
        'response=${response.body}',
      );
      _logIndentsCreated(response, 'KypMaterialShift');

      final message = _successMessageOrThrow(
        response,
        'Shift request recorded',
      );
      _showSnackBar(message);

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }

      List<Map<String, dynamic>> finalList = [];
      var taskRouted = false;
      if (decoded is Map) {
        finalList = _mapListFlexible(decoded['final_list']);
        taskRouted = decoded['task_routed'] == true;
      }

      return _KypMaterialShiftSubmitResult(
        finalList: finalList,
        taskRouted: taskRouted,
      );
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return null;
    }
  }

  Future<void> _showKypMaterialShiftSheet() async {
    final materials = _kypMaterialShiftItems(action);
    final title = action['heading']?.toString().trim().isNotEmpty == true
        ? action['heading'].toString().trim()
        : _label('Shift material');
    final submitLabel =
        action['submit_button_label']?.toString().trim().isNotEmpty == true
            ? action['submit_button_label'].toString().trim()
            : 'Submit shift request';
    final destinationProjectId =
        action['to_project_id']?.toString().trim().isNotEmpty == true
            ? action['to_project_id'].toString().trim()
            : task['project_id']?.toString() ?? '';
    final destinationProjectName = _firstString(action, [
          'to_project_name',
          'destination_project_name',
        ]) ??
        (task['project_name']?.toString().trim().isNotEmpty == true
            ? task['project_name'].toString().trim()
            : 'Destination project');
    final finalListTitle =
        action['final_list_title']?.toString().trim().isNotEmpty == true
            ? action['final_list_title'].toString().trim()
            : 'Final list';
    final finalListHelp =
        action['final_list_help']?.toString().trim().isNotEmpty == true
            ? action['final_list_help'].toString().trim()
            : 'Remaining quantity after shift (standard minus shift qty).';
    final initialFinalList = _mapListFlexible(action['final_list']);
    final response = _configMap(action['response']);
    final submittedMaterials = response == null
        ? <Map<String, dynamic>>[]
        : _mapListFlexible(response['materials']);
    final isReadOnly =
        submittedMaterials.isNotEmpty || response?['message'] != null;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: title,
        icon: Icons.move_up_outlined,
        child: isReadOnly
            ? _KypMaterialShiftReadOnlyView(
                response: response ?? {},
                destinationProjectId: destinationProjectId,
                destinationProjectName: destinationProjectName,
                finalListTitle: finalListTitle,
                finalListHelp: finalListHelp,
                actionFinalList: initialFinalList,
              )
            : _KypMaterialShiftSheet(
                materials: materials,
                destinationProjectId: destinationProjectId,
                destinationProjectName: destinationProjectName,
                submitLabel: submitLabel,
                finalListTitle: finalListTitle,
                finalListHelp: finalListHelp,
                initialFinalList: initialFinalList,
                draftFromProjectId:
                    action['from_project_id']?.toString().trim(),
                onSubmit: _submitKypMaterialShift,
              ),
      ),
    );

    if (submitted == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  void _logChecklistFollowupConfig() {
    if (_loggedChecklistFollowupConfig) return;
    _loggedChecklistFollowupConfig = true;
    final directItems = _mapListFlexible(action['items']);
    final priorChecklist = _configMap(action['prior_checklist']);
    final priorItems = _mapListFlexible(priorChecklist?['items']);
    final firstItem = directItems.isNotEmpty
        ? directItems.first
        : priorItems.isNotEmpty
            ? priorItems.first
            : null;
    final firstItemAttachmentFields = firstItem == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.fromEntries(
            firstItem.entries.where(
              (entry) => const {
                'image',
                'file',
                'files',
                'attachments',
                'uploaded_file',
                'uploaded_files',
              }.contains(entry.key),
            ),
          );
    final normalizedAttachments = firstItem == null
        ? <Map<String, dynamic>>[]
        : _followupItemFiles(firstItem);

    print(
      '[UserChecklistFollowup] task_id=${task['id']} '
      'resolved_item_run_id=$_resolvedWorkflowItemRunId '
      'action_id=${action['id']} '
      'type=${action['type']} '
      'items=${action['items']} '
      'prior_checklist=${action['prior_checklist']} '
      'response_mode=${action['response_mode']} '
      'require_comment_per_item=${action['require_comment_per_item']} '
      'require_document_per_item=${action['require_document_per_item']} '
      'first_item_attachment_fields=$firstItemAttachmentFields '
      'normalized_attachments=$normalizedAttachments',
    );
  }

  Future<bool> _submitUserChecklistFollowup(
    List<_ChecklistFollowupResponse> responses,
  ) async {
    final responsePayload = responses
        .map(
          (response) => {
            'item_id': response.itemId,
            'comment': response.comment,
          },
        )
        .toList();
    final hasFiles = responses.any((response) => response.file != null);

    try {
      final credentials = await _credentials();
      final uri = Uri.parse(
        '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/user-checklist-followup',
      );

      if (!hasFiles) {
        final response = await ApiHttp.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'user_id': credentials.userId,
                'api_token': credentials.apiToken,
                'action_id': action['id']?.toString() ?? '',
                'responses': responsePayload,
              }),
            )
            .timeout(Duration(seconds: 30));
        final message = _successMessageOrThrow(
          response,
          'Checklist response submitted',
        );
        _showSnackBar(message);
        return true;
      }

      final request = http.MultipartRequest('POST', uri);
      request.fields['user_id'] = credentials.userId;
      request.fields['api_token'] = credentials.apiToken;
      request.fields['action_id'] = action['id']?.toString() ?? '';
      request.fields['responses'] = jsonEncode(responsePayload);

      for (final response in responses) {
        final file = response.file;
        if (file == null) continue;
        request.files.add(
          await http.MultipartFile.fromPath(
            'ucl_file_${response.itemId}',
            file.path,
            filename: file.name,
          ),
        );
      }

      final streamedResponse =
          await ApiHttp.send(request).timeout(Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      final message = _successMessageOrThrow(
        response,
        'Checklist response submitted',
      );
      _showSnackBar(message);
      return true;
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return false;
    }
  }

  Future<void> _closeSheetAndRefresh(BuildContext sheetContext) async {
    if (!mounted) return;
    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
      await Future<void>.delayed(Duration(milliseconds: 350));
    }
    if (!mounted) return;
    await widget.onActionCompleted();
  }

  Future<void> _showUploadSheet() async {
    final uploadAction = await _resolveFreshUploadAction();
    if (_truthyValue(uploadAction['blocked'])) {
      await _showWorkflowUploadAlert(
        context,
        message: uploadAction['blocked_message']?.toString().trim().isNotEmpty ==
                true
            ? uploadAction['blocked_message'].toString().trim()
            : 'Upload not available',
      );
      return;
    }
    if (uploadAction['add_percent_to_task'] == true) {
      await _showPercentProgressUploadSheet(uploadAction);
      return;
    }
    final commentController = TextEditingController();
    final uploadSources = _resolveWorkflowUploadSources(uploadAction);
    final allowedFormats = uploadSources.allAllowedFormats.isNotEmpty
        ? uploadSources.allAllowedFormats
        : _stringList(uploadAction['allowed_formats']);
    final allowFileUpload = uploadAction['allow_file_upload'] != false;
    final minFiles = _intValue(uploadAction['min_files']) ?? 0;
    final maxFiles = _intValue(uploadAction['max_files']);
    final allowMultiple = uploadAction['allow_multiple'] == true;
    final cameraOnly = uploadSources.cameraOnly;
    final allowComment = uploadAction['allow_comment'] == true;
    final requireComment = uploadAction['require_comment'] == true;
    final existingResponse =
        _configMap(_actionResponsePayloadFor(uploadAction)) ?? {};
    final existingFiles = _mapListFlexible(existingResponse['files']);
    final requireNearSite = _truthyValue(
      _slotActionValue('require_near_site', source: uploadAction) ??
          uploadAction['require_near_site'],
    );
    final requireGpsForUpload = _truthyValue(
      uploadAction['require_gps_for_upload'],
    );
    final needsGps = requireNearSite || requireGpsForUpload;
    final nearSiteRadiusMeters = _intValue(
          _slotActionValue('near_site_radius_meters', source: uploadAction) ??
              uploadAction['near_site_radius_meters'],
        ) ??
        500;
    final siteLocation = _parseSiteLocation(
      _slotActionValue('site_location', source: uploadAction) ??
          uploadAction['site_location'],
    );
    final siteLocationAvailableRaw =
        _slotActionValue('site_location_available', source: uploadAction) ??
            uploadAction['site_location_available'];
    final siteLocationAvailable = siteLocationAvailableRaw == null
        ? siteLocation != null
        : _truthyValue(siteLocationAvailableRaw);

    _logNearSiteUploadConfig(
      task: task,
      action: uploadAction,
      itemRunId: _resolvedWorkflowItemRunId,
      requireNearSite: requireNearSite,
      nearSiteRadiusMeters: nearSiteRadiusMeters,
      siteLocationRaw: _slotActionValue('site_location', source: uploadAction) ??
          uploadAction['site_location'],
      siteLocationAvailableRaw: siteLocationAvailableRaw,
      siteLocationAvailable: siteLocationAvailable,
      parsedSiteLocation: siteLocation,
    );

    List<_SelectedUploadFile> selectedFiles = <_SelectedUploadFile>[];
    bool isSubmitting = false;
    bool refreshAfterClose = false;
    bool isCheckingLocation = needsGps;
    String? nearSiteError;
    bool openSettingsHint = false;
    double? distanceMeters;
    double? deviceLatitude;
    double? deviceLongitude;

    Future<_SelectedUploadFile?> captureLiveImage() async {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (picked == null) return null;

      final capturedAt = DateTime.now();
      final sourceFile = File(picked.path);
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(capturedAt);
      final stampedName = 'live_$timestamp.jpg';
      final stampedPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}$stampedName';
      final copiedFile = await sourceFile.copy(stampedPath);

      return _SelectedUploadFile(
        path: copiedFile.path,
        name: stampedName,
        capturedAt: capturedAt,
      );
    }

    Future<_NearSiteCheckResult> checkNearSite() async {
      Future<_NearSiteCheckResult> runCheck() async {
        if (!needsGps) {
          return const _NearSiteCheckResult(ok: true);
        }
        if (requireNearSite &&
            (!siteLocationAvailable || siteLocation == null)) {
          return const _NearSiteCheckResult(
            ok: false,
            error: 'Project site map coordinates are not configured.',
          );
        }

        final permission = await _ensureLocationPermission();
        if (!permission.ok) {
          return _NearSiteCheckResult(
            ok: false,
            error: permission.error ??
                'Your device location is required to upload near the site.',
            openSettings: permission.openSettings,
          );
        }

        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 15));
          final distance = siteLocation == null
              ? 0.0
              : Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  siteLocation.latitude,
                  siteLocation.longitude,
                );
          final roundedDistance = distance.round();
          if (requireNearSite && siteLocation != null) {
            _logNearSiteDistanceCheck(
              itemRunId: _resolvedWorkflowItemRunId,
              projectId: task['project_id']?.toString() ?? '',
              siteLatitude: siteLocation.latitude,
              siteLongitude: siteLocation.longitude,
              deviceLatitude: position.latitude,
              deviceLongitude: position.longitude,
              distanceMeters: distance,
              nearSiteRadiusMeters: nearSiteRadiusMeters,
              withinRadius: distance <= nearSiteRadiusMeters,
            );
            if (distance > nearSiteRadiusMeters) {
              return _NearSiteCheckResult(
                ok: false,
                error:
                    'You must be within $nearSiteRadiusMeters m of the project site (you are about $roundedDistance m away). '
                    'Site reference: ${siteLocation.latitude.toStringAsFixed(7)}, '
                    '${siteLocation.longitude.toStringAsFixed(7)}',
                distanceMeters: distance,
                latitude: position.latitude,
                longitude: position.longitude,
              );
            }
          }
          return _NearSiteCheckResult(
            ok: true,
            distanceMeters: siteLocation == null ? null : distance,
            latitude: position.latitude,
            longitude: position.longitude,
          );
        } on TimeoutException {
          return const _NearSiteCheckResult(
            ok: false,
            error: 'Could not get your location in time. Please try again.',
          );
        } catch (e) {
          return _NearSiteCheckResult(
            ok: false,
            error: e.toString().replaceAll('Exception: ', ''),
          );
        }
      }

      final result = await runCheck();
      return _applyDebugNearSiteOverrideIfNeeded(
        context,
        result,
        siteLocation: siteLocation,
      );
    }

    void applyNearSiteResult(_NearSiteCheckResult result) {
      isCheckingLocation = false;
      nearSiteError = result.ok ? null : result.error;
      openSettingsHint = result.openSettings;
      distanceMeters = result.distanceMeters;
      deviceLatitude = result.latitude;
      deviceLongitude = result.longitude;
    }

    if (needsGps) {
      applyNearSiteResult(await checkNearSite());
    }

    final withinNearSite =
        !needsGps || (nearSiteError == null && deviceLatitude != null);

    if (cameraOnly && withinNearSite) {
      final captured = await captureLiveImage();
      if (captured == null) {
        commentController.dispose();
        return;
      }
      selectedFiles = [captured];
    }

    if (!allowFileUpload && !allowComment) {
      commentController.dispose();
      _showSnackBar('This upload action is not configured for mobile.',
          isError: true);
      return;
    }

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final canInteract = !isSubmitting &&
                !isCheckingLocation &&
                (!needsGps || nearSiteError == null);

            Future<void> ensureGpsForPick() async {
              if (!needsGps) return;
              setSheetState(() {
                isCheckingLocation = true;
              });
              final result = await checkNearSite();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                applyNearSiteResult(result);
              });
              if (!result.ok) {
                final message =
                    result.error ?? 'Your device location is required to upload near the site.';
                await _showWorkflowUploadAlert(
                  context,
                  message: message,
                  title: 'Location required',
                );
                throw Exception(message);
              }
            }

            Future<void> refreshLocation() async {
              setSheetState(() {
                isCheckingLocation = true;
                nearSiteError = null;
                openSettingsHint = false;
              });
              final result = await checkNearSite();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                applyNearSiteResult(result);
              });
            }

            Future<void> pickGallery() async {
              try {
                await ensureGpsForPick();
              } catch (_) {
                return;
              }

              final picked = await _pickWorkflowGalleryFile(
                allowedFormats: uploadSources.imageFormats,
              );
              if (picked == null) return;
              setSheetState(() {
                if (allowMultiple) {
                  selectedFiles.add(picked);
                } else {
                  selectedFiles = [picked];
                }
              });
            }

            Future<void> pickCamera() async {
              try {
                await ensureGpsForPick();
              } catch (_) {
                return;
              }

              final captured = await captureLiveImage();
              if (captured == null) return;
              setSheetState(() {
                if (allowMultiple) {
                  selectedFiles.add(captured);
                } else {
                  selectedFiles = [captured];
                }
              });
            }

            Future<void> pickDocument() async {
              try {
                await ensureGpsForPick();
              } catch (_) {
                return;
              }

              final picked = await _pickWorkflowDocumentFile(
                documentFormats: uploadSources.documentFormats,
              );
              if (picked == null) return;
              setSheetState(() {
                if (allowMultiple) {
                  selectedFiles.add(picked);
                } else {
                  selectedFiles = [picked];
                }
              });
            }

            Future<void> pickVideo() async {
              try {
                await ensureGpsForPick();
              } catch (_) {
                return;
              }

              final maxVideoDuration =
                  _intValue(uploadAction['max_video_duration_seconds']) ?? 60;
              final maxVideoSizeMb =
                  _intValue(uploadAction['max_video_size_mb']) ?? 50;
              final picked = await _recordWorkflowVideoFile(
                context: context,
                videoFormats: uploadSources.videoFormats,
                maxDurationSeconds: maxVideoDuration,
                maxSizeMb: maxVideoSizeMb,
              );
              if (picked == null) return;
              setSheetState(() {
                if (allowMultiple) {
                  selectedFiles.add(picked);
                } else {
                  selectedFiles = [picked];
                }
              });
            }

            Future<void> pickFiles() async {
              if (uploadSources.allowDocument && !uploadSources.allowGallery) {
                await pickDocument();
                return;
              }
              if (uploadSources.allowGallery && uploadSources.allowCamera) {
                return;
              }
              if (uploadSources.allowCamera) {
                await pickCamera();
                return;
              }
              if (uploadSources.allowVideo) {
                await pickVideo();
                return;
              }
              if (uploadSources.allowDocument) {
                await pickDocument();
                return;
              }
              await pickGallery();
            }

            Future<void> submit() async {
              FocusManager.instance.primaryFocus?.unfocus();
              var closeSheet = false;
              if (allowFileUpload && selectedFiles.length < minFiles) {
                _showSnackBar('Please select at least $minFiles file(s).',
                    isError: true);
                return;
              }
              if (allowFileUpload &&
                  maxFiles != null &&
                  selectedFiles.length > maxFiles) {
                _showSnackBar('Please select no more than $maxFiles file(s).',
                    isError: true);
                return;
              }
              if (!allowFileUpload && selectedFiles.isNotEmpty) {
                _showSnackBar('File upload is not allowed for this action.',
                    isError: true);
                return;
              }
              if (requireComment && commentController.text.trim().isEmpty) {
                await _showWorkflowUploadAlert(
                  context,
                  message: 'Please add a comment.',
                );
                return;
              }
              if (!allowFileUpload &&
                  !requireComment &&
                  commentController.text.trim().isEmpty) {
                await _showWorkflowUploadAlert(
                  context,
                  message: 'Please add a comment.',
                );
                return;
              }

              setSheetState(() {
                isSubmitting = true;
              });

              try {
                double? uploadLat = deviceLatitude;
                double? uploadLng = deviceLongitude;

                if (needsGps) {
                  final nearSiteResult = await checkNearSite();
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    applyNearSiteResult(nearSiteResult);
                  });
                  if (!nearSiteResult.ok) {
                    final message = nearSiteResult.error ??
                        'Your device location is required to upload near the site.';
                    await _showWorkflowUploadAlert(
                      context,
                      message: message,
                      title: 'Location required',
                    );
                    return;
                  }
                  uploadLat = nearSiteResult.latitude;
                  uploadLng = nearSiteResult.longitude;
                }

                final credentials = await _credentials();
                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse(
                    '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/upload',
                  ),
                );
                request.fields['user_id'] = credentials.userId;
                request.fields['api_token'] = credentials.apiToken;
                request.fields['action_id'] =
                    uploadAction['id']?.toString() ?? '';
                if (allowComment) {
                  request.fields['upload_comment'] =
                      commentController.text.trim();
                }
                if (needsGps && uploadLat != null && uploadLng != null) {
                  request.fields['latitude'] = uploadLat.toString();
                  request.fields['longitude'] = uploadLng.toString();
                }
                if (_shouldSendLiveImageOnlyUpload(
                  cameraOnly: cameraOnly,
                  files: selectedFiles,
                )) {
                  request.fields['live_image_only'] = 'true';
                  request.fields['captured_at'] = selectedFiles
                      .map((file) => file.capturedAt?.toIso8601String())
                      .whereType<String>()
                      .join(',');
                }

                for (final file in selectedFiles) {
                  if (!_isAllowedWorkflowUploadFile(file, uploadSources)) {
                    throw Exception(
                      'File type not allowed. Allowed: ${_allowedFormatsMessage(uploadSources)}',
                    );
                  }
                  request.files.add(await _workflowUploadMultipartFile(file));
                }
                _appendWorkflowVideoDurationField(request, selectedFiles);

                final streamedResponse =
                    await ApiHttp.send(request).timeout(Duration(seconds: 60));
                final response =
                    await http.Response.fromStream(streamedResponse);
                final message = _successMessageOrThrow(
                  response,
                  'Files uploaded successfully',
                );
                if (!mounted) return;
                _showSnackBar(message);
                closeSheet = true;
                refreshAfterClose = true;
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
              } catch (e) {
                final errorMessage =
                    e.toString().replaceAll('Exception: ', '').trim();
                if (errorMessage.isNotEmpty) {
                  await _showWorkflowUploadAlert(
                    context,
                    message: errorMessage,
                    title: 'Upload failed',
                  );
                }
              } finally {
                if (mounted && !closeSheet) {
                  setSheetState(() {
                    isSubmitting = false;
                  });
                }
              }
            }

            return _BottomSheetFrame(
              title: _label('Upload'),
              icon: Icons.upload_file,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActionMetaText(
                    label: 'Allowed formats',
                    value: cameraOnly
                        ? 'Live camera image only'
                        : allowedFormats.isEmpty
                            ? 'Any file'
                            : allowedFormats.join(', '),
                  ),
                  _ActionMetaText(
                    label: 'Files',
                    value: allowFileUpload
                        ? 'Minimum ${minFiles == 0 ? 'optional' : minFiles}, maximum ${maxFiles?.toString() ?? (allowMultiple ? 'multiple' : '1')}'
                        : 'Comment only (no files)',
                  ),
                  if (existingFiles.isNotEmpty) ...[
                    SizedBox(height: 12),
                    _ResponseSectionHeader(
                      icon: Icons.attach_file_rounded,
                      label: existingFiles.length == 1
                          ? 'Uploaded file'
                          : 'Uploaded files',
                    ),
                    SizedBox(height: 8),
                    ...existingFiles.map(
                      (file) => _ResponseFileTile(
                        file: file,
                        relatedFiles: existingFiles,
                      ),
                    ),
                  ],
                  if (needsGps) ...[
                    SizedBox(height: 12),
                    _NearSiteStatusBanner(
                      isChecking: isCheckingLocation,
                      error: nearSiteError,
                      distanceMeters: distanceMeters,
                      radiusMeters: nearSiteRadiusMeters,
                      siteLatitude: siteLocation?.latitude,
                      siteLongitude: siteLocation?.longitude,
                      showOpenSettings: openSettingsHint,
                      onRecheck: isSubmitting ? null : refreshLocation,
                      onOpenSettings: openSettingsHint
                          ? () async {
                              await Geolocator.openAppSettings();
                            }
                          : null,
                    ),
                  ],
                  if (allowFileUpload && uploadSources.hasAnySource) ...[
                    SizedBox(height: 12),
                    _WorkflowUploadSourceButtons(
                      sources: uploadSources,
                      onPickGallery: canInteract ? pickGallery : null,
                      onPickCamera: canInteract ? pickCamera : null,
                      onPickDocument: canInteract ? pickDocument : null,
                      onPickVideo: canInteract ? pickVideo : null,
                    ),
                  ] else if (allowFileUpload) ...[
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: canInteract ? pickFiles : null,
                      icon: Icon(Icons.attach_file_rounded),
                      label: Text('Attach file'),
                    ),
                  ],
                  if (selectedFiles.isNotEmpty) ...[
                    SizedBox(height: 12),
                    _SelectedUploadFilesPreview(
                      files: selectedFiles,
                      onRemove: isSubmitting
                          ? null
                          : (index) {
                              setSheetState(() {
                                if (index >= 0 && index < selectedFiles.length) {
                                  selectedFiles =
                                      List<_SelectedUploadFile>.from(
                                          selectedFiles)
                                        ..removeAt(index);
                                }
                              });
                            },
                    ),
                  ],
                  if (allowComment) ...[
                    SizedBox(height: 14),
                    _SheetTextField(
                      controller: commentController,
                      label: requireComment ? 'Comment *' : 'Comment',
                      maxLines: 3,
                    ),
                  ],
                  SizedBox(height: 20),
                  _SheetSubmitButton(
                    label: 'Submit upload',
                    isSubmitting: isSubmitting,
                    onPressed: canInteract ? submit : null,
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(Duration(milliseconds: 350));
    commentController.dispose();
    if (refreshAfterClose && mounted) {
      await widget.onActionCompleted();
    }
  }

  Future<void> _showPercentProgressUploadSheet(
    Map<String, dynamic> uploadAction,
  ) async {
    final fresh = await _loadFreshWorkflowActionContext();
    uploadAction = fresh.action;
    final canUpdate = fresh.canUpdate ?? _canUpdateTask;
    final initialResponse =
        _configMap(_actionResponsePayloadFor(uploadAction)) ?? {};
    var progressSnapshot = _uploadProgressSnapshot(uploadAction, initialResponse);
    var currentPercent = progressSnapshot.currentPercent;
    var progressEntries = progressSnapshot.progressEntries;
    var minNextPercent = progressSnapshot.minNextPercent;

    final commentController = TextEditingController();
    final percentController = TextEditingController();
    final percentFocusNode = FocusNode();
    final saveDocumentKey = GlobalKey();
    final sheetScrollController = ScrollController();

    void ensureSaveDocumentVisible() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final targetContext = saveDocumentKey.currentContext;
        if (targetContext == null) return;
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 1.0,
        );
      });
    }

    percentFocusNode.addListener(() {
      if (percentFocusNode.hasFocus) {
        ensureSaveDocumentVisible();
      }
    });
    final uploadSources = _resolveWorkflowUploadSources(uploadAction);
    final cameraOnly = uploadSources.cameraOnly;
    final allowComment = uploadAction['allow_comment'] == true;
    final requireComment = uploadAction['require_comment'] == true;
    final requireNearSite = _truthyValue(
      _slotActionValue('require_near_site', source: uploadAction) ??
          uploadAction['require_near_site'],
    );
    final requireGpsForUpload = _truthyValue(
      uploadAction['require_gps_for_upload'],
    );
    final needsGps = requireNearSite || requireGpsForUpload;
    final nearSiteRadiusMeters = _intValue(
          _slotActionValue('near_site_radius_meters', source: uploadAction) ??
              uploadAction['near_site_radius_meters'],
        ) ??
        500;
    final siteLocation = _parseSiteLocation(
      _slotActionValue('site_location', source: uploadAction) ??
          uploadAction['site_location'],
    );
    final siteLocationAvailableRaw =
        _slotActionValue('site_location_available', source: uploadAction) ??
            uploadAction['site_location_available'];
    final siteLocationAvailable = siteLocationAvailableRaw == null
        ? siteLocation != null
        : _truthyValue(siteLocationAvailableRaw);
    final submitLabel =
        uploadAction['label']?.toString().trim().isNotEmpty == true
            ? uploadAction['label'].toString().trim()
            : 'Upload';

    _SelectedUploadFile? pendingFile;
    bool isSaving = false;
    bool isFinalizing = false;
    bool isDeleting = false;
    int? deletingIndex;
    int? confirmDeleteIndex;
    bool refreshAfterClose = false;
    bool isCheckingLocation = needsGps;
    String? nearSiteError;
    bool openSettingsHint = false;
    String? percentError;
    String? formError;
    double? distanceMeters;
    double? deviceLatitude;
    double? deviceLongitude;

    Future<_SelectedUploadFile?> captureLiveImage() async {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (picked == null) return null;

      final capturedAt = DateTime.now();
      final sourceFile = File(picked.path);
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(capturedAt);
      final stampedName = 'live_$timestamp.jpg';
      final stampedPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}$stampedName';
      final copiedFile = await sourceFile.copy(stampedPath);

      return _SelectedUploadFile(
        path: copiedFile.path,
        name: stampedName,
        capturedAt: capturedAt,
      );
    }

    Future<_NearSiteCheckResult> checkNearSite() async {
      Future<_NearSiteCheckResult> runCheck() async {
        if (!needsGps) {
          return const _NearSiteCheckResult(ok: true);
        }
        if (requireNearSite &&
            (!siteLocationAvailable || siteLocation == null)) {
          return const _NearSiteCheckResult(
            ok: false,
            error: 'Project site map coordinates are not configured.',
          );
        }

        final permission = await _ensureLocationPermission();
        if (!permission.ok) {
          return _NearSiteCheckResult(
            ok: false,
            error: permission.error ??
                'Your device location is required to upload near the site.',
            openSettings: permission.openSettings,
          );
        }

        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 15));
          final distance = siteLocation == null
              ? 0.0
              : Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  siteLocation.latitude,
                  siteLocation.longitude,
                );
          if (requireNearSite && siteLocation != null) {
            if (distance > nearSiteRadiusMeters) {
              final roundedDistance = distance.round();
              return _NearSiteCheckResult(
                ok: false,
                error:
                    'You must be within $nearSiteRadiusMeters m of the project site (you are about $roundedDistance m away).',
                distanceMeters: distance,
                latitude: position.latitude,
                longitude: position.longitude,
              );
            }
          }
          return _NearSiteCheckResult(
            ok: true,
            distanceMeters: siteLocation == null ? null : distance,
            latitude: position.latitude,
            longitude: position.longitude,
          );
        } on TimeoutException {
          return const _NearSiteCheckResult(
            ok: false,
            error: 'Could not get your location in time. Please try again.',
          );
        } catch (e) {
          return _NearSiteCheckResult(
            ok: false,
            error: e.toString().replaceAll('Exception: ', ''),
          );
        }
      }

      final result = await runCheck();
      return _applyDebugNearSiteOverrideIfNeeded(
        context,
        result,
        siteLocation: siteLocation,
      );
    }

    void applyNearSiteResult(_NearSiteCheckResult result) {
      isCheckingLocation = false;
      nearSiteError = result.ok ? null : result.error;
      openSettingsHint = result.openSettings;
      distanceMeters = result.distanceMeters;
      deviceLatitude = result.latitude;
      deviceLongitude = result.longitude;
    }

    if (needsGps) {
      applyNearSiteResult(await checkNearSite());
    }

    void applyProgressFromResponse(Map<String, dynamic> decoded) {
      if (decoded.containsKey('current_percent')) {
        currentPercent = _uploadCurrentPercent(decoded);
      }
      if (decoded['progress_entries'] != null) {
        progressEntries = _uploadProgressEntries(decoded);
      }
      if (decoded.containsKey('min_next_percent')) {
        minNextPercent = _uploadMinNextPercent(decoded, currentPercent);
      } else {
        minNextPercent = _uploadMinNextPercent(uploadAction, currentPercent);
      }
    }

    Future<void> refreshProgressFromServer() async {
      final refreshed = await _loadFreshWorkflowActionContext();
      uploadAction = refreshed.action;
      final responseMap =
          _configMap(_actionResponsePayloadFor(uploadAction)) ?? {};
      progressSnapshot = _uploadProgressSnapshot(uploadAction, responseMap);
      currentPercent = progressSnapshot.currentPercent;
      progressEntries = progressSnapshot.progressEntries;
      minNextPercent = progressSnapshot.minNextPercent;
    }

    Future<void> ensureGpsForPick(
      void Function(void Function()) setSheetState,
    ) async {
      if (!needsGps) return;
      setSheetState(() {
        isCheckingLocation = true;
      });
      final result = await checkNearSite();
      if (!context.mounted) return;
      setSheetState(() {
        applyNearSiteResult(result);
      });
      if (!result.ok) {
        final message = result.error ??
            'Your device location is required to upload near the site.';
        await _showWorkflowUploadAlert(
          context,
          message: message,
          title: 'Location required',
        );
        throw Exception(message);
      }
    }

    void scrollSheetToActions() {
      // Keep the attach/submit section in view after picking a file.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!sheetScrollController.hasClients) return;
        sheetScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      });
    }

    Future<void> pickGallery(void Function(void Function()) setSheetState) async {
      try {
        await ensureGpsForPick(setSheetState);
      } catch (_) {
        return;
      }

      final picked = await _pickWorkflowGalleryFile(
        allowedFormats: uploadSources.imageFormats,
      );
      if (picked == null) return;
      setSheetState(() {
        pendingFile = picked;
        percentError = null;
        formError = null;
      });
      scrollSheetToActions();
    }

    Future<void> pickCamera(void Function(void Function()) setSheetState) async {
      try {
        await ensureGpsForPick(setSheetState);
      } catch (_) {
        return;
      }

      final captured = await captureLiveImage();
      if (captured == null) return;
      setSheetState(() {
        pendingFile = captured;
        percentError = null;
        formError = null;
      });
      scrollSheetToActions();
    }

    Future<void> pickDocument(void Function(void Function()) setSheetState) async {
      try {
        await ensureGpsForPick(setSheetState);
      } catch (_) {
        return;
      }

      final picked = await _pickWorkflowDocumentFile(
        documentFormats: uploadSources.documentFormats,
      );
      if (picked == null) return;
      setSheetState(() {
        pendingFile = picked;
        percentError = null;
        formError = null;
      });
      scrollSheetToActions();
    }

    Future<void> pickVideo(void Function(void Function()) setSheetState) async {
      try {
        await ensureGpsForPick(setSheetState);
      } catch (_) {
        return;
      }

      final maxVideoDuration =
          _intValue(uploadAction['max_video_duration_seconds']) ?? 60;
      final maxVideoSizeMb =
          _intValue(uploadAction['max_video_size_mb']) ?? 50;
      final picked = await _recordWorkflowVideoFile(
        context: context,
        videoFormats: uploadSources.videoFormats,
        maxDurationSeconds: maxVideoDuration,
        maxSizeMb: maxVideoSizeMb,
      );
      if (picked == null) return;
      setSheetState(() {
        pendingFile = picked;
        percentError = null;
        formError = null;
      });
      scrollSheetToActions();
    }

    String? validatePercentInput(String raw, int previousPercent) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return 'Enter completion % for this document.';
      }
      final parsed = int.tryParse(trimmed);
      if (parsed == null || parsed < 1 || parsed > 100) {
        return 'Enter a whole number from 1 to 100.';
      }
      if (parsed < minNextPercent) {
        return 'Enter at least $minNextPercent%.';
      }
      if (parsed <= previousPercent) {
        return 'Must be greater than the last saved progress ($previousPercent%).';
      }
      return null;
    }

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isBusy =
                isSaving || isFinalizing || isCheckingLocation || isDeleting;
            final withinNearSite =
                !needsGps || (nearSiteError == null && deviceLatitude != null);
            // Keep the selected-file UI visible while a save is in flight so the
            // image preview and progress bar stay on screen after upload starts.
            final canAddDocument = canUpdate &&
                currentPercent < 100 &&
                withinNearSite &&
                (!isBusy || (isSaving && pendingFile != null));
            final canFinalize =
                canUpdate && currentPercent >= 100 && withinNearSite && !isBusy;
            final showCommentOnFinalize = allowComment && currentPercent >= 100;

            Future<void> refreshLocation() async {
              setSheetState(() {
                isCheckingLocation = true;
                nearSiteError = null;
                openSettingsHint = false;
              });
              final result = await checkNearSite();
              if (!sheetContext.mounted) return;
              setSheetState(() {
                applyNearSiteResult(result);
              });
            }

            List<Map<String, dynamic>> imageFilesForEntry(
              Map<String, dynamic> entry,
            ) {
              final files = _mapListFlexible(entry['files']);
              return files.where((file) {
                final url = _workflowAttachmentUrl(file);
                if (url == null) return false;
                final contentType =
                    _firstString(file, ['content_type', 'mime_type']);
                final name = _firstString(file, [
                  'filename',
                  'name',
                  'original_filename',
                  'file_name',
                ]);
                return _isImageAttachment(url, contentType: contentType) ||
                    (name != null && _looksLikeImage(name));
              }).toList();
            }

            void requestDeleteDocument(int index) {
              if (index < 0 || index >= progressEntries.length || isBusy) {
                return;
              }
              setSheetState(() {
                confirmDeleteIndex = index;
                formError = null;
              });
            }

            void cancelDeleteDocument() {
              if (isDeleting) return;
              setSheetState(() {
                confirmDeleteIndex = null;
              });
            }

            Future<void> confirmDeleteDocument() async {
              final index = confirmDeleteIndex;
              if (index == null ||
                  index < 0 ||
                  index >= progressEntries.length) {
                return;
              }

              setSheetState(() {
                isDeleting = true;
                deletingIndex = index;
                formError = null;
              });

              try {
                final credentials = await _credentials();
                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse(
                    '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/upload',
                  ),
                );
                request.fields['user_id'] = credentials.userId;
                request.fields['api_token'] = credentials.apiToken;
                request.fields['action_id'] =
                    uploadAction['id']?.toString() ?? '';
                request.fields['delete_progress_index'] = index.toString();

                final streamedResponse = await request
                    .send()
                    .timeout(const Duration(seconds: 60));
                final response =
                    await http.Response.fromStream(streamedResponse);
                final message = _successMessageOrThrow(
                  response,
                  'Document removed',
                );

                dynamic decoded;
                try {
                  decoded = jsonDecode(response.body);
                } catch (_) {
                  decoded = null;
                }
                if (decoded is Map) {
                  applyProgressFromResponse(
                    Map<String, dynamic>.from(decoded),
                  );
                }

                if (!mounted) return;
                _showSnackBar(message);
                setSheetState(() {
                  confirmDeleteIndex = null;
                });
              } catch (e) {
                if (!mounted) return;
                final errorMessage =
                    e.toString().replaceAll('Exception: ', '').trim();
                setSheetState(() {
                  formError = errorMessage;
                });
                if (errorMessage.isNotEmpty) {
                  await _showWorkflowUploadAlert(
                    context,
                    message: errorMessage,
                    title: 'Upload failed',
                  );
                }
              } finally {
                if (mounted) {
                  setSheetState(() {
                    isDeleting = false;
                    deletingIndex = null;
                  });
                }
              }
            }

            Future<void> saveDocument() async {
              FocusManager.instance.primaryFocus?.unfocus();
              if (pendingFile == null) {
                setSheetState(() {
                  formError = 'Select a file to upload.';
                });
                return;
              }

              final validation = validatePercentInput(
                percentController.text,
                currentPercent,
              );
              if (validation != null) {
                setSheetState(() {
                  percentError = validation;
                  formError = null;
                });
                return;
              }

              setSheetState(() {
                isSaving = true;
                formError = null;
                percentError = null;
              });

              var closeSheet = false;
              try {
                if (!_isAllowedWorkflowUploadFile(pendingFile!, uploadSources)) {
                  throw Exception(
                    'File type not allowed. Allowed: ${_allowedFormatsMessage(uploadSources)}',
                  );
                }

                double? uploadLat = deviceLatitude;
                double? uploadLng = deviceLongitude;
                if (needsGps) {
                  final nearSiteResult = await checkNearSite();
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    applyNearSiteResult(nearSiteResult);
                  });
                  if (!nearSiteResult.ok) {
                    throw Exception(
                      nearSiteResult.error ??
                          'Your device location is required to upload near the site.',
                    );
                  }
                  uploadLat = nearSiteResult.latitude;
                  uploadLng = nearSiteResult.longitude;
                }

                final percentValue = int.parse(percentController.text.trim());
                final credentials = await _credentials();
                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse(
                    '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/upload',
                  ),
                );
                request.fields['user_id'] = credentials.userId;
                request.fields['api_token'] = credentials.apiToken;
                request.fields['action_id'] =
                    uploadAction['id']?.toString() ?? '';
                request.fields['completion_percents'] =
                    jsonEncode([percentValue]);
                if (needsGps && uploadLat != null && uploadLng != null) {
                  request.fields['latitude'] = uploadLat.toString();
                  request.fields['longitude'] = uploadLng.toString();
                }
                if (_shouldSendLiveImageOnlyUpload(
                  cameraOnly: cameraOnly,
                  files: [pendingFile!],
                )) {
                  request.fields['live_image_only'] = 'true';
                  if (pendingFile!.capturedAt != null) {
                    request.fields['captured_at'] =
                        pendingFile!.capturedAt!.toIso8601String();
                  }
                }

                request.files.add(
                  await _workflowUploadMultipartFile(pendingFile!),
                );
                _appendWorkflowVideoDurationField(request, [pendingFile!]);

                final streamedResponse =
                    await ApiHttp.send(request).timeout(const Duration(seconds: 60));
                final response =
                    await http.Response.fromStream(streamedResponse);
                final message = _successMessageOrThrow(
                  response,
                  'Upload saved',
                );

                dynamic decoded;
                try {
                  decoded = jsonDecode(response.body);
                } catch (_) {
                  decoded = null;
                }
                if (decoded is Map) {
                  applyProgressFromResponse(Map<String, dynamic>.from(decoded));
                }
                await refreshProgressFromServer();

                if (!mounted) return;
                _showSnackBar(message);
                if (decoded is Map && decoded['task_completed'] == true) {
                  closeSheet = true;
                  refreshAfterClose = true;
                }
                setSheetState(() {
                  pendingFile = null;
                  percentController.clear();
                });
                if (closeSheet && sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
              } catch (e) {
                if (!mounted) return;
                final errorMessage =
                    e.toString().replaceAll('Exception: ', '').trim();
                setSheetState(() {
                  formError = errorMessage;
                });
                if (errorMessage.isNotEmpty) {
                  await _showWorkflowUploadAlert(
                    context,
                    message: errorMessage,
                    title: 'Upload failed',
                  );
                }
              } finally {
                if (mounted && !closeSheet) {
                  setSheetState(() {
                    isSaving = false;
                  });
                }
              }
            }

            Future<void> finalizeUpload() async {
              FocusManager.instance.primaryFocus?.unfocus();
              if (requireComment && commentController.text.trim().isEmpty) {
                setSheetState(() {
                  formError = 'Please add a comment.';
                });
                await _showWorkflowUploadAlert(
                  context,
                  message: 'Please add a comment.',
                );
                return;
              }
              if (currentPercent < 100) {
                setSheetState(() {
                  formError =
                      'Upload progress must reach 100% before finishing.';
                });
                return;
              }

              setSheetState(() {
                isFinalizing = true;
                formError = null;
              });

              var closeSheet = false;
              try {
                if (needsGps) {
                  final nearSiteResult = await checkNearSite();
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    applyNearSiteResult(nearSiteResult);
                  });
                  if (!nearSiteResult.ok) {
                    throw Exception(
                      nearSiteResult.error ??
                          'Your device location is required to upload near the site.',
                    );
                  }
                }

                final credentials = await _credentials();
                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse(
                    '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/upload',
                  ),
                );
                request.fields['user_id'] = credentials.userId;
                request.fields['api_token'] = credentials.apiToken;
                request.fields['action_id'] =
                    uploadAction['id']?.toString() ?? '';
                request.fields['finalize'] = '1';
                if (allowComment) {
                  request.fields['upload_comment'] =
                      commentController.text.trim();
                }
                if (needsGps && deviceLatitude != null && deviceLongitude != null) {
                  request.fields['latitude'] = deviceLatitude!.toString();
                  request.fields['longitude'] = deviceLongitude!.toString();
                }

                final streamedResponse =
                    await ApiHttp.send(request).timeout(const Duration(seconds: 60));
                final response =
                    await http.Response.fromStream(streamedResponse);
                final message = _successMessageOrThrow(
                  response,
                  'Upload complete',
                );

                if (!mounted) return;
                _showSnackBar(message);
                closeSheet = true;
                refreshAfterClose = true;
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
              } catch (e) {
                if (!mounted) return;
                final errorMessage =
                    e.toString().replaceAll('Exception: ', '').trim();
                setSheetState(() {
                  formError = errorMessage;
                });
                if (errorMessage.isNotEmpty) {
                  await _showWorkflowUploadAlert(
                    context,
                    message: errorMessage,
                    title: 'Upload failed',
                  );
                }
              } finally {
                if (mounted && !closeSheet) {
                  setSheetState(() {
                    isFinalizing = false;
                  });
                }
              }
            }

            // Show overall progress only after an upload has started/completed,
            // not merely when a file is attached.
            final showOverallProgress = isSaving ||
                isFinalizing ||
                currentPercent > 0 ||
                progressEntries.isNotEmpty;

            if (confirmDeleteIndex != null &&
                confirmDeleteIndex! >= 0 &&
                confirmDeleteIndex! < progressEntries.length) {
              final entry = progressEntries[confirmDeleteIndex!];
              final files = _mapListFlexible(entry['files']);
              final imageFiles = imageFilesForEntry(entry);
              final uploadedAt = entry['uploaded_at']?.toString();

              return _BottomSheetFrame(
                title: 'Remove document',
                icon: Icons.delete_outline,
                scrollController: sheetScrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageFiles.isNotEmpty) ...[
                      Center(
                        child: imageFiles.length == 1
                            ? _UploadedDocumentImagePreview(
                                file: imageFiles.first,
                                relatedFiles: files,
                                size: 220,
                                enableTap: false,
                              )
                            : SizedBox(
                                height: 160,
                                width: double.maxFinite,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: imageFiles.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (context, imageIndex) {
                                    return _UploadedDocumentImagePreview(
                                      file: imageFiles[imageIndex],
                                      relatedFiles: files,
                                      size: 160,
                                      enableTap: false,
                                    );
                                  },
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (uploadedAt != null && uploadedAt.trim().isNotEmpty) ...[
                      Text(
                        _formatUploadProgressDate(uploadedAt),
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Remove this document? Overall progress will be recalculated.',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    if (formError != null && formError!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SlotServerErrorBanner(message: formError!),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                isDeleting ? null : cancelDeleteDocument,
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor:
                                  AppTheme.getTextPrimary(context),
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                isDeleting ? null : confirmDeleteDocument,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isDeleting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Remove',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return _BottomSheetFrame(
              title: _label(submitLabel),
              icon: Icons.upload_file,
              scrollController: sheetScrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showOverallProgress) ...[
                    _WorkflowUploadProgressBar(percent: currentPercent),
                    SizedBox(height: 16),
                  ],
                  if (needsGps) ...[
                    _NearSiteStatusBanner(
                      isChecking: isCheckingLocation,
                      error: nearSiteError,
                      distanceMeters: distanceMeters,
                      radiusMeters: nearSiteRadiusMeters,
                      siteLatitude: siteLocation?.latitude,
                      siteLongitude: siteLocation?.longitude,
                      showOpenSettings: openSettingsHint == true,
                      onRecheck: isBusy ? null : refreshLocation,
                      onOpenSettings: openSettingsHint == true
                          ? () async {
                              await Geolocator.openAppSettings();
                            }
                          : null,
                    ),
                    SizedBox(height: 16),
                  ],
                  if (formError != null && formError!.trim().isNotEmpty) ...[
                    _SlotServerErrorBanner(message: formError!),
                    SizedBox(height: 12),
                  ],
                  // Keep attach/submit above history so the submit button stays
                  // reachable without scrolling past existing uploads.
                  if (canAddDocument) ...[
                    Text(
                      'Choose how you want to upload',
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    if (uploadSources.hasAnySource)
                      _WorkflowUploadSourceButtons(
                        sources: uploadSources,
                        onPickGallery: isBusy
                            ? null
                            : () => pickGallery(setSheetState),
                        onPickCamera: isBusy
                            ? null
                            : () => pickCamera(setSheetState),
                        onPickDocument: isBusy
                            ? null
                            : () => pickDocument(setSheetState),
                        onPickVideo: isBusy
                            ? null
                            : () => pickVideo(setSheetState),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: Icon(Icons.attach_file_rounded),
                        label: Text('No upload sources configured'),
                      ),
                    if (pendingFile != null) ...[
                      SizedBox(height: 12),
                      _SelectedUploadPreview(
                        file: pendingFile!,
                        onRemove: isBusy
                            ? null
                            : () {
                                setSheetState(() {
                                  pendingFile = null;
                                  percentController.clear();
                                  percentError = null;
                                  formError = null;
                                });
                              },
                      ),
                      SizedBox(height: 10),
                      TextField(
                        controller: percentController,
                        focusNode: percentFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onTap: ensureSaveDocumentVisible,
                        onChanged: (_) {
                          if (percentError != null) {
                            setSheetState(() {
                              percentError = null;
                              formError = null;
                            });
                          }
                        },
                        style: TextStyle(color: AppTheme.getTextPrimary(context)),
                        decoration: _sheetInputDecoration(
                          context,
                          'Complete % ($minNextPercent–100)',
                        ).copyWith(errorText: percentError),
                      ),
                      SizedBox(height: 12),
                      KeyedSubtree(
                        key: saveDocumentKey,
                        child: _SheetSubmitButton(
                          label: isSaving ? 'Saving...' : 'Save document',
                          isSubmitting: isSaving,
                          onPressed: isBusy ? null : saveDocument,
                        ),
                      ),
                    ],
                    if (progressEntries.isNotEmpty) SizedBox(height: 18),
                  ] else if (canUpdate && currentPercent >= 100) ...[
                    SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Color(0xFF10B981).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '100% reached — use the button below to finish.',
                        style: TextStyle(
                          color: Color(0xFF065F46),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (progressEntries.isNotEmpty) SizedBox(height: 18),
                  ],
                  if (progressEntries.isNotEmpty) ...[
                    _WorkflowUploadProgressHistory(
                      entries: progressEntries,
                      canDelete: canUpdate && !isBusy,
                      deletingIndex: isDeleting ? deletingIndex : null,
                      onDelete: canUpdate ? requestDeleteDocument : null,
                    ),
                  ],
                  if (showCommentOnFinalize && canUpdate) ...[
                    SizedBox(height: 14),
                    _SheetTextField(
                      controller: commentController,
                      label: requireComment ? 'Comment *' : 'Comment',
                      maxLines: 3,
                    ),
                  ],
                  if (canFinalize) ...[
                    SizedBox(height: 20),
                    _SheetSubmitButton(
                      label: submitLabel,
                      isSubmitting: isFinalizing,
                      onPressed: finalizeUpload,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    commentController.dispose();
    percentController.dispose();
    percentFocusNode.dispose();
    sheetScrollController.dispose();
    if (refreshAfterClose && mounted) {
      await widget.onActionCompleted();
    }
  }

  Future<void> _showStatusSheet() async {
    final statuses = _stringList(action['allowed_statuses']);
    final allowComment = action['allow_comment'] == true;
    final requireComment = action['require_comment'] == true;
    final showNote = action['show_note'] == true;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: _label('Update status'),
        icon: Icons.sync,
        child: _UpdateStatusSheet(
          statuses: statuses,
          allowComment: allowComment,
          requireComment: requireComment,
          showNote: showNote,
          submitLabel:
              action['submit_button_label']?.toString().trim().isNotEmpty ==
                      true
                  ? action['submit_button_label'].toString().trim()
                  : 'Submit status',
          onSubmit: ({
            required String status,
            required String comment,
            required String note,
          }) {
            return _submitJson(
              endpoint:
                  '/API/workflow/item-runs/$_resolvedWorkflowItemRunId/status',
              payload: {
                'action_id': action['id'],
                'status': status,
                'comment': comment,
                'note': note,
              },
              successMessage: 'Status updated',
              refreshOnSuccess: false,
            );
          },
        ),
      ),
    );

    if (updated == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  Future<void> _showYesNoSheet() async {
    final commentController = TextEditingController();
    final allowComment = action['allow_comment'] == true;
    final requireComment = action['require_comment'] == true;
    final yesLabel =
        toSentenceCaseLabel(action['yes_label']?.toString() ?? 'Yes');
    final noLabel =
        toSentenceCaseLabel(action['no_label']?.toString() ?? 'No');
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit(String decision) async {
              if (requireComment && commentController.text.trim().isEmpty) {
                _showSnackBar('Comment is required.', isError: true);
                return;
              }

              setSheetState(() {
                isSubmitting = true;
              });
              final success = await _submitComplete(
                decision: decision,
                note: commentController.text.trim(),
                refreshOnSuccess: false,
              );
              if (success) {
                await _closeSheetAndRefresh(sheetContext);
              } else if (mounted) {
                setSheetState(() {
                  isSubmitting = false;
                });
              }
            }

            return _BottomSheetFrame(
              title: _label('Yes / no'),
              icon: Icons.rule,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (allowComment)
                    _SheetTextField(
                      controller: commentController,
                      label: requireComment ? 'Comment *' : 'Comment',
                      maxLines: 3,
                    ),
                  if (allowComment) SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSubmitting ? null : () => submit('yes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF10B981),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(yesLabel),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSubmitting ? null : () => submit('no'),
                          child: Text(noLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(Duration(milliseconds: 350));
    commentController.dispose();
  }

  Future<void> _showChecklistSheet() async {
    final items = _mapList(action['items']);
    final responses = <String, dynamic>{};
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              for (final item in items) {
                final id = _itemId(item);
                if (item['required'] == true &&
                    !_hasChecklistValue(responses[id])) {
                  _showSnackBar('${item['label'] ?? 'Item'} is required.',
                      isError: true);
                  return;
                }
              }

              setSheetState(() {
                isSubmitting = true;
              });
              final success = await _submitJson(
                endpoint:
                    '/API/workflow/item-runs/$_workflowItemRunId/checklist',
                payload: {
                  'action_id': action['id'],
                  'responses': responses,
                },
                successMessage: 'Checklist submitted',
                refreshOnSuccess: false,
              );
              if (success) {
                await _closeSheetAndRefresh(sheetContext);
              } else if (mounted) {
                setSheetState(() {
                  isSubmitting = false;
                });
              }
            }

            return _BottomSheetFrame(
              title: _label('Checklist'),
              icon: Icons.checklist,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isEmpty)
                    Text(
                      'No checklist items available.',
                      style:
                          TextStyle(color: AppTheme.getTextSecondary(context)),
                    ),
                  ...items.map(
                    (item) => _ChecklistItemField(
                      item: item,
                      value: responses[_itemId(item)],
                      onChanged: (value) {
                        setSheetState(() {
                          responses[_itemId(item)] = value;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 20),
                  _SheetSubmitButton(
                    label: 'Submit checklist',
                    isSubmitting: isSubmitting,
                    onPressed: items.isEmpty ? null : submit,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showUserChecklistSheet() async {
    final allowComment = action['allow_comment_per_item'] == true;
    final uploadSources = _resolveUserChecklistUploadSources(action);
    final maxVideoDurationSeconds =
        _intValue(action['max_video_duration_seconds']) ?? 60;
    final maxVideoSizeMb = _intValue(action['max_video_size_mb']) ?? 50;
    final submitLabel =
        action['submit_button_label']?.toString().trim().isNotEmpty == true
            ? action['submit_button_label'].toString().trim()
            : 'Submit user checklist';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: _label('User checklist'),
        icon: Icons.playlist_add_check,
        child: _UserChecklistSheet(
          allowComment: allowComment,
          uploadSources: uploadSources,
          maxVideoDurationSeconds: maxVideoDurationSeconds,
          maxVideoSizeMb: maxVideoSizeMb,
          submitLabel: submitLabel,
          onSubmit: (rows) => _submitUserChecklistRows(
            rows,
            uploadSources: uploadSources,
          ),
        ),
      ),
    );

    if (submitted == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  Future<bool> _submitUserChecklistRows(
    List<_UserChecklistRow> validRows, {
    required _WorkflowUploadSourceConfig uploadSources,
  }) async {
    try {
      final credentials = await _credentials();
      final allowImage =
          uploadSources.allowGallery || uploadSources.allowCamera;
      final allowVideo = uploadSources.allowVideo;
      final allowDocument = uploadSources.allowDocument;

      final items = validRows
          .map((row) => {
                'id': row.id,
                'label': row.labelController.text.trim(),
                'checked': row.checked,
                'comment': row.commentController.text.trim(),
              })
          .toList();

      final hasImages = allowImage &&
          validRows.any(
            (row) => row.file != null && row.file!.path.isNotEmpty,
          );
      final hasVideos = allowVideo &&
          validRows.any(
            (row) => row.videoFile != null && row.videoFile!.path.isNotEmpty,
          );
      final hasDocuments = allowDocument &&
          validRows.any(
            (row) => row.docFile != null && row.docFile!.path.isNotEmpty,
          );

      if (hasImages || hasVideos || hasDocuments) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(
            '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/user-checklist',
          ),
        );
        request.fields['user_id'] = credentials.userId;
        request.fields['api_token'] = credentials.apiToken;
        request.fields['action_id'] = action['id']?.toString() ?? '';
        request.fields['items'] = jsonEncode(items);

        for (final row in validRows) {
          if (allowImage &&
              row.file != null &&
              row.file!.path.isNotEmpty &&
              _isAllowedWorkflowUploadFile(row.file!, uploadSources)) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'ucl_file_${row.id}',
                row.file!.path,
                filename: row.file!.name,
                contentType: _workflowUploadMediaType(row.file!),
              ),
            );
          }
          if (allowVideo &&
              row.videoFile != null &&
              row.videoFile!.path.isNotEmpty &&
              _isAllowedWorkflowUploadFile(row.videoFile!, uploadSources)) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'ucl_video_${row.id}',
                row.videoFile!.path,
                filename: row.videoFile!.name,
                contentType: _workflowUploadMediaType(row.videoFile!),
              ),
            );
          }
          if (allowDocument &&
              row.docFile != null &&
              row.docFile!.path.isNotEmpty &&
              _isAllowedWorkflowUploadFile(row.docFile!, uploadSources)) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'ucl_doc_${row.id}',
                row.docFile!.path,
                filename: row.docFile!.name,
                contentType: _workflowUploadMediaType(row.docFile!),
              ),
            );
          }
        }

        final streamed =
            await ApiHttp.send(request).timeout(Duration(seconds: 60));
        final response = await http.Response.fromStream(streamed);
        final message = _successMessageOrThrow(
          response,
          'User checklist submitted',
        );
        _showSnackBar(message);
        return true;
      }

      final response = await ApiHttp.post(
            Uri.parse(
              '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/user-checklist',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': credentials.userId,
              'api_token': credentials.apiToken,
              'action_id': action['id'],
              'items': items,
            }),
          )
          .timeout(Duration(seconds: 30));
      final message =
          _successMessageOrThrow(response, 'User checklist submitted');
      _showSnackBar(message);
      return true;
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return false;
    }
  }

  Future<void> _showSlotSelectionSheet() async {
    final configuredSlotCount = _intValue(_slotActionValue('slot_count')) ?? 3;
    final slotCount = configuredSlotCount.clamp(1, 12).toInt();
    final minNoticeHours = _intValue(_slotActionValue('min_notice_hours'));
    final allowNote = !_falseyValue(_slotActionValue('allow_note'));
    final requireNote = _truthyValue(_slotActionValue('require_note'));
    final timeOptions = _slotTimeOptions(_slotActionValue('time_options'));
    final usePredefinedTimes =
        _truthyValue(_slotActionValue('use_predefined_times')) &&
            timeOptions.isNotEmpty;
    final rows = List<_SlotSelectionRow>.generate(
      slotCount,
      (_) => _SlotSelectionRow(),
    );
    final noteController = TextEditingController();
    final title = _label('Select slots');
    final heading = _slotActionValue('heading')?.toString().trim() ?? '';
    final submitButtonLabel =
        _slotActionValue('submit_button_label')?.toString().trim() ?? '';
    final submitLabel =
        submitButtonLabel.isNotEmpty ? submitButtonLabel : 'Submit slots';
    bool isSubmitting = false;
    String? serverError;
    Map<int, String> rowErrors = <int, String>{};
    String? noteError;

    bool basicFieldsComplete() {
      final slotsReady = rows.every(
        (row) => usePredefinedTimes
            ? row.date != null && row.timeOption != null
            : row.dateTime != null,
      );
      final noteReady = !requireNote || noteController.text.trim().isNotEmpty;
      return slotsReady && noteReady;
    }

    Map<int, String> validateRows() {
      final errors = <int, String>{};
      final seen = <String>{};
      final now = DateTime.now();
      final validLabels = timeOptions.map((option) => option.label).toSet();

      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        late final DateTime selectedAt;
        late final String duplicateKey;

        if (usePredefinedTimes) {
          if (row.date == null || row.timeOption == null) {
            errors[index] = 'Choose a date and time option.';
            continue;
          }
          if (!validLabels.contains(row.timeOption!.label)) {
            errors[index] = 'Choose one of the available time options.';
            continue;
          }
          selectedAt = _combineSlotDateAndTime(row.date!, row.timeOption!.time);
          duplicateKey =
              '${_formatSlotDate(row.date!)} ${row.timeOption!.time}';
        } else {
          if (row.dateTime == null) {
            errors[index] = 'Choose a date and time.';
            continue;
          }
          selectedAt = row.dateTime!;
          duplicateKey = _formatSlotDateTimeValue(row.dateTime!);
        }

        if (minNoticeHours != null &&
            selectedAt.isBefore(now.add(Duration(hours: minNoticeHours)))) {
          errors[index] = 'Slot must be at least $minNoticeHours hours away.';
          continue;
        }
        if (!seen.add(duplicateKey)) {
          errors[index] = 'This date and time is already selected.';
        }
      }

      return errors;
    }

    final submittedResult = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void clearValidationForEdit() {
              rowErrors = <int, String>{};
              noteError = null;
              serverError = null;
            }

            Future<void> pickDate(_SlotSelectionRow row) async {
              final now = DateTime.now();
              final selected = await showDatePicker(
                context: context,
                initialDate: row.date ?? now,
                firstDate: DateTime(now.year, now.month, now.day),
                lastDate: DateTime(now.year + 5),
              );
              if (selected == null) return;
              setSheetState(() {
                clearValidationForEdit();
                row.date = selected;
              });
            }

            Future<void> pickDateTime(_SlotSelectionRow row) async {
              final now = DateTime.now();
              final current = row.dateTime ?? now.add(Duration(hours: 1));
              final selectedDate = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(now.year, now.month, now.day),
                lastDate: DateTime(now.year + 5),
              );
              if (selectedDate == null) return;

              final selectedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(current),
              );
              if (selectedTime == null) return;

              setSheetState(() {
                clearValidationForEdit();
                row.dateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
              });
            }

            Future<void> pickPredefinedTime(_SlotSelectionRow row) async {
              final selected = await showModalBottomSheet<_SlotTimeOption>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _SlotTimeOptionPickerSheet(
                  options: timeOptions,
                  selected: row.timeOption,
                ),
              );
              if (selected == null) return;
              setSheetState(() {
                clearValidationForEdit();
                row.timeOption = selected;
              });
            }

            Future<void> submit() async {
              final validationErrors = validateRows();
              final validationNoteError =
                  requireNote && noteController.text.trim().isEmpty
                      ? 'Comment is required.'
                      : null;

              if (validationErrors.isNotEmpty || validationNoteError != null) {
                setSheetState(() {
                  rowErrors = validationErrors;
                  noteError = validationNoteError;
                  serverError = null;
                });
                return;
              }

              setSheetState(() {
                isSubmitting = true;
                rowErrors = <int, String>{};
                noteError = null;
                serverError = null;
              });

              try {
                final credentials = await _credentials();
                final slotPayload = <Map<String, dynamic>>[];

                for (var index = 0; index < rows.length; index++) {
                  final row = rows[index];
                  if (usePredefinedTimes) {
                    slotPayload.add({
                      'date': _formatSlotDate(row.date!),
                      'time_label': row.timeOption!.label,
                    });
                  } else {
                    slotPayload.add({
                      'value': row.dateTime!.toIso8601String(),
                    });
                  }
                }

                final endpoint =
                    '$_workflowApiBaseUrl/API/workflow/item-runs/$_resolvedWorkflowItemRunId/slot-selection';
                final payload = <String, dynamic>{
                  'user_id': credentials.userId,
                  'api_token': credentials.apiToken,
                  'action_id': action['id']?.toString() ?? '',
                  'slots': slotPayload,
                };
                if (allowNote) {
                  payload['note'] = noteController.text.trim();
                }

                final response = await ApiHttp.post(
                      Uri.parse(endpoint),
                      headers: {
                        'Content-Type': 'application/json',
                        'X-Api-Token': credentials.apiToken,
                      },
                      body: jsonEncode(payload),
                    )
                    .timeout(Duration(seconds: 30));
                print(
                  '[WorkflowSlotSelection] endpoint=$endpoint '
                  'item_run_id=$_resolvedWorkflowItemRunId '
                  'action_id=${action['id']} '
                  'use_predefined_times=$usePredefinedTimes '
                  'slots=$slotPayload '
                  'payload=$payload '
                  'status=${response.statusCode} '
                  'body=${response.body}',
                );
                final message =
                    _successMessageOrThrow(response, 'Slots submitted');
                if (!mounted) return;
                _showSnackBar(message);
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, true);
                }
              } catch (e) {
                final message = e.toString().replaceAll('Exception: ', '');
                setSheetState(() {
                  serverError = message;
                  isSubmitting = false;
                });
                _showSnackBar(message, isError: true);
              }
            }

            final helperText = _slotHelperText(
              heading: heading,
              minNoticeHours: minNoticeHours,
            );
            final canSubmit = basicFieldsComplete();

            return _SlotSelectionSheetFrame(
              title: title,
              subtitle: helperText,
              slotCount: slotCount,
              isSubmitting: isSubmitting,
              submitLabel: submitLabel,
              canSubmit: canSubmit,
              onSubmit: submit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (serverError != null) ...[
                    _SlotServerErrorBanner(message: serverError!),
                    SizedBox(height: 14),
                  ],
                  ...rows.asMap().entries.map(
                        (entry) => _SlotSelectionRowCard(
                          number: entry.key + 1,
                          row: entry.value,
                          usePredefinedTimes: usePredefinedTimes,
                          timeOptions: timeOptions,
                          error: rowErrors[entry.key],
                          onPickDate: () => pickDate(entry.value),
                          onPickDateTime: () => pickDateTime(entry.value),
                          onPickPredefinedTime: () =>
                              pickPredefinedTime(entry.value),
                          onSelectTime: (option) {
                            setSheetState(() {
                              clearValidationForEdit();
                              entry.value.timeOption = option;
                            });
                          },
                        ),
                      ),
                  if (allowNote) ...[
                    SizedBox(height: 4),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      onChanged: (_) => setSheetState(() {
                        noteError = null;
                      }),
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                      ),
                      decoration: _sheetInputDecoration(
                        context,
                        requireNote ? 'Comment *' : 'Comment',
                      ).copyWith(errorText: noteError),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    // The modal can rebuild briefly during route teardown; disposing here can
    // race with TextField cleanup and trigger "controller used after dispose".
    if (submittedResult == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  Future<void> _openRedirect() async {
    final redirectUrl = action['redirect_url']?.toString() ?? '';
    if (redirectUrl.trim().isEmpty) {
      _showSnackBar('No redirect URL available.', isError: true);
      return;
    }

    final uri = Uri.tryParse(redirectUrl);
    if (uri == null) {
      _showSnackBar('Invalid redirect URL.', isError: true);
      return;
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showSnackBar('Could not open link.', isError: true);
    }
  }

  Future<void> _showResponseSheet() async {
    final fresh = await _loadFreshWorkflowActionContext();
    final responseAction = fresh.action;
    final response = _priorResponsePayloadFrom(responseAction);
    final enableApproveValue =
        _actionConfigValueFrom(responseAction, 'enable_approve');
    final allowApprove = _actionType == 'view_prior_response' &&
        _truthyValue(enableApproveValue);
    final approveLabel = _approveResponseLabelFrom(responseAction);
    final requireComment = allowApprove &&
        _truthyValue(_actionConfigValueFrom(responseAction, 'require_comment'));
    final showComment = allowApprove ||
        _truthyValue(_actionConfigValueFrom(responseAction, 'show_comment'));

    _logViewPriorResponseConfig(enableApproveValue);

    final approved = await _showReadOnlyWidgetSheet(
      title: 'View response',
      icon: Icons.visibility_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WorkflowResponseView(response: response),
          if (allowApprove) ...[
            SizedBox(height: 18),
            _ViewPriorResponseApprovalPanel(
              approveLabel: approveLabel,
              showComment: showComment,
              requireComment: requireComment,
              onApprove: (comment) async {
                return _submitViewPriorResponseApproval(
                  comment: comment,
                );
              },
            ),
          ],
        ],
      ),
    );

    if (approved == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  dynamic _actionConfigValue(String key, {Map<String, dynamic>? source}) {
    return _actionConfigValueFrom(source ?? action, key);
  }

  dynamic _actionConfigValueFrom(Map<String, dynamic> source, String key) {
    final directValue = source[key];
    if (!_isBlankConfigValue(directValue)) return directValue;

    for (final configKey in const [
      'config',
      'action_config',
      'task_action_config',
      'settings',
    ]) {
      final config = _configMap(source[configKey]);
      if (config == null) continue;
      final value = config[key];
      if (!_isBlankConfigValue(value)) return value;
    }

    return null;
  }

  String _submitEndpointForAction(
    Map<String, dynamic> source,
    String fallbackSlug,
  ) {
    final configured = source['submit_endpoint']?.toString().trim() ?? '';
    if (configured.isNotEmpty) return configured;
    return '/API/workflow/item-runs/$_resolvedWorkflowItemRunId/$fallbackSlug';
  }

  dynamic _actionResponsePayloadFor(Map<String, dynamic> source) {
    final actionId = source['id'];
    final candidates = <dynamic>[
      source['response'],
      _workflowResponseForAction(task['workflow_action_responses'], actionId),
    ];
    for (final candidate in candidates) {
      final normalized = _decodeResponsePayload(candidate);
      if (normalized is Map && !_isEmptyResponse(normalized)) {
        return normalized;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _pictureChoicePickOptions(
    Map<String, dynamic> pickAction,
  ) {
    final directOptions = _mapListFlexible(pickAction['options']);
    if (directOptions.isNotEmpty) return directOptions;

    final priorList = _priorPictureChoiceListFrom(pickAction);
    return _mapListFlexible(priorList?['options']);
  }

  void _logViewPriorResponseConfig(dynamic enableApproveValue) {
    if (_actionType != 'view_prior_response' ||
        _loggedViewPriorResponseConfig) {
      return;
    }
    _loggedViewPriorResponseConfig = true;

    final configKeys = <String, List<String>>{};
    for (final configKey in const [
      'config',
      'action_config',
      'task_action_config',
      'settings',
    ]) {
      final config = _configMap(action[configKey]);
      if (config != null) {
        configKeys[configKey] =
            config.keys.map((key) => key.toString()).toList();
      }
    }

    print(
      '[ViewPriorResponse] task_id=${task['id']} '
      'resolved_item_run_id=$_resolvedWorkflowItemRunId '
      'action_id=${action['id']} '
      'type=${action['type']} '
      'enable_approve=${action['enable_approve']} '
      'enable_approve_resolved=$enableApproveValue '
      'show_comment=${action['show_comment']} '
      'require_comment=${action['require_comment']} '
      'approve_button_label=${action['approve_button_label']} '
      'action_keys=${action.keys.map((key) => key.toString()).toList()} '
      'config_keys=$configKeys',
    );
  }

  String _approveResponseLabelFrom(Map<String, dynamic> sourceAction) {
    final approveButtonLabel = _actionConfigValueFrom(
      sourceAction,
      'approve_button_label',
    )?.toString().trim();
    if (approveButtonLabel != null && approveButtonLabel.isNotEmpty) {
      return approveButtonLabel;
    }

    final approveLabel =
        _actionConfigValueFrom(sourceAction, 'approve_label')?.toString().trim();
    if (approveLabel != null && approveLabel.isNotEmpty) return approveLabel;

    final submitLabel = _actionConfigValueFrom(
      sourceAction,
      'submit_button_label',
    )?.toString().trim();
    if (submitLabel != null && submitLabel.isNotEmpty) return submitLabel;

    return 'Approve';
  }

  Future<void> _showTextListSheet() async {
    final fresh = await _loadFreshWorkflowActionContext();
    final textAction = fresh.action;
    final canUpdate = fresh.canUpdate ?? _canUpdateTask;
    final response = _configMap(_actionResponsePayloadFor(textAction));
    final isSubmitted =
        textAction['submitted'] == true || response?['submitted'] == true;
    final isReadOnly = !canUpdate || isSubmitted;
    final heading =
        _actionConfigValueFrom(textAction, 'heading')?.toString().trim();
    final title = heading?.isNotEmpty == true
        ? heading!
        : _label('Material request');
    final submitLabel =
        _actionConfigValueFrom(textAction, 'submit_button_label')
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? _actionConfigValueFrom(textAction, 'submit_button_label')
                .toString()
                .trim()
            : 'Send to next task';
    final standardLines = _workflowTextListStandardLines(textAction);
    final linesNeedingQuantity =
        _mapListFlexible(textAction['lines_needing_quantity']);
    final quantityUnits = _stringList(textAction['quantity_units']);
    final allowUserAddedLines =
        textAction['allow_user_added_lines'] == true;
    final userAddedLinesLabel =
        _actionConfigValueFrom(textAction, 'user_added_lines_label')
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? _actionConfigValueFrom(textAction, 'user_added_lines_label')
            .toString()
            .trim()
        : 'Add other';
    final indentEnabled = _workflowTextListIndentEnabled(textAction);
    final createsIndent = textAction['creates_indent'] == true;
    final indentTarget =
        textAction['indent_target']?.toString().trim().toLowerCase() ?? '';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: title,
        icon: Icons.inventory_2_outlined,
        child: isReadOnly
            ? _WorkflowTextListReadOnlyView(
                response: response ?? {},
                textAction: textAction,
                heading: heading,
                indentTarget: indentTarget,
              )
            : _WorkflowTextListSheet(
                heading: heading,
                standardLines: standardLines,
                linesNeedingQuantity: linesNeedingQuantity,
                quantityUnits: quantityUnits.isNotEmpty
                    ? quantityUnits
                    : const ['', 'Bags', 'CFT', 'CUM', 'Kg', 'MT', 'Nos'],
                allowUserAddedLines: allowUserAddedLines,
                userAddedLinesLabel: userAddedLinesLabel,
                indentEnabled: indentEnabled,
                createsIndent: createsIndent,
                submitLabel: submitLabel,
                onSubmit: ({
                  required customLines,
                  required lineQuantities,
                }) =>
                    _submitTextList(
                  textListAction: textAction,
                  customLines: customLines,
                  lineQuantities: lineQuantities,
                ),
              ),
      ),
    );

    if (submitted == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  bool get _canUpdateTask => canUpdateWorkflowTask(task);

  dynamic _currentActionResponse() =>
      _actionResponsePayloadFor(action);

  Map<String, dynamic>? _priorPictureChoiceListFrom(
    Map<String, dynamic> pickAction,
  ) {
    final actionId = pickAction['id']?.toString() ?? '';
    final candidates = <dynamic>[
      pickAction['prior_picture_choice_list'],
      _workflowResponseForAction(
        task['workflow_prior_picture_choice_lists'],
        actionId,
      ),
      _workflowResponseForAction(
        pickAction['workflow_prior_picture_choice_lists'],
        actionId,
      ),
    ];

    for (final candidate in candidates) {
      final map = _configMap(candidate);
      if (map == null) continue;
      if (_mapListFlexible(map['options']).isNotEmpty) return map;
      if (map['submitted_by'] != null || map['submitted_at'] != null) {
        return map;
      }
    }
    return null;
  }

  Map<String, dynamic>? _priorPictureChoiceList() =>
      _priorPictureChoiceListFrom(action);

  String _workflowSuccessMessage(http.Response response, String fallback) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}

    final base = _successMessageOrThrow(response, fallback);
    if (decoded is Map &&
        (decoded['task_routed'] == true || decoded['routed'] == true)) {
      return '$base. Next step started.';
    }
    return base;
  }

  Future<void> _showPictureChoiceListSheet() async {
    final fresh = await _loadFreshWorkflowActionContext();
    final listAction = fresh.action;
    final canUpdate = fresh.canUpdate ?? _canUpdateTask;
    final response = _configMap(_actionResponsePayloadFor(listAction));
    final isReadOnly = !canUpdate || response?['submitted'] == true;
    final heading =
        _actionConfigValueFrom(listAction, 'heading')?.toString().trim().isNotEmpty ==
                true
            ? _actionConfigValueFrom(listAction, 'heading').toString().trim()
            : null;
    final title = heading ?? _label('Picture choice list');
    final submitLabel =
        _actionConfigValueFrom(listAction, 'submit_button_label')
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? _actionConfigValueFrom(listAction, 'submit_button_label')
                .toString()
                .trim()
            : 'Send options to client';
    final allowRuntimeAdd =
        _actionConfigValueFrom(listAction, 'allow_runtime_add') != false;
    final minOptions =
        (_intValue(_actionConfigValueFrom(listAction, 'min_options')) ?? 1)
            .clamp(1, 20);
    final presetOptions = _mapListFlexible(
      _actionConfigValueFrom(listAction, 'options') ?? listAction['options'],
    );

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: title,
        icon: Icons.palette_outlined,
        child: isReadOnly
            ? _PictureChoiceListReadOnlyView(
                response: response ?? {},
                heading: heading,
              )
            : _PictureChoiceListSheet(
                presetOptions: presetOptions,
                heading: heading,
                allowRuntimeAdd: allowRuntimeAdd,
                minOptions: minOptions,
                submitLabel: submitLabel,
                onSubmit: (rows) =>
                    _submitPictureChoiceList(rows, listAction: listAction),
              ),
      ),
    );

    if (submitted == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  Future<bool> _submitPictureChoiceList(
    List<_PictureChoiceListRowState> rows, {
    required Map<String, dynamic> listAction,
  }) async {
    final endpoint =
        _submitEndpointForAction(listAction, 'picture-choice-list');
    final actionId = listAction['id']?.toString() ?? '';
    if (actionId.isEmpty) {
      _showSnackBar('Missing action id.', isError: true);
      return false;
    }

    try {
      final credentials = await _credentials();
      final repeatedFields = <MapEntry<String, String>>[];
      final fileFields = <_PictureChoiceFileField>[];

      for (final row in rows) {
        repeatedFields.add(MapEntry('pcho_name[]', row.name.trim()));
        repeatedFields.add(MapEntry('pcho_id[]', row.id));
        if (row.localImagePath != null) {
          fileFields.add(
            _PictureChoiceFileField(
              field: 'pcho_file_${row.id}',
              path: row.localImagePath!,
              filename: row.localImageName ?? 'option.jpg',
            ),
          );
        }
      }

      final response = await _postWorkflowMultipart(
        uri: Uri.parse(_absoluteWorkflowUrl(endpoint)),
        fields: {
          'user_id': credentials.userId,
          'api_token': credentials.apiToken,
          'action_id': actionId,
        },
        repeatedFields: repeatedFields,
        fileFields: fileFields,
        headers: {'X-Api-Token': credentials.apiToken},
      );
      print(
        '[PictureChoiceList] endpoint=$endpoint '
        'absolute=${_absoluteWorkflowUrl(endpoint)} '
        'item_run_id=$_resolvedWorkflowItemRunId '
        'action_id=$actionId '
        'rows=${rows.length} '
        'status=${response.statusCode} '
        'body=${response.body}',
      );

      final message = _workflowSuccessMessage(
        response,
        'Options sent to client',
      );
      _showSnackBar(message);
      return true;
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return false;
    }
  }

  Future<void> _showPictureChoicePickSheet() async {
    final fresh = await _loadFreshWorkflowActionContext();
    final pickAction = fresh.action;
    final canUpdate = fresh.canUpdate ?? _canUpdateTask;
    final response = _configMap(_actionResponsePayloadFor(pickAction));
    final isReadOnly = !canUpdate || response?['submitted'] == true;
    final pickOptions = _pictureChoicePickOptions(pickAction);
    final priorList = _priorPictureChoiceListFrom(pickAction);
    final heading =
        _actionConfigValueFrom(pickAction, 'heading')?.toString().trim().isNotEmpty ==
                true
            ? _actionConfigValueFrom(pickAction, 'heading').toString().trim()
            : null;
    final title = heading ?? _label('Pick from list');
    final submitLabel =
        _actionConfigValueFrom(pickAction, 'submit_button_label')
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? _actionConfigValueFrom(pickAction, 'submit_button_label')
                .toString()
                .trim()
            : 'Submit choice';
    final allowNote = _actionConfigValueFrom(pickAction, 'allow_note') == true;
    final requireNote =
        _actionConfigValueFrom(pickAction, 'require_note') == true;
    final sourceTaskName =
        _firstString(priorList ?? {}, ['source_task_name', 'task_name']);

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: title,
        icon: Icons.color_lens_outlined,
        child: isReadOnly
            ? _PictureChoicePickReadOnlyView(response: response ?? {})
            : pickOptions.isEmpty
                ? _ResponseEmptyState(
                    message:
                        'Complete picture choice list task first.',
                  )
                : _PictureChoicePickSheet(
                    options: pickOptions,
                    heading: heading,
                    sourceTaskName: sourceTaskName,
                    allowNote: allowNote,
                    requireNote: requireNote,
                    submitLabel: submitLabel,
                    onSubmit: ({
                      required selectedOptionId,
                      required note,
                    }) =>
                        _submitPictureChoicePick(
                      selectedOptionId: selectedOptionId,
                      note: note,
                      pickAction: pickAction,
                    ),
                  ),
      ),
    );

    if (submitted == true && mounted) {
      await Future<void>.delayed(Duration(milliseconds: 250));
      if (mounted) {
        await widget.onActionCompleted();
      }
    }
  }

  Future<bool> _submitPictureChoicePick({
    required String selectedOptionId,
    required String note,
    required Map<String, dynamic> pickAction,
  }) async {
    final endpoint =
        _submitEndpointForAction(pickAction, 'picture-choice-pick');
    final actionId = pickAction['id']?.toString() ?? '';
    if (actionId.isEmpty) {
      _showSnackBar('Missing action id.', isError: true);
      return false;
    }

    try {
      final credentials = await _credentials();
      final body = <String, String>{
        'user_id': credentials.userId,
        'api_token': credentials.apiToken,
        'action_id': actionId,
        'selected_option_id': selectedOptionId,
      };
      if (note.trim().isNotEmpty) {
        body['note'] = note.trim();
      }

      final response = await ApiHttp.post(
            Uri.parse(_absoluteWorkflowUrl(endpoint)),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-Api-Token': credentials.apiToken,
            },
            body: body,
          )
          .timeout(Duration(seconds: 30));
      print(
        '[PictureChoicePick] endpoint=$endpoint '
        'absolute=${_absoluteWorkflowUrl(endpoint)} '
        'item_run_id=$_resolvedWorkflowItemRunId '
        'action_id=$actionId '
        'selected_option_id=$selectedOptionId '
        'status=${response.statusCode} '
        'body=${response.body}',
      );

      final message = _workflowSuccessMessage(response, 'Choice submitted');
      _showSnackBar(message);
      return true;
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
      return false;
    }
  }

  void _showReadOnlySheet({
    required String title,
    required IconData icon,
    required String content,
  }) {
    _showReadOnlyWidgetSheet(
      title: title,
      icon: icon,
      child: SelectableText(
        content.isEmpty ? 'No response available.' : content,
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Future<dynamic> _showReadOnlyWidgetSheet({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetFrame(
        title: title,
        icon: icon,
        child: child,
      ),
    );
  }

  dynamic _priorResponsePayloadFrom(Map<String, dynamic> sourceAction) {
    final actionId = sourceAction['id'];
    final candidates = <dynamic>[
      sourceAction['response'],
      sourceAction['prior_response'],
      _workflowResponseForAction(sourceAction['prior_responses'], actionId),
      _directResponsePayload(sourceAction['prior_responses']),
      _workflowResponseForAction(
        sourceAction['workflow_prior_responses'],
        actionId,
      ),
      _workflowResponseForAction(task['workflow_prior_responses'], actionId),
      _workflowResponseForAction(task['workflow_action_responses'], actionId),
    ];

    for (final candidate in candidates) {
      final normalized = _decodeResponsePayload(candidate);
      if (!_isEmptyResponse(normalized)) return normalized;
    }
    return null;
  }

  dynamic _directResponsePayload(dynamic value) {
    final normalized = _decodeResponsePayload(value);
    if (normalized is Map &&
        (_mapList(normalized['entries']).isNotEmpty ||
            _mapList(normalized['tasks']).isNotEmpty)) {
      return normalized;
    }
    if (normalized is List) return normalized;
    return null;
  }

  String _successMessageOrThrow(http.Response response, String fallback) {
    // Safety net: if ApiHttp somehow returned an invalid-token body (e.g. the
    // soft confirm probe failed), still show the popup and log the user out.
    if (SessionManager.instance.isSessionInvalidResponse(response)) {
      SessionManager.instance.handleResponse(
        response,
        confirmBeforeLogout: false,
      );
      throw SessionInvalidatedException();
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map && decoded['success'] == false) {
        final message = decoded['message']?.toString() ?? 'Action failed';
        throw Exception(message);
      }
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
      return fallback;
    }

    if (decoded is Map && decoded['message'] != null) {
      final message = decoded['message'].toString().trim();
      if (message.isNotEmpty) {
        throw Exception(message);
      }
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final location = response.headers['location'];
      if (location != null && location.trim().isNotEmpty) {
        throw Exception('Request was redirected to $location');
      }
      throw Exception('Request was redirected by the server.');
    }
    throw Exception('Server error: ${response.statusCode}');
  }

  dynamic _workflowResponseForAction(dynamic responses, dynamic actionId) {
    responses = _decodeResponsePayload(responses);
    if (responses is Map) {
      return responses[actionId?.toString()] ?? responses[actionId];
    }
    if (responses is List) {
      for (final response in responses) {
        if (response is Map &&
            response['action_id']?.toString() == actionId?.toString()) {
          return response;
        }
      }
    }
    return null;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final cleaned = message.replaceAll('Exception: ', '').trim();
    if (cleaned.isEmpty) return;
    if (cleaned == SessionManager.logoutMessage ||
        cleaned == SessionManager.logoutDialogTitle ||
        cleaned.toLowerCase().contains('invalid api token') ||
        cleaned.toLowerCase().contains('signed in on another device') ||
        cleaned.toLowerCase().contains('two devices')) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cleaned),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

class _WorkflowButtonData {
  final String defaultLabel;
  final IconData icon;
  final Color color;
  final bool outlined;

  const _WorkflowButtonData({
    required this.defaultLabel,
    required this.icon,
    required this.color,
    this.outlined = false,
  });
}

class _WorkflowCredentials {
  final String userId;
  final String apiToken;

  const _WorkflowCredentials({
    required this.userId,
    required this.apiToken,
  });
}

class _FreshWorkflowActionContext {
  final Map<String, dynamic> action;
  final bool? canUpdate;

  const _FreshWorkflowActionContext({
    required this.action,
    this.canUpdate,
  });
}

class _WorkflowTextListCustomRow {
  final TextEditingController nameController;
  final TextEditingController quantityController;
  String unit;

  _WorkflowTextListCustomRow({
    required this.nameController,
    required this.quantityController,
    this.unit = '',
  });

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
  }
}

class _WorkflowTextListSheet extends StatefulWidget {
  final String? heading;
  final List<Map<String, dynamic>> standardLines;
  final List<Map<String, dynamic>> linesNeedingQuantity;
  final List<String> quantityUnits;
  final bool allowUserAddedLines;
  final String userAddedLinesLabel;
  final bool indentEnabled;
  final bool createsIndent;
  final String submitLabel;
  final Future<bool> Function({
    required List<Map<String, dynamic>> customLines,
    required Map<String, Map<String, String>> lineQuantities,
  }) onSubmit;

  const _WorkflowTextListSheet({
    required this.heading,
    required this.standardLines,
    required this.linesNeedingQuantity,
    required this.quantityUnits,
    required this.allowUserAddedLines,
    required this.userAddedLinesLabel,
    required this.indentEnabled,
    required this.createsIndent,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_WorkflowTextListSheet> createState() => _WorkflowTextListSheetState();
}

class _WorkflowTextListSheetState extends State<_WorkflowTextListSheet> {
  late final Map<String, TextEditingController> _quantityControllers;
  late final Map<String, String> _unitSelections;
  final List<_WorkflowTextListCustomRow> _customRows = [];
  bool _isSubmitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _quantityControllers = {
      for (final line in widget.linesNeedingQuantity)
        if (_firstString(line, ['id']) != null)
          _firstString(line, ['id'])!: TextEditingController(),
    };
    _unitSelections = {
      for (final line in widget.linesNeedingQuantity)
        if (_firstString(line, ['id']) != null)
          _firstString(line, ['id'])!:
              _firstString(line, ['unit']) ?? widget.quantityUnits.first,
    };
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    for (final row in _customRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addCustomRow() {
    setState(() {
      _customRows.add(
        _WorkflowTextListCustomRow(
          nameController: TextEditingController(),
          quantityController: TextEditingController(),
          unit: widget.quantityUnits.first,
        ),
      );
      _formError = null;
    });
  }

  void _removeCustomRow(int index) {
    setState(() {
      _customRows[index].dispose();
      _customRows.removeAt(index);
      _formError = null;
    });
  }

  String? _validate() {
    final totalLines =
        widget.standardLines.length + _customRows.length;
    if (totalLines == 0) {
      return 'Add at least one material line.';
    }

    if (widget.createsIndent) {
      for (final line in widget.linesNeedingQuantity) {
        final id = _firstString(line, ['id']);
        if (id == null) continue;
        final qty = _quantityControllers[id]?.text.trim() ?? '';
        if (qty.isEmpty || (double.tryParse(qty) ?? 0) <= 0) {
          final label = _textListLineLabel(line);
          return 'Quantity required for $label';
        }
      }

      for (final row in _customRows) {
        final name = row.nameController.text.trim();
        if (name.isEmpty) {
          return 'Item name is required for custom lines.';
        }
        if (widget.indentEnabled) {
          final qty = row.quantityController.text.trim();
          if (qty.isEmpty || (double.tryParse(qty) ?? 0) <= 0) {
            return 'Quantity required for $name';
          }
        }
      }
    } else {
      for (final row in _customRows) {
        if (row.nameController.text.trim().isEmpty) {
          return 'Item name is required for custom lines.';
        }
      }
    }

    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final validationError = _validate();
    if (validationError != null) {
      setState(() {
        _formError = validationError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    final lineQuantities = <String, Map<String, String>>{};
    for (final entry in _quantityControllers.entries) {
      final qty = entry.value.text.trim();
      if (qty.isEmpty) continue;
      lineQuantities[entry.key] = {
        'quantity': qty,
        'unit': _unitSelections[entry.key]?.trim() ?? '',
      };
    }

    final customLines = _customRows
        .map((row) {
          final payload = <String, dynamic>{
            'text': row.nameController.text.trim(),
          };
          if (widget.indentEnabled) {
            payload['quantity'] = row.quantityController.text.trim();
            payload['unit'] = row.unit.trim();
          }
          return payload;
        })
        .where((line) => line['text'].toString().trim().isNotEmpty)
        .map((line) => Map<String, dynamic>.from(line))
        .toList();

    final submitted = await widget.onSubmit(
      customLines: customLines,
      lineQuantities: lineQuantities,
    );
    if (!mounted) return;

    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.standardLines.isEmpty &&
        widget.linesNeedingQuantity.isEmpty &&
        !widget.allowUserAddedLines) {
      return _ResponseEmptyState(message: 'No material items available.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.heading != null && widget.heading!.isNotEmpty) ...[
          Text(
            widget.heading!,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          SizedBox(height: 14),
        ],
        if (_formError != null) ...[
          _SlotServerErrorBanner(message: _formError!),
          SizedBox(height: 14),
        ],
        if (widget.linesNeedingQuantity.isNotEmpty) ...[
          Text(
            'Enter quantities',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          ...widget.linesNeedingQuantity.map((line) {
            final id = _firstString(line, ['id']) ?? '';
            final controller = _quantityControllers[id];
            if (controller == null) return SizedBox.shrink();
            return _WorkflowTextListQuantityRow(
              label: _textListLineLabel(line),
              quantityController: controller,
              unit: _unitSelections[id] ?? widget.quantityUnits.first,
              quantityUnits: widget.quantityUnits,
              required: widget.createsIndent,
              onUnitChanged: (value) {
                setState(() {
                  _unitSelections[id] = value;
                });
              },
            );
          }),
          SizedBox(height: 14),
        ],
        if (widget.allowUserAddedLines) ...[
          Row(
            children: [
              Text(
                widget.userAddedLinesLabel,
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              TextButton.icon(
                onPressed: _isSubmitting ? null : _addCustomRow,
                icon: Icon(Icons.add_circle_outline),
                label: Text('Add row'),
              ),
            ],
          ),
          ..._customRows.asMap().entries.map(
                (entry) => _WorkflowTextListCustomLineCard(
                  index: entry.key,
                  row: entry.value,
                  indentEnabled: widget.indentEnabled,
                  quantityUnits: widget.quantityUnits,
                  onRemove: () => _removeCustomRow(entry.key),
                  onUnitChanged: (value) {
                    setState(() {
                      entry.value.unit = value;
                    });
                  },
                ),
              ),
          SizedBox(height: 14),
        ],
        _ApproveResponseButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _WorkflowTextListStandardLineCard extends StatelessWidget {
  final Map<String, dynamic> line;
  final bool indentEnabled;

  const _WorkflowTextListStandardLineCard({
    required this.line,
    required this.indentEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•',
            style: TextStyle(
              color: AppTheme.getPrimaryColor(context),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _textListLineDisplay(line, indentEnabled: indentEnabled),
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowTextListQuantityRow extends StatelessWidget {
  final String label;
  final TextEditingController quantityController;
  final String unit;
  final List<String> quantityUnits;
  final bool required;
  final ValueChanged<String> onUnitChanged;

  const _WorkflowTextListQuantityRow({
    required this.label,
    required this.quantityController,
    required this.unit,
    required this.quantityUnits,
    required this.required,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppTheme.getTextPrimary(context)),
                  decoration: _sheetInputDecoration(
                    context,
                    required ? 'Quantity *' : 'Quantity',
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: quantityUnits.contains(unit)
                      ? unit
                      : quantityUnits.first,
                  items: quantityUnits
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option,
                          child: Text(
                            option.isEmpty ? 'Unit' : option,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onUnitChanged(value);
                  },
                  decoration: _sheetInputDecoration(context, 'Unit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkflowTextListCustomLineCard extends StatelessWidget {
  final int index;
  final _WorkflowTextListCustomRow row;
  final bool indentEnabled;
  final List<String> quantityUnits;
  final VoidCallback onRemove;
  final ValueChanged<String> onUnitChanged;

  const _WorkflowTextListCustomLineCard({
    required this.index,
    required this.row,
    required this.indentEnabled,
    required this.quantityUnits,
    required this.onRemove,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Custom ${index + 1}',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.delete_outline, color: Colors.red[400]),
              ),
            ],
          ),
          TextField(
            controller: row.nameController,
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: _sheetInputDecoration(context, 'Item name *'),
          ),
          if (indentEnabled) ...[
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.quantityController,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppTheme.getTextPrimary(context)),
                    decoration: _sheetInputDecoration(context, 'Quantity *'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: quantityUnits.contains(row.unit)
                        ? row.unit
                        : quantityUnits.first,
                    items: quantityUnits
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option,
                            child: Text(
                              option.isEmpty ? 'Unit' : option,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onUnitChanged(value);
                    },
                    decoration: _sheetInputDecoration(context, 'Unit'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkflowTextListReadOnlyView extends StatelessWidget {
  final Map<String, dynamic> response;
  final Map<String, dynamic> textAction;
  final String? heading;
  final String indentTarget;

  const _WorkflowTextListReadOnlyView({
    required this.response,
    required this.textAction,
    required this.heading,
    required this.indentTarget,
  });

  @override
  Widget build(BuildContext context) {
    final savedLines = _mapListFlexible(
      response['saved_lines'] ?? response['lines'] ?? textAction['saved_lines'],
    );
    final indents = _mapListFlexible(response['indents_created']);
    final submittedBy = _firstString(response, [
      'submitted_by',
      'submitted_by_name',
    ]);
    final submittedAt = response['submitted_at']?.toString();
    final message = response['message']?.toString();
    final indentEnabled = _workflowTextListIndentEnabled(textAction);
    final displayLines = savedLines.isNotEmpty
        ? savedLines
        : _workflowTextListStandardLines(textAction);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading != null && heading!.isNotEmpty) ...[
          Text(
            heading!,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          SizedBox(height: 14),
        ],
        if (message != null && message.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Color(0xFF10B981).withOpacity(0.25)),
            ),
            child: Text(
              message,
              style: TextStyle(
                color: Color(0xFF065F46),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: 12),
        ],
        if (submittedBy != null || submittedAt != null) ...[
          _FollowupInfoBlock(
            label: 'Submitted',
            text: [
              if (submittedBy != null) submittedBy,
              if (submittedAt != null) submittedAt,
            ].join(' • '),
            icon: Icons.check_circle_outline,
          ),
          SizedBox(height: 14),
        ],
        if (displayLines.isNotEmpty) ...[
          Text(
            'Saved lines',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          ...displayLines.map(
            (line) => _WorkflowTextListStandardLineCard(
              line: line,
              indentEnabled: indentEnabled,
            ),
          ),
          SizedBox(height: 14),
        ],
        if (indents.isNotEmpty) ...[
          Text(
            _textListIndentQueueLabel(indentTarget),
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          ...indents.map(
            (indent) => _WorkflowTextListIndentLinkCard(
              indent: indent,
              textAction: textAction,
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkflowTextListIndentLinkCard extends StatelessWidget {
  final Map<String, dynamic> indent;
  final Map<String, dynamic> textAction;

  const _WorkflowTextListIndentLinkCard({
    required this.indent,
    required this.textAction,
  });

  @override
  Widget build(BuildContext context) {
    final indentId = indent['id']?.toString() ?? '';
    final lineCount = indent['line_count']?.toString();
    final detailsUrl = _firstString(indent, ['url']) ??
        _textListIndentPath(
          textAction['indent_details_path'],
          indentId: indentId,
        );
    final materialUrl = _firstString(indent, [
      'view_material_url',
      'view_material_path',
    ]) ??
        _textListIndentPath(
          textAction['view_material_path'],
          indentId: indentId,
        );

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            indentId.isEmpty ? 'Indent created' : 'Indent #$indentId',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (lineCount != null) ...[
            SizedBox(height: 4),
            Text(
              '$lineCount line${lineCount == '1' ? '' : 's'}',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (detailsUrl != null) ...[
            SizedBox(height: 8),
            _WorkflowTextListLinkButton(
              label: 'Indent details',
              url: detailsUrl,
            ),
          ],
          if (materialUrl != null) ...[
            SizedBox(height: 6),
            _WorkflowTextListLinkButton(
              label: 'View material list',
              url: materialUrl,
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkflowTextListLinkButton extends StatelessWidget {
  final String label;
  final String url;

  const _WorkflowTextListLinkButton({
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openExternalUrl(url),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.open_in_new, size: 16, color: AppTheme.getPrimaryColor(context)),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppTheme.getPrimaryColor(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KypMaterialShiftSubmitResult {
  final List<Map<String, dynamic>> finalList;
  final bool taskRouted;

  const _KypMaterialShiftSubmitResult({
    required this.finalList,
    required this.taskRouted,
  });
}

class _KypMaterialShiftItem {
  final String material;
  final double standardQty;
  final String unit;
  final String display;
  final String source;
  final double draftShiftQty;

  const _KypMaterialShiftItem({
    required this.material,
    required this.standardQty,
    required this.unit,
    required this.display,
    required this.source,
    required this.draftShiftQty,
  });
}

class _KypFinalListRow {
  final String material;
  final double remaining;
  final String unit;

  const _KypFinalListRow({
    required this.material,
    required this.remaining,
    required this.unit,
  });
}

class _KypMaterialShiftRow {
  final _KypMaterialShiftItem item;
  final TextEditingController quantityController;

  _KypMaterialShiftRow({required this.item})
      : quantityController = TextEditingController(
          text: item.draftShiftQty > 0
              ? _formatKypQty(item.draftShiftQty)
              : '',
        );

  void dispose() {
    quantityController.dispose();
  }

  double get parsedShiftQty {
    final raw = quantityController.text.trim();
    if (raw.isEmpty) return 0;
    return double.tryParse(raw) ?? 0;
  }
}

class _KypMaterialShiftSheet extends StatefulWidget {
  final List<_KypMaterialShiftItem> materials;
  final String destinationProjectId;
  final String destinationProjectName;
  final String submitLabel;
  final String finalListTitle;
  final String finalListHelp;
  final List<Map<String, dynamic>> initialFinalList;
  final String? draftFromProjectId;
  final Future<_KypMaterialShiftSubmitResult?> Function({
    required String fromProjectId,
    required List<Map<String, dynamic>> materials,
    String? shiftingDate,
    String? differenceCost,
  }) onSubmit;

  const _KypMaterialShiftSheet({
    required this.materials,
    required this.destinationProjectId,
    required this.destinationProjectName,
    required this.submitLabel,
    required this.finalListTitle,
    required this.finalListHelp,
    required this.initialFinalList,
    this.draftFromProjectId,
    required this.onSubmit,
  });

  @override
  State<_KypMaterialShiftSheet> createState() => _KypMaterialShiftSheetState();
}

class _KypMaterialShiftSheetState extends State<_KypMaterialShiftSheet> {
  late final List<_KypMaterialShiftRow> _rows;
  final TextEditingController _differenceCostController =
      TextEditingController(text: '0');
  List<Map<String, dynamic>> _projects = <Map<String, dynamic>>[];
  Map<String, dynamic>? _selectedProject;
  DateTime? _shiftingDate;
  bool _isLoadingProjects = true;
  bool _isSubmitting = false;
  String? _projectError;
  String? _materialError;
  final Map<int, String?> _rowQuantityErrors = {};
  late List<_KypFinalListRow> _finalListRows;

  @override
  void initState() {
    super.initState();
    _rows = widget.materials
        .map((item) => _KypMaterialShiftRow(item: item))
        .toList();
    _finalListRows = _initialFinalListRows();
    _loadProjects();
  }

  List<_KypFinalListRow> _initialFinalListRows() {
    if (widget.initialFinalList.isNotEmpty) {
      return widget.initialFinalList
          .map(
            (row) => _KypFinalListRow(
              material: _firstString(row, ['material', 'name']) ?? '',
              remaining: _parseKypQty(
                    row['remaining'] ??
                        row['remaining_qty'] ??
                        row['quantity'],
                  ) ??
                  0,
              unit: _firstString(row, ['unit']) ?? '',
            ),
          )
          .where((row) => row.material.isNotEmpty)
          .toList();
    }
    return _computeFinalListRows();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _differenceCostController.dispose();
    super.dispose();
  }

  List<_KypFinalListRow> _computeFinalListRows() {
    return _rows
        .map(
          (row) => _KypFinalListRow(
            material: row.item.material,
            remaining: row.item.standardQty - row.parsedShiftQty,
            unit: row.item.unit,
          ),
        )
        .toList();
  }

  void _onShiftQtyChanged(int index) {
    setState(() {
      _rowQuantityErrors.remove(index);
      _materialError = null;
      final row = _rows[index];
      final shiftQty = row.parsedShiftQty;
      final raw = row.quantityController.text.trim();
      if (raw.isNotEmpty && shiftQty <= 0) {
        _rowQuantityErrors[index] = 'Enter a valid shift quantity.';
      } else if (shiftQty > row.item.standardQty) {
        _rowQuantityErrors[index] =
            'Cannot exceed ${_formatKypQty(row.item.standardQty)} ${row.item.unit}.';
      }
      _finalListRows = _computeFinalListRows();
    });
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoadingProjects = true;
    });
    await DataProvider().loadProjects();
    if (!mounted) return;

    final destinationId = widget.destinationProjectId;
    final projects = DataProvider()
        .projects
        .whereType<Map>()
        .map((project) => Map<String, dynamic>.from(project))
        .where((project) => project['id']?.toString() != destinationId)
        .toList();

    Map<String, dynamic>? preselected;
    final draftId = widget.draftFromProjectId;
    if (draftId != null && draftId.isNotEmpty) {
      for (final project in projects) {
        if (project['id']?.toString() == draftId) {
          preselected = project;
          break;
        }
      }
    }

    setState(() {
      _projects = projects;
      _selectedProject = preselected;
      _isLoadingProjects = false;
    });
  }

  Future<void> _pickSourceProject() async {
    if (_projects.isEmpty && !_isLoadingProjects) {
      await _loadProjects();
    }
    if (!mounted) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KypProjectPickerSheet(
        projects: _projects,
        selectedProjectId: _selectedProject?['id']?.toString(),
        isLoading: _isLoadingProjects,
      ),
    );
    if (selected == null) return;

    setState(() {
      _selectedProject = selected;
      _projectError = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _shiftingDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (selected == null) return;
    setState(() {
      _shiftingDate = selected;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final fromProjectId = _selectedProject?['id']?.toString().trim() ?? '';
    final materials = <Map<String, dynamic>>[];
    final rowErrors = <int, String?>{};
    var hasRowError = false;

    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      final rawQuantity = row.quantityController.text.trim();
      if (rawQuantity.isEmpty) continue;

      final quantity = double.tryParse(rawQuantity);
      if (quantity == null || quantity <= 0) {
        rowErrors[index] = 'Enter a valid shift quantity.';
        hasRowError = true;
        continue;
      }
      if (quantity > row.item.standardQty) {
        rowErrors[index] =
            'Cannot exceed ${_formatKypQty(row.item.standardQty)} ${row.item.unit}.';
        hasRowError = true;
        continue;
      }

      materials.add({
        'material': row.item.material,
        'quantity': _jsonQuantity(quantity),
        'unit': row.item.unit,
        'source': row.item.source,
      });
    }

    if (fromProjectId.isEmpty || hasRowError || materials.isEmpty) {
      setState(() {
        _projectError =
            fromProjectId.isEmpty ? 'Select source project.' : null;
        _rowQuantityErrors
          ..clear()
          ..addAll(rowErrors);
        _materialError = hasRowError
            ? 'Fix shift quantity errors before submitting.'
            : (materials.isEmpty
                ? 'Enter shift quantity for at least one material.'
                : null);
      });
      return;
    }

    final differenceCost = _differenceCostController.text.trim();
    if (differenceCost.isNotEmpty && double.tryParse(differenceCost) == null) {
      setState(() {
        _materialError = 'Difference cost must be a valid number.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _projectError = null;
      _materialError = null;
      _rowQuantityErrors.clear();
    });

    final result = await widget.onSubmit(
      fromProjectId: fromProjectId,
      materials: materials,
      shiftingDate: _shiftingDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(_shiftingDate!),
      differenceCost: differenceCost.isEmpty ? '0' : differenceCost,
    );
    if (!mounted) return;

    if (result != null) {
      if (result.finalList.isNotEmpty) {
        setState(() {
          _finalListRows = result.finalList
              .map(
                (row) => _KypFinalListRow(
                  material: _firstString(row, ['material', 'name']) ?? '',
                  remaining: _parseKypQty(
                        row['remaining'] ??
                            row['remaining_qty'] ??
                            row['quantity'],
                      ) ??
                      0,
                  unit: _firstString(row, ['unit']) ?? '',
                ),
              )
              .where((row) => row.material.isNotEmpty)
              .toList();
        });
      }
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedProjectName = _projectDisplayName(_selectedProject);
    final destinationName = widget.destinationProjectId.isEmpty
        ? widget.destinationProjectName
        : '${widget.destinationProjectName} (${widget.destinationProjectId})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KypShiftProjectCard(
          label: 'Shift from project',
          value: _isLoadingProjects
              ? 'Loading projects...'
              : selectedProjectName ?? 'Select source project',
          icon: Icons.outbox_outlined,
          onTap: _isSubmitting || _isLoadingProjects ? null : _pickSourceProject,
          isError: _projectError != null,
        ),
        if (_projectError != null) ...[
          SizedBox(height: 6),
          Text(
            _projectError!,
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        SizedBox(height: 12),
        _KypShiftProjectCard(
          label: 'Shift to project',
          value: destinationName,
          icon: Icons.inbox_outlined,
          onTap: null,
        ),
        SizedBox(height: 16),
        Text(
          'Materials',
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        _KypMaterialShiftTableHeader(),
        SizedBox(height: 6),
        if (_rows.isEmpty)
          _ResponseEmptyState(message: 'No materials configured for shifting.')
        else
          ..._rows.asMap().entries.map(
                (entry) => _KypMaterialShiftRowCard(
                  row: entry.value,
                  rowIndex: entry.key,
                  isLast: entry.key == _rows.length - 1,
                  quantityError: _rowQuantityErrors[entry.key],
                  onChanged: () => _onShiftQtyChanged(entry.key),
                ),
              ),
        if (_materialError != null) ...[
          SizedBox(height: 8),
          Text(
            _materialError!,
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        SizedBox(height: 18),
        Text(
          widget.finalListTitle,
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          widget.finalListHelp,
          style: TextStyle(
            color: AppTheme.getTextSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        SizedBox(height: 8),
        _KypFinalListTable(rows: _finalListRows),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _KypOptionalFieldCard(
                label: 'Shifting date',
                value: _shiftingDate == null
                    ? 'Optional'
                    : DateFormat('yyyy-MM-dd').format(_shiftingDate!),
                icon: Icons.calendar_today_outlined,
                onTap: _isSubmitting ? null : _pickDate,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _differenceCostController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AppTheme.getTextPrimary(context)),
                decoration: _sheetInputDecoration(
                  context,
                  'Difference cost',
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 18),
        _ApproveResponseButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _KypMaterialShiftReadOnlyView extends StatelessWidget {
  final Map<String, dynamic> response;
  final String destinationProjectId;
  final String destinationProjectName;
  final String finalListTitle;
  final String finalListHelp;
  final List<Map<String, dynamic>> actionFinalList;

  const _KypMaterialShiftReadOnlyView({
    required this.response,
    required this.destinationProjectId,
    required this.destinationProjectName,
    required this.finalListTitle,
    required this.finalListHelp,
    required this.actionFinalList,
  });

  @override
  Widget build(BuildContext context) {
    final fromProjectId = response['from_project_id']?.toString() ?? '';
    final fromProjectName = _firstString(response, [
          'from_project_name',
          'source_project_name',
        ]) ??
        (fromProjectId.isEmpty ? 'Source project' : 'Project $fromProjectId');
    final shiftedMaterials = _mapListFlexible(response['materials']);
    final finalList = _mapListFlexible(response['final_list']).isNotEmpty
        ? _mapListFlexible(response['final_list'])
        : actionFinalList;
    final message = response['message']?.toString();
    final requestedBy = _firstString(response, [
      'requested_by',
      'requested_by_name',
      'submitted_by',
      'submitted_by_name',
    ]);

    final finalRows = finalList
        .map(
          (row) => _KypFinalListRow(
            material: _firstString(row, ['material', 'name']) ?? '',
            remaining: _parseKypQty(
                  row['remaining'] ??
                      row['remaining_qty'] ??
                      row['quantity'],
                ) ??
                0,
            unit: _firstString(row, ['unit']) ?? '',
          ),
        )
        .where((row) => row.material.isNotEmpty)
        .toList();

    final destinationLabel = destinationProjectId.isEmpty
        ? destinationProjectName
        : '$destinationProjectName ($destinationProjectId)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message != null && message.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Color(0xFF10B981).withOpacity(0.25)),
            ),
            child: Text(
              message,
              style: TextStyle(
                color: Color(0xFF065F46),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: 12),
        ],
        _KypShiftProjectCard(
          label: 'Shift from project',
          value: fromProjectName,
          icon: Icons.outbox_outlined,
          onTap: null,
        ),
        SizedBox(height: 10),
        _KypShiftProjectCard(
          label: 'Shift to project',
          value: destinationLabel,
          icon: Icons.inbox_outlined,
          onTap: null,
        ),
        if (requestedBy != null) ...[
          SizedBox(height: 10),
          _KypShiftProjectCard(
            label: 'Requested by',
            value: requestedBy,
            icon: Icons.person_outline,
            onTap: null,
          ),
        ],
        if (shiftedMaterials.isNotEmpty) ...[
          SizedBox(height: 16),
          Text(
            'Shifted materials',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          ...shiftedMaterials.map((row) {
            final material =
                _firstString(row, ['material', 'name']) ?? 'Material';
            final qty = _firstString(row, ['quantity']) ??
                _formatKypQty(
                  _parseKypQty(row['quantity']) ?? 0,
                );
            final unit = _firstString(row, ['unit']) ?? '';
            return Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _premiumSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Color(0xFFE5E7EB)),
              ),
              child: Text(
                '$material — $qty $unit'.trim(),
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }),
        ],
        SizedBox(height: 16),
        Text(
          finalListTitle,
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          finalListHelp,
          style: TextStyle(
            color: AppTheme.getTextSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8),
        _KypFinalListTable(rows: finalRows),
      ],
    );
  }
}

class _KypMaterialShiftTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle style = TextStyle(
      color: AppTheme.getTextSecondary(context),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Material', style: style)),
          Expanded(flex: 3, child: Text('Standard qty', style: style)),
          Expanded(flex: 2, child: Text('Unit', style: style)),
          Expanded(flex: 3, child: Text('Shift qty', style: style)),
        ],
      ),
    );
  }
}

class _KypFinalListTable extends StatelessWidget {
  final List<_KypFinalListRow> rows;

  const _KypFinalListTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _ResponseEmptyState(message: 'No materials to display.');
    }

    TextStyle headerStyle = TextStyle(
      color: AppTheme.getTextSecondary(context),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('Material', style: headerStyle)),
                Expanded(flex: 3, child: Text('Remaining', style: headerStyle)),
                Expanded(flex: 2, child: Text('Unit', style: headerStyle)),
              ],
            ),
          ),
          Divider(height: 1, color: Color(0xFFE5E7EB)),
          ...rows.asMap().entries.map((entry) {
            final row = entry.value;
            final isLast = entry.key == rows.length - 1;
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          row.material,
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _formatKypQty(row.remaining),
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          row.unit,
                          style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast) Divider(height: 1, color: Color(0xFFE5E7EB)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _KypShiftProjectCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isError;

  const _KypShiftProjectCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _premiumSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isError ? Colors.red : Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      AppTheme.getPrimaryColor(context).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.getPrimaryColor(context)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.getTextSecondary(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KypMaterialShiftRowCard extends StatelessWidget {
  final _KypMaterialShiftRow row;
  final int rowIndex;
  final bool isLast;
  final String? quantityError;
  final VoidCallback onChanged;

  const _KypMaterialShiftRowCard({
    required this.row,
    required this.rowIndex,
    required this.isLast,
    required this.quantityError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final item = row.item;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: quantityError != null ? Colors.red : Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  item.material,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  _formatKypQty(item.standardQty),
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.unit,
                  style: TextStyle(
                    color: AppTheme.getTextSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: row.quantityController,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 12.5,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    hintText: '0',
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppTheme.getPrimaryColor(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (quantityError != null) ...[
            SizedBox(height: 6),
            Text(
              quantityError!,
              style: TextStyle(
                color: Colors.red,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KypOptionalFieldCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _KypOptionalFieldCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _premiumSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.getPrimaryColor(context)),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KypProjectPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> projects;
  final String? selectedProjectId;
  final bool isLoading;

  const _KypProjectPickerSheet({
    required this.projects,
    required this.selectedProjectId,
    required this.isLoading,
  });

  @override
  State<_KypProjectPickerSheet> createState() => _KypProjectPickerSheetState();
}

class _KypProjectPickerSheetState extends State<_KypProjectPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase().trim();
    final filtered = query.isEmpty
        ? widget.projects
        : widget.projects.where((project) {
            final name = _projectDisplayName(project)?.toLowerCase() ?? '';
            final id = project['id']?.toString().toLowerCase() ?? '';
            final client =
                project['client_name']?.toString().toLowerCase() ?? '';
            return name.contains(query) ||
                id.contains(query) ||
                client.contains(query);
          }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Shift from project',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: AppTheme.getTextPrimary(context)),
              decoration: _sheetInputDecoration(
                context,
                'Search projects',
              ).copyWith(prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: widget.isLoading
                ? const SkeletonSheetLoader(itemCount: 6)
                : filtered.isEmpty
                    ? _ResponseEmptyState(message: 'No source projects found.')
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 18),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final project = filtered[index];
                          final projectId = project['id']?.toString() ?? '';
                          final selected =
                              projectId == widget.selectedProjectId;
                          final name =
                              _projectDisplayName(project) ?? 'Unnamed project';
                          final client =
                              project['client_name']?.toString().trim() ?? '';

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, project),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _premiumSurface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? AppTheme.getPrimaryColor(context)
                                        : Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.folder_outlined,
                                      color: selected
                                          ? AppTheme.getPrimaryColor(context)
                                          : AppTheme.getTextSecondary(context),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: TextStyle(
                                              color:
                                                  AppTheme.getTextPrimary(context),
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if (client.isNotEmpty ||
                                              projectId.isNotEmpty) ...[
                                            SizedBox(height: 3),
                                            Text(
                                              [
                                                if (projectId.isNotEmpty)
                                                  'ID: $projectId',
                                                if (client.isNotEmpty) client,
                                              ].join('  •  '),
                                              style: TextStyle(
                                                color:
                                                    AppTheme.getTextSecondary(
                                                        context),
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowResponseView extends StatelessWidget {
  final dynamic response;

  const _WorkflowResponseView({required this.response});

  @override
  Widget build(BuildContext context) {
    final normalizedResponse = _decodeResponsePayload(response);
    if (_isEmptyResponse(normalizedResponse)) {
      return _ResponseEmptyState();
    }

    if (normalizedResponse is Map) {
      final map = Map<String, dynamic>.from(normalizedResponse);
      final entries = _priorResponseEntriesFromMap(map);
      if (entries.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...entries.asMap().entries.map(
                  (entry) => _ResponseEntryCard(
                    entry: entry.value,
                    index: entry.key,
                    totalEntries: entries.length,
                  ),
                ),
            _buildTrailingFields(
              map,
              ignoredKeys: {'entries', 'completions'},
            ),
          ],
        );
      }
      final taskGroups = _priorResponseTaskGroups(map);
      if (taskGroups.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...taskGroups.asMap().entries.map(
                  (group) => _ResponseEntryGroup(
                    title: group.value.title,
                    entries: group.value.entries,
                    startIndex: _entryStartIndex(taskGroups, group.key),
                  ),
                ),
            _buildTrailingFields(
              map,
              ignoredKeys: {'tasks', 'entries', 'completions'},
            ),
          ],
        );
      }
      return _ResponseEntryCard(entry: map, index: 0, showIndex: false);
    }

    if (normalizedResponse is List) {
      final entries = _sortResponseEntriesByTimestamp(
        normalizedResponse
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
      );
      if (entries.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries
              .asMap()
              .entries
              .map(
                (entry) => _ResponseEntryCard(
                  entry: entry.value,
                  index: entry.key,
                  totalEntries: entries.length,
                ),
              )
              .toList(),
        );
      }
    }

    return _ResponseTextBlock(text: normalizedResponse.toString());
  }

  Widget _buildTrailingFields(
    Map<String, dynamic> map, {
    required Set<String> ignoredKeys,
  }) {
    final fields = map.entries
        .where((entry) => !ignoredKeys.contains(entry.key))
        .where((entry) => !_responseHiddenKeys.contains(entry.key))
        .where((entry) => !_isEmptyResponse(entry.value))
        .toList();

    if (fields.isEmpty) return SizedBox.shrink();
    return Column(
      children: fields
          .map((entry) =>
              _ResponseFieldRow(label: entry.key, value: entry.value))
          .toList(),
    );
  }
}

class _ResponseEntryGroup extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> entries;
  final int startIndex;

  const _ResponseEntryGroup({
    required this.title,
    required this.entries,
    required this.startIndex,
  });

  @override
  Widget build(BuildContext context) {
    final showGroupTitle = _shouldShowResponseGroupTitle(title, entries);

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showGroupTitle) ...[
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                title,
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          ...entries.asMap().entries.map(
                (entry) => _ResponseEntryCard(
                  entry: entry.value,
                  index: startIndex + entry.key,
                  totalEntries: entries.length,
                ),
              ),
        ],
      ),
    );
  }
}

class _PriorResponseGroup {
  final String title;
  final List<Map<String, dynamic>> entries;

  const _PriorResponseGroup({
    required this.title,
    required this.entries,
  });
}

bool _shouldShowResponseGroupTitle(
  String title,
  List<Map<String, dynamic>> entries,
) {
  final normalizedTitle = _normalizedResponseHeading(title);
  if (normalizedTitle.isEmpty || normalizedTitle == 'viewresponse') {
    return false;
  }

  final hasFileEntry =
      entries.any((entry) => _mapList(entry['files']).isNotEmpty);
  final hasCommentEntry = entries.any(
    (entry) => _firstString(entry, ['comment', 'note', 'remarks']) != null,
  );

  if (hasFileEntry &&
      (normalizedTitle == 'uploadfile' ||
          normalizedTitle == 'uploadedfile' ||
          normalizedTitle == 'uploadedfiles')) {
    return false;
  }
  if (hasCommentEntry &&
      (normalizedTitle == 'comment' || normalizedTitle == 'comments')) {
    return false;
  }

  if (entries.length == 1) {
    final entryTitle = _firstString(entries.first, [
      'source_task_name',
      'task_name',
      'document_name',
      'label',
      'heading',
      'name',
    ]);
    if (_normalizedResponseHeading(entryTitle ?? '') == normalizedTitle) {
      return false;
    }
  }

  return true;
}

bool _shouldShowResponseEntryTitle(
  String title, {
  required bool hasFiles,
  required bool hasComment,
}) {
  final normalizedTitle = _normalizedResponseHeading(title);
  if (normalizedTitle.isEmpty || normalizedTitle == 'viewresponse')
    return false;

  if (hasFiles &&
      (normalizedTitle == 'uploadfile' ||
          normalizedTitle == 'uploadedfile' ||
          normalizedTitle == 'uploadedfiles')) {
    return false;
  }
  if (hasComment &&
      (normalizedTitle == 'comment' || normalizedTitle == 'comments')) {
    return false;
  }

  if (hasFiles || hasComment) return false;
  return true;
}

String _normalizedResponseHeading(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _ResponseEntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int index;
  final bool showIndex;
  final int? totalEntries;

  const _ResponseEntryCard({
    required this.entry,
    required this.index,
    this.showIndex = true,
    this.totalEntries,
  });

  @override
  Widget build(BuildContext context) {
    final files = _mapList(entry['files']);
    final title = _firstString(entry, [
          'source_task_name',
          'task_name',
          'document_name',
          'label',
          'heading',
          'name',
        ]) ??
        (showIndex ? 'Response ${index + 1}' : 'Response');
    final comment = _firstString(entry, ['comment', 'note', 'remarks']);
    final qaItems = _mapList(entry['qa_items']);
    final lines = _responseLines(entry['lines']);
    final checklistFollowupResponses = _mapList(entry['responses']);
    final completedAt =
        _firstString(entry, ['completed_at', 'updated_at', 'created_at']);
    final entryType = entry['type']?.toString().trim() ?? '';
    final responseMode = entry['response_mode']?.toString().trim();
    final showMultipleSubmissions = (totalEntries ?? 1) > 1;
    final showTitle = _shouldShowResponseEntryTitle(
      title,
      hasFiles: files.isNotEmpty,
      hasComment: comment != null,
    );
    final fields = entry.entries
        .where((item) => !_responseHiddenKeys.contains(item.key))
        .where((item) => !_isEmptyResponse(item.value))
        .toList();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimary(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMultipleSubmissions || completedAt != null) ...[
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppTheme.getTextSecondary(context),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    completedAt != null
                        ? 'Completed $completedAt'
                        : 'Submission ${index + 1}',
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
          ],
          if (showTitle) ...[
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    files.isNotEmpty
                        ? Icons.attach_file_rounded
                        : Icons.article_outlined,
                    color: AppTheme.getPrimaryColor(context),
                    size: 18,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (entryType == 'user_checklist_followup' &&
              responseMode != null &&
              responseMode.isNotEmpty) ...[
            SizedBox(height: showTitle ? 10 : 0),
            Text(
              'Response mode: ${_responseLabel(responseMode)}',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (files.isNotEmpty) ...[
            SizedBox(height: showTitle ? 14 : 0),
            _ResponseSectionHeader(
              icon: Icons.attach_file_rounded,
              label: files.length == 1 ? 'Uploaded file' : 'Uploaded files',
            ),
            SizedBox(height: 10),
            ...files.map(
              (file) => _ResponseFileTile(file: file, relatedFiles: files),
            ),
          ],
          if (comment != null) ...[
            SizedBox(height: 14),
            _ResponseSectionHeader(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Comments',
            ),
            SizedBox(height: 10),
            _ResponseTextBlock(text: comment),
          ],
          if (qaItems.isNotEmpty) ...[
            SizedBox(height: 12),
            _ResponseQaList(items: qaItems),
          ],
          if (lines.isNotEmpty) ...[
            SizedBox(height: 12),
            _ResponseLinesList(lines: lines),
          ],
          if (checklistFollowupResponses.isNotEmpty) ...[
            SizedBox(height: 12),
            _ChecklistFollowupResponseList(
              responses: checklistFollowupResponses,
            ),
          ],
          if (fields.isNotEmpty) ...[
            SizedBox(height: 12),
            ...fields.map(
              (field) => _ResponseFieldRow(
                label: field.key,
                value: field.value,
              ),
            ),
          ],
          if (!showMultipleSubmissions && completedAt != null) ...[
            SizedBox(height: 10),
            Text(
              'Completed $completedAt',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponseSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ResponseSectionHeader({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            color: AppTheme.getPrimaryColor(context),
            size: 15,
          ),
        ),
        SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ResponseQaList extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _ResponseQaList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.asMap().entries.map((entry) {
        final item = entry.value;
        final question = _firstString(item, ['question', 'q', 'label']) ??
            'Question ${entry.key + 1}';
        final answer = _firstString(item, ['answer', 'a', 'value']) ?? '-';
        final comment = _firstString(item, ['comment', 'note', 'remarks']);

        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              _ResponseFieldRow(label: 'Answer', value: answer),
              if (comment != null)
                _ResponseFieldRow(label: 'Comment', value: comment),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ResponseLinesList extends StatelessWidget {
  final List<String> lines;

  const _ResponseLinesList({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .asMap()
            .entries
            .map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == lines.length - 1 ? 0 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.getPrimaryColor(context)
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppTheme.getPrimaryColor(context),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ChecklistFollowupResponseList extends StatelessWidget {
  final List<Map<String, dynamic>> responses;

  const _ChecklistFollowupResponseList({required this.responses});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponseSectionHeader(
          icon: Icons.assignment_turned_in_outlined,
          label: responses.length == 1
              ? 'Checklist follow-up response'
              : 'Checklist follow-up responses',
        ),
        SizedBox(height: 10),
        ...responses.map((response) => _ChecklistFollowupResponseTile(
              response: response,
            )),
      ],
    );
  }
}

class _ChecklistFollowupResponseTile extends StatelessWidget {
  final Map<String, dynamic> response;

  const _ChecklistFollowupResponseTile({required this.response});

  @override
  Widget build(BuildContext context) {
    final title = _firstString(response, [
      'item_label',
      'label',
      'name',
      'title',
      'item_name',
    ]);
    final comment = _firstString(response, ['comment', 'note', 'remarks']);
    final files = [
      ..._mapListFlexible(response['files']),
      ..._mapListFlexible(response['attachments']),
      ..._mapListFlexible(response['uploaded_files']),
    ];

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 10),
          ],
          if (comment != null) ...[
            _ResponseSectionHeader(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Response comment',
            ),
            SizedBox(height: 8),
            _ResponseTextBlock(text: comment),
          ],
          if (files.isNotEmpty) ...[
            if (comment != null) SizedBox(height: 12),
            _ResponseSectionHeader(
              icon: Icons.attach_file_rounded,
              label: files.length == 1 ? 'Uploaded file' : 'Uploaded files',
            ),
            SizedBox(height: 10),
            ...files.map(
              (file) => _ResponseFileTile(file: file, relatedFiles: files),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponseFileTile extends StatelessWidget {
  final Map<String, dynamic> file;
  final List<Map<String, dynamic>>? relatedFiles;

  const _ResponseFileTile({
    required this.file,
    this.relatedFiles,
  });

  @override
  Widget build(BuildContext context) {
    final url = _workflowAttachmentUrl(file);
    final name = _displayFileName(
      _firstString(file, [
            'original_filename',
            'filename',
            'file_name',
            'document_name',
            'name',
          ]),
      fallback: 'Uploaded file',
    );
    final contentType = _firstString(file, ['content_type', 'mime_type']);
    final isImage =
        url != null && _isImageAttachment(url, contentType: contentType);
    final isVideo =
        url != null && _isVideoAttachment(url, contentType: contentType, name: name);
    final isPdf =
        url != null && _isPdfAttachment(url, contentType: contentType, name: name);

    return InkWell(
      onTap: url == null
          ? null
          : () => _openWorkflowAttachment(
                context,
                file,
                relatedFiles: relatedFiles,
              ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _premiumSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 58,
                height: 58,
                color:
                    AppTheme.getPrimaryColor(context).withValues(alpha: 0.07),
                child: isImage
                    ? Image.network(
                        _absoluteWorkflowUrl(url),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fileIcon(context, isVideo: isVideo, isPdf: isPdf),
                      )
                    : _fileIcon(context, isVideo: isVideo, isPdf: isPdf),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (contentType != null) ...[
                    SizedBox(height: 3),
                    Text(
                      contentType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (url != null) ...[
                    SizedBox(height: 7),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.getPrimaryColor(context)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isImage
                            ? 'Tap to view'
                            : (isVideo
                                ? 'Tap to play'
                                : (isPdf ? 'Tap to view PDF' : 'Tap to open')),
                        style: TextStyle(
                          color: AppTheme.getPrimaryColor(context),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (url != null)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color:
                      AppTheme.getPrimaryColor(context).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isImage
                      ? Icons.visibility_outlined
                      : (isVideo
                          ? Icons.play_circle_outline
                          : Icons.open_in_new_rounded),
                  color: AppTheme.getPrimaryColor(context),
                  size: 17,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fileIcon(
    BuildContext context, {
    bool isVideo = false,
    bool isPdf = false,
  }) {
    return Icon(
      isVideo
          ? Icons.videocam_outlined
          : (isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined),
      color: AppTheme.getPrimaryColor(context),
      size: 24,
    );
  }
}

class _ResponseFieldRow extends StatelessWidget {
  final String label;
  final dynamic value;

  const _ResponseFieldRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _responseLabel(label),
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 3),
          Text(
            _responseDisplayValue(value),
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseTextBlock extends StatelessWidget {
  final String text;

  const _ResponseTextBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 13,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResponseEmptyState extends StatelessWidget {
  final String message;

  const _ResponseEmptyState({this.message = 'No response available.'});

  @override
  Widget build(BuildContext context) {
    return _ResponseTextBlock(text: message);
  }
}

class _WorkflowUploadProgressBar extends StatelessWidget {
  final int percent;

  const _WorkflowUploadProgressBar({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Overall progress',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            Spacer(),
            Text(
              '$percent%',
              style: TextStyle(
                color: AppTheme.getPrimaryColor(context),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (percent.clamp(0, 100)) / 100,
            minHeight: 10,
            backgroundColor: Color(0xFFE5E7EB),
            valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.getPrimaryColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkflowUploadProgressHistory extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final bool canDelete;
  final int? deletingIndex;
  final void Function(int index)? onDelete;

  const _WorkflowUploadProgressHistory({
    required this.entries,
    this.canDelete = false,
    this.deletingIndex,
    this.onDelete,
  });

  List<Map<String, dynamic>> _imageFilesFor(Map<String, dynamic> entry) {
    final files = _mapListFlexible(entry['files']);
    return files.where((file) {
      final url = _workflowAttachmentUrl(file);
      if (url == null) return false;
      final contentType = _firstString(file, ['content_type', 'mime_type']);
      final name = _firstString(file, [
        'filename',
        'name',
        'original_filename',
        'file_name',
      ]);
      return _isImageAttachment(url, contentType: contentType) ||
          (name != null && _looksLikeImage(name));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Uploaded documents',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              '${entries.length}',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final files = _mapListFlexible(entry['files']);
              final imageFiles = _imageFilesFor(entry);
              final isDeletingRow = deletingIndex == index;
              final percent = entry['percent']?.toString() ?? '';
              final uploadedAt = entry['uploaded_at']?.toString();
              final dateLabel = uploadedAt == null || uploadedAt.trim().isEmpty
                  ? 'Uploaded'
                  : _formatUploadProgressDate(uploadedAt);

              return _UploadedProgressCarouselCard(
                width: 148,
                height: 168,
                imageFile: imageFiles.isEmpty ? null : imageFiles.first,
                relatedFiles: files,
                percentLabel: percent.isEmpty ? null : '$percent%',
                dateLabel: dateLabel,
                fallbackLabel: _uploadProgressEntryFileName(entry),
                isDeleting: isDeletingRow,
                canDelete: canDelete && onDelete != null,
                onDelete: deletingIndex == null && onDelete != null
                    ? () => onDelete!(index)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UploadedProgressCarouselCard extends StatelessWidget {
  final double width;
  final double height;
  final Map<String, dynamic>? imageFile;
  final List<Map<String, dynamic>> relatedFiles;
  final String? percentLabel;
  final String dateLabel;
  final String fallbackLabel;
  final bool isDeleting;
  final bool canDelete;
  final VoidCallback? onDelete;

  const _UploadedProgressCarouselCard({
    required this.width,
    required this.height,
    required this.imageFile,
    required this.relatedFiles,
    required this.percentLabel,
    required this.dateLabel,
    required this.fallbackLabel,
    required this.isDeleting,
    required this.canDelete,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = imageFile == null
        ? null
        : _workflowAttachmentUrl(imageFile!);
    final absoluteUrl =
        imageUrl == null ? null : _absoluteWorkflowUrl(imageUrl);

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: absoluteUrl == null || imageFile == null
              ? null
              : () => _openWorkflowAttachment(
                    context,
                    imageFile!,
                    relatedFiles: relatedFiles,
                  ),
          borderRadius: BorderRadius.circular(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: const Color(0xFF111827),
                  child: absoluteUrl == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: Colors.white70,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  fallbackLabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Image.network(
                          absoluteUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 28,
                            ),
                          ),
                        ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0xB3000000),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
                if (percentLabel != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        percentLabel!,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (canDelete)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: isDeleting ? null : onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: isDeleting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Text(
                    dateLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      shadows: [
                        Shadow(
                          color: Color(0x99000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
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

class _UploadedDocumentImagePreview extends StatelessWidget {
  final Map<String, dynamic> file;
  final List<Map<String, dynamic>> relatedFiles;
  final double size;
  final bool enableTap;

  const _UploadedDocumentImagePreview({
    required this.file,
    required this.relatedFiles,
    required this.size,
    this.enableTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final url = _workflowAttachmentUrl(file);
    if (url == null) return const SizedBox.shrink();
    final absoluteUrl = _absoluteWorkflowUrl(url);

    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: const Color(0xFFF3F4F6),
        child: Image.network(
          absoluteUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Color(0xFF9CA3AF),
              size: 28,
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: enableTap
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openWorkflowAttachment(
                  context,
                  file,
                  relatedFiles: relatedFiles,
                ),
                borderRadius: BorderRadius.circular(14),
                child: preview,
              ),
            )
          : preview,
    );
  }
}

class _SelectedUploadFile {
  final String path;
  final String name;
  final DateTime? capturedAt;
  final double? videoDurationSeconds;

  const _SelectedUploadFile({
    required this.path,
    required this.name,
    this.capturedAt,
    this.videoDurationSeconds,
  });
}

const Set<String> _workflowImageFormats = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'heic',
};

const Set<String> _workflowVideoFormats = {
  'mp4',
  'mov',
  'webm',
  'avi',
  'mkv',
  'm4v',
};

const Set<String> _workflowDocumentFormats = {
  'pdf',
  'doc',
  'docx',
  'dwg',
  'dxf',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'csv',
};

const List<String> _defaultWorkflowDocumentFormats = [
  'pdf',
  'doc',
  'docx',
];

List<String> _normalizeAllowedFormats(List<String> allowedFormats) {
  return allowedFormats
      .map((format) => format.replaceAll('.', '').toLowerCase())
      .where((format) => format.isNotEmpty)
      .toList();
}

class _WorkflowFormatProfile {
  final bool hasImages;
  final bool hasVideos;
  final bool hasDocuments;

  const _WorkflowFormatProfile({
    required this.hasImages,
    required this.hasVideos,
    required this.hasDocuments,
  });

  bool get hasNonImageFormats => hasVideos || hasDocuments;

  List<String> get imageExtensions =>
      _workflowImageFormats.toList(growable: false);

  List<String> nonImageExtensions(List<String> normalizedFormats) {
    if (normalizedFormats.isEmpty) {
      return [
        ..._workflowVideoFormats,
        'pdf',
        'doc',
        'docx',
        'dwg',
        'dxf',
      ];
    }
    return normalizedFormats
        .where((format) => !_workflowImageFormats.contains(format))
        .toList();
  }

  List<String> imageExtensionsFrom(List<String> normalizedFormats) {
    if (normalizedFormats.isEmpty) return imageExtensions;
    return normalizedFormats
        .where((format) => _workflowImageFormats.contains(format))
        .toList();
  }
}

_WorkflowFormatProfile _classifyAllowedFormats(List<String> allowedFormats) {
  final formats = _normalizeAllowedFormats(allowedFormats);
  if (formats.isEmpty) {
    return const _WorkflowFormatProfile(
      hasImages: true,
      hasVideos: true,
      hasDocuments: true,
    );
  }

  final hasImages =
      formats.any((format) => _workflowImageFormats.contains(format));
  final hasVideos =
      formats.any((format) => _workflowVideoFormats.contains(format));
  final hasDocuments = formats.any(
    (format) =>
        !_workflowImageFormats.contains(format) &&
        !_workflowVideoFormats.contains(format),
  );

  return _WorkflowFormatProfile(
    hasImages: hasImages,
    hasVideos: hasVideos,
    hasDocuments: hasDocuments,
  );
}

class _WorkflowUploadSourceConfig {
  final bool allowGallery;
  final bool allowCamera;
  final bool allowDocument;
  final bool allowVideo;
  final List<String> imageFormats;
  final List<String> documentFormats;
  final List<String> videoFormats;

  const _WorkflowUploadSourceConfig({
    required this.allowGallery,
    required this.allowCamera,
    this.allowDocument = false,
    this.allowVideo = false,
    this.imageFormats = const [],
    this.documentFormats = const [],
    this.videoFormats = const [],
  });

  bool get cameraOnly =>
      allowCamera && !allowGallery && !allowDocument && !allowVideo;

  bool get hasAnySource =>
      allowGallery || allowCamera || allowDocument || allowVideo;

  List<String> get allAllowedFormats => [
        ...imageFormats,
        ...documentFormats,
        ...videoFormats,
      ];
}

List<String> _workflowFormatsFromAction(
  Map<String, dynamic> action, {
  required String key,
  required List<String> Function(List<String> allowed) fromAllowed,
  List<String> defaultWhenEmpty = const [],
}) {
  final explicit = _normalizeAllowedFormats(_stringList(action[key]));
  if (explicit.isNotEmpty) return explicit;

  final allowed = _normalizeAllowedFormats(_stringList(action['allowed_formats']));
  if (allowed.isNotEmpty) {
    final derived = fromAllowed(allowed);
    if (derived.isNotEmpty) return derived;
  }

  return List<String>.from(defaultWhenEmpty);
}

_WorkflowUploadSourceConfig _resolveWorkflowUploadSources(
  Map<String, dynamic> action, {
  List<String>? allowedFormats,
}) {
  final imageFormats = _workflowFormatsFromAction(
    action,
    key: 'image_formats',
    fromAllowed: (formats) => formats
        .where((format) => _workflowImageFormats.contains(format))
        .toList(),
    defaultWhenEmpty: _workflowImageFormats.toList(growable: false),
  );
  final documentFormats = _workflowFormatsFromAction(
    action,
    key: 'document_formats',
    fromAllowed: (formats) => formats
        .where(
          (format) =>
              _workflowDocumentFormats.contains(format) ||
              (!_workflowImageFormats.contains(format) &&
                  !_workflowVideoFormats.contains(format)),
        )
        .toList(),
    defaultWhenEmpty: _defaultWorkflowDocumentFormats,
  );
  final videoFormats = _workflowFormatsFromAction(
    action,
    key: 'video_formats',
    fromAllowed: (formats) => formats
        .where((format) => _workflowVideoFormats.contains(format))
        .toList(),
    defaultWhenEmpty: _workflowVideoFormats.toList(growable: false),
  );

  if (action['allow_file_upload'] == false) {
    return _WorkflowUploadSourceConfig(
      allowGallery: false,
      allowCamera: false,
      allowDocument: false,
      allowVideo: false,
      imageFormats: imageFormats,
      documentFormats: documentFormats,
      videoFormats: videoFormats,
    );
  }

  final requireNearSite = _truthyValue(action['require_near_site']);
  final liveImageOnly = action['live_image_only'] == true;
  final hideGallery = requireNearSite || liveImageOnly;

  final uploadSources = _stringList(action['upload_sources'])
      .map((source) => source.toLowerCase())
      .toList();

  if (uploadSources.isNotEmpty) {
    return _WorkflowUploadSourceConfig(
      allowGallery: !hideGallery &&
          uploadSources.contains('gallery') &&
          action['allow_gallery_upload'] == true &&
          imageFormats.isNotEmpty,
      allowCamera: uploadSources.contains('camera') &&
          action['allow_live_image'] != false &&
          imageFormats.isNotEmpty,
      allowDocument: uploadSources.contains('document') &&
          action['allow_document_upload'] != false &&
          documentFormats.isNotEmpty,
      allowVideo: uploadSources.contains('video') &&
          action['allow_video_upload'] != false &&
          videoFormats.isNotEmpty,
      imageFormats: imageFormats,
      documentFormats: documentFormats,
      videoFormats: videoFormats,
    );
  }

  if (action['live_image_only'] == true) {
    return _WorkflowUploadSourceConfig(
      allowGallery: false,
      allowCamera: action['allow_live_image'] != false,
      allowDocument: action['allow_document_upload'] != false &&
          documentFormats.isNotEmpty,
      allowVideo: action['allow_video_upload'] != false &&
          videoFormats.isNotEmpty,
      imageFormats: imageFormats,
      documentFormats: documentFormats,
      videoFormats: videoFormats,
    );
  }

  if (action.containsKey('allow_gallery_upload') ||
      action.containsKey('allow_live_image') ||
      action.containsKey('allow_document_upload') ||
      action.containsKey('allow_video_upload')) {
    return _WorkflowUploadSourceConfig(
      allowGallery: !hideGallery &&
          action['allow_gallery_upload'] == true &&
          imageFormats.isNotEmpty,
      allowCamera: action['allow_live_image'] == true &&
          imageFormats.isNotEmpty,
      allowDocument: action['allow_document_upload'] != false &&
          documentFormats.isNotEmpty,
      allowVideo: action['allow_video_upload'] != false &&
          videoFormats.isNotEmpty,
      imageFormats: imageFormats,
      documentFormats: documentFormats,
      videoFormats: videoFormats,
    );
  }

  final formats = _normalizeAllowedFormats(
    allowedFormats ?? _stringList(action['allowed_formats']),
  );
  final profile = _classifyAllowedFormats(formats);
  final hasImageFormats = formats.isEmpty || profile.hasImages;
  final nonImageOnly = formats.isNotEmpty && !hasImageFormats;

  if (nonImageOnly) {
    return _WorkflowUploadSourceConfig(
      allowGallery: false,
      allowCamera: false,
      allowDocument: profile.hasDocuments,
      allowVideo: profile.hasVideos,
      imageFormats: imageFormats,
      documentFormats: documentFormats.isNotEmpty
          ? documentFormats
          : formats
              .where(
                (format) =>
                    !_workflowImageFormats.contains(format) &&
                    !_workflowVideoFormats.contains(format),
              )
              .toList(),
      videoFormats: videoFormats.isNotEmpty
          ? videoFormats
          : formats
              .where((format) => _workflowVideoFormats.contains(format))
              .toList(),
    );
  }

  return _WorkflowUploadSourceConfig(
    allowGallery: !hideGallery && hasImageFormats,
    allowCamera: false,
    allowDocument: profile.hasNonImageFormats,
    allowVideo: profile.hasVideos,
    imageFormats: imageFormats,
    documentFormats: documentFormats,
    videoFormats: videoFormats,
  );
}

/// Resolves Build checklist (user_checklist) upload sources.
/// Prefer upload_sources / allow_* flags (same as Upload). Fall back to
/// allowed_formats, then legacy allow_*_per_item flags.
_WorkflowUploadSourceConfig _resolveUserChecklistUploadSources(
  Map<String, dynamic> action,
) {
  final hasUploadSources = _stringList(action['upload_sources']).isNotEmpty;
  final hasModernFlags = action.containsKey('allow_gallery_upload') ||
      action.containsKey('allow_live_image') ||
      action.containsKey('allow_document_upload') ||
      action.containsKey('allow_video_upload');

  if (hasUploadSources || hasModernFlags) {
    return _resolveWorkflowUploadSources(action);
  }

  if (action.containsKey('allowed_formats')) {
    final allowedFormats =
        _normalizeAllowedFormats(_stringList(action['allowed_formats']));
    if (allowedFormats.isEmpty) {
      return const _WorkflowUploadSourceConfig(
        allowGallery: false,
        allowCamera: false,
        allowDocument: false,
        allowVideo: false,
      );
    }

    final resolved = _resolveWorkflowUploadSources(
      action,
      allowedFormats: allowedFormats,
    );
    final profile = _classifyAllowedFormats(allowedFormats);
    final imageFormats = resolved.imageFormats.isNotEmpty
        ? resolved.imageFormats
        : allowedFormats
            .where((format) => _workflowImageFormats.contains(format))
            .toList();
    final documentFormats = allowedFormats
        .where(
          (format) =>
              _workflowDocumentFormats.contains(format) ||
              (!_workflowImageFormats.contains(format) &&
                  !_workflowVideoFormats.contains(format)),
        )
        .toList();
    final videoFormats = allowedFormats
        .where((format) => _workflowVideoFormats.contains(format))
        .toList();

    // Drive sources strictly from allowed_formats for checklist.
    // Image formats → gallery + camera (acceptance).
    return _WorkflowUploadSourceConfig(
      allowGallery: profile.hasImages,
      allowCamera: profile.hasImages,
      allowDocument: profile.hasDocuments,
      allowVideo: profile.hasVideos,
      imageFormats: imageFormats,
      documentFormats: documentFormats,
      videoFormats: videoFormats,
    );
  }

  // Legacy actions without allowed_formats / upload hints.
  final allowImage = action['allow_image_per_item'] == true;
  final allowVideo = action['allow_video_per_item'] == true;
  final allowDocument = action['allow_document_per_item'] == true;

  return _WorkflowUploadSourceConfig(
    allowGallery: allowImage,
    allowCamera: allowImage,
    allowDocument: allowDocument,
    allowVideo: allowVideo,
    imageFormats: allowImage
        ? _workflowImageFormats.toList(growable: false)
        : const [],
    documentFormats: allowDocument
        ? _workflowDocumentFormats.toList(growable: false)
        : const [],
    videoFormats: allowVideo
        ? _workflowVideoFormats.toList(growable: false)
        : const [],
  );
}

bool _isAllowedUploadFormat(String fileName, List<String> allowedFormats) {
  if (allowedFormats.isEmpty) return true;
  final parts = fileName.split('.');
  if (parts.length < 2) return false;
  final ext = parts.last.toLowerCase();
  final normalized = allowedFormats
      .map((format) => format.replaceAll('.', '').toLowerCase())
      .where((format) => format.isNotEmpty)
      .toList();
  return normalized.contains(ext);
}

String _displayFileName(String? value, {String fallback = 'Document'}) {
  if (value == null) return fallback;
  var name = value.trim();
  if (name.isEmpty) return fallback;

  // Drop query/hash fragments from URLs, then keep only the last path segment.
  name = name.split('?').first.split('#').first;
  name = name.split('/').last;
  name = name.split(r'\').last;
  name = name.split(Platform.pathSeparator).last.trim();

  return name.isEmpty ? fallback : name;
}

String _uploadFileNameFromPath({required String name, required String path}) {
  final fromName = _displayFileName(name, fallback: '');
  if (fromName.contains('.') && fromName.split('.').last.trim().isNotEmpty) {
    return fromName;
  }
  final fromPath = _displayFileName(path, fallback: '');
  if (fromPath.contains('.')) return fromPath;
  return fromName.isNotEmpty
      ? fromName
      : (fromPath.isNotEmpty ? fromPath : 'Document');
}

bool _looksLikeDocument(String value) {
  if (value.isEmpty) return false;
  final lower = value.toLowerCase().split('?').first;
  return _workflowDocumentFormats.any((ext) => lower.endsWith('.$ext'));
}

bool _isWorkflowDocumentUpload(_SelectedUploadFile file) {
  return _looksLikeDocument(file.name) ||
      _looksLikeDocument(file.path);
}

bool _isWorkflowVideoUpload(_SelectedUploadFile file) {
  return file.videoDurationSeconds != null || _looksLikeVideo(file.name);
}

bool _isWorkflowLiveImageUpload(_SelectedUploadFile file) {
  return file.capturedAt != null ||
      (_looksLikeImage(file.name) &&
          !_isWorkflowDocumentUpload(file) &&
          !_isWorkflowVideoUpload(file));
}

bool _shouldSendLiveImageOnlyUpload({
  required bool cameraOnly,
  required List<_SelectedUploadFile> files,
}) {
  if (files.isEmpty) return false;
  if (files.any(_isWorkflowVideoUpload) || files.any(_isWorkflowDocumentUpload)) {
    return false;
  }
  return cameraOnly || files.every(_isWorkflowLiveImageUpload);
}

bool _isAllowedWorkflowUploadFile(
  _SelectedUploadFile file,
  _WorkflowUploadSourceConfig sources,
) {
  if (_isWorkflowVideoUpload(file)) {
    if (sources.videoFormats.isEmpty) return true;
    if (_isAllowedUploadFormat(file.name, sources.videoFormats)) return true;
    if (_isAllowedUploadFormat(file.path, sources.videoFormats)) return true;
    return file.videoDurationSeconds != null &&
        sources.videoFormats
            .map((format) => format.toLowerCase())
            .contains('mp4');
  }
  if (_isWorkflowDocumentUpload(file)) {
    return sources.documentFormats.isEmpty ||
        _isAllowedUploadFormat(file.name, sources.documentFormats) ||
        _isAllowedUploadFormat(file.path, sources.documentFormats);
  }
  if (file.capturedAt != null || _looksLikeImage(file.name)) {
    return sources.imageFormats.isEmpty ||
        _isAllowedUploadFormat(file.name, sources.imageFormats);
  }
  return true;
}

String _allowedFormatsMessage(_WorkflowUploadSourceConfig sources) {
  final formats = sources.allAllowedFormats;
  if (formats.isEmpty) return 'No file types configured for this action.';
  return formats.join(', ');
}

MediaType? _workflowUploadMediaType(_SelectedUploadFile file) {
  if (file.videoDurationSeconds != null || _looksLikeVideo(file.name)) {
    final parts = file.name.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : 'mp4';
    switch (ext) {
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'webm':
        return MediaType('video', 'webm');
      case 'avi':
        return MediaType('video', 'x-msvideo');
      case 'mkv':
        return MediaType('video', 'x-matroska');
      case 'm4v':
        return MediaType('video', 'x-m4v');
      default:
        return MediaType('video', 'mp4');
    }
  }
  if (_isWorkflowDocumentUpload(file)) {
    final parts = file.name.split('.');
    final pathParts = file.path.split('.');
    final ext = parts.length > 1
        ? parts.last.toLowerCase()
        : (pathParts.length > 1 ? pathParts.last.toLowerCase() : 'pdf');
    switch (ext) {
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        return MediaType('application', 'octet-stream');
    }
  }
  if (_looksLikePdf(file.name) || _looksLikePdf(file.path)) {
    return MediaType('application', 'pdf');
  }
  if (_looksLikeImage(file.name) || file.capturedAt != null) {
    final parts = file.name.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : 'jpeg';
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'gif':
        return MediaType('image', 'gif');
      default:
        return MediaType('image', 'jpeg');
    }
  }
  return null;
}

Future<http.MultipartFile> _workflowUploadMultipartFile(
  _SelectedUploadFile file,
) async {
  return http.MultipartFile.fromPath(
    'files',
    file.path,
    filename: file.name,
    contentType: _workflowUploadMediaType(file),
  );
}

Future<_SelectedUploadFile> _finalizeVideoUploadFile({
  required String sourcePath,
  required String sourceName,
  required double durationSeconds,
  required List<String> videoFormats,
}) async {
  final normalizedFormats = _normalizeAllowedFormats(videoFormats);
  final preferredExt = normalizedFormats.contains('mp4')
      ? 'mp4'
      : (normalizedFormats.isNotEmpty ? normalizedFormats.first : 'mp4');
  var name = sourceName.trim();
  if (!_looksLikeVideo(name)) {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    name = 'video_$timestamp.$preferredExt';
  }

  var path = sourcePath;
  if (name != sourceName.split(Platform.pathSeparator).last) {
    final stampedPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
    await File(sourcePath).copy(stampedPath);
    path = stampedPath;
  }

  return _SelectedUploadFile(
    path: path,
    name: name,
    videoDurationSeconds: durationSeconds,
  );
}

Future<_SelectedUploadFile?> _pickWorkflowGalleryFile({
  required List<String> allowedFormats,
}) async {
  final normalized = _normalizeAllowedFormats(allowedFormats);
  final profile = _classifyAllowedFormats(normalized);
  final imageExtensions = profile.imageExtensionsFrom(normalized);
  if (imageExtensions.isEmpty) return null;

  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final name = picked.name.trim().isNotEmpty
      ? picked.name
      : picked.path.split(Platform.pathSeparator).last;
  if (!_isAllowedUploadFormat(name, allowedFormats)) return null;
  return _SelectedUploadFile(path: picked.path, name: name);
}

Future<_SelectedUploadFile?> _pickWorkflowDocumentFile({
  required List<String> documentFormats,
}) async {
  final extensions = _normalizeAllowedFormats(documentFormats);
  if (extensions.isEmpty) return null;

  final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.path == null || file.path!.isEmpty) return null;
  final resolvedName = _uploadFileNameFromPath(
    name: file.name,
    path: file.path!,
  );
  if (!_isAllowedUploadFormat(resolvedName, documentFormats) &&
      !_isAllowedUploadFormat(file.path!, documentFormats)) {
    return null;
  }
  return _SelectedUploadFile(path: file.path!, name: resolvedName);
}

Future<_SelectedUploadFile?> _recordWorkflowVideoFile({
  required BuildContext context,
  required List<String> videoFormats,
  int maxDurationSeconds = 60,
  int maxSizeMb = 50,
}) async {
  final extensions = _normalizeAllowedFormats(videoFormats);
  if (extensions.isEmpty) return null;

  final result = await Navigator.of(context).push<_WorkflowVideoRecordResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _WorkflowVideoRecorderPage(
        maxDurationSeconds: maxDurationSeconds,
      ),
    ),
  );
  if (result == null) return null;

  final finalized = await _finalizeVideoUploadFile(
    sourcePath: result.path,
    sourceName: result.name,
    durationSeconds: result.durationSeconds,
    videoFormats: videoFormats,
  );

  if (!_isAllowedWorkflowUploadFile(finalized, _WorkflowUploadSourceConfig(
        allowGallery: false,
        allowCamera: false,
        allowVideo: true,
        videoFormats: videoFormats,
      ))) {
    await _showWorkflowUploadAlert(
      context,
      message:
          'Video format not allowed. Allowed: ${_normalizeAllowedFormats(videoFormats).join(', ')}',
      title: 'Upload failed',
    );
    return null;
  }

  final fileSize = await File(finalized.path).length();
  final maxBytes = maxSizeMb * 1024 * 1024;
  if (fileSize > maxBytes) {
    await _showWorkflowUploadAlert(
      context,
      message: 'Video must be $maxSizeMb MB or smaller.',
      title: 'Upload failed',
    );
    return null;
  }

  return finalized;
}

void _appendWorkflowVideoDurationField(
  http.MultipartRequest request,
  List<_SelectedUploadFile> files,
) {
  for (final file in files) {
    if (file.videoDurationSeconds == null) continue;
    request.fields['video_duration_seconds'] =
        file.videoDurationSeconds!.toString();
    return;
  }
}

class _WorkflowVideoRecordResult {
  final String path;
  final String name;
  final double durationSeconds;

  const _WorkflowVideoRecordResult({
    required this.path,
    required this.name,
    required this.durationSeconds,
  });
}

class _WorkflowVideoRecorderPage extends StatefulWidget {
  final int maxDurationSeconds;

  const _WorkflowVideoRecorderPage({required this.maxDurationSeconds});

  @override
  State<_WorkflowVideoRecorderPage> createState() =>
      _WorkflowVideoRecorderPageState();
}

class _WorkflowVideoRecorderPageState extends State<_WorkflowVideoRecorderPage> {
  CameraController? _controller;
  bool _initializing = true;
  String? _initError;
  bool _isRecording = false;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera available on this device.');
      }
      final rear = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = e.toString().replaceAll('Exception: ', '');
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) {
      if (mounted) {
        setState(() => _isRecording = false);
      }
      return;
    }

    try {
      final file = await controller.stopVideoRecording();
      final path = file.path;
      final name = path.split(Platform.pathSeparator).last;
      if (!mounted) return;
      Navigator.of(context).pop(
        _WorkflowVideoRecordResult(
          path: path,
          name: name.isNotEmpty ? name : 'video.mp4',
          durationSeconds: _elapsedSeconds.toDouble(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _initError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isRecording) {
      return;
    }

    try {
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _elapsedSeconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final next = _elapsedSeconds + 1;
        setState(() => _elapsedSeconds = next);
        if (next >= widget.maxDurationSeconds) {
          timer.cancel();
          _stopRecording();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', '').trim().isNotEmpty
                ? e.toString().replaceAll('Exception: ', '')
                : 'Could not start recording.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final timerLabel =
        '${_formatDuration(_elapsedSeconds)} / ${_formatDuration(widget.maxDurationSeconds)}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Record video'),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _initError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                )
              : controller == null || !controller.value.isInitialized
                  ? const Center(
                      child: Text(
                        'Camera unavailable',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(controller),
                        SafeArea(
                          child: Column(
                            children: [
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  timerLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              GestureDetector(
                                onTap: _toggleRecording,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                  ),
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      width: _isRecording ? 28 : 56,
                                      height: _isRecording ? 28 : 56,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(
                                          _isRecording ? 6 : 999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}

Future<void> _showWorkflowUploadAlert(
  BuildContext context, {
  required String message,
  String title = 'Upload',
}) async {
  if (!context.mounted || message.trim().isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message.trim()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Debug-only: let developers continue when not physically at site.
Future<_NearSiteCheckResult> _applyDebugNearSiteOverrideIfNeeded(
  BuildContext context,
  _NearSiteCheckResult result, {
  _SiteCoordinates? siteLocation,
}) async {
  if (result.ok || !kDebugMode || !context.mounted) {
    return result;
  }

  final override = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Debug: Override site check?',
          style: TextStyle(
            color: _premiumInk,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This task requires you to be at the project site location.',
              style: TextStyle(
                color: _premiumInk,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              result.error?.trim().isNotEmpty == true
                  ? result.error!.trim()
                  : 'Location check failed.',
              style: const TextStyle(
                color: _premiumMuted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: const Text(
                'Debug builds only. Overriding lets you continue without being on site.',
                style: TextStyle(
                  color: Color(0xFF9A3412),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep blocked'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _premiumInk,
              foregroundColor: Colors.white,
            ),
            child: const Text('Override'),
          ),
        ],
      );
    },
  );

  if (override == true) {
    debugPrint(
      '[DEBUG] Near-site location check overridden by user. '
      'error=${result.error}',
    );
    return _NearSiteCheckResult(
      ok: true,
      distanceMeters: result.distanceMeters ?? 0,
      latitude: result.latitude ?? siteLocation?.latitude ?? 0,
      longitude: result.longitude ?? siteLocation?.longitude ?? 0,
    );
  }

  return result;
}

Future<_SelectedUploadFile?> _pickWorkflowCameraFile() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 88,
  );
  if (picked == null) return null;

  final capturedAt = DateTime.now();
  final sourceFile = File(picked.path);
  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(capturedAt);
  final stampedName = 'live_$timestamp.jpg';
  final stampedPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}$stampedName';
  final copiedFile = await sourceFile.copy(stampedPath);

  return _SelectedUploadFile(
    path: copiedFile.path,
    name: stampedName,
    capturedAt: capturedAt,
  );
}

class _WorkflowUploadSourceButtons extends StatelessWidget {
  final _WorkflowUploadSourceConfig sources;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickDocument;
  final VoidCallback? onPickVideo;

  const _WorkflowUploadSourceButtons({
    required this.sources,
    required this.onPickGallery,
    required this.onPickCamera,
    this.onPickDocument,
    this.onPickVideo,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    if (sources.allowCamera) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
          ),
        ),
      );
    }

    if (sources.allowDocument) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickDocument ?? onPickGallery,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Upload document'),
          ),
        ),
      );
    }

    if (sources.allowVideo) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickVideo,
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('Record video'),
          ),
        ),
      );
    }

    if (sources.allowGallery) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
          ),
        ),
      );
    }

    if (buttons.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onPickDocument ?? onPickGallery,
        icon: const Icon(Icons.attach_file_rounded),
        label: const Text('Attach file'),
      );
    }

    if (buttons.length == 1) return buttons.first;

    return Column(
      children: [
        for (var index = 0; index < buttons.length; index += 2) ...[
          if (index > 0) const SizedBox(height: 10),
          Row(
            children: [
              buttons[index],
              if (index + 1 < buttons.length) ...[
                const SizedBox(width: 10),
                buttons[index + 1],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

bool _isSelectedImageFile(_SelectedUploadFile file) {
  return file.capturedAt != null ||
      _looksLikeImage(file.name) ||
      _looksLikeImage(file.path);
}

class _SelectedUploadPreview extends StatelessWidget {
  final _SelectedUploadFile file;
  final VoidCallback? onRemove;

  const _SelectedUploadPreview({
    required this.file,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (_isSelectedImageFile(file)) {
      return _SelectedUploadFilesPreview(
        files: [file],
        onRemove: onRemove == null ? null : (_) => onRemove!(),
      );
    }

    final isVideo =
        file.videoDurationSeconds != null || _looksLikeVideo(file.name);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(
            isVideo
                ? Icons.videocam_outlined
                : Icons.insert_drive_file_outlined,
            color: const Color(0xFF2563EB),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayFileName(file.name, fallback: 'Selected file'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _premiumInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (file.capturedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(file.capturedAt!),
                    style: const TextStyle(
                      color: _premiumMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove selected file',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 20),
              color: AppTheme.getTextSecondary(context),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _SelectedUploadFilesPreview extends StatelessWidget {
  final List<_SelectedUploadFile> files;
  final void Function(int index)? onRemove;

  const _SelectedUploadFilesPreview({
    required this.files,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    final imageFiles = files.where(_isSelectedImageFile).toList();
    final otherFiles =
        files.where((file) => !_isSelectedImageFile(file)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageFiles.isNotEmpty)
          imageFiles.length == 1
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: _SelectedImagePreviewTile(
                    file: imageFiles.first,
                    size: 168,
                    onRemove: onRemove == null
                        ? null
                        : () => onRemove!(files.indexOf(imageFiles.first)),
                  ),
                )
              : SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: imageFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final file = imageFiles[index];
                      return _SelectedImagePreviewTile(
                        file: file,
                        size: 120,
                        onRemove: onRemove == null
                            ? null
                            : () => onRemove!(files.indexOf(file)),
                      );
                    },
                  ),
                ),
        if (otherFiles.isNotEmpty) ...[
          if (imageFiles.isNotEmpty) const SizedBox(height: 10),
          ...otherFiles.map((file) {
            final isVideo = file.videoDurationSeconds != null ||
                _looksLikeVideo(file.name);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isVideo
                          ? Icons.videocam_outlined
                          : Icons.insert_drive_file_outlined,
                      color: const Color(0xFF2563EB),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        file.capturedAt == null
                            ? _displayFileName(file.name, fallback: 'Selected file')
                            : '${_displayFileName(file.name, fallback: 'Selected file')} • ${DateFormat('dd MMM, hh:mm a').format(file.capturedAt!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _premiumInk,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: 'Remove selected file',
                        onPressed: () => onRemove!(files.indexOf(file)),
                        icon: const Icon(Icons.close, size: 20),
                        color: AppTheme.getTextSecondary(context),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _SelectedImagePreviewTile extends StatelessWidget {
  final _SelectedUploadFile file;
  final double size;
  final VoidCallback? onRemove;

  const _SelectedImagePreviewTile({
    required this.file,
    required this.size,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: const Color(0xFFF3F4F6),
                child: Image.file(
                  File(file.path),
                  fit: BoxFit.contain,
                  width: size,
                  height: size,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF9CA3AF),
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SiteCoordinates {
  final double latitude;
  final double longitude;

  const _SiteCoordinates({
    required this.latitude,
    required this.longitude,
  });
}

class _NearSiteCheckResult {
  final bool ok;
  final String? error;
  final bool openSettings;
  final double? distanceMeters;
  final double? latitude;
  final double? longitude;

  const _NearSiteCheckResult({
    required this.ok,
    this.error,
    this.openSettings = false,
    this.distanceMeters,
    this.latitude,
    this.longitude,
  });
}

class _NearSiteStatusBanner extends StatelessWidget {
  final bool isChecking;
  final String? error;
  final double? distanceMeters;
  final int radiusMeters;
  final double? siteLatitude;
  final double? siteLongitude;
  final bool showOpenSettings;
  final VoidCallback? onRecheck;
  final VoidCallback? onOpenSettings;

  const _NearSiteStatusBanner({
    required this.isChecking,
    required this.error,
    required this.distanceMeters,
    required this.radiusMeters,
    this.siteLatitude,
    this.siteLongitude,
    required this.showOpenSettings,
    required this.onRecheck,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    final bg = hasError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    final border =
        hasError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0);
    final ink = hasError ? const Color(0xFF991B1B) : const Color(0xFF065F46);
    final distanceText = distanceMeters == null
        ? null
        : 'You are ${distanceMeters!.round()} m from site (limit $radiusMeters m)';
    final siteCoordsText = siteLatitude != null && siteLongitude != null
        ? 'Site: ${siteLatitude!.toStringAsFixed(7)}, ${siteLongitude!.toStringAsFixed(7)}'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isChecking)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  hasError
                      ? Icons.location_off_outlined
                      : Icons.location_on_outlined,
                  size: 18,
                  color: ink,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isChecking
                      ? 'Checking your distance from the project site…'
                      : (hasError
                          ? error!
                          : (distanceText ??
                              'You are within $radiusMeters m of the project site.')),
                  style: TextStyle(
                    color: ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (!isChecking && siteCoordsText != null) ...[
            const SizedBox(height: 8),
            Text(
              siteCoordsText,
              style: TextStyle(
                color: ink.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onRecheck,
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('Recheck location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  side: BorderSide(color: border),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (showOpenSettings && onOpenSettings != null)
                TextButton(
                  onPressed: onOpenSettings,
                  style: TextButton.styleFrom(
                    foregroundColor: ink,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Open settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

_SiteCoordinates? _parseSiteLocation(dynamic value) {
  if (value == null) return null;

  dynamic normalized = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      normalized = jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
  if (normalized is! Map) return null;

  final map = Map<String, dynamic>.from(normalized);
  final lat = _doubleValue(
    map['latitude'] ?? map['lat'] ?? map['site_latitude'],
  );
  final lng = _doubleValue(
    map['longitude'] ?? map['lng'] ?? map['lon'] ?? map['site_longitude'],
  );
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return _SiteCoordinates(latitude: lat, longitude: lng);
}

void _logNearSiteUploadConfig({
  required Map<String, dynamic> task,
  required Map<String, dynamic> action,
  required String itemRunId,
  required bool requireNearSite,
  required int nearSiteRadiusMeters,
  required dynamic siteLocationRaw,
  required dynamic siteLocationAvailableRaw,
  required bool siteLocationAvailable,
  required _SiteCoordinates? parsedSiteLocation,
}) {
  final redactedAction = _redactWorkflowActionForLog(action);
  final siteMap = _configMap(siteLocationRaw);
  print(
    '[NearSiteUpload] config '
    'item_run_id=$itemRunId '
    'project_id=${task['project_id']} '
    'task_id=${task['id']} '
    'action_id=${action['id']} '
    'require_near_site=$requireNearSite '
    'near_site_radius_meters=$nearSiteRadiusMeters '
    'site_location_available_raw=$siteLocationAvailableRaw '
    'site_location_available=$siteLocationAvailable '
    'site_location_raw=$siteLocationRaw '
    'site_location_link=${siteMap?['location_link']} '
    'parsed_site_latitude=${parsedSiteLocation?.latitude} '
    'parsed_site_longitude=${parsedSiteLocation?.longitude} '
    'action_source_keys=${action.keys.map((key) => key.toString()).toList()} '
    'upload_action=$redactedAction',
  );
}

void _logNearSiteDistanceCheck({
  required String itemRunId,
  required String projectId,
  required double siteLatitude,
  required double siteLongitude,
  required double deviceLatitude,
  required double deviceLongitude,
  required double distanceMeters,
  required int nearSiteRadiusMeters,
  required bool withinRadius,
}) {
  print(
    '[NearSiteUpload] distance_check '
    'item_run_id=$itemRunId '
    'project_id=$projectId '
    'site_latitude=$siteLatitude '
    'site_longitude=$siteLongitude '
    'device_latitude=$deviceLatitude '
    'device_longitude=$deviceLongitude '
    'distance_meters=${distanceMeters.round()} '
    'near_site_radius_meters=$nearSiteRadiusMeters '
    'within_radius=$withinRadius',
  );
}

Map<String, dynamic> _redactWorkflowActionForLog(Map<String, dynamic> action) {
  final copy = Map<String, dynamic>.from(action);
  for (final key in copy.keys.toList()) {
    final normalized = key.toString().toLowerCase();
    if (normalized.contains('token') ||
        normalized.contains('password') ||
        normalized.contains('secret')) {
      copy[key] = '[redacted]';
    }
  }
  return copy;
}

double? _doubleValue(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

Future<_NearSiteCheckResult> _ensureLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const _NearSiteCheckResult(
      ok: false,
      error:
          'Location services are turned off. Turn them on to upload near the project site.',
      openSettings: true,
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    return const _NearSiteCheckResult(
      ok: false,
      error:
          'Location permission is required to upload near the project site.',
      openSettings: true,
    );
  }

  if (permission == LocationPermission.deniedForever) {
    return const _NearSiteCheckResult(
      ok: false,
      error:
          'Location permission is permanently denied. Enable it in app settings.',
      openSettings: true,
    );
  }

  return const _NearSiteCheckResult(ok: true);
}

class _ChecklistFollowupResponse {
  final String itemId;
  final String comment;
  final _SelectedUploadFile? file;

  const _ChecklistFollowupResponse({
    required this.itemId,
    required this.comment,
    this.file,
  });
}

class _UserChecklistFollowupSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<String> allowedFormats;
  final _WorkflowUploadSourceConfig uploadSources;
  final bool requireComment;
  final bool requireDocument;
  final bool showComment;
  final bool showDocument;
  final String submitLabel;
  final Future<bool> Function(List<_ChecklistFollowupResponse> responses)
      onSubmit;

  const _UserChecklistFollowupSheet({
    required this.items,
    required this.allowedFormats,
    required this.uploadSources,
    required this.requireComment,
    required this.requireDocument,
    required this.showComment,
    required this.showDocument,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_UserChecklistFollowupSheet> createState() =>
      _UserChecklistFollowupSheetState();
}

class _UserChecklistFollowupSheetState
    extends State<_UserChecklistFollowupSheet> {
  final Map<String, TextEditingController> _commentControllers = {};
  final Map<String, _SelectedUploadFile> _selectedFiles = {};
  final Map<String, String?> _commentErrors = {};
  final Map<String, String?> _fileErrors = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (final item in _items) {
      final itemId = _followupItemId(item);
      _commentControllers[itemId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _items {
    if (widget.items.isNotEmpty) return widget.items;
    return [
      {'id': 'item_1', 'label': 'Checklist follow-up'}
    ];
  }

  Future<void> _setSelectedFile(String itemId, _SelectedUploadFile? file) async {
    if (file != null &&
        !_isAllowedWorkflowUploadFile(file, widget.uploadSources)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File type not allowed. Allowed: ${_allowedFormatsMessage(widget.uploadSources)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      if (file == null) {
        _selectedFiles.remove(itemId);
      } else {
        _selectedFiles[itemId] = file;
      }
      _fileErrors[itemId] = null;
    });
  }

  Future<void> _pickGallery(String itemId) async {
    final picked = await _pickWorkflowGalleryFile(
      allowedFormats: widget.uploadSources.imageFormats,
    );
    if (picked == null) return;
    await _setSelectedFile(itemId, picked);
  }

  Future<void> _pickCamera(String itemId) async {
    final picked = await _pickWorkflowCameraFile();
    if (picked == null) return;
    await _setSelectedFile(itemId, picked);
  }

  Future<void> _pickDocument(String itemId) async {
    final picked = await _pickWorkflowDocumentFile(
      documentFormats: widget.uploadSources.documentFormats,
    );
    if (picked == null) return;
    await _setSelectedFile(itemId, picked);
  }

  Future<void> _pickVideo(String itemId) async {
    final picked = await _recordWorkflowVideoFile(
      context: context,
      videoFormats: widget.uploadSources.videoFormats,
    );
    if (picked == null) return;
    await _setSelectedFile(itemId, picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    var hasError = false;
    setState(() {
      _commentErrors.clear();
      _fileErrors.clear();

      for (final item in _items) {
        final itemId = _followupItemId(item);
        final comment = _commentControllers[itemId]?.text.trim() ?? '';

        if (widget.requireComment && comment.isEmpty) {
          _commentErrors[itemId] = 'Response comment is required.';
          hasError = true;
        }
        if (widget.requireDocument && _selectedFiles[itemId] == null) {
          _fileErrors[itemId] = 'Proof attachment is required.';
          hasError = true;
        }
      }
    });

    if (hasError) return;

    final responses = _items.map((item) {
      final itemId = _followupItemId(item);
      return _ChecklistFollowupResponse(
        itemId: itemId,
        comment: _commentControllers[itemId]?.text.trim() ?? '',
        file: _selectedFiles[itemId],
      );
    }).toList();

    setState(() {
      _isSubmitting = true;
    });

    final submitted = await widget.onSubmit(responses);
    if (!mounted) return;

    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._items.map((item) {
          final itemId = _followupItemId(item);
          final itemTitle =
              _firstString(item, ['label', 'name', 'title'])?.trim() ?? '';
          final showItemHeader = _items.length > 1 ||
              (itemTitle.isNotEmpty &&
                  itemTitle.toLowerCase() != 'checklist follow-up');
          return _ChecklistFollowupItemCard(
            item: item,
            itemId: itemId,
            allowedFormats: widget.allowedFormats,
            uploadSources: widget.uploadSources,
            showComment: widget.showComment,
            showDocument: widget.showDocument,
            requireComment: widget.requireComment,
            requireDocument: widget.requireDocument,
            commentController: _commentControllers[itemId]!,
            selectedFile: _selectedFiles[itemId],
            commentError: _commentErrors[itemId],
            fileError: _fileErrors[itemId],
            onPickGallery:
                _isSubmitting ? null : () => _pickGallery(itemId),
            onPickCamera: _isSubmitting ? null : () => _pickCamera(itemId),
            onPickDocument: _isSubmitting ? null : () => _pickDocument(itemId),
            onPickVideo: _isSubmitting ? null : () => _pickVideo(itemId),
            onRemoveFile: _isSubmitting
                ? null
                : () => _setSelectedFile(itemId, null),
            showItemHeader: showItemHeader,
            onCommentChanged: () {
              if (_commentErrors[itemId] != null) {
                setState(() {
                  _commentErrors[itemId] = null;
                });
              }
            },
          );
        }),
        SizedBox(height: 6),
        _SheetSubmitButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _ChecklistFollowupItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String itemId;
  final List<String> allowedFormats;
  final _WorkflowUploadSourceConfig uploadSources;
  final bool showComment;
  final bool showDocument;
  final bool requireComment;
  final bool requireDocument;
  final TextEditingController commentController;
  final _SelectedUploadFile? selectedFile;
  final String? commentError;
  final String? fileError;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickDocument;
  final VoidCallback? onPickVideo;
  final VoidCallback? onRemoveFile;
  final VoidCallback onCommentChanged;
  final bool showItemHeader;

  const _ChecklistFollowupItemCard({
    required this.item,
    required this.itemId,
    required this.allowedFormats,
    required this.uploadSources,
    required this.showComment,
    required this.showDocument,
    required this.requireComment,
    required this.requireDocument,
    required this.commentController,
    required this.selectedFile,
    required this.commentError,
    required this.fileError,
    required this.onPickGallery,
    required this.onPickCamera,
    this.onPickDocument,
    this.onPickVideo,
    this.onRemoveFile,
    required this.onCommentChanged,
    this.showItemHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final title =
        _firstString(item, ['label', 'name', 'title']) ?? 'Checklist follow-up';
    final originalComment = _firstString(item, ['comment', 'note', 'remarks']);
    final originalFiles = _followupItemFiles(item);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showItemHeader)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.assignment_turned_in_outlined,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: _premiumInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          if (originalComment != null) ...[
            SizedBox(height: 14),
            _FollowupInfoBlock(
              label: 'Original comment',
              text: originalComment,
              icon: Icons.chat_bubble_outline_rounded,
            ),
          ],
          if (originalFiles.isNotEmpty) ...[
            SizedBox(height: 14),
            _ResponseSectionHeader(
              icon: Icons.attach_file_rounded,
              label: originalFiles.length == 1
                  ? 'Original attachment'
                  : 'Original attachments',
            ),
            SizedBox(height: 10),
            ...originalFiles.map(
              (file) => _ResponseFileTile(
                file: file,
                relatedFiles: originalFiles,
              ),
            ),
          ],
          if (showComment) ...[
            SizedBox(height: 16),
            _ResponseSectionHeader(
              icon: Icons.chat_bubble_outline_rounded,
              label: requireComment
                  ? 'Response comment *'
                  : 'Response comment',
            ),
            SizedBox(height: 8),
            TextField(
              controller: commentController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => onCommentChanged(),
              style: TextStyle(
                color: _premiumInk,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
              decoration: _sheetInputDecoration(
                context,
                'Write your response...',
              ).copyWith(
                labelText: '',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                hintText: 'Write your response...',
                hintStyle: TextStyle(
                  color: _premiumMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                errorText: commentError,
              ),
            ),
          ],
          if (showDocument) ...[
            SizedBox(height: 16),
            _ResponseSectionHeader(
              icon: Icons.attach_file_rounded,
              label: requireDocument ? 'Attach proof *' : 'Attach proof',
            ),
            SizedBox(height: 8),
            _WorkflowUploadSourceButtons(
              sources: uploadSources,
              onPickGallery: onPickGallery,
              onPickCamera: onPickCamera,
              onPickDocument: onPickDocument,
              onPickVideo: onPickVideo,
            ),
            if (allowedFormats.isNotEmpty) ...[
              SizedBox(height: 6),
              Text(
                'Allowed: ${allowedFormats.join(', ')}',
                style: TextStyle(
                  color: _premiumMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (selectedFile != null) ...[
              SizedBox(height: 10),
              _SelectedUploadPreview(
                file: selectedFile!,
                onRemove: onRemoveFile,
              ),
            ],
            if (fileError != null) ...[
              SizedBox(height: 6),
              Text(
                fileError!,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FollowupInfoBlock extends StatelessWidget {
  final String label;
  final String text;
  final IconData icon;

  const _FollowupInfoBlock({
    required this.label,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Color(0xFF2563EB)),
              SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: _premiumInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: _premiumMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequiredFieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const _RequiredFieldLabel({
    required this.label,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

class _SlotSelectionRow {
  DateTime? date;
  DateTime? dateTime;
  _SlotTimeOption? timeOption;
}

class _SlotTimeOption {
  final String label;
  final String time;

  const _SlotTimeOption({
    required this.label,
    required this.time,
  });
}

class _SlotSelectionSheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final int slotCount;
  final Widget child;
  final String submitLabel;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onSubmit;

  const _SlotSelectionSheetFrame({
    required this.title,
    required this.subtitle,
    required this.slotCount,
    required this.child,
    required this.submitLabel,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppTheme.getPrimaryColor(context)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.event_available_outlined,
                      color: AppTheme.getPrimaryColor(context),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: AppTheme.getTextPrimary(context),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.getPrimaryColor(context)
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$slotCount slots',
                                style: TextStyle(
                                  color: AppTheme.getPrimaryColor(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle.isNotEmpty) ...[
                          SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close),
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(18),
                child: child,
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 18),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundSecondary(context),
                border: Border(
                  top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSubmitting || !canSubmit ? null : onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getPrimaryColor(context),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.getTextSecondary(context)
                        .withValues(alpha: 0.22),
                    padding: EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          submitLabel,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotSelectionRowCard extends StatelessWidget {
  final int number;
  final _SlotSelectionRow row;
  final bool usePredefinedTimes;
  final List<_SlotTimeOption> timeOptions;
  final String? error;
  final VoidCallback onPickDate;
  final VoidCallback onPickDateTime;
  final VoidCallback onPickPredefinedTime;
  final ValueChanged<_SlotTimeOption> onSelectTime;

  const _SlotSelectionRowCard({
    required this.number,
    required this.row,
    required this.usePredefinedTimes,
    required this.timeOptions,
    required this.error,
    required this.onPickDate,
    required this.onPickDateTime,
    required this.onPickPredefinedTime,
    required this.onSelectTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimary(context).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: error == null
              ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.12)
              : Colors.red.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slot $number',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 10),
                if (usePredefinedTimes) ...[
                  _SlotPickerTile(
                    icon: Icons.calendar_today_outlined,
                    label: row.date == null
                        ? 'Select date'
                        : _formatDisplayDate(row.date!),
                    onTap: onPickDate,
                  ),
                  SizedBox(height: 10),
                  if (timeOptions.length <= 5)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: timeOptions
                          .map(
                            (option) => _SlotTimeChip(
                              option: option,
                              selected: row.timeOption?.label == option.label,
                              onTap: () => onSelectTime(option),
                            ),
                          )
                          .toList(),
                    )
                  else
                    _SlotPickerTile(
                      icon: Icons.access_time_outlined,
                      label: row.timeOption == null
                          ? 'Select predefined time'
                          : _slotOptionDisplay(row.timeOption!),
                      onTap: onPickPredefinedTime,
                    ),
                ] else
                  _SlotPickerTile(
                    icon: Icons.schedule_outlined,
                    label: row.dateTime == null
                        ? 'Select date and time'
                        : _formatDisplayDateTime(row.dateTime!),
                    onTap: onPickDateTime,
                  ),
                if (error != null) ...[
                  SizedBox(height: 9),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

class _SlotPickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SlotPickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.getPrimaryColor(context)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                color: AppTheme.getTextSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotTimeChip extends StatelessWidget {
  final _SlotTimeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _SlotTimeChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(option.label),
          SizedBox(height: 2),
          Text(
            _formatSlotTime(option.time),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white.withValues(alpha: 0.88)
                  : AppTheme.getTextSecondary(context),
            ),
          ),
        ],
      ),
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.getPrimaryColor(context),
      backgroundColor: AppTheme.getBackgroundSecondary(context),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.getTextPrimary(context),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected
              ? AppTheme.getPrimaryColor(context)
              : AppTheme.getPrimaryColor(context).withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _SlotTimeOptionPickerSheet extends StatelessWidget {
  final List<_SlotTimeOption> options;
  final _SlotTimeOption? selected;

  const _SlotTimeOptionPickerSheet({
    required this.options,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select time option',
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close),
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
                itemCount: options.length,
                separatorBuilder: (_, __) => SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = selected?.label == option.label;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, option),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.getPrimaryColor(context)
                                  .withValues(alpha: 0.12)
                              : AppTheme.getBackgroundPrimary(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.getPrimaryColor(context)
                                : AppTheme.getPrimaryColor(context)
                                    .withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.label,
                                    style: TextStyle(
                                      color: AppTheme.getTextPrimary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    _formatSlotTime(option.time),
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: AppTheme.getPrimaryColor(context),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotServerErrorBanner extends StatelessWidget {
  final String message;

  const _SlotServerErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red[700]),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotConfirmationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic>? priorSelection;
  final bool allowNote;
  final bool requireNote;
  final String submitLabel;
  final Future<bool> Function({
    required int acceptedSlotIndex,
    required String comment,
  }) onSubmit;
  final void Function(int slotIndex) onSelectedForDebug;

  const _SlotConfirmationSheet({
    required this.slots,
    required this.priorSelection,
    required this.allowNote,
    required this.requireNote,
    required this.submitLabel,
    required this.onSubmit,
    required this.onSelectedForDebug,
  });

  @override
  State<_SlotConfirmationSheet> createState() => _SlotConfirmationSheetState();
}

class _SlotConfirmationSheetState extends State<_SlotConfirmationSheet> {
  final TextEditingController _noteController = TextEditingController();
  int? _selectedSlotIndex;
  bool _isSubmitting = false;
  String? _slotError;
  String? _noteError;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final note = _noteController.text.trim();
    if (_selectedSlotIndex == null || (widget.requireNote && note.isEmpty)) {
      setState(() {
        _slotError =
            _selectedSlotIndex == null ? 'Please select one slot.' : null;
        _noteError = widget.requireNote && note.isEmpty
            ? 'Confirmation note is required.'
            : null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _slotError = null;
      _noteError = null;
    });

    final submitted = await widget.onSubmit(
      acceptedSlotIndex: _selectedSlotIndex!,
      comment: note,
    );
    if (!mounted) return;

    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sourceTask = widget.priorSelection == null
        ? null
        : _firstString(
            widget.priorSelection!, ['source_task_name', 'task_name']);
    final clientNote = widget.priorSelection == null
        ? null
        : _firstString(widget.priorSelection!, ['note', 'comment']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sourceTask != null) ...[
          Text(
            'Slots from $sourceTask',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
        ],
        if (clientNote != null) ...[
          _FollowupInfoBlock(
            label: 'Client comment',
            text: clientNote,
            icon: Icons.chat_bubble_outline_rounded,
          ),
          SizedBox(height: 14),
        ],
        ...widget.slots.asMap().entries.map((entry) {
          final slot = entry.value;
          final slotIndex = _slotIndex(slot, entry.key);
          final selected = _selectedSlotIndex == slotIndex;
          return _SlotConfirmationOptionCard(
            number: entry.key + 1,
            slot: slot,
            selected: selected,
            onTap: () {
              setState(() {
                _selectedSlotIndex = slotIndex;
                _slotError = null;
              });
              widget.onSelectedForDebug(slotIndex);
            },
          );
        }),
        if (_slotError != null) ...[
          SizedBox(height: 4),
          Text(
            _slotError!,
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (widget.allowNote) ...[
          SizedBox(height: 14),
          _RequiredFieldLabel(
            label: 'Confirmation note',
            required: widget.requireNote,
          ),
          SizedBox(height: 8),
          TextField(
            controller: _noteController,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) {
              if (_noteError != null) {
                setState(() {
                  _noteError = null;
                });
              }
            },
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: _sheetInputDecoration(
              context,
              'Add confirmation note...',
            ).copyWith(errorText: _noteError),
          ),
        ],
        SizedBox(height: 18),
        _ApproveResponseButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _SlotConfirmationOptionCard extends StatelessWidget {
  final int number;
  final Map<String, dynamic> slot;
  final bool selected;
  final VoidCallback onTap;

  const _SlotConfirmationOptionCard({
    required this.number,
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = _slotDisplay(slot);
    final timeDetail = _slotTimeDetail(slot);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? Color(0xFF10B981).withValues(alpha: 0.10)
              : _premiumSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Color(0xFF10B981) : Color(0xFFE5E7EB),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: Color(0xFF10B981),
            ),
            SizedBox(width: 4),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? Color(0xFF10B981)
                    : AppTheme.getPrimaryColor(context).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppTheme.getPrimaryColor(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (timeDetail.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      timeDetail,
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PictureChoiceListRowState {
  final String id;
  String name;
  String? localImagePath;
  String? localImageName;
  String? existingImageUrl;

  _PictureChoiceListRowState({
    required this.id,
    this.name = '',
    this.localImagePath,
    this.localImageName,
    this.existingImageUrl,
  });
}

class _PictureChoiceFileField {
  final String field;
  final String path;
  final String filename;

  const _PictureChoiceFileField({
    required this.field,
    required this.path,
    required this.filename,
  });
}

class _PictureChoiceListSheet extends StatefulWidget {
  final List<Map<String, dynamic>> presetOptions;
  final String? heading;
  final bool allowRuntimeAdd;
  final int minOptions;
  final String submitLabel;
  final Future<bool> Function(List<_PictureChoiceListRowState> rows) onSubmit;

  const _PictureChoiceListSheet({
    required this.presetOptions,
    required this.heading,
    required this.allowRuntimeAdd,
    required this.minOptions,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_PictureChoiceListSheet> createState() => _PictureChoiceListSheetState();
}

class _PictureChoiceListSheetState extends State<_PictureChoiceListSheet> {
  late List<_PictureChoiceListRowState> _rows;
  bool _isSubmitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _rows = _pictureChoiceListInitialRows(widget.presetOptions);
  }

  Future<void> _pickImage(_PictureChoiceListRowState row) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined),
              title: Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
    );
    if (picked == null) return;

    setState(() {
      row.localImagePath = picked.path;
      row.localImageName = picked.name;
      row.existingImageUrl = null;
      _formError = null;
    });
  }

  void _addRow() {
    setState(() {
      _rows.add(_PictureChoiceListRowState(id: _generatePictureChoiceOptionId()));
      _formError = null;
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index);
      _formError = null;
    });
  }

  String? _validateRows() {
    if (_rows.length < widget.minOptions) {
      return 'Add at least ${widget.minOptions} option'
          '${widget.minOptions == 1 ? '' : 's'}.';
    }

    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      if (row.name.trim().isEmpty) {
        return 'Option ${index + 1} needs a name.';
      }
      if (row.localImagePath == null && row.existingImageUrl == null) {
        return 'Option ${index + 1} needs an image.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final validationError = _validateRows();
    if (validationError != null) {
      setState(() {
        _formError = validationError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    final submitted = await widget.onSubmit(_rows);
    if (!mounted) return;

    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.heading != null) ...[
          Text(
            widget.heading!,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          SizedBox(height: 14),
        ],
        if (_formError != null) ...[
          _SlotServerErrorBanner(message: _formError!),
          SizedBox(height: 14),
        ],
        ..._rows.asMap().entries.map(
              (entry) => _PictureChoiceListRowCard(
                index: entry.key,
                row: entry.value,
                canRemove: _rows.length > 1,
                onPickImage: () => _pickImage(entry.value),
                onRemove: () => _removeRow(entry.key),
                onNameChanged: (value) {
                  setState(() {
                    entry.value.name = value;
                    _formError = null;
                  });
                },
              ),
            ),
        if (widget.allowRuntimeAdd) ...[
          SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isSubmitting ? null : _addRow,
            icon: Icon(Icons.add_circle_outline),
            label: Text('Add option'),
          ),
        ],
        SizedBox(height: 18),
        _ApproveResponseButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _PictureChoiceListRowCard extends StatelessWidget {
  final int index;
  final _PictureChoiceListRowState row;
  final bool canRemove;
  final VoidCallback onPickImage;
  final VoidCallback onRemove;
  final ValueChanged<String> onNameChanged;

  const _PictureChoiceListRowCard({
    required this.index,
    required this.row,
    required this.canRemove,
    required this.onPickImage,
    required this.onRemove,
    required this.onNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = row.localImagePath ?? row.existingImageUrl;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Option ${index + 1}',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                  tooltip: 'Remove option',
                ),
            ],
          ),
          SizedBox(height: 10),
          InkWell(
            onTap: onPickImage,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              height: 140,
              decoration: BoxDecoration(
                color: _premiumBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Color(0xFFE5E7EB)),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppTheme.getPrimaryColor(context),
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap to add image',
                          style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : _PictureChoiceImagePreview(url: imageUrl),
            ),
          ),
          SizedBox(height: 12),
          TextFormField(
            initialValue: row.name,
            onChanged: onNameChanged,
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: _sheetInputDecoration(context, 'Name / code *'),
          ),
        ],
      ),
    );
  }
}

class _PictureChoiceListReadOnlyView extends StatelessWidget {
  final Map<String, dynamic> response;
  final String? heading;

  const _PictureChoiceListReadOnlyView({
    required this.response,
    required this.heading,
  });

  @override
  Widget build(BuildContext context) {
    final options = _mapListFlexible(response['options']);
    final submittedBy = _firstString(response, [
      'submitted_by',
      'submitted_by_name',
    ]);
    final submittedAt = response['submitted_at']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading != null) ...[
          Text(
            heading!,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          SizedBox(height: 14),
        ],
        if (submittedBy != null || submittedAt != null) ...[
          _FollowupInfoBlock(
            label: 'Submitted',
            text: [
              if (submittedBy != null) submittedBy,
              if (submittedAt != null) submittedAt,
            ].join(' • '),
            icon: Icons.check_circle_outline,
          ),
          SizedBox(height: 14),
        ],
        if (options.isEmpty)
          _ResponseEmptyState(message: 'No options submitted yet.')
        else
          ...options.map(
            (option) => _PictureChoiceReadOnlyOptionCard(option: option),
          ),
      ],
    );
  }
}

class _PictureChoicePickSheet extends StatefulWidget {
  final List<Map<String, dynamic>> options;
  final String? heading;
  final String? sourceTaskName;
  final bool allowNote;
  final bool requireNote;
  final String submitLabel;
  final Future<bool> Function({
    required String selectedOptionId,
    required String note,
  }) onSubmit;

  const _PictureChoicePickSheet({
    required this.options,
    required this.heading,
    required this.sourceTaskName,
    required this.allowNote,
    required this.requireNote,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_PictureChoicePickSheet> createState() => _PictureChoicePickSheetState();
}

class _PictureChoicePickSheetState extends State<_PictureChoicePickSheet> {
  final TextEditingController _noteController = TextEditingController();
  String? _selectedOptionId;
  bool _isSubmitting = false;
  String? _selectionError;
  String? _noteError;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final note = _noteController.text.trim();
    if (_selectedOptionId == null ||
        (widget.requireNote && note.isEmpty)) {
      setState(() {
        _selectionError =
            _selectedOptionId == null ? 'Please select one option.' : null;
        _noteError = widget.requireNote && note.isEmpty
            ? 'Comment is required.'
            : null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _selectionError = null;
      _noteError = null;
    });

    final submitted = await widget.onSubmit(
      selectedOptionId: _selectedOptionId!,
      note: note,
    );
    if (!mounted) return;

    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.heading != null) ...[
          Text(
            widget.heading!,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          SizedBox(height: 10),
        ],
        if (widget.sourceTaskName != null) ...[
          Text(
            'Options from ${widget.sourceTaskName}',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
        ],
        ...widget.options.map((option) {
          final optionId = option['id']?.toString() ?? '';
          final selected = _selectedOptionId == optionId;
          return _PictureChoicePickOptionCard(
            option: option,
            selected: selected,
            onTap: () {
              setState(() {
                _selectedOptionId = optionId;
                _selectionError = null;
              });
            },
          );
        }),
        if (_selectionError != null) ...[
          SizedBox(height: 4),
          Text(
            _selectionError!,
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (widget.allowNote) ...[
          SizedBox(height: 14),
          _RequiredFieldLabel(
            label: 'Comment',
            required: widget.requireNote,
          ),
          SizedBox(height: 8),
          TextField(
            controller: _noteController,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) {
              if (_noteError != null) {
                setState(() {
                  _noteError = null;
                });
              }
            },
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: _sheetInputDecoration(
              context,
              widget.requireNote ? 'Add a comment *' : 'Add a comment',
            ).copyWith(errorText: _noteError),
          ),
        ],
        SizedBox(height: 18),
        _ApproveResponseButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _PictureChoicePickReadOnlyView extends StatelessWidget {
  final Map<String, dynamic> response;

  const _PictureChoicePickReadOnlyView({required this.response});

  @override
  Widget build(BuildContext context) {
    final selectedOption = _configMap(response['selected_option']) ?? {};
    final note = _firstString(response, ['note', 'comment']);
    final submittedBy = _firstString(response, [
      'submitted_by',
      'submitted_by_name',
    ]);
    final submittedAt = response['submitted_at']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (submittedBy != null || submittedAt != null) ...[
          _FollowupInfoBlock(
            label: 'Submitted',
            text: [
              if (submittedBy != null) submittedBy,
              if (submittedAt != null) submittedAt,
            ].join(' • '),
            icon: Icons.check_circle_outline,
          ),
          SizedBox(height: 14),
        ],
        if (selectedOption.isNotEmpty)
          _PictureChoiceReadOnlyOptionCard(
            option: selectedOption,
            highlight: true,
          )
        else
          _ResponseEmptyState(message: 'No selection recorded.'),
        if (note != null) ...[
          SizedBox(height: 14),
          _FollowupInfoBlock(
            label: 'Comment',
            text: note,
            icon: Icons.chat_bubble_outline_rounded,
          ),
        ],
      ],
    );
  }
}

class _PictureChoicePickOptionCard extends StatelessWidget {
  final Map<String, dynamic> option;
  final bool selected;
  final VoidCallback onTap;

  const _PictureChoicePickOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = _firstString(option, ['name', 'label', 'title']) ?? 'Option';
    final imageUrl = _pictureChoiceOptionImageUrl(option);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? Color(0xFF0D9488).withValues(alpha: 0.10)
              : _premiumSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Color(0xFF0D9488) : Color(0xFFE5E7EB),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: Color(0xFF0D9488),
            ),
            SizedBox(width: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: imageUrl == null
                    ? Container(
                        color: _premiumBackground,
                        child: Icon(Icons.image_outlined, color: _premiumMuted),
                      )
                    : _PictureChoiceImagePreview(url: imageUrl),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PictureChoiceReadOnlyOptionCard extends StatelessWidget {
  final Map<String, dynamic> option;
  final bool highlight;

  const _PictureChoiceReadOnlyOptionCard({
    required this.option,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = _firstString(option, ['name', 'label', 'title']) ?? 'Option';
    final imageUrl = _pictureChoiceOptionImageUrl(option);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? Color(0xFF0D9488).withValues(alpha: 0.08)
            : _premiumSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? Color(0xFF0D9488) : Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl == null
                  ? Container(
                      color: _premiumBackground,
                      child: Icon(Icons.image_outlined, color: _premiumMuted),
                    )
                  : _PictureChoiceImagePreview(url: imageUrl),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PictureChoiceImagePreview extends StatelessWidget {
  final String url;

  const _PictureChoiceImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = url.startsWith('/') ? '$_workflowApiBaseUrl$url' : url;
    final uri = Uri.tryParse(resolvedUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Image.network(
        resolvedUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    final file = File(url);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      color: _premiumBackground,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: _premiumMuted),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isOutlined;
  final bool isLoading;
  final VoidCallback? onPressed;
  final String? blockedMessage;
  final bool expand;

  const _ActionChipButton({
    required this.label,
    required this.icon,
    required this.color,
    this.isOutlined = false,
    this.isLoading = false,
    this.onPressed,
    this.blockedMessage,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final effectiveColor = disabled ? AppTheme.mutedGrey : color;
    final isPrimary = !isOutlined && !disabled;
    // Soft tinted fills keep action identity without neon solid blocks.
    final fillColor = isPrimary
        ? effectiveColor.withValues(alpha: 0.12)
        : _premiumSurface;
    final contentColor = isPrimary ? effectiveColor : _premiumInk;
    final iconColor = isPrimary ? effectiveColor : effectiveColor;

    final button = Opacity(
      opacity: disabled ? 0.62 : 1,
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: expand ? 52 : 46),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(expand ? 17 : 14),
              child: Container(
                height: expand ? 52 : 46,
                padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 14),
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(expand ? 17 : 14),
                  border: Border.all(
                    color: isPrimary
                        ? effectiveColor.withValues(alpha: 0.28)
                        : AppTheme.border,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.softShadow,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: expand
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            iconColor,
                          ),
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 18,
                        color: iconColor,
                      ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: contentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (blockedMessage == null || blockedMessage!.isEmpty) return button;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        SizedBox(height: 5),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 220),
          child: Text(
            blockedMessage!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFFB45309),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomSheetFrame extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final ScrollController? scrollController;

  const _BottomSheetFrame({
    required this.title,
    required this.icon,
    required this.child,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.getPrimaryColor(context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: AppTheme.getPrimaryColor(context),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close),
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
              SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;

  const _SheetTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: AppTheme.getTextPrimary(context)),
      decoration: _sheetInputDecoration(context, label),
    );
  }
}

class _UpdateStatusSheet extends StatefulWidget {
  final List<String> statuses;
  final bool allowComment;
  final bool requireComment;
  final bool showNote;
  final String submitLabel;
  final Future<bool> Function({
    required String status,
    required String comment,
    required String note,
  }) onSubmit;

  const _UpdateStatusSheet({
    required this.statuses,
    required this.allowComment,
    required this.requireComment,
    required this.showNote,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String? _selectedStatus;
  String? _commentError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.statuses.isNotEmpty ? widget.statuses.first : null;
  }

  @override
  void dispose() {
    _commentController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    if (_selectedStatus == null || _selectedStatus!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a status.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.requireComment && _commentController.text.trim().isEmpty) {
      setState(() {
        _commentError = 'Comment is required.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _commentError = null;
    });

    final success = await widget.onSubmit(
      status: _selectedStatus!,
      comment: _commentController.text.trim(),
      note: _noteController.text.trim(),
    );
    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        TaskStatusChipSet(
          currentStatus: _selectedStatus ?? '',
          statuses: widget.statuses,
          enabled: !_isSubmitting,
          onStatusSelected: (value) {
            setState(() {
              _selectedStatus = value;
            });
          },
        ),
        if (widget.allowComment) ...[
          SizedBox(height: 14),
          TextField(
            controller: _commentController,
            maxLines: 3,
            onChanged: (_) {
              if (_commentError != null) {
                setState(() {
                  _commentError = null;
                });
              }
            },
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: _sheetInputDecoration(
              context,
              widget.requireComment ? 'Comment *' : 'Comment',
            ).copyWith(errorText: _commentError),
          ),
        ],
        if (widget.showNote) ...[
          SizedBox(height: 14),
          _SheetTextField(
            controller: _noteController,
            label: 'Note',
            maxLines: 3,
          ),
        ],
        SizedBox(height: 20),
        _SheetSubmitButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _SheetSubmitButton extends StatelessWidget {
  final String label;
  final bool isSubmitting;
  final VoidCallback? onPressed;

  const _SheetSubmitButton({
    required this.label,
    required this.isSubmitting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.getPrimaryColor(context),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 14),
        ),
        child: isSubmitting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(toSentenceCaseLabel(label)),
      ),
    );
  }
}

class _ApproveResponseButton extends StatelessWidget {
  final String label;
  final bool isSubmitting;
  final VoidCallback? onPressed;

  const _ApproveResponseButton({
    required this.label,
    required this.isSubmitting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: isSubmitting ? null : onPressed,
        icon: isSubmitting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(Icons.check_circle_outline_rounded, size: 20),
        label: Text(
          isSubmitting ? 'Approving...' : toSentenceCaseLabel(label),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColorConst,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              AppTheme.primaryColorConst.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shadowColor: AppTheme.primaryColorConst.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _ViewPriorResponseApprovalPanel extends StatefulWidget {
  final String approveLabel;
  final bool showComment;
  final bool requireComment;
  final Future<bool> Function(String comment) onApprove;

  const _ViewPriorResponseApprovalPanel({
    required this.approveLabel,
    required this.showComment,
    required this.requireComment,
    required this.onApprove,
  });

  @override
  State<_ViewPriorResponseApprovalPanel> createState() =>
      _ViewPriorResponseApprovalPanelState();
}

class _ViewPriorResponseApprovalPanelState
    extends State<_ViewPriorResponseApprovalPanel> {
  final TextEditingController _commentController = TextEditingController();
  bool _isApproving = false;
  String? _commentError;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_isApproving) return;

    final comment = _commentController.text.trim();
    if (widget.requireComment && comment.isEmpty) {
      setState(() {
        _commentError = 'Comment is required.';
      });
      return;
    }

    setState(() {
      _isApproving = true;
      _commentError = null;
    });

    final approved = await widget.onApprove(comment);
    if (!mounted) return;

    if (approved) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isApproving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showComment) ...[
            RichText(
              text: TextSpan(
                text: 'Comment',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
                children: [
                  if (widget.requireComment)
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _commentController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) {
                if (_commentError != null) {
                  setState(() {
                    _commentError = null;
                  });
                }
              },
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 13,
              ),
              decoration: _sheetInputDecoration(
                context,
                'Add your review comment...',
              ).copyWith(errorText: _commentError),
            ),
            SizedBox(height: 14),
          ],
          _ApproveResponseButton(
            label: widget.approveLabel,
            isSubmitting: _isApproving,
            onPressed: _approve,
          ),
        ],
      ),
    );
  }
}

class _ActionMetaText extends StatelessWidget {
  final String label;
  final String value;

  const _ActionMetaText({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: AppTheme.getTextSecondary(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChecklistItemField extends StatelessWidget {
  final Map<String, dynamic> item;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  const _ChecklistItemField({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fieldType = item['field_type']?.toString() ?? 'checkbox';
    final label = item['label']?.toString() ?? 'Checklist item';
    final requiredLabel = item['required'] == true ? ' *' : '';

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimary(context).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _fieldForType(context, fieldType, '$label$requiredLabel'),
    );
  }

  Widget _fieldForType(BuildContext context, String fieldType, String label) {
    switch (fieldType) {
      case 'checkbox':
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label,
              style: TextStyle(color: AppTheme.getTextPrimary(context))),
          value: value == true,
          onChanged: (checked) => onChanged(checked == true),
        );
      case 'radio':
        final options = _stringList(item['options']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: AppTheme.getTextPrimary(context))),
            ...options.map(
              (option) => RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(option,
                    style: TextStyle(color: AppTheme.getTextPrimary(context))),
                value: option,
                groupValue: value?.toString(),
                onChanged: onChanged,
              ),
            ),
          ],
        );
      case 'text':
      case 'comment':
      case 'material_qty':
        return TextField(
          keyboardType: fieldType == 'material_qty'
              ? TextInputType.number
              : TextInputType.text,
          onChanged: onChanged,
          style: TextStyle(color: AppTheme.getTextPrimary(context)),
          decoration: _sheetInputDecoration(context, label),
        );
      default:
        return TextField(
          onChanged: onChanged,
          style: TextStyle(color: AppTheme.getTextPrimary(context)),
          decoration: _sheetInputDecoration(context, label),
        );
    }
  }
}

class _UserChecklistRow {
  final String id = DateTime.now().microsecondsSinceEpoch.toString();
  final TextEditingController labelController = TextEditingController();
  final TextEditingController commentController = TextEditingController();
  bool checked = true;
  _SelectedUploadFile? file;
  _SelectedUploadFile? videoFile;
  _SelectedUploadFile? docFile;

  void dispose() {
    labelController.dispose();
    commentController.dispose();
  }
}

class _UserChecklistSheet extends StatefulWidget {
  final bool allowComment;
  final _WorkflowUploadSourceConfig uploadSources;
  final int maxVideoDurationSeconds;
  final int maxVideoSizeMb;
  final String submitLabel;
  final Future<bool> Function(List<_UserChecklistRow> validRows) onSubmit;

  const _UserChecklistSheet({
    required this.allowComment,
    required this.uploadSources,
    required this.maxVideoDurationSeconds,
    required this.maxVideoSizeMb,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_UserChecklistSheet> createState() => _UserChecklistSheetState();
}

class _UserChecklistSheetState extends State<_UserChecklistSheet> {
  final List<_UserChecklistRow> _rows = [_UserChecklistRow()];
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _rejectDisallowed(_SelectedUploadFile file) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'File type not allowed. Allowed: ${_allowedFormatsMessage(widget.uploadSources)}',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _setRowImage(
    _UserChecklistRow row,
    _SelectedUploadFile? file,
  ) async {
    if (file != null &&
        !_isAllowedWorkflowUploadFile(file, widget.uploadSources)) {
      await _rejectDisallowed(file);
      return;
    }
    if (!mounted) return;
    setState(() {
      row.file = file;
    });
  }

  Future<void> _setRowVideo(
    _UserChecklistRow row,
    _SelectedUploadFile? file,
  ) async {
    if (file != null &&
        !_isAllowedWorkflowUploadFile(file, widget.uploadSources)) {
      await _rejectDisallowed(file);
      return;
    }
    if (!mounted) return;
    setState(() {
      row.videoFile = file;
    });
  }

  Future<void> _setRowDocument(
    _UserChecklistRow row,
    _SelectedUploadFile? file,
  ) async {
    if (file != null &&
        !_isAllowedWorkflowUploadFile(file, widget.uploadSources)) {
      await _rejectDisallowed(file);
      return;
    }
    if (!mounted) return;
    setState(() {
      row.docFile = file;
    });
  }

  Future<void> _pickGallery(_UserChecklistRow row) async {
    final picked = await _pickWorkflowGalleryFile(
      allowedFormats: widget.uploadSources.imageFormats,
    );
    if (picked == null) return;
    await _setRowImage(row, picked);
  }

  Future<void> _pickCamera(_UserChecklistRow row) async {
    final picked = await _pickWorkflowCameraFile();
    if (picked == null) return;
    await _setRowImage(row, picked);
  }

  Future<void> _pickDocument(_UserChecklistRow row) async {
    final picked = await _pickWorkflowDocumentFile(
      documentFormats: widget.uploadSources.documentFormats,
    );
    if (picked == null) return;
    await _setRowDocument(row, picked);
  }

  Future<void> _pickVideo(_UserChecklistRow row) async {
    final picked = await _recordWorkflowVideoFile(
      context: context,
      videoFormats: widget.uploadSources.videoFormats,
      maxDurationSeconds: widget.maxVideoDurationSeconds,
      maxSizeMb: widget.maxVideoSizeMb,
    );
    if (picked == null) return;
    await _setRowVideo(row, picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final validRows = _rows
        .where((row) => row.labelController.text.trim().isNotEmpty)
        .toList();
    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please add at least one checklist item.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final submitted = await widget.onSubmit(validRows);
    if (!mounted) return;

    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._rows.map(
          (row) => _UserChecklistRowWidget(
            row: row,
            allowComment: widget.allowComment,
            uploadSources: widget.uploadSources,
            onChanged: () => setState(() {}),
            onPickGallery: () => _pickGallery(row),
            onPickCamera: () => _pickCamera(row),
            onPickDocument: () => _pickDocument(row),
            onPickVideo: () => _pickVideo(row),
            onClearImage: () => setState(() => row.file = null),
            onClearVideo: () => setState(() => row.videoFile = null),
            onClearDocument: () => setState(() => row.docFile = null),
            onRemove: _rows.length == 1
                ? null
                : () {
                    setState(() {
                      _rows.remove(row);
                      row.dispose();
                    });
                  },
          ),
        ),
        TextButton.icon(
          onPressed: _isSubmitting
              ? null
              : () {
                  setState(() {
                    _rows.add(_UserChecklistRow());
                  });
                },
          icon: Icon(Icons.add),
          label: Text('Add item'),
        ),
        SizedBox(height: 16),
        _SheetSubmitButton(
          label: widget.submitLabel,
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _UserChecklistRowWidget extends StatelessWidget {
  final _UserChecklistRow row;
  final bool allowComment;
  final _WorkflowUploadSourceConfig uploadSources;
  final VoidCallback onChanged;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickDocument;
  final VoidCallback onPickVideo;
  final VoidCallback onClearImage;
  final VoidCallback onClearVideo;
  final VoidCallback onClearDocument;
  final VoidCallback? onRemove;

  const _UserChecklistRowWidget({
    required this.row,
    required this.allowComment,
    required this.uploadSources,
    required this.onChanged,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickDocument,
    required this.onPickVideo,
    required this.onClearImage,
    required this.onClearVideo,
    required this.onClearDocument,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final showMedia = uploadSources.hasAnySource;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimary(context).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: row.checked,
                onChanged: (value) {
                  row.checked = value == true;
                  onChanged();
                },
              ),
              Expanded(
                child: TextField(
                  controller: row.labelController,
                  onChanged: (_) => onChanged(),
                  style: TextStyle(color: AppTheme.getTextPrimary(context)),
                  decoration: _sheetInputDecoration(context, 'Item name'),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                ),
            ],
          ),
          if (allowComment) ...[
            SizedBox(height: 10),
            _SheetTextField(
              controller: row.commentController,
              label: 'Comment',
              maxLines: 2,
            ),
          ],
          if (showMedia) ...[
            SizedBox(height: 10),
            _WorkflowUploadSourceButtons(
              sources: uploadSources,
              onPickGallery: onPickGallery,
              onPickCamera: onPickCamera,
              onPickDocument: onPickDocument,
              onPickVideo: onPickVideo,
            ),
            if (row.file != null) ...[
              SizedBox(height: 10),
              _SelectedUploadPreview(
                file: row.file!,
                onRemove: onClearImage,
              ),
            ],
            if (row.videoFile != null) ...[
              SizedBox(height: 10),
              _SelectedUploadPreview(
                file: row.videoFile!,
                onRemove: onClearVideo,
              ),
            ],
            if (row.docFile != null) ...[
              SizedBox(height: 10),
              _SelectedUploadPreview(
                file: row.docFile!,
                onRemove: onClearDocument,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final Color color;
  final String? displayLabel;

  const _StatusPill({
    required this.status,
    required this.color,
    this.displayLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6),
          Text(
            _formatStatusLabel(displayLabel ?? status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatStatusLabel(String value) {
    final words = value.replaceAll('_', ' ').split(' ');
    return words
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _premiumSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: _premiumMuted),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _premiumMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: _premiumInk,
                    fontSize: 13,
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

class _EmptyTasksState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _EmptyTasksState({
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 86,
              width: 86,
              decoration: BoxDecoration(
                color: AppTheme.getPrimaryColor(context).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: AppTheme.getPrimaryColor(context),
                size: 42,
              ),
            ),
            SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _sheetInputDecoration(BuildContext context, String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
    filled: true,
    fillColor: AppTheme.getBackgroundPrimary(context),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppTheme.getPrimaryColor(context).withOpacity(0.18),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppTheme.getPrimaryColor(context)),
    ),
  );
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return <String>[];
}

int _uploadCurrentPercent(Map<String, dynamic>? response) {
  if (response == null) return 0;
  final raw = response['current_percent'];
  final parsed = _intValue(raw) ?? int.tryParse(raw?.toString() ?? '');
  return (parsed ?? 0).clamp(0, 100);
}

int _uploadMinNextPercent(
  Map<String, dynamic> action,
  int currentPercent,
) {
  final configured = _intValue(action['min_next_percent']);
  if (configured != null && configured > currentPercent) {
    return configured.clamp(1, 100);
  }
  return (currentPercent + 1).clamp(1, 100);
}

class _UploadProgressSnapshot {
  final int currentPercent;
  final int minNextPercent;
  final List<Map<String, dynamic>> progressEntries;

  const _UploadProgressSnapshot({
    required this.currentPercent,
    required this.minNextPercent,
    required this.progressEntries,
  });
}

_UploadProgressSnapshot _uploadProgressSnapshot(
  Map<String, dynamic> action,
  Map<String, dynamic> responseFallback,
) {
  final currentPercent = action.containsKey('current_percent')
      ? _uploadCurrentPercent(action)
      : _uploadCurrentPercent(responseFallback);
  final progressEntries = action['progress_entries'] != null
      ? _uploadProgressEntries(action)
      : _uploadProgressEntries(responseFallback);
  return _UploadProgressSnapshot(
    currentPercent: currentPercent,
    minNextPercent: _uploadMinNextPercent(action, currentPercent),
    progressEntries: progressEntries,
  );
}

List<Map<String, dynamic>> _uploadProgressEntries(
  Map<String, dynamic>? response,
) {
  return _mapListFlexible(response?['progress_entries']);
}

String _uploadProgressEntryFileName(Map<String, dynamic> entry) {
  final files = _mapListFlexible(entry['files']);
  if (files.isEmpty) {
    return _displayFileName(
      _firstString(entry, ['text', 'filename', 'name', 'original_filename']),
    );
  }
  final file = files.first;
  return _displayFileName(
    _firstString(file, [
      'original_filename',
      'filename',
      'file_name',
      'name',
    ]),
  );
}

String _formatUploadProgressDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Uploaded';
  try {
    return DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(trimmed));
  } catch (_) {
    // Already a human-readable date from the API.
    return trimmed;
  }
}

List<Map<String, dynamic>> _workflowTextListStandardLines(
  Map<String, dynamic> action,
) {
  final lines = _mapListFlexible(action['lines'])
      .map((line) => Map<String, dynamic>.from(line))
      .where((line) => line['user_added'] != true)
      .toList();
  lines.sort((a, b) {
    final aOrder = _intValue(a['sort_order']) ?? 0;
    final bOrder = _intValue(b['sort_order']) ?? 0;
    return aOrder.compareTo(bOrder);
  });
  return lines;
}

bool _workflowTextListIndentEnabled(Map<String, dynamic> action) {
  return action['indent_enabled'] == true ||
      action['creates_indent'] == true ||
      action['enable_indent_creation'] == true ||
      action['enable_qs_indent_creation'] == true;
}

String _textListLineLabel(Map<String, dynamic> line) {
  return _firstString(line, ['text', 'material', 'name', 'title', 'display']) ??
      'Item';
}

String _textListLineDisplay(
  Map<String, dynamic> line, {
  required bool indentEnabled,
}) {
  final display = _firstString(line, ['display']);
  if (display != null && display.isNotEmpty) return display;

  final name = _textListLineLabel(line);
  final quantity = _firstString(line, ['quantity']);
  final unit = _firstString(line, ['unit']) ?? '';
  if (indentEnabled &&
      quantity != null &&
      quantity.isNotEmpty &&
      quantity != '0') {
    final qtyText = unit.isEmpty ? quantity : '$quantity $unit';
    return '$name — $qtyText';
  }
  return name;
}

String _textListIndentQueueLabel(String indentTarget) {
  switch (indentTarget) {
    case 'qs':
      return 'Indent for QS';
    case 'purchase':
      return 'Indent for purchase';
    default:
      return 'Indents created';
  }
}

String? _textListIndentPath(String? template, {required String indentId}) {
  if (indentId.isEmpty) return null;
  final trimmed = template?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed.replaceAll('{indent_id}', indentId);
}

List<_KypMaterialShiftItem> _kypMaterialShiftItems(
  Map<String, dynamic> action,
) {
  var materials = _mapListFlexible(action['standard_materials']);
  if (materials.isEmpty) {
    materials = _mapListFlexible(action['materials']);
  }

  return materials.map((line) {
    final material =
        _firstString(line, ['material', 'text', 'name', 'title']) ?? 'Material';
    final unit = _firstString(line, ['unit']) ?? '';
    final standardQty = _parseKypQty(
          line['standard_qty'] ?? line['quantity'] ?? line['standard'],
        ) ??
        0;
    final draftShiftQty = _parseKypQty(line['shift_qty']) ?? 0;
    final display = _firstString(line, ['display']) ??
        '$material - ${_formatKypQty(standardQty)} $unit'.trim();
    final source = _firstString(line, ['source']) ?? 'standard';

    return _KypMaterialShiftItem(
      material: material,
      standardQty: standardQty,
      unit: unit,
      display: display,
      source: source,
      draftShiftQty: draftShiftQty,
    );
  }).toList();
}

double? _parseKypQty(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') return null;
  return double.tryParse(text);
}

String _formatKypQty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

Object _jsonQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt();
  return value;
}

String? _projectDisplayName(Map<String, dynamic>? project) {
  if (project == null) return null;
  return _firstString(project, [
    'project_name',
    'name',
    'client_name',
    'title',
  ]);
}

List<String> _responseLines(dynamic value) {
  if (value is List) {
    return value
        .map((item) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            return _firstString(map, [
              'text',
              'line',
              'label',
              'value',
              'answer',
              'comment',
            ]);
          }
          return item?.toString().trim();
        })
        .whereType<String>()
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return <String>[];
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<Map<String, dynamic>> _mapListFlexible(dynamic value) {
  dynamic normalized = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      normalized = jsonDecode(value);
    } catch (_) {
      normalized = value;
    }
  }
  return _mapList(normalized);
}

dynamic _decodeResponsePayload(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
  return value;
}

List<_PriorResponseGroup> _priorResponseTaskGroups(Map<String, dynamic> map) {
  final groups = <_PriorResponseGroup>[];
  final tasks = _mapList(map['tasks']);

  for (var index = 0; index < tasks.length; index++) {
    final task = tasks[index];
    final entries = _sortResponseEntriesByTimestamp(
      _mapList(task['entries'])
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
    );
    if (entries.isEmpty) continue;

    final title = _firstString(task, [
          'source_task_name',
          'task_name',
          'name',
          'title',
        ]) ??
        'Source task ${index + 1}';

    final entriesWithSource = entries.map((entry) {
      if (_firstString(entry, ['source_task_name']) == null) {
        entry['source_task_name'] = title;
      }
      return entry;
    }).toList();

    groups.add(_PriorResponseGroup(title: title, entries: entriesWithSource));
  }

  return groups;
}

DateTime? _parseResponseTimestamp(Map<String, dynamic> entry) {
  for (final key in const ['completed_at', 'updated_at', 'created_at']) {
    final value = entry[key]?.toString().trim();
    if (value == null || value.isEmpty || value == 'null') continue;

    final normalized = value.contains(' ') && !value.contains('T')
        ? value.replaceFirst(' ', 'T')
        : value;
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;
  }
  return null;
}

List<Map<String, dynamic>> _sortResponseEntriesByTimestamp(
  List<Map<String, dynamic>> entries,
) {
  final sorted =
      entries.map((entry) => Map<String, dynamic>.from(entry)).toList();
  sorted.sort((a, b) {
    final aTime = _parseResponseTimestamp(a);
    final bTime = _parseResponseTimestamp(b);
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  });
  return sorted;
}

List<Map<String, dynamic>> _priorResponseEntriesFromMap(
  Map<String, dynamic> map,
) {
  final entries = _mapList(map['entries']);
  if (entries.isNotEmpty) {
    return _sortResponseEntriesByTimestamp(entries);
  }

  // Legacy fallback for older backends that only populated completions.
  final completions = _mapList(map['completions']);
  if (completions.isNotEmpty) {
    return _sortResponseEntriesByTimestamp(completions);
  }

  return entries;
}

int _entryStartIndex(List<_PriorResponseGroup> groups, int groupIndex) {
  var count = 0;
  for (var index = 0; index < groupIndex; index++) {
    count += groups[index].entries.length;
  }
  return count;
}

Map<String, dynamic>? _configMap(dynamic value) {
  dynamic normalized = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      normalized = jsonDecode(value);
    } catch (_) {
      normalized = value;
    }
  }
  if (normalized is Map) return Map<String, dynamic>.from(normalized);
  return null;
}

bool _isBlankConfigValue(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty || value.trim() == 'null';
  if (value is List || value is Map) return value.isEmpty;
  return false;
}

String _itemId(Map<String, dynamic> item) {
  return (item['id'] ?? item['label'] ?? DateTime.now().microsecondsSinceEpoch)
      .toString();
}

String _followupItemId(Map<String, dynamic> item) {
  return (item['id'] ?? item['item_id'] ?? item['label'] ?? 'item_1')
      .toString();
}

List<Map<String, dynamic>> _followupItemFiles(Map<String, dynamic> item) {
  final files = <Map<String, dynamic>>[];

  for (final key in const [
    'image',
    'file',
    'files',
    'attachments',
    'uploaded_file',
    'uploaded_files',
  ]) {
    _collectChecklistAttachment(item[key], files);
  }

  final seen = <String>{};
  return files.where((file) {
    final key = (_firstString(file, ['url', 'file_url', 'path', 'name']) ??
            file.toString())
        .toLowerCase();
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

void _collectChecklistAttachment(
  dynamic value,
  List<Map<String, dynamic>> files,
) {
  if (value == null) return;

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'null') return;
    files.add(_normalizedChecklistAttachment(url: trimmed));
    return;
  }

  if (value is List) {
    for (final item in value) {
      _collectChecklistAttachment(item, files);
    }
    return;
  }

  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final url = _firstString(map, [
      'url',
      'file_url',
      'file_path',
      'path',
      'image_url',
      'photo_url',
      'attachment_url',
    ]);
    final name = _firstString(map, [
      'filename',
      'original_name',
      'file_name',
      'name',
      'document_name',
      'label',
    ]);

    if (url != null || name != null) {
      files.add(_normalizedChecklistAttachment(
        url: url,
        name: name,
      ));
    }
  }
}

Map<String, dynamic> _normalizedChecklistAttachment({
  String? url,
  String? name,
}) {
  final resolvedName = name?.trim().isNotEmpty == true
      ? name!.trim()
      : url == null
          ? 'Uploaded file'
          : url.split('/').last;
  final lower = '${url ?? ''} $resolvedName'.toLowerCase().split('?').first;
  final type = lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif')
      ? 'image'
      : lower.endsWith('.pdf')
          ? 'pdf'
          : 'file';

  final normalized = {
    'name': resolvedName,
    'filename': resolvedName,
    'type': type,
    'content_type': type == 'image'
        ? 'Image'
        : type == 'pdf'
            ? 'PDF'
            : 'File',
  };
  if (url != null && url.trim().isNotEmpty) {
    normalized['url'] = _absoluteWorkflowUrl(url);
  }
  return normalized;
}

bool _hasChecklistValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  return true;
}

int? _intValue(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

List<_SlotTimeOption> _slotTimeOptions(dynamic value) {
  dynamic normalized = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      normalized = jsonDecode(value);
    } catch (_) {
      normalized = value;
    }
  }
  if (normalized is! List) return <_SlotTimeOption>[];
  return normalized
      .whereType<Map>()
      .map((item) {
        final map = Map<String, dynamic>.from(item);
        final label = map['label']?.toString().trim() ?? '';
        final time = map['time']?.toString().trim() ?? '';
        if (label.isEmpty || time.isEmpty) return null;
        return _SlotTimeOption(label: label, time: time);
      })
      .whereType<_SlotTimeOption>()
      .toList();
}

bool _truthyValue(dynamic value) {
  if (value == true) return true;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

bool _falseyValue(dynamic value) {
  if (value == false) return true;
  if (value is num) return value == 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'false' || normalized == '0' || normalized == 'no';
  }
  return false;
}

String _slotHelperText({
  required String heading,
  required int? minNoticeHours,
}) {
  final parts = <String>[];
  if (heading.isNotEmpty) parts.add(heading);
  if (minNoticeHours != null) {
    parts.add('Select slots at least $minNoticeHours hours from now.');
  }
  return parts.join(' ');
}

DateTime _combineSlotDateAndTime(DateTime date, String time) {
  final parts = time.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

String _formatSlotDate(DateTime value) {
  return DateFormat('yyyy-MM-dd').format(value);
}

String _formatSlotDateTimeValue(DateTime value) {
  return DateFormat("yyyy-MM-dd'T'HH:mm").format(value);
}

String _formatDisplayDate(DateTime value) {
  return DateFormat('dd-MMM-yyyy').format(value);
}

String _formatDisplayDateTime(DateTime value) {
  return DateFormat('dd-MMM-yyyy hh:mm a').format(value);
}

String _slotOptionDisplay(_SlotTimeOption option) {
  return '${option.label} - ${_formatSlotTime(option.time)}';
}

int _slotIndex(Map<String, dynamic> slot, int fallbackIndex) {
  return _intValue(slot['index']) ?? fallbackIndex + 1;
}

Map<String, dynamic>? _slotByIndex(
  List<Map<String, dynamic>> slots,
  int acceptedSlotIndex,
) {
  for (var fallbackIndex = 0; fallbackIndex < slots.length; fallbackIndex++) {
    final slot = slots[fallbackIndex];
    if (_slotIndex(slot, fallbackIndex) == acceptedSlotIndex) {
      return slot;
    }
  }
  return null;
}

String _slotDisplay(Map<String, dynamic> slot) {
  return _firstString(slot, ['display', 'datetime', 'value']) ?? 'Slot';
}

String _slotTimeDetail(Map<String, dynamic> slot) {
  final timeLabel = _firstString(slot, ['time_label']);
  final time = _firstString(slot, ['time']);
  if (timeLabel != null && time != null)
    return '$timeLabel • ${_formatSlotTime(time)}';
  if (timeLabel != null) return timeLabel;
  if (time != null) return _formatSlotTime(time);
  return '';
}

String _formatSlotTime(String time) {
  final parts = time.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  if (hour == null || minute == null) return time;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
}

String _readableValue(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  const encoder = JsonEncoder.withIndent('  ');
  try {
    return encoder.convert(value);
  } catch (_) {
    return value.toString();
  }
}

const Set<String> _responseHiddenKeys = {
  'entries',
  'completions',
  'files',
  'url',
  'file_url',
  'path',
  'filename',
  'file_name',
  'name',
  'content_type',
  'mime_type',
  'task_name',
  'document_name',
  'label',
  'heading',
  'comment',
  'note',
  'remarks',
  'qa_items',
  'lines',
  'responses',
  'tasks',
  'source_task_name',
  'source_erp_category',
  'source_erp_categories',
  'source_categories',
  'source_type',
  'sourceType',
  'multi_source',
  'multiSource',
  'workflow_run_id',
  'workflowRunId',
  'workflow_item_run_id',
  'workflowItemRunId',
  'run_id',
  'item_run_id',
  'itemRunId',
  'prior_item_run_id',
  'priorItemRunId',
  'prior_run_id',
  'priorRunId',
  'prior_workflow_item_run_id',
  'priorWorkflowItemRunId',
  'source_node_key',
  'sourceNodeKey',
  'node_key',
  'nodeKey',
  'source_item_run_id',
  'sourceItemRunId',
  'source_workflow_item_run_id',
  'sourceWorkflowItemRunId',
  'source_node_keys',
  'sourceNodeKeys',
  'scoped_to_current_spawn',
  'scopedToCurrentSpawn',
  'current_spawn',
  'currentSpawn',
  'project_id',
  'projectId',
  'category',
  'erp_category',
  'erp_categories',
  'field_type',
  'type',
  'action_id',
  'actionId',
  'id',
  'created_at',
  'updated_at',
  'completed_at',
  'createdAt',
  'updatedAt',
  'completedAt',
  'response_mode',
  'responseMode',
};

bool _isEmptyResponse(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is List || value is Map) return value.isEmpty;
  return false;
}

String? _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return null;
}

String _responseLabel(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

String _responseDisplayValue(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return value.toString();
  if (value is List) {
    final items = value
        .map((item) => _responseDisplayValue(item))
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (items.isEmpty) return '';
    return items.map((item) => '- $item').join('\n');
  }
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final directText = _firstString(map, [
      'text',
      'line',
      'label',
      'value',
      'answer',
      'comment',
      'name',
      'title',
    ]);
    if (directText != null) return directText;
    return map.entries
        .where((entry) => !_responseHiddenKeys.contains(entry.key))
        .where((entry) => !_isEmptyResponse(entry.value))
        .map((entry) {
          final displayValue = _responseDisplayValue(entry.value);
          if (displayValue.trim().isEmpty) return '';
          return '${_responseLabel(entry.key.toString())}: $displayValue';
        })
        .where((item) => item.trim().isNotEmpty)
        .join('\n');
  }
  return value.toString();
}

String _absoluteWorkflowUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) return '$_workflowApiBaseUrl$trimmed';
  return '$_workflowApiBaseUrl/$trimmed';
}

String? _workflowAttachmentUrl(Map<String, dynamic> file) {
  return _firstString(file, [
    'url',
    'file_url',
    'file_path',
    'path',
  ]);
}

Future<void> _openExternalUrl(String value, {LaunchMode? mode}) async {
  final uri = Uri.tryParse(_absoluteWorkflowUrl(value));
  if (uri == null) return;
  await launchUrl(uri, mode: mode ?? LaunchMode.externalApplication);
}

bool _isImageAttachment(String url, {String? contentType}) {
  final mime = contentType?.trim().toLowerCase() ?? '';
  if (mime.startsWith('image/')) return true;
  return _looksLikeImage(url);
}

bool _isVideoAttachment(
  String url, {
  String? contentType,
  String? name,
}) {
  final mime = contentType?.trim().toLowerCase() ?? '';
  if (mime.startsWith('video/')) return true;
  return _looksLikeVideo(name ?? url);
}

bool _isPdfAttachment(
  String url, {
  String? contentType,
  String? name,
}) {
  final mime = contentType?.trim().toLowerCase() ?? '';
  if (mime == 'application/pdf') return true;
  return _looksLikePdf(name ?? url);
}

List<String> _imageAttachmentUrls(List<Map<String, dynamic>> files) {
  final urls = <String>[];
  final seen = <String>{};
  for (final file in files) {
    final url = _workflowAttachmentUrl(file);
    if (url == null) continue;
    final contentType = _firstString(file, ['content_type', 'mime_type']);
    if (!_isImageAttachment(url, contentType: contentType)) continue;
    final resolved = _absoluteWorkflowUrl(url);
    final key = _normalizePhotoDedupeKey(resolved);
    if (seen.add(key)) urls.add(resolved);
  }
  return urls;
}

Future<void> _openWorkflowAttachment(
  BuildContext context,
  Map<String, dynamic> file, {
  List<Map<String, dynamic>>? relatedFiles,
}) async {
  final url = _workflowAttachmentUrl(file);
  if (url == null) return;

  final absoluteUrl = _absoluteWorkflowUrl(url);
  final contentType = _firstString(file, ['content_type', 'mime_type']);
  final name = _firstString(file, ['filename', 'file_name', 'name']) ?? '';

  if (_isImageAttachment(url, contentType: contentType)) {
    var imageUrls = _imageAttachmentUrls(relatedFiles ?? [file]);
    if (imageUrls.isEmpty) {
      imageUrls = [absoluteUrl];
    }

    var initialIndex = imageUrls.indexWhere(
      (item) => _normalizePhotoDedupeKey(item) == _normalizePhotoDedupeKey(absoluteUrl),
    );
    if (initialIndex < 0) initialIndex = 0;

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImage(
          imageUrls[initialIndex],
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
    return;
  }

  if (_isPdfAttachment(url, contentType: contentType, name: name) ||
      _isVideoAttachment(url, contentType: contentType, name: name)) {
    await _openExternalUrl(url, mode: LaunchMode.inAppWebView);
    return;
  }

  await _openExternalUrl(url);
}

List<String> _taskUploadedPhotoUrls(Map<String, dynamic> task) {
  final photos = <String>[];

  for (final key in const [
    'uploads',
    'uploaded_files',
    'uploaded_file',
    'attachments',
    'files',
    'images',
    'photos',
  ]) {
    _collectUploadedPhotosFromAttachments(task[key], photos);
  }

  for (final key in const [
    'workflow_action_responses',
    'workflow_prior_responses',
  ]) {
    _collectUploadedPhotosFromResponses(task[key], photos);
  }

  final actions = [
    ..._mapListFlexible(task['workflow_task_actions']),
    ..._mapListFlexible(task['workflow_actions']),
  ];
  for (final action in actions) {
    _collectUploadedPhotosFromResponses(action['response'], photos);
    _collectUploadedPhotosFromResponses(action['prior_response'], photos);
    _collectUploadedPhotosFromResponses(action['prior_responses'], photos);
    _collectUploadedPhotosFromResponses(
      action['workflow_prior_responses'],
      photos,
    );
  }

  return _dedupePhotoUrls(photos);
}

void _collectUploadedPhotosFromAttachments(
  dynamic value,
  List<String> photos,
) {
  final files = <Map<String, dynamic>>[];
  _collectChecklistAttachment(value, files);
  for (final file in files) {
    final url = _firstString(file, [
      'url',
      'file_url',
      'file_path',
      'path',
      'image_url',
      'photo_url',
      'attachment_url',
    ]);
    if (url != null && _isValidUploadedPhotoUrl(url)) {
      photos.add(url);
    }
  }
}

void _collectUploadedPhotosFromResponses(
  dynamic value,
  List<String> photos,
) {
  final decoded = _decodeResponsePayload(value);
  if (decoded == null) return;

  if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    for (final key in const [
      'files',
      'attachments',
      'uploaded_files',
      'uploaded_file',
      'uploads',
      'images',
      'photos',
    ]) {
      _collectUploadedPhotosFromAttachments(map[key], photos);
    }

    for (final entry in _mapListFlexible(map['entries'])) {
      _collectUploadedPhotosFromResponses(entry, photos);
    }
    for (final entry in _mapListFlexible(map['responses'])) {
      _collectUploadedPhotosFromResponses(entry, photos);
    }
    for (final entry in _mapListFlexible(map['tasks'])) {
      _collectUploadedPhotosFromResponses(entry, photos);
    }
    for (final entry in _mapListFlexible(map['options'])) {
      final imageUrl = _pictureChoiceOptionImageUrl(entry);
      if (imageUrl != null && _isValidUploadedPhotoUrl(imageUrl)) {
        photos.add(imageUrl);
      }
    }
    final selectedOption = _configMap(map['selected_option']);
    if (selectedOption != null) {
      final imageUrl = _pictureChoiceOptionImageUrl(selectedOption);
      if (imageUrl != null && _isValidUploadedPhotoUrl(imageUrl)) {
        photos.add(imageUrl);
      }
    }

    final hasKnownStructure = map.containsKey('files') ||
        map.containsKey('entries') ||
        map.containsKey('responses') ||
        map.containsKey('tasks');
    if (!hasKnownStructure) {
      for (final entry in map.values) {
        _collectUploadedPhotosFromResponses(entry, photos);
      }
    }
    return;
  }

  if (decoded is List) {
    for (final item in decoded) {
      _collectUploadedPhotosFromResponses(item, photos);
    }
  }
}

bool _isValidUploadedPhotoUrl(String value) {
  if (!_looksLikeImage(value)) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'null') return false;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return true;
  }
  if (trimmed.startsWith('/')) return true;
  return trimmed.contains('/') || trimmed.contains('\\');
}

List<String> _dedupePhotoUrls(List<String> photos) {
  final seen = <String>{};
  final result = <String>[];
  for (final photo in photos) {
    final key = _normalizePhotoDedupeKey(photo);
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(photo);
  }
  return result;
}

String _normalizePhotoDedupeKey(String url) {
  var trimmed = url.trim();
  if (trimmed.startsWith('/')) {
    trimmed = '$_workflowApiBaseUrl$trimmed';
  }
  return trimmed.split('?').first.toLowerCase();
}

bool _looksLikeImage(String value) {
  if (value.isEmpty) return false;
  final lower = value.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.gif');
}

bool _looksLikeVideo(String value) {
  if (value.isEmpty) return false;
  final lower = value.toLowerCase().split('?').first;
  return _workflowVideoFormats.any((ext) => lower.endsWith('.$ext'));
}

bool _looksLikePdf(String value) {
  if (value.isEmpty) return false;
  final lower = value.toLowerCase().split('?').first;
  return lower.endsWith('.pdf');
}

String _generatePictureChoiceOptionId() {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final random = stamp.toRadixString(36);
  return 'pcho_$random';
}

List<_PictureChoiceListRowState> _pictureChoiceListInitialRows(
  List<Map<String, dynamic>> presetOptions,
) {
  if (presetOptions.isEmpty) {
    return [_PictureChoiceListRowState(id: _generatePictureChoiceOptionId())];
  }

  final sorted = List<Map<String, dynamic>>.from(presetOptions);
  sorted.sort((a, b) {
    final aOrder = _intValue(a['sort_order']) ?? 0;
    final bOrder = _intValue(b['sort_order']) ?? 0;
    return aOrder.compareTo(bOrder);
  });

  return sorted
      .map(
        (preset) => _PictureChoiceListRowState(
          id: preset['id']?.toString().trim().isNotEmpty == true
              ? preset['id'].toString().trim()
              : _generatePictureChoiceOptionId(),
          name: preset['name']?.toString() ?? '',
        ),
      )
      .toList();
}

String? _pictureChoiceOptionImageUrl(Map<String, dynamic> option) {
  final image = _configMap(option['image']);
  if (image == null) return null;
  return _firstString(image, [
    'url',
    'file_url',
    'file_path',
    'path',
    'image_url',
    'photo_url',
  ]);
}

String _pictureChoiceMimeType(String path) {
  final lower = path.toLowerCase().split('?').first;
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

Future<http.Response> _postWorkflowMultipart({
  required Uri uri,
  required Map<String, String> fields,
  required List<MapEntry<String, String>> repeatedFields,
  required List<_PictureChoiceFileField> fileFields,
  Map<String, String>? headers,
}) async {
  final boundary =
      '----buildahome-${DateTime.now().microsecondsSinceEpoch}';
  final body = BytesBuilder();

  void writeLine(String line) {
    body.add(utf8.encode('$line\r\n'));
  }

  void writeField(String name, String value) {
    writeLine('--$boundary');
    writeLine('Content-Disposition: form-data; name="$name"');
    writeLine('');
    writeLine(value);
  }

  fields.forEach((key, value) => writeField(key, value));
  for (final entry in repeatedFields) {
    writeField(entry.key, entry.value);
  }

  for (final fileField in fileFields) {
    final bytes = await File(fileField.path).readAsBytes();
    writeLine('--$boundary');
    writeLine(
      'Content-Disposition: form-data; name="${fileField.field}"; '
      'filename="${fileField.filename}"',
    );
    writeLine('Content-Type: ${_pictureChoiceMimeType(fileField.path)}');
    writeLine('');
    body.add(bytes);
    writeLine('');
  }

  writeLine('--$boundary--');

  return ApiHttp.post(
        uri,
        headers: {
          'Content-Type': 'multipart/form-data; boundary=$boundary',
          ...?headers,
        },
        body: body.toBytes(),
      )
      .timeout(const Duration(seconds: 60));
}
