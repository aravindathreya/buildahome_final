class MobileLiveTestDevice {
  final int? id;
  final String publicId;
  final String displayName;
  final bool enabled;
  final int? activeRunId;
  final String? lastSeenAt;
  final String connectionStatus;
  final String connectionLabel;
  final int? registeredBy;
  final String? deviceToken;

  const MobileLiveTestDevice({
    this.id,
    this.publicId = '',
    this.displayName = 'Test Device',
    this.enabled = false,
    this.activeRunId,
    this.lastSeenAt,
    this.connectionStatus = 'offline',
    this.connectionLabel = 'Offline',
    this.registeredBy,
    this.deviceToken,
  });

  bool get isConnected => connectionStatus == 'connected';

  factory MobileLiveTestDevice.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestDevice(
      id: _asInt(json['id']),
      publicId: _asString(json['public_id']),
      displayName: _asString(json['display_name'], fallback: 'Test Device'),
      enabled: _truthy(json['enabled']) || _truthy(json['test_mode']),
      activeRunId: _asInt(json['active_run_id']),
      lastSeenAt: _asString(json['last_seen_at']).isEmpty
          ? null
          : _asString(json['last_seen_at']),
      connectionStatus: _asString(
        json['connection_status'],
        fallback: 'offline',
      ),
      connectionLabel: _asString(
        json['connection_label'],
        fallback: 'Offline',
      ),
      registeredBy: _asInt(json['registered_by']),
      deviceToken: _asString(json['device_token']).isEmpty
          ? null
          : _asString(json['device_token']),
    );
  }
}

class MobileLiveTestRun {
  final int runId;
  final int workflowId;
  final String workflowName;
  final String status;
  final Map<String, dynamic> roleUserMap;

  const MobileLiveTestRun({
    required this.runId,
    this.workflowId = 0,
    this.workflowName = '',
    this.status = '',
    this.roleUserMap = const {},
  });

  String get displayLabel {
    if (workflowName.trim().isNotEmpty) return workflowName.trim();
    return 'TEST-${runId.toString().padLeft(3, '0')}';
  }

  factory MobileLiveTestRun.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    final map = json['role_user_map'];
    return MobileLiveTestRun(
      runId: _asInt(json['run_id']) ?? 0,
      workflowId: _asInt(json['workflow_id']) ?? 0,
      workflowName: _asString(json['workflow_name']),
      status: _asString(json['status']),
      roleUserMap: map is Map
          ? Map<String, dynamic>.from(map)
          : const {},
    );
  }
}

class MobileLiveTestTask {
  final int? itemRunId;
  final String nodeKey;
  final String name;
  final String role;
  final int? assignedUserId;
  final String assignedUserName;
  final String status;
  final bool canComplete;
  final String? requiredDecision;
  final List<dynamic> options;
  final String blockReason;
  final bool infoOnly;

  const MobileLiveTestTask({
    this.itemRunId,
    this.nodeKey = '',
    this.name = '',
    this.role = '',
    this.assignedUserId,
    this.assignedUserName = '',
    this.status = '',
    this.canComplete = false,
    this.requiredDecision,
    this.options = const [],
    this.blockReason = '',
    this.infoOnly = false,
  });

  String get statusLabel {
    final value = status.trim();
    if (value.isEmpty) return 'Ready';
    return value
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  factory MobileLiveTestTask.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestTask(
      itemRunId: _asInt(json['item_run_id']),
      nodeKey: _asString(json['node_key']),
      name: _asString(json['name'], fallback: 'Task'),
      role: _asString(json['role']),
      assignedUserId: _asInt(json['assigned_user_id']),
      assignedUserName: _asString(json['assigned_user_name']),
      status: _asString(json['status'], fallback: 'ready'),
      canComplete: _truthy(json['can_complete']),
      requiredDecision: _asString(json['required_decision']).isEmpty
          ? null
          : _asString(json['required_decision']),
      options: json['options'] is List
          ? List<dynamic>.from(json['options'] as List)
          : const [],
      blockReason: _asString(json['block_reason']),
      infoOnly: _truthy(json['info_only']),
    );
  }
}

class MobileLiveTestSiteLocation {
  final double latitude;
  final double longitude;

  const MobileLiveTestSiteLocation({
    required this.latitude,
    required this.longitude,
  });

  factory MobileLiveTestSiteLocation.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    final lat = _asDouble(json['latitude'] ?? json['lat']);
    final lng = _asDouble(json['longitude'] ?? json['lng']);
    if (lat == null || lng == null) {
      return const MobileLiveTestSiteLocation(latitude: 0, longitude: 0);
    }
    return MobileLiveTestSiteLocation(latitude: lat, longitude: lng);
  }

  bool get isValid => latitude != 0 || longitude != 0;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

class MobileLiveTestSession {
  final bool success;
  final bool testMode;
  final bool skipProjectGates;
  final MobileLiveTestDevice? device;
  final MobileLiveTestRun? activeRun;
  final List<MobileLiveTestTask> tasks;
  final String message;

  const MobileLiveTestSession({
    this.success = false,
    this.testMode = true,
    this.skipProjectGates = true,
    this.device,
    this.activeRun,
    this.tasks = const [],
    this.message = '',
  });

  bool get hasAssignedRun => activeRun != null && (activeRun!.runId) > 0;

  bool get isWaitingForAssignment => success && testMode && !hasAssignedRun;

  /// One ready task per workflow node so parallel duplicates do not slow testing.
  List<MobileLiveTestTask> get dedupedTasks =>
      MobileLiveTestTaskDeduper.dedupeByNodeKey(
        tasks.where((task) => !task.infoOnly).toList(),
      );

  factory MobileLiveTestSession.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    final runRaw = json['active_run'];
    final tasksRaw = json['tasks'];
    final deviceRaw = json['device'];
    return MobileLiveTestSession(
      success: json.containsKey('success') ? _truthy(json['success']) : true,
      testMode: json.containsKey('test_mode')
          ? _truthy(json['test_mode'])
          : true,
      skipProjectGates: json.containsKey('skip_project_gates')
          ? _truthy(json['skip_project_gates'])
          : true,
      device: deviceRaw is Map
          ? MobileLiveTestDevice.fromJson(
              Map<String, dynamic>.from(deviceRaw),
            )
          : null,
      activeRun: runRaw is Map
          ? MobileLiveTestRun.fromJson(Map<String, dynamic>.from(runRaw))
          : null,
      tasks: tasksRaw is List
          ? tasksRaw
              .whereType<Map>()
              .map((item) => MobileLiveTestTask.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      message: _asString(json['message']),
    );
  }

  static const empty = MobileLiveTestSession();
}

class MobileLiveTestUser {
  final int? id;
  final String name;
  final String role;

  const MobileLiveTestUser({
    this.id,
    this.name = '',
    this.role = '',
  });

  factory MobileLiveTestUser.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestUser(
      id: _asInt(json['user_id'] ?? json['id']),
      name: _asString(json['name']),
      role: _asString(json['role']),
    );
  }
}

class MobileLiveTestTaskOption {
  final String decision;
  final String label;
  final String kind;

  const MobileLiveTestTaskOption({
    this.decision = '',
    this.label = '',
    this.kind = '',
  });

  bool get isApprove =>
      decision == 'approve' || kind == 'yes' && decision == 'approve';
  bool get isReject => decision == 'reject' || kind == 'no' && decision == 'reject';
  bool get isYes => decision == 'yes';
  bool get isNo => decision == 'no';
  bool get isComplete =>
      kind == 'complete' || decision.isEmpty && label.isNotEmpty;

  factory MobileLiveTestTaskOption.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestTaskOption(
      decision: _asString(json['decision']),
      label: _asString(json['label']),
      kind: _asString(json['kind']),
    );
  }
}

class MobileLiveTestTaskRequirement {
  final String type;
  final String message;
  final bool satisfied;
  final List<MobileLiveTestTaskOption> options;

  static const supportedTypes = {
    'yes_no',
    'approve_reject',
    'mandatory_upload',
    'document_upload',
  };

  const MobileLiveTestTaskRequirement({
    this.type = '',
    this.message = '',
    this.satisfied = true,
    this.options = const [],
  });

  bool get isUnsupportedInput {
    if (type.isEmpty || satisfied) return false;
    return !supportedTypes.contains(type);
  }

  factory MobileLiveTestTaskRequirement.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    final optionsRaw = json['options'];
    return MobileLiveTestTaskRequirement(
      type: _asString(json['type']),
      message: _asString(json['message']),
      satisfied: json.containsKey('satisfied') ? _truthy(json['satisfied']) : true,
      options: optionsRaw is List
          ? optionsRaw
              .whereType<Map>()
              .map((item) => MobileLiveTestTaskOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
    );
  }
}

class MobileLiveTestTaskDetail {
  final int? itemRunId;
  final String nodeKey;
  final String name;
  final String description;
  final String instructions;
  final String status;
  final String statusLabel;
  final String role;
  final String assignee;
  final bool canComplete;
  final String blockReason;
  final bool mandatoryUploadsPending;
  final String? requiredDecision;
  final List<MobileLiveTestTaskOption> options;
  final List<MobileLiveTestTaskRequirement> requirements;
  final List<MobileLiveTestWorkflowAction> workflowActions;
  final Map<String, dynamic> actionResponses;
  final List<dynamic> actions;
  final List<dynamic> documents;
  final List<dynamic> comments;

  const MobileLiveTestTaskDetail({
    this.itemRunId,
    this.nodeKey = '',
    this.name = '',
    this.description = '',
    this.instructions = '',
    this.status = '',
    this.statusLabel = '',
    this.role = '',
    this.assignee = '',
    this.canComplete = false,
    this.blockReason = '',
    this.mandatoryUploadsPending = false,
    this.requiredDecision,
    this.options = const [],
    this.requirements = const [],
    this.workflowActions = const [],
    this.actionResponses = const {},
    this.actions = const [],
    this.documents = const [],
    this.comments = const [],
  });

  bool get hasUnsupportedRequirements =>
      requirements.any((req) => req.isUnsupportedInput);

  List<MobileLiveTestWorkflowAction> get interactiveActions =>
      MobileLiveTestWorkflowAction.filterExclusiveActions(
        workflowActions.where((a) => a.isInteractive).toList(),
        actionResponses,
      );

  String get unsupportedMessage {
    for (final req in requirements) {
      if (req.isUnsupportedInput) {
        if (req.message.trim().isNotEmpty) return req.message.trim();
      }
    }
    if (mandatoryUploadsPending) {
      return 'Complete required uploads before finishing this task.';
    }
    if (blockReason.trim().isNotEmpty) return blockReason.trim();
    return 'Additional task input is required before this task can be completed.';
  }

  bool get showActionButtons =>
      canComplete && !hasUnsupportedRequirements && options.isNotEmpty;

  bool get showPlainComplete =>
      canComplete &&
      !hasUnsupportedRequirements &&
      options.isEmpty &&
      (requiredDecision == null || requiredDecision!.isEmpty);

  factory MobileLiveTestTaskDetail.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    final optionsRaw = json['options'];
    final requirementsRaw = json['requirements'];
    final actionsRaw = json['actions'];
    final responsesRaw = json['action_responses'];
    final parsedActions = actionsRaw is List
        ? actionsRaw
            .whereType<Map>()
            .map((item) => MobileLiveTestWorkflowAction.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : const <MobileLiveTestWorkflowAction>[];
    return MobileLiveTestTaskDetail(
      itemRunId: _asInt(json['item_run_id']),
      nodeKey: _asString(json['node_key']),
      name: _asString(json['name'], fallback: 'Task'),
      description: _asString(json['description']),
      instructions: _asString(json['instructions']),
      status: _asString(json['status']),
      statusLabel: _asString(json['status_label']),
      role: _asString(json['role']),
      assignee: _asString(json['assignee']),
      canComplete: _truthy(json['can_complete']),
      blockReason: _asString(json['block_reason']),
      mandatoryUploadsPending: _truthy(json['mandatory_uploads_pending']),
      requiredDecision: _asString(json['required_decision']).isEmpty
          ? null
          : _asString(json['required_decision']),
      options: optionsRaw is List
          ? optionsRaw
              .whereType<Map>()
              .map((item) => MobileLiveTestTaskOption.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      requirements: requirementsRaw is List
          ? requirementsRaw
              .whereType<Map>()
              .map((item) => MobileLiveTestTaskRequirement.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      workflowActions: parsedActions,
      actionResponses: responsesRaw is Map
          ? Map<String, dynamic>.from(responsesRaw)
          : const {},
      actions: actionsRaw is List
          ? List<dynamic>.from(actionsRaw)
          : const [],
      documents: json['documents'] is List
          ? List<dynamic>.from(json['documents'] as List)
          : const [],
      comments: json['comments'] is List
          ? List<dynamic>.from(json['comments'] as List)
          : const [],
    );
  }
}

class MobileLiveTestExecutionContext {
  final bool success;
  final bool testExecution;
  final bool testMode;
  final int runId;
  final int itemRunId;
  final MobileLiveTestUser? authenticatedUser;
  final MobileLiveTestUser? actingUser;
  final MobileLiveTestTaskDetail task;
  final String message;

  const MobileLiveTestExecutionContext({
    this.success = false,
    this.testExecution = true,
    this.testMode = true,
    this.runId = 0,
    this.itemRunId = 0,
    this.authenticatedUser,
    this.actingUser,
    this.task = const MobileLiveTestTaskDetail(),
    this.message = '',
  });

  factory MobileLiveTestExecutionContext.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    final taskRaw = json['task'];
    return MobileLiveTestExecutionContext(
      success: json.containsKey('success') ? _truthy(json['success']) : true,
      testExecution: _truthy(json['test_execution']),
      testMode: json.containsKey('test_mode')
          ? _truthy(json['test_mode'])
          : true,
      runId: _asInt(json['run_id']) ?? 0,
      itemRunId: _asInt(json['item_run_id']) ?? 0,
      authenticatedUser: json['authenticated_user'] is Map
          ? MobileLiveTestUser.fromJson(
              Map<String, dynamic>.from(json['authenticated_user'] as Map),
            )
          : null,
      actingUser: json['acting_user'] is Map
          ? MobileLiveTestUser.fromJson(
              Map<String, dynamic>.from(json['acting_user'] as Map),
            )
          : null,
      task: taskRaw is Map
          ? MobileLiveTestTaskDetail.fromJson(
              Map<String, dynamic>.from(taskRaw),
            )
          : const MobileLiveTestTaskDetail(),
      message: _asString(json['message']),
    );
  }
}

class MobileLiveTestCompletionResult {
  final bool success;
  final bool testExecution;
  final bool testMode;
  final int runId;
  final int itemRunId;
  final MobileLiveTestUser? actingUser;
  final String engine;
  final String status;
  final String decision;
  final bool taskCompleted;
  final List<dynamic> newReady;
  final List<dynamic> remainingParallel;
  final String message;

  const MobileLiveTestCompletionResult({
    this.success = false,
    this.testExecution = true,
    this.testMode = true,
    this.runId = 0,
    this.itemRunId = 0,
    this.actingUser,
    this.engine = '',
    this.status = '',
    this.decision = '',
    this.taskCompleted = false,
    this.newReady = const [],
    this.remainingParallel = const [],
    this.message = '',
  });

  factory MobileLiveTestCompletionResult.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestCompletionResult(
      success: _truthy(json['success']),
      testExecution: _truthy(json['test_execution']),
      testMode: json.containsKey('test_mode')
          ? _truthy(json['test_mode'])
          : true,
      runId: _asInt(json['run_id']) ?? 0,
      itemRunId: _asInt(json['item_run_id']) ?? 0,
      actingUser: json['acting_user'] is Map
          ? MobileLiveTestUser.fromJson(
              Map<String, dynamic>.from(json['acting_user'] as Map),
            )
          : null,
      engine: _asString(json['engine']),
      status: _asString(json['status']),
      decision: _asString(json['decision']),
      taskCompleted: _truthy(json['task_completed']),
      newReady: json['new_ready'] is List
          ? List<dynamic>.from(json['new_ready'] as List)
          : const [],
      remainingParallel: json['remaining_parallel'] is List
          ? List<dynamic>.from(json['remaining_parallel'] as List)
          : const [],
      message: _asString(json['message']),
    );
  }

  List<MobileLiveTestTask> get newReadyTasks {
    return newReady
        .whereType<Map>()
        .map(
          (item) => MobileLiveTestTask.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((task) => task.itemRunId != null && task.itemRunId! > 0)
        .toList();
  }
}

class MobileLiveTestWorkflowAction {
  final Map<String, dynamic> raw;

  const MobileLiveTestWorkflowAction(this.raw);

  static const readOnlyTypes = {
    'delay_timer',
    'yes_no_summary',
    'user_checklist_summary',
    'text_list_summary',
    'material_shift_summary',
    'redirect_button',
  };

  static const interactiveTypes = {
    'upload',
    'update_status',
    'yes_no',
    'checklist',
    'user_checklist',
    'user_checklist_followup',
    'slot_selection',
    'slot_confirmation',
    'kyp_material_shift',
    'text_list',
    'picture_choice_list',
    'picture_choice_pick',
    'complete_button',
    'view_prior_response',
  };

  String get id => _asString(raw['id']);
  String get type => _asString(raw['type']).toLowerCase();
  String get label {
    final text = _asString(raw['label']);
    if (text.isNotEmpty) return text;
    return _defaultLabelForType(type);
  }

  String get documentName =>
      _asString(raw['document_name'], fallback: label);
  bool get mandatory => _truthy(raw['mandatory']);
  bool get blocked => _truthy(raw['blocked']);
  String get blockedMessage => _asString(raw['blocked_message']);
  bool get allowComment => _truthy(raw['allow_comment']);
  bool get requireComment => _truthy(raw['require_comment']);
  bool get liveImageOnly => _truthy(raw['live_image_only']);
  bool get requireNearSite => _truthy(raw['require_near_site']);
  bool get requireGpsForUpload => _truthy(raw['require_gps_for_upload']);
  int get nearSiteRadiusMeters =>
      _asInt(raw['near_site_radius_meters']) ?? 500;
  bool get allowGalleryUpload =>
      !_truthy(raw['live_image_only']) &&
      !requireNearSite &&
      (raw.containsKey('allow_gallery_upload')
          ? _truthy(raw['allow_gallery_upload'])
          : true);
  bool get allowLiveCamera =>
      raw.containsKey('allow_live_image')
          ? _truthy(raw['allow_live_image'])
          : true;
  bool get allowVideoUpload =>
      raw.containsKey('allow_video_upload')
          ? _truthy(raw['allow_video_upload'])
          : false;
  int? get maxVideoDurationSeconds =>
      _asInt(raw['max_video_duration_seconds']);
  int? get maxVideoSizeMb => _asInt(raw['max_video_size_mb']);
  List<String> get videoFormats => _stringList(raw['video_formats']);
  List<String> get imageFormats => _stringList(raw['image_formats']);
  MobileLiveTestSiteLocation? get siteLocation {
    final rawLoc = raw['site_location'];
    if (rawLoc is Map) {
      final loc = MobileLiveTestSiteLocation.fromJson(
        Map<String, dynamic>.from(rawLoc),
      );
      return loc.isValid ? loc : null;
    }
    return null;
  }

  bool get needsGpsForUpload => requireNearSite || requireGpsForUpload;
  bool get allowFileUpload => raw.containsKey('allow_file_upload')
      ? _truthy(raw['allow_file_upload'])
      : type == 'upload';
  bool get addPercentToTask {
    if (_truthy(raw['add_percent_to_task'])) return true;
    if (_asInt(raw['min_next_percent']) != null) return true;
    final entries = raw['progress_entries'];
    if (entries is List && entries.isNotEmpty) return true;
    return false;
  }
  int? get currentPercent => _asInt(raw['current_percent']);
  int get minNextPercent {
    final configured = _asInt(raw['min_next_percent']);
    final current = currentPercent ?? 0;
    if (configured != null && configured > current) {
      return configured.clamp(1, 100);
    }
    return (current + 1).clamp(1, 100);
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
    final minNext = minNextPercent;
    if (parsed < minNext) {
      return 'Enter at least $minNext%.';
    }
    if (parsed <= previousPercent) {
      return 'Must be greater than the last saved progress ($previousPercent%).';
    }
    return null;
  }
  List<dynamic> get progressEntries =>
      raw['progress_entries'] is List
          ? List<dynamic>.from(raw['progress_entries'] as List)
          : const [];
  List<dynamic> get items =>
      raw['items'] is List ? List<dynamic>.from(raw['items'] as List) : const [];
  List<String> get allowedStatuses => _stringList(raw['allowed_statuses']);
  bool get showNote => _truthy(raw['show_note']);
  String get yesLabel => _asString(raw['yes_label'], fallback: 'Yes');
  String get noLabel => _asString(raw['no_label'], fallback: 'No');
  bool get enableApprove => _truthy(raw['enable_approve']);
  Map<String, dynamic> get response {
    final embedded = raw['response'];
    if (embedded is Map) return Map<String, dynamic>.from(embedded);
    return const {};
  }

  bool get isSubmitted =>
      _truthy(response['submitted']) ||
      _truthy(response['completed']) ||
      (response.isNotEmpty && type == 'upload' && response['files'] is List);

  static const exclusiveIndentShiftGroup = 'indent-or-shift';

  String get exclusiveGroup => _asString(raw['exclusive_group']);
  String get exclusiveChoice => _asString(raw['exclusive_choice']);
  bool get exclusiveHidesOnSelect => _truthy(raw['exclusive_hides_on_select']);

  bool choiceStarted(Map<String, dynamic> actionResponses) {
    final slot = _responseSlot(actionResponses, id);
    if (type == 'text_list') {
      return _truthy(slot['submitted']) ||
          _asString(slot['submitted_at']).isNotEmpty ||
          _truthy(slot['indents_created']);
    }
    if (type == 'kyp_material_shift') {
      if (_truthy(slot['indents_created']) ||
          slot['from_project_id'] != null ||
          _asString(slot['from_project']).isNotEmpty) {
        return true;
      }
      return slot['materials'] is List && (slot['materials'] as List).isNotEmpty;
    }
    return isSubmitted;
  }

  static Map<String, dynamic> _responseSlot(
    Map<String, dynamic> actionResponses,
    String actionId,
  ) {
    if (actionId.isEmpty) return const {};
    final slot = actionResponses[actionId] ?? actionResponses[actionId.toString()];
    if (slot is Map) return Map<String, dynamic>.from(slot);
    return const {};
  }

  /// Starter kit indent vs labour shed shift: hide the other option once one starts.
  static List<MobileLiveTestWorkflowAction> filterExclusiveActions(
    List<MobileLiveTestWorkflowAction> actions,
    Map<String, dynamic> actionResponses,
  ) {
    final hasIndent =
        actions.any((a) => a.exclusiveChoice == 'indent');
    final hasShift =
        actions.any((a) => a.exclusiveChoice == 'shift');
    if (!hasIndent || !hasShift) return actions;

    final indentChosen = actions.any(
      (a) => a.exclusiveChoice == 'indent' && a.choiceStarted(actionResponses),
    );
    final shiftChosen = actions.any(
      (a) => a.exclusiveChoice == 'shift' && a.choiceStarted(actionResponses),
    );
    if (indentChosen) {
      return actions.where((a) => a.exclusiveChoice != 'shift').toList();
    }
    if (shiftChosen) {
      return actions.where((a) => a.exclusiveChoice != 'indent').toList();
    }
    return actions;
  }

  bool get isInteractive {
    if (readOnlyTypes.contains(type)) return false;
    if (!interactiveTypes.contains(type)) return false;
    if (type == 'view_prior_response' && !enableApprove) return false;
    return true;
  }

  bool get usesMultipart =>
      type == 'upload' ||
      type == 'picture_choice_list' ||
      type == 'user_checklist' ||
      type == 'user_checklist_followup' ||
      type == 'text_list';

  factory MobileLiveTestWorkflowAction.fromJson(Map<String, dynamic>? json) {
    return MobileLiveTestWorkflowAction(json ?? const {});
  }

  static String _defaultLabelForType(String type) {
    switch (type) {
      case 'upload':
        return 'Upload';
      case 'update_status':
        return 'Update status';
      case 'checklist':
        return 'Checklist';
      case 'yes_no':
        return 'Yes / No';
      case 'complete_button':
        return 'Complete task';
      case 'text_list':
        return 'Form';
      case 'kyp_material_shift':
        return 'Material shift';
      case 'user_checklist':
        return 'User checklist';
      case 'user_checklist_followup':
        return 'Checklist follow-up';
      case 'slot_selection':
        return 'Slot selection';
      case 'slot_confirmation':
        return 'Slot confirmation';
      case 'picture_choice_list':
        return 'Picture choice list';
      case 'picture_choice_pick':
        return 'Picture choice';
      case 'view_prior_response':
        return 'Review prior response';
      default:
        return 'Action';
    }
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }
}

class MobileLiveTestComment {
  final int? id;
  final String body;
  final String authorName;
  final String authorRole;
  final String createdAt;

  const MobileLiveTestComment({
    this.id,
    this.body = '',
    this.authorName = '',
    this.authorRole = '',
    this.createdAt = '',
  });

  factory MobileLiveTestComment.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestComment(
      id: _asInt(json['id'] ?? json['comment_id']),
      body: _asString(json['body'] ?? json['comment'] ?? json['text']),
      authorName: _asString(json['author_name'] ?? json['user_name'] ?? json['name']),
      authorRole: _asString(json['author_role'] ?? json['role']),
      createdAt: _asString(
        json['created_at'] ?? json['timestamp'] ?? json['posted_at'],
      ),
    );
  }
}

class MobileLiveTestActionResult {
  final bool success;
  final bool testExecution;
  final int runId;
  final int itemRunId;
  final String message;
  final bool taskCompleted;
  final bool taskRouted;
  final int? currentPercent;
  final Map<String, dynamic> raw;

  const MobileLiveTestActionResult({
    this.success = false,
    this.testExecution = true,
    this.runId = 0,
    this.itemRunId = 0,
    this.message = '',
    this.taskCompleted = false,
    this.taskRouted = false,
    this.currentPercent,
    this.raw = const {},
  });

  factory MobileLiveTestActionResult.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return MobileLiveTestActionResult(
      success: _truthy(json['success']),
      testExecution: json.containsKey('test_execution')
          ? _truthy(json['test_execution'])
          : true,
      runId: _asInt(json['run_id']) ?? 0,
      itemRunId: _asInt(json['item_run_id']) ?? 0,
      message: _asString(json['message']),
      taskCompleted: _truthy(json['task_completed']),
      taskRouted: _truthy(json['task_routed']) || _truthy(json['routed']),
      currentPercent: _asInt(json['current_percent']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class MobileLiveTestTaskDeduper {
  const MobileLiveTestTaskDeduper._();

  static String dedupeKey(MobileLiveTestTask task) {
    final nodeKey = task.nodeKey.trim();
    if (nodeKey.isNotEmpty) return 'node:$nodeKey';
    final name = task.name.trim().toLowerCase();
    if (name.isNotEmpty) return 'name:$name';
    final id = task.itemRunId;
    if (id != null && id > 0) return 'run:$id';
    return '';
  }

  static List<MobileLiveTestTask> dedupeByNodeKey(
    List<MobileLiveTestTask> tasks,
  ) {
    final seen = <String>{};
    final out = <MobileLiveTestTask>[];
    for (final task in tasks) {
      final key = dedupeKey(task);
      if (key.isEmpty) {
        out.add(task);
        continue;
      }
      if (seen.add(key)) {
        out.add(task);
      }
    }
    return out;
  }
}

class MobileLiveTestUploadPart {
  final String fieldName;
  final String filePath;
  final String? filename;

  const MobileLiveTestUploadPart({
    required this.fieldName,
    required this.filePath,
    this.filename,
  });
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return text;
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
