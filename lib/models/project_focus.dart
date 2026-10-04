/// Typed models for `GET /api/projects/{sales_sop_id}/focus`.
/// Backend is the source of truth — these only parse the payload.

class ProjectFocus {
  final int? salesSopId;
  final int? workflowId;
  final int? workflowRunId;
  final String? clientName;
  final CurrentPhase? currentPhase;
  final List<CurrentPhase> phases;
  final ProjectActivity? projectActivity;
  final ProjectBlocker? projectBlocker;
  final List<ActiveWorkItem> activeWork;
  final List<ActiveFlowBranch> activeFlow;
  final MyNextInvolvement? myNextInvolvement;
  final List<WorkflowAttentionItem> workflowAttention;
  final List<MyNextAction> myNextActions;
  final List<NextWorkflowTask> next;

  const ProjectFocus({
    this.salesSopId,
    this.workflowId,
    this.workflowRunId,
    this.clientName,
    this.currentPhase,
    this.phases = const [],
    this.projectActivity,
    this.projectBlocker,
    this.activeWork = const [],
    this.activeFlow = const [],
    this.myNextInvolvement,
    this.workflowAttention = const [],
    this.myNextActions = const [],
    this.next = const [],
  });

  factory ProjectFocus.fromJson(Map<String, dynamic> json) {
    final root = _unwrapPayload(json);

    return ProjectFocus(
      salesSopId: _asInt(root['sales_sop_id'] ?? root['salesSopId']),
      workflowId: _asInt(root['workflow_id'] ?? root['workflowId']),
      workflowRunId: _asInt(root['workflow_run_id'] ?? root['workflowRunId']),
      clientName: _asString(root['client_name'] ?? root['clientName']),
      currentPhase: CurrentPhase.tryParse(
        root['current_phase'] ?? root['currentPhase'] ?? root['phase'],
      ),
      phases: _parsePhases(root),
      projectActivity: ProjectActivity.tryParse(
        root['project_activity'] ?? root['projectActivity'],
      ),
      projectBlocker: ProjectBlocker.tryParse(
        root['project_blocker'] ?? root['projectBlocker'],
      ),
      activeWork: _parseActiveWork(
        root['active_work'] ?? root['activeWork'],
      ),
      activeFlow: _parseActiveFlow(
        root['active_flow'] ?? root['activeFlow'],
      ),
      myNextInvolvement: MyNextInvolvement.tryParse(
        root['my_next_involvement'] ?? root['myNextInvolvement'],
      ),
      workflowAttention: _parseWorkflowAttention(
        root['workflow_attention'] ?? root['workflowAttention'],
      ),
      myNextActions: _parseNextActions(
        root['my_next_actions'] ?? root['myNextActions'],
      ),
      next: _parseNextTasks(root['next']),
    );
  }

  bool get hasBlocker => projectBlocker != null;

  bool get hasActiveWork => activeWork.isNotEmpty;

  bool get hasWorkflowAttention => workflowAttention.isNotEmpty;

  bool get hasMyActions => myNextActions.isNotEmpty;

  ProjectActivityState get resolvedActivityState {
    final fromApi = projectActivity?.state;
    if (fromApi != null && fromApi != ProjectActivityState.unknown) {
      return fromApi;
    }
    if (hasWorkflowAttention) return ProjectActivityState.workflowAttention;
    if (hasBlocker) return ProjectActivityState.blocked;
    return ProjectActivityState.moving;
  }
}

enum ProjectActivityState {
  moving,
  blocked,
  waiting,
  workflowAttention,
  unknown,
}

class ProjectActivity {
  final ProjectActivityState state;
  final String? label;
  final String? message;

  const ProjectActivity({
    required this.state,
    this.label,
    this.message,
  });

  static ProjectActivity? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final state = _parseActivityState(raw);
      if (state == ProjectActivityState.unknown) return null;
      return ProjectActivity(state: state);
    }
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return ProjectActivity(
      state: _parseActivityState(
        map['state'] ?? map['status'] ?? map['activity'],
      ),
      label: _asString(map['label'] ?? map['title'] ?? map['name']),
      message: _asString(
        map['message'] ?? map['summary'] ?? map['description'] ?? map['reason'],
      ),
    );
  }
}

class CurrentPhase {
  final String key;
  final String label;
  final String state;

  const CurrentPhase({
    required this.key,
    required this.label,
    this.state = '',
  });

  static CurrentPhase? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final key = _asString(map['key']) ?? '';
    final label = _asString(map['label'] ?? map['name'] ?? map['title']) ?? '';
    if (key.isEmpty && label.isEmpty) return null;
    return CurrentPhase(
      key: key.isEmpty ? _slug(label) : key,
      label: label.isEmpty ? _titleFromKey(key) : label,
      state: (_asString(map['state'] ?? map['status']) ?? '').toLowerCase(),
    );
  }

  bool get isCurrent =>
      state == 'current' || state == 'in_progress' || state == 'inprogress';

  bool get isCompleted =>
      state == 'completed' ||
      state == 'done' ||
      state == 'complete' ||
      state == 'finished';

  bool get isUpcoming =>
      state == 'upcoming' || state == 'future' || state == 'pending';
}

class ProjectBlocker {
  final BlockedTask? task;
  final List<WaitingDependency> waitingFor;

  const ProjectBlocker({
    this.task,
    this.waitingFor = const [],
  });

  static ProjectBlocker? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is String &&
        (raw.trim().isEmpty || raw.trim().toLowerCase() == 'null')) {
      return null;
    }
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map.isEmpty) return null;

    final task = BlockedTask.tryParse(map['task']);
    final waiting = _parseWaiting(
      map['waiting_for'] ??
          map['waitingFor'] ??
          map['dependencies'] ??
          map['blockers'],
    );
    if (task == null && waiting.isEmpty) return null;
    return ProjectBlocker(task: task, waitingFor: waiting);
  }

  int get waitingCount => waitingFor.length;
}

class BlockedTask {
  final String name;
  final String? nodeKey;
  final String status;
  final int? workflowItemRunId;

  const BlockedTask({
    required this.name,
    this.nodeKey,
    this.status = '',
    this.workflowItemRunId,
  });

  static BlockedTask? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final name = _asString(
          map['name'] ?? map['task_name'] ?? map['title'] ?? map['label'],
        ) ??
        '';
    if (name.isEmpty) return null;
    return BlockedTask(
      name: name,
      nodeKey: _asString(map['node_key'] ?? map['nodeKey']),
      status: _asString(map['status']) ?? '',
      workflowItemRunId: _asInt(
        map['workflow_item_run_id'] ?? map['workflowItemRunId'],
      ),
    );
  }

  bool get canOpen => workflowItemRunId != null;
}

class WaitingDependency {
  final String name;
  final String? type;
  final String status;
  final String statusLabel;
  final String? waitingWith;
  final String? role;
  final int? workflowItemRunId;
  final String? category;

  const WaitingDependency({
    required this.name,
    this.type,
    this.status = '',
    this.statusLabel = '',
    this.waitingWith,
    this.role,
    this.workflowItemRunId,
    this.category,
  });

  factory WaitingDependency.fromJson(Map<String, dynamic> json) {
    final status = _asString(json['status']) ?? '';
    final label = _asString(json['status_label'] ?? json['statusLabel']);
    return WaitingDependency(
      name: _asString(
            json['name'] ??
                json['task_name'] ??
                json['title'] ??
                json['label'],
          ) ??
          'Untitled task',
      type: _asString(json['type'] ?? json['blocker_type'] ?? json['kind']),
      status: status,
      statusLabel: label ?? _defaultStatusLabel(status),
      waitingWith: _asString(
        json['waiting_with'] ??
            json['waitingWith'] ??
            json['assignee'] ??
            json['assignee_name'] ??
            json['assigned_to_name'] ??
            json['assigned_to'],
      ),
      role: _asString(
        json['role'] ??
            json['assignee_role'] ??
            json['assigned_to_role'] ??
            json['assigned_role'],
      ),
      workflowItemRunId: _asInt(
        json['workflow_item_run_id'] ?? json['workflowItemRunId'],
      ),
      category: _asString(
        json['category'] ??
            json['discipline'] ??
            json['group'] ??
            json['section'],
      ),
    );
  }

  bool get canOpen => workflowItemRunId != null;

  bool get hasPerson => waitingWith != null && waitingWith!.isNotEmpty;

  bool get hasRole => role != null && role!.isNotEmpty;
}

class ActiveWorkItem {
  final String name;
  final String status;
  final String statusLabel;
  final String? assignee;
  final String? role;
  final int? workflowItemRunId;
  final String? category;

  const ActiveWorkItem({
    required this.name,
    this.status = '',
    this.statusLabel = '',
    this.assignee,
    this.role,
    this.workflowItemRunId,
    this.category,
  });

  factory ActiveWorkItem.fromJson(Map<String, dynamic> json) {
    final status = _asString(json['status']) ?? '';
    final label = _asString(json['status_label'] ?? json['statusLabel']);
    return ActiveWorkItem(
      name: _asString(
            json['name'] ??
                json['task_name'] ??
                json['title'] ??
                json['label'],
          ) ??
          'Untitled task',
      status: status,
      statusLabel: label ?? _defaultStatusLabel(status),
      assignee: _asString(
        json['assignee'] ??
            json['assignee_name'] ??
            json['waiting_with'] ??
            json['waitingWith'] ??
            json['assigned_to_name'] ??
            json['assigned_to'],
      ),
      role: _asString(
        json['role'] ??
            json['assignee_role'] ??
            json['assigned_to_role'] ??
            json['assigned_role'],
      ),
      workflowItemRunId: _asInt(
        json['workflow_item_run_id'] ?? json['workflowItemRunId'],
      ),
      category: _asString(json['category'] ?? json['phase_label']),
    );
  }

  bool get canOpen => workflowItemRunId != null;
}

class ActiveFlowItem {
  final String name;
  final String status;
  final String statusLabel;
  final String? assignee;
  final String? role;
  final int? workflowItemRunId;
  final String? branchKey;

  const ActiveFlowItem({
    required this.name,
    this.status = '',
    this.statusLabel = '',
    this.assignee,
    this.role,
    this.workflowItemRunId,
    this.branchKey,
  });

  factory ActiveFlowItem.fromJson(Map<String, dynamic> json) {
    final status = _asString(json['status']) ?? '';
    final label = _asString(json['status_label'] ?? json['statusLabel']);
    return ActiveFlowItem(
      name: _asString(
            json['name'] ??
                json['task_name'] ??
                json['title'] ??
                json['label'],
          ) ??
          'Upcoming task',
      status: status,
      statusLabel: label ?? _defaultStatusLabel(status),
      assignee: _asString(
        json['assignee'] ??
            json['assignee_name'] ??
            json['waiting_with'] ??
            json['waitingWith'] ??
            json['assigned_to_name'],
      ),
      role: _asString(
        json['role'] ??
            json['assignee_role'] ??
            json['assigned_to_role'] ??
            json['assigned_role'],
      ),
      workflowItemRunId: _asInt(
        json['workflow_item_run_id'] ?? json['workflowItemRunId'],
      ),
      branchKey: _asString(
        json['branch_key'] ??
            json['branchKey'] ??
            json['branch_id'] ??
            json['branchId'] ??
            json['path_key'],
      ),
    );
  }
}

class ActiveFlowBranch {
  final String? label;
  final List<ActiveFlowItem> items;

  const ActiveFlowBranch({
    this.label,
    this.items = const [],
  });
}

class MyNextInvolvement {
  final String? name;
  final String status;
  final String statusLabel;
  final int? workflowItemRunId;
  final List<WaitingDependency> waitingFor;
  final String? message;

  const MyNextInvolvement({
    this.name,
    this.status = '',
    this.statusLabel = '',
    this.workflowItemRunId,
    this.waitingFor = const [],
    this.message,
  });

  static MyNextInvolvement? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is String &&
        (raw.trim().isEmpty || raw.trim().toLowerCase() == 'null')) {
      return null;
    }
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map.isEmpty) return null;

    final status = _asString(map['status']) ?? '';
    final label = _asString(map['status_label'] ?? map['statusLabel']);
    final nestedTask = map['task'];
    final nestedTaskName = nestedTask is Map
        ? _asString(nestedTask['name'] ?? nestedTask['task_name'])
        : null;
    final name = _asString(
          map['name'] ??
              map['task_name'] ??
              map['title'] ??
              map['label'] ??
              nestedTaskName,
        );
    final waiting = _parseWaiting(
      map['waiting_for'] ??
          map['waitingFor'] ??
          map['dependencies'] ??
          map['blocked_by'],
    );
    final message = _asString(
      map['message'] ?? map['summary'] ?? map['description'],
    );
    if (name == null && waiting.isEmpty && message == null) return null;

    return MyNextInvolvement(
      name: name,
      status: status,
      statusLabel: label ?? _defaultStatusLabel(status),
      workflowItemRunId: _asInt(
        map['workflow_item_run_id'] ?? map['workflowItemRunId'],
      ),
      waitingFor: waiting,
      message: message,
    );
  }

  bool get canOpen => workflowItemRunId != null;
}

class WorkflowAttentionItem {
  final String name;
  final String? message;
  final int? workflowItemRunId;
  final String? status;

  const WorkflowAttentionItem({
    required this.name,
    this.message,
    this.workflowItemRunId,
    this.status,
  });

  factory WorkflowAttentionItem.fromJson(Map<String, dynamic> json) {
    return WorkflowAttentionItem(
      name: _asString(
            json['name'] ??
                json['task_name'] ??
                json['title'] ??
                json['label'],
          ) ??
          'Workflow attention needed',
      message: _asString(
        json['message'] ??
            json['reason'] ??
            json['description'] ??
            json['summary'] ??
            json['detail'],
      ),
      workflowItemRunId: _asInt(
        json['workflow_item_run_id'] ?? json['workflowItemRunId'],
      ),
      status: _asString(json['status']),
    );
  }

  bool get canOpen => workflowItemRunId != null;
}

class MyNextAction {
  final String name;
  final String status;
  final String statusLabel;
  final int? workflowItemRunId;
  final String? category;
  final List<WaitingDependency> waitingFor;

  const MyNextAction({
    required this.name,
    this.status = '',
    this.statusLabel = '',
    this.workflowItemRunId,
    this.category,
    this.waitingFor = const [],
  });

  factory MyNextAction.fromJson(Map<String, dynamic> json) {
    final status = _asString(json['status']) ?? '';
    final label = _asString(json['status_label'] ?? json['statusLabel']);
    return MyNextAction(
      name: _asString(
            json['name'] ??
                json['task_name'] ??
                json['title'] ??
                json['label'],
          ) ??
          'Untitled task',
      status: status,
      statusLabel: label ?? _defaultStatusLabel(status),
      workflowItemRunId: _asInt(
        json['workflow_item_run_id'] ?? json['workflowItemRunId'],
      ),
      category: _asString(
        json['category'] ??
            json['discipline'] ??
            json['group'] ??
            json['section'],
      ),
      waitingFor: _parseWaiting(
        json['waiting_for'] ??
            json['waitingFor'] ??
            json['blockers'] ??
            json['dependencies'],
      ),
    );
  }

  bool get canOpen => workflowItemRunId != null;
}

class NextWorkflowTask {
  final String name;

  const NextWorkflowTask({required this.name});

  factory NextWorkflowTask.fromJson(Map<String, dynamic> json) {
    return NextWorkflowTask(
      name: _asString(
            json['name'] ??
                json['task_name'] ??
                json['title'] ??
                json['label'],
          ) ??
          'Upcoming task',
    );
  }
}

class ProjectFocusException implements Exception {
  final String message;
  final int? statusCode;

  const ProjectFocusException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

// ── Parsing helpers ──────────────────────────────────────────────────────────

Map<String, dynamic> _unwrapPayload(Map<String, dynamic> json) {
  if (json.containsKey('current_phase') ||
      json.containsKey('currentPhase') ||
      json.containsKey('project_blocker') ||
      json.containsKey('projectBlocker') ||
      json.containsKey('active_work') ||
      json.containsKey('activeWork') ||
      json.containsKey('project_activity') ||
      json.containsKey('projectActivity') ||
      json.containsKey('my_next_actions') ||
      json.containsKey('myNextActions')) {
    return json;
  }
  for (final key in const ['data', 'focus', 'result', 'payload']) {
    final nested = json[key];
    if (nested is Map) return Map<String, dynamic>.from(nested);
  }
  return json;
}

ProjectActivityState _parseActivityState(dynamic raw) {
  final value = (raw?.toString() ?? '').trim().toLowerCase().replaceAll(' ', '_');
  switch (value) {
    case 'moving':
    case 'in_progress':
    case 'progressing':
    case 'active':
      return ProjectActivityState.moving;
    case 'blocked':
    case 'stuck':
      return ProjectActivityState.blocked;
    case 'waiting':
    case 'pending':
      return ProjectActivityState.waiting;
    case 'workflow_attention':
    case 'attention':
    case 'needs_attention':
    case 'attention_needed':
      return ProjectActivityState.workflowAttention;
    default:
      return ProjectActivityState.unknown;
  }
}

List<CurrentPhase> _parsePhases(Map<String, dynamic> root) {
  final raw = root['phases'] ??
      root['phase_list'] ??
      root['phase_roadmap'] ??
      root['roadmap'] ??
      root['phaseRoadmap'];
  if (raw is! List) return const [];
  final out = <CurrentPhase>[];
  for (final row in raw) {
    final phase = CurrentPhase.tryParse(row);
    if (phase != null) out.add(phase);
  }
  return out;
}

List<WaitingDependency> _parseWaiting(dynamic raw) {
  if (raw is Map) {
    return [WaitingDependency.fromJson(Map<String, dynamic>.from(raw))];
  }
  if (raw is! List) return const [];
  final out = <WaitingDependency>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(WaitingDependency.fromJson(Map<String, dynamic>.from(row)));
    } else if (row is String && row.trim().isNotEmpty) {
      out.add(WaitingDependency(name: row.trim()));
    }
  }
  return out;
}

List<ActiveWorkItem> _parseActiveWork(dynamic raw) {
  if (raw is Map) {
    return [ActiveWorkItem.fromJson(Map<String, dynamic>.from(raw))];
  }
  if (raw is! List) return const [];
  final out = <ActiveWorkItem>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(ActiveWorkItem.fromJson(Map<String, dynamic>.from(row)));
    }
  }
  return out;
}

List<ActiveFlowBranch> _parseActiveFlow(dynamic raw) {
  if (raw == null) return const [];

  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    final branchesRaw = map['branches'] ?? map['paths'] ?? map['chains'];
    if (branchesRaw is List) {
      return _parseFlowBranches(branchesRaw);
    }
    final itemsRaw = map['items'] ?? map['steps'] ?? map['tasks'];
    if (itemsRaw is List) {
      final items = _parseFlowItems(itemsRaw);
      if (items.isEmpty) return const [];
      return [ActiveFlowBranch(items: items)];
    }
    // Single item shaped as a map.
    final item = ActiveFlowItem.fromJson(map);
    if (item.name.isEmpty) return const [];
    return [
      ActiveFlowBranch(items: [item]),
    ];
  }

  if (raw is! List) return const [];
  if (raw.isEmpty) return const [];

  // List of branch objects.
  if (raw.first is Map) {
    final first = Map<String, dynamic>.from(raw.first as Map);
    if (first.containsKey('items') ||
        first.containsKey('steps') ||
        first.containsKey('tasks') ||
        first.containsKey('nodes')) {
      return _parseFlowBranches(raw);
    }
  }

  // Flat list of items — group by branch_key when present.
  final items = _parseFlowItems(raw);
  if (items.isEmpty) return const [];

  final byBranch = <String, List<ActiveFlowItem>>{};
  final unbranched = <ActiveFlowItem>[];
  for (final item in items) {
    final key = item.branchKey?.trim();
    if (key == null || key.isEmpty) {
      unbranched.add(item);
    } else {
      byBranch.putIfAbsent(key, () => <ActiveFlowItem>[]).add(item);
    }
  }

  if (byBranch.isEmpty) {
    return [ActiveFlowBranch(items: unbranched)];
  }

  final branches = <ActiveFlowBranch>[];
  var index = 1;
  for (final entry in byBranch.entries) {
    branches.add(
      ActiveFlowBranch(
        label: byBranch.length > 1 ? 'Path $index' : null,
        items: entry.value,
      ),
    );
    index += 1;
  }
  if (unbranched.isNotEmpty) {
    branches.add(
      ActiveFlowBranch(
        label: branches.isEmpty ? null : 'Also',
        items: unbranched,
      ),
    );
  }
  return branches;
}

List<ActiveFlowBranch> _parseFlowBranches(List raw) {
  final out = <ActiveFlowBranch>[];
  var index = 1;
  for (final row in raw) {
    if (row is! Map) continue;
    final map = Map<String, dynamic>.from(row);
    final items = _parseFlowItems(
      map['items'] ?? map['steps'] ?? map['tasks'] ?? map['nodes'] ?? row,
    );
    if (items.isEmpty) continue;
    out.add(
      ActiveFlowBranch(
        label: _asString(map['label'] ?? map['name'] ?? map['title']) ??
            (raw.length > 1 ? 'Path $index' : null),
        items: items,
      ),
    );
    index += 1;
  }
  return out;
}

List<ActiveFlowItem> _parseFlowItems(dynamic raw) {
  if (raw is Map) {
    return [ActiveFlowItem.fromJson(Map<String, dynamic>.from(raw))];
  }
  if (raw is! List) return const [];
  final out = <ActiveFlowItem>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(ActiveFlowItem.fromJson(Map<String, dynamic>.from(row)));
    } else if (row is String && row.trim().isNotEmpty) {
      out.add(ActiveFlowItem(name: row.trim()));
    }
  }
  return out;
}

List<WorkflowAttentionItem> _parseWorkflowAttention(dynamic raw) {
  if (raw is Map) {
    return [WorkflowAttentionItem.fromJson(Map<String, dynamic>.from(raw))];
  }
  if (raw is! List) return const [];
  final out = <WorkflowAttentionItem>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(WorkflowAttentionItem.fromJson(Map<String, dynamic>.from(row)));
    } else if (row is String && row.trim().isNotEmpty) {
      out.add(WorkflowAttentionItem(name: row.trim()));
    }
  }
  return out;
}

List<MyNextAction> _parseNextActions(dynamic raw) {
  if (raw is! List) return const [];
  final out = <MyNextAction>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(MyNextAction.fromJson(Map<String, dynamic>.from(row)));
    }
  }
  return out;
}

List<NextWorkflowTask> _parseNextTasks(dynamic raw) {
  if (raw is! List) return const [];
  final out = <NextWorkflowTask>[];
  for (final row in raw) {
    if (row is Map) {
      out.add(NextWorkflowTask.fromJson(Map<String, dynamic>.from(row)));
    } else if (row is String && row.trim().isNotEmpty) {
      out.add(NextWorkflowTask(name: row.trim()));
    }
  }
  return out;
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return int.tryParse(text);
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

String _slug(String label) {
  return label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _titleFromKey(String key) {
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

String _defaultStatusLabel(String status) {
  switch (status.toLowerCase().replaceAll(' ', '_')) {
    case 'ready':
      return 'Ready to start';
    case 'in_progress':
    case 'inprogress':
      return 'In progress';
    case 'waiting':
      return 'Waiting';
    case 'not_started':
    case 'notstarted':
      return 'Not started';
    case 'blocked':
      return 'Blocked';
    default:
      if (status.isEmpty) return '';
      return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}
