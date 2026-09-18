import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_http.dart';
import 'client_generation_service.dart';
import 'mobile_documents_service.dart';
import 'session_manager.dart';

class DataProvider {
  static final DataProvider _instance = DataProvider._internal();
  factory DataProvider() => _instance;
  DataProvider._internal();

  // For non-Client users: list of projects
  List<dynamic> projects = [];
  bool projectsLoading = false;
  DateTime? lastProjectsLoad;

  // For Client users: project data
  String? clientProjectId;
  String? clientSalesSopId;
  String? clientProjectLocation;
  String? clientProjectCompletion;
  dynamic clientProjectUpdates;
  bool? clientProjectBlocked;
  String? clientProjectBlockReason;
  String? clientProjectValue;
  List<dynamic> clientWorkflowDashboardSlots = [];
  List<Map<String, dynamic>> clientPendingTasks = [];
  int clientPendingTaskCount = 0;
  Map<String, dynamic>? clientCurrentPendingTask;
  bool clientPendingTasksLoaded = false;
  List<Map<String, dynamic>> clientTimelineTasks = [];
  int clientTimelineTaskCount = 0;
  int clientTimelinePendingCount = 0;
  int clientTimelineCompletedCount = 0;
  int clientTimelineUpcomingCount = 0;
  bool clientTimelineLoaded = false;
  bool clientDataLoading = false;
  DateTime? lastClientDataLoad;
  DateTime? lastUpdatesLoad;
  bool isLoadingUpdates = false;

  String? currentRole;
  String? currentUserId;
  String? currentApiToken;

  /// ERP project_id → sales_sop_id learned from get_tasks / project payloads.
  final Map<String, String> _projectSalesSopByErpId = {};

  /// Latest task rows kept briefly for chat SOP resolution fallbacks.
  List<dynamic> _taskSalesSopHints = [];

  /// context_id → {title, status} for ERP tasks / workflow runs (chat list).
  final Map<String, Map<String, String>> erpTaskMetaById = {};
  final Map<String, Map<String, String>> workflowRunMetaById = {};

  List<String> get knownWorkflowRunIds => workflowRunMetaById.keys.toList();

  // Cached data for non-Client users (payments, gallery, schedule, notes, documents)
  Map<String, dynamic>? cachedPayments;
  List<dynamic>? cachedGallery;
  List<dynamic>? cachedSchedule;
  List<dynamic>? cachedNotes;
  List<dynamic>? cachedDocuments;
  DateTime? lastPaymentsLoad;
  DateTime? lastGalleryLoad;
  DateTime? lastScheduleLoad;
  DateTime? lastNotesLoad;
  DateTime? lastDocumentsLoad;
  bool isLoadingProjectData = false;

  /// User-scoped task list shared by Home, My Tasks, and View All Tasks.
  List<dynamic> cachedUserTasks = [];
  DateTime? lastUserTasksLoad;
  Future<void>? _userTasksInFlight;
  String? _userTasksInFlightKey;

  Future<void>? _openHomeInFlight;
  String? _openHomeKey;
  Future<void>? _projectDataInFlight;
  String? _projectDataInFlightId;

  /// Last sales_sop_details URI that returned 200 for a project.
  final Map<String, Uri> _workingSopDetailsUriByProject = {};

  static const Duration _homeDataTtl = Duration(minutes: 5);
  static const Duration _tasksTtl = Duration(seconds: 45);
  static const Duration _projectsTtl = Duration(minutes: 5);

  // Load projects for non-Client users
  Future<void> loadProjects({bool force = false}) async {
    if (projectsLoading && !force) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Always refresh credentials from SharedPreferences to ensure we have the latest
    currentRole = prefs.getString('role');
    currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');
    currentApiToken = prefs.getString('api_token');

    if (currentRole == null ||
        currentUserId == null ||
        currentApiToken == null) {
      print('[DataProvider] Cannot load projects: missing credentials');
      return;
    }

    if (currentRole == 'Client') {
      return; // Don't load projects for clients
    }

    if (!force &&
        lastProjectsLoad != null &&
        projects.isNotEmpty &&
        DateTime.now().difference(lastProjectsLoad!) < _projectsTtl) {
      return;
    }

    // Force refreshes credentials/cache timestamp but keeps the current list
    // visible so pickers can open immediately while data reloads.
    if (force) {
      lastProjectsLoad = null;
    }

    projectsLoading = true;
    try {
      final payload = {
        "user_id": currentUserId!,
        "role": currentRole!,
        "api_token": currentApiToken!,
      };
      print('[DataProvider] Loading projects with $payload');
      var response = await ApiHttp.post(
            Uri.parse(
                "https://office1.buildahome.in/API/get_projects_for_user"),
            body: payload,
          )
          .timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // Ensure we're getting a list
        if (decoded is List) {
          projects = decoded;
        } else {
          projects = [];
          print('[DataProvider] Unexpected response format: $decoded');
        }
        lastProjectsLoad = DateTime.now();
        print(
            '[DataProvider] Loaded ${projects.length} projects for user $currentUserId (role: $currentRole)');
      } else {
        print('[DataProvider] Failed to load projects: ${response.statusCode}');
        if (projects.isEmpty) {
          projects = [];
        }
      }
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print('[DataProvider] Error loading projects: $e');
      if (projects.isEmpty) {
        projects = [];
      }
    } finally {
      projectsLoading = false;
    }
  }

  // Load project data for Client users
  Future<void> loadClientProjectData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role');

    final role = (currentRole ?? '').trim().toLowerCase();
    if (role != 'client') {
      return; // Don't load client data for non-clients
    }

    var projectId = prefs.getString('project_id');
    if (projectId == null || projectId.trim().isEmpty) {
      print('[DataProvider] loadClientProjectData: missing project_id');
      return;
    }

    await _loadProjectData(projectId.trim());
  }

  Future<void> loadProjectDataForProject(
    String projectId, {
    bool force = false,
  }) async {
    projectId = projectId.trim();
    if (projectId.isEmpty) return;

    if (!force &&
        clientProjectId == projectId &&
        lastClientDataLoad != null &&
        DateTime.now().difference(lastClientDataLoad!) < _homeDataTtl) {
      return;
    }

    if (_projectDataInFlight != null &&
        _projectDataInFlightId == projectId &&
        !force) {
      await _projectDataInFlight;
      return;
    }

    final future = _loadProjectData(projectId, force: force);
    _projectDataInFlight = future;
    _projectDataInFlightId = projectId;
    try {
      await future;
    } finally {
      if (identical(_projectDataInFlight, future)) {
        _projectDataInFlight = null;
        _projectDataInFlightId = null;
      }
    }
  }

  Future<void> _loadProjectData(String projectId, {bool force = false}) async {
    projectId = projectId.trim();
    if (projectId.isEmpty) return;

    if (clientDataLoading && clientProjectId == projectId && !force) {
      while (clientDataLoading && clientProjectId == projectId) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (currentRole == null) {
      currentRole = prefs.getString('role');
    }

    final switchingProject = clientProjectId != projectId;
    clientProjectId = projectId;
    clientDataLoading = true;

    print('[DataProvider] Loading project data for project $projectId');
    print('[DataProvider] Current role: $currentRole');
    print('[DataProvider] Current user id: $currentUserId');

    // Keep cached updates on a background refresh so Home does not flash empty.
    if (force || switchingProject || clientProjectUpdates == null) {
      clientProjectUpdates = null;
    }

    // Load project value from SharedPreferences (synchronous, no API call needed)
    final role = (currentRole ?? '').trim().toLowerCase();
    if (role == 'client') {
      var value = prefs.getString('project_value');
      if (value != null) {
        clientProjectValue = value;
      }
    } else {
      // For non-Client users, try to load from API or set empty
      clientProjectValue = '';
    }

    try {
      // Load critical data first: updates and percentage (required for immediate display)
      // Never skip on a fresh project load — skipIfRecent can hide updates after reset.
      await Future.wait([
        _loadLatestUpdates(projectId, prefs, skipIfRecent: !force && !switchingProject),
        _loadProjectPercentage(projectId, prefs),
      ], eagerError: false);

      print('[DataProvider] Updates and percentage loaded for $projectId');

      // Then load other project data (location, block status) after critical data is ready
      await Future.wait([
        _loadProjectLocation(projectId),
        _loadProjectBlockStatus(projectId),
        _loadWorkflowDashboardSlots(projectId),
      ], eagerError: false);

      lastClientDataLoad = DateTime.now();
      print('[DataProvider] Successfully loaded project data for $projectId');
    } catch (e) {
      print('[DataProvider] Error loading client project data: $e');
    } finally {
      clientDataLoading = false;
    }
  }

  Future<void> _loadWorkflowDashboardSlots(String projectId) async {
    clientPendingTasks = [];
    clientPendingTaskCount = 0;
    clientCurrentPendingTask = null;
    clientPendingTasksLoaded = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiToken = _normalizeApiToken(prefs.getString('api_token'));
      if (apiToken == null) {
        clientWorkflowDashboardSlots = [];
        clientPendingTasksLoaded = true;
        return;
      }

      final sopContext = await _fetchSalesSopDetailsContext(
        projectId: projectId,
        apiToken: apiToken,
      );
      final decoded = sopContext?['decoded'] as Map<String, dynamic>?;
      final details = sopContext?['details'] as Map<String, dynamic>?;

      if (details != null &&
          details['workflow_dashboard_slots'] is List) {
        clientWorkflowDashboardSlots = details['workflow_dashboard_slots'];
      } else {
        clientWorkflowDashboardSlots = [];
      }

      _applyPendingTasksFromPayload(decoded, details);

      final resolvedSopId = _extractSalesSopId(decoded, details, projectId);
      if (resolvedSopId != null) {
        await _cacheSalesSopId(resolvedSopId, projectId);
      }

      if (clientPendingTasks.isEmpty && clientPendingTaskCount == 0) {
        final salesSopId = resolvedSopId ??
            await resolveSalesSopId(
              projectId: projectId,
              apiToken: apiToken,
              useCache: true,
            );
        if (salesSopId != null) {
          await _loadPendingTasksFromEndpoint(salesSopId, apiToken, projectId);
        } else {
          clientPendingTasksLoaded = true;
        }
      } else {
        clientPendingTasksLoaded = true;
      }
    } catch (e) {
      print('[DataProvider] Error loading workflow dashboard slots: $e');
      clientWorkflowDashboardSlots = [];
      clientPendingTasksLoaded = true;
    }
  }

  void _applyPendingTasksFromPayload(
    Map<String, dynamic>? decoded,
    Map<String, dynamic>? details,
  ) {
    final sources = <Map<String, dynamic>>[
      if (decoded != null) decoded,
      if (details != null) details,
    ];

    for (final source in sources) {
      final hasPendingPayload = source.containsKey('pending_tasks') ||
          source.containsKey('pending_timeline_tasks') ||
          source.containsKey('pending_task_count');

      final tasks = _parsePendingTaskList(source['pending_tasks']);
      final timelineTasks =
          _parsePendingTaskList(source['pending_timeline_tasks']);
      if (tasks.isNotEmpty) {
        clientPendingTasks = tasks;
      } else if (timelineTasks.isNotEmpty) {
        clientPendingTasks = timelineTasks;
      }

      final count = int.tryParse(source['pending_task_count']?.toString() ?? '');
      if (count != null) {
        clientPendingTaskCount = count;
      } else if (clientPendingTasks.isNotEmpty) {
        clientPendingTaskCount = clientPendingTasks.length;
      }

      final current = source['current_pending_task'];
      if (current is Map) {
        clientCurrentPendingTask = Map<String, dynamic>.from(current);
      }

      if (hasPendingPayload ||
          clientPendingTasks.isNotEmpty ||
          clientPendingTaskCount > 0 ||
          clientCurrentPendingTask != null) {
        if (clientCurrentPendingTask == null && clientPendingTasks.isNotEmpty) {
          clientCurrentPendingTask = clientPendingTasks.first;
        }
        if (clientPendingTaskCount == 0 && clientPendingTasks.isNotEmpty) {
          clientPendingTaskCount = clientPendingTasks.length;
        }
        clientPendingTasksLoaded = true;
        return;
      }
    }
  }

  Future<void> refreshProjectPendingTasks({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final projectId = prefs.getString('project_id');
    if (projectId == null || projectId.isEmpty) {
      clientPendingTasks = [];
      clientPendingTaskCount = 0;
      clientCurrentPendingTask = null;
      clientPendingTasksLoaded = true;
      return;
    }

    if (!force && clientPendingTasksLoaded) return;
    await _loadWorkflowDashboardSlots(projectId);
  }

  Future<void> loadProjectTimeline({bool force = false}) async {
    if (!force && clientTimelineLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    final projectId = prefs.getString('project_id');
    final role = prefs.getString('role');
    final apiToken = _normalizeApiToken(prefs.getString('api_token'));
    currentApiToken = apiToken;
    currentRole = role;

    if (apiToken == null) {
      clientTimelineTasks = [];
      clientTimelineTaskCount = 0;
      clientTimelinePendingCount = 0;
      clientTimelineCompletedCount = 0;
      clientTimelineUpcomingCount = 0;
      clientTimelineLoaded = true;
      throw Exception(
        'API token missing. Please log out and log in again.',
      );
    }

    final salesSopId = await resolveSalesSopId(
      projectId: projectId,
      apiToken: apiToken,
    );
    final isClient = role == 'Client';

    final timelinePaths = [
      'https://office.buildahome.in/API/sales_sop_project_timeline',
      'https://office.buildahome.in/api/sales_sop_project_timeline',
    ];

    final endpointAttempts = <Map<String, dynamic>>[];
    for (final basePath in timelinePaths) {
      if (salesSopId != null && salesSopId.isNotEmpty) {
        endpointAttempts.add({
          'uri': Uri.parse('$basePath/$salesSopId'),
          'query': {'api_token': apiToken},
        });
        endpointAttempts.add({
          'uri': Uri.parse(basePath),
          'query': {
            'api_token': apiToken,
            'sales_sop_id': salesSopId,
          },
        });
        endpointAttempts.add({
          'uri': Uri.parse(basePath),
          'query': {
            'api_token': apiToken,
            'id': salesSopId,
          },
        });
      }
      if (!isClient &&
          (salesSopId == null || salesSopId.isEmpty) &&
          projectId != null &&
          projectId.isNotEmpty) {
        // Staff timeline requires sales_sop_id. Calling with only project_id
        // returns 401 and was being shown as "session expired".
        continue;
      }
      if (projectId != null && projectId.isNotEmpty) {
        endpointAttempts.add({
          'uri': Uri.parse(basePath),
          'query': {
            'api_token': apiToken,
            'project_id': projectId,
          },
        });
      }
      if (isClient) {
        endpointAttempts.add({
          'uri': Uri.parse(basePath),
          'query': {'api_token': apiToken},
        });
      }
    }

    Object? lastError;
    int? lastStatusCode;
    for (final attempt in endpointAttempts) {
      try {
        final uri = (attempt['uri'] as Uri).replace(
          queryParameters:
              Map<String, String>.from(attempt['query'] as Map<String, String>),
        );
        print('[DataProvider] Loading project timeline: $uri');
        final response = await ApiHttp.get(
          uri,
          headers: _apiAuthHeaders(apiToken),
        ).timeout(Duration(seconds: 20));

        lastStatusCode = response.statusCode;
        if (response.statusCode != 200) {
          lastError = _timelineErrorMessage(response);
          // 401 on a project_id-only URL usually means the endpoint wants
          // sales_sop_id, not that the user's session is dead.
          final query = attempt['query'] as Map<String, String>;
          final usedSop = (salesSopId != null &&
                  salesSopId.isNotEmpty &&
                  ((attempt['uri'] as Uri)
                          .path
                          .contains('/$salesSopId') ||
                      query['sales_sop_id'] == salesSopId ||
                      query['id'] == salesSopId));
          if (response.statusCode == 401 && usedSop) {
            break;
          }
          continue;
        }

        final body = jsonDecode(response.body);
        if (body is! Map || body['success'] != true) {
          lastError = _timelineErrorMessageFromBody(body);
          continue;
        }

        final decoded = Map<String, dynamic>.from(body);
        await _cacheSalesSopIdFromPayload(decoded, projectId);

        clientTimelineTasks = _sortTimelineTasks(
          _parsePendingTaskList(decoded['timeline_tasks']),
        );
        clientTimelineTaskCount =
            int.tryParse(decoded['timeline_task_count']?.toString() ?? '') ??
                clientTimelineTasks.length;
        clientTimelinePendingCount =
            int.tryParse(decoded['pending_count']?.toString() ?? '') ??
                int.tryParse(decoded['pending_task_count']?.toString() ?? '') ??
                0;
        clientTimelineCompletedCount =
            int.tryParse(decoded['completed_count']?.toString() ?? '') ?? 0;
        clientTimelineUpcomingCount =
            int.tryParse(decoded['upcoming_count']?.toString() ?? '') ?? 0;

        _applyPendingTasksFromPayload(decoded, null);
        clientTimelineLoaded = true;
        return;
      } catch (e) {
        lastError = e;
        print('[DataProvider] Timeline attempt skipped: $e');
      }
    }

    if (salesSopId == null || salesSopId.isEmpty) {
      if (!isClient) {
        throw Exception(
          'This project does not have a sales SOP id yet, so the timeline cannot load. '
          'Select the project again or contact support.',
        );
      }
    }
    if (lastStatusCode == 401) {
      throw Exception(
        'Unauthorized. Your API token is missing or expired. Please log out and log in again.',
      );
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Unable to load project timeline right now.',
    );
  }

  /// Fetches a sales SOP card:
  /// GET /api/sales_sop_details/{id}/cards/{cardKey}
  Future<Map<String, dynamic>> loadSalesSopCard(String cardKey) async {
    final prefs = await SharedPreferences.getInstance();
    final projectId = prefs.getString('project_id');
    final role = prefs.getString('role');
    final apiToken = _normalizeApiToken(prefs.getString('api_token'));
    currentApiToken = apiToken;
    currentRole = role;

    if (apiToken == null) {
      throw Exception(
        'API token missing. Please log out and log in again.',
      );
    }

    final salesSopId = await resolveSalesSopId(
      projectId: projectId,
      apiToken: apiToken,
    );
    final isClient = role == 'Client';

    if (salesSopId == null || salesSopId.isEmpty) {
      if (!isClient) {
        throw Exception(
          'Could not resolve sales SOP id for this project. '
          'Try selecting the project again or contact support.',
        );
      }
      throw Exception('Sales SOP details are not available yet.');
    }

    final cardPaths = [
      'https://office.buildahome.in/api/sales_sop_details/$salesSopId/cards/$cardKey',
      'https://office.buildahome.in/API/sales_sop_details/$salesSopId/cards/$cardKey',
    ];

    Object? lastError;
    int? lastStatusCode;
    for (final path in cardPaths) {
      try {
        final uri = Uri.parse(path).replace(
          queryParameters: {'api_token': apiToken},
        );
        print('[DataProvider] Loading sales SOP card: $uri');
        final response = await http.get(
          uri,
          headers: _apiAuthHeaders(apiToken),
        ).timeout(const Duration(seconds: 20));

        lastStatusCode = response.statusCode;
        if (response.statusCode != 200) {
          lastError = _timelineErrorMessage(response);
          if (response.statusCode == 401) break;
          continue;
        }

        final body = jsonDecode(response.body);
        if (body is! Map || body['success'] != true) {
          lastError = _timelineErrorMessageFromBody(body) ??
              'Unable to load $cardKey card.';
          continue;
        }

        final decoded = Map<String, dynamic>.from(body);
        await _cacheSalesSopIdFromPayload(decoded, projectId);

        final convertedId = _stringValue(decoded['converted_project_id']);
        if (convertedId != null) {
          await _cacheSalesSopId(salesSopId, convertedId);
        }

        return decoded;
      } catch (e) {
        lastError = e;
        print('[DataProvider] Sales SOP card attempt skipped: $e');
      }
    }

    if (lastStatusCode == 401) {
      throw Exception(
        'Unauthorized. Your API token is missing or expired. Please log out and log in again.',
      );
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Unable to load $cardKey right now.',
    );
  }

  Future<String?> resolveSalesSopId({
    String? projectId,
    required String apiToken,
    bool useCache = true,
    Map<String, dynamic>? projectHint,
    Iterable<dynamic>? tasksHint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final erpProjectId = projectId ?? prefs.getString('project_id');

    // a) Explicit project object
    final fromHint = _salesSopIdFromProjectMap(projectHint, erpProjectId);
    if (fromHint != null) {
      await _cacheSalesSopId(fromHint, erpProjectId);
      print(
        '[DataProvider] Resolved sales_sop_id=$fromHint from project object '
        '(ERP project $erpProjectId)',
      );
      return fromHint;
    }

    if (useCache) {
      final cachedSopId = prefs.getString('sales_sop_id');
      final cachedErpId = prefs.getString('sales_sop_erp_project_id');
      final role = prefs.getString('role');
      // Client: accept cached sales_sop_id even without ERP pairing.
      if (role == 'Client' &&
          cachedSopId != null &&
          cachedSopId.isNotEmpty &&
          _isValidSalesSopId(cachedSopId, null)) {
        clientSalesSopId = cachedSopId;
        return cachedSopId;
      }
      if (cachedSopId != null &&
          cachedSopId.isNotEmpty &&
          cachedErpId == erpProjectId &&
          _isValidSalesSopId(cachedSopId, erpProjectId)) {
        clientSalesSopId = cachedSopId;
        return cachedSopId;
      }
    }

    if (clientSalesSopId != null &&
        _isValidSalesSopId(clientSalesSopId, erpProjectId)) {
      return clientSalesSopId;
    }

    // a2) Selected / matching project in DataProvider.projects
    final fromProjects = _salesSopIdFromProjectsList(erpProjectId);
    if (fromProjects != null) {
      await _cacheSalesSopId(fromProjects, erpProjectId);
      print(
        '[DataProvider] Resolved sales_sop_id=$fromProjects from projects list '
        '(ERP project $erpProjectId)',
      );
      return fromProjects;
    }

    // b) Any loaded task for this project_id (get_tasks already returns sales_sop_id)
    final fromTasks = _salesSopIdFromTasks(tasksHint, erpProjectId) ??
        _salesSopIdFromTasks(_taskSalesSopHints, erpProjectId);
    if (fromTasks != null) {
      await _cacheSalesSopId(fromTasks, erpProjectId);
      print(
        '[DataProvider] Resolved sales_sop_id=$fromTasks from tasks '
        '(ERP project $erpProjectId)',
      );
      return fromTasks;
    }

    // In-memory map populated by cacheSalesSopIdsFromTasks
    if (erpProjectId != null &&
        _projectSalesSopByErpId.containsKey(erpProjectId)) {
      final mapped = _projectSalesSopByErpId[erpProjectId]!;
      await _cacheSalesSopId(mapped, erpProjectId);
      print(
        '[DataProvider] Resolved sales_sop_id=$mapped from task cache map '
        '(ERP project $erpProjectId)',
      );
      return mapped;
    }

    // c) Lookup via sales_sop details (converted_project_id / id)
    final sopContext = await _fetchSalesSopDetailsContext(
      projectId: erpProjectId,
      apiToken: apiToken,
    );
    final salesSopId = _extractSalesSopIdFromContext(sopContext, erpProjectId);
    if (salesSopId != null) {
      await _cacheSalesSopId(salesSopId, erpProjectId);
      print(
        '[DataProvider] Resolved sales_sop_id=$salesSopId from SOP details '
        '(ERP project $erpProjectId)',
      );
      return salesSopId;
    }

    print(
      '[DataProvider] Could not resolve sales_sop_id for ERP project $erpProjectId',
    );
    return null;
  }

  /// Cache sales_sop_id values found on get_tasks / task payloads.
  Future<void> cacheSalesSopIdsFromTasks(Iterable<dynamic> tasks) async {
    _taskSalesSopHints = List<dynamic>.from(tasks);
    for (final task in tasks) {
      if (task is! Map) continue;
      final map = Map<String, dynamic>.from(task);
      final projectId = _stringValue(map['project_id']);
      final sopId = _stringValue(map['sales_sop_id']) ??
          _stringValue(map['sop_id']) ??
          _stringValue(map['sales_sop_project_id']);
      if (projectId != null &&
          sopId != null &&
          _isValidSalesSopId(sopId, projectId)) {
        _projectSalesSopByErpId[projectId] = sopId;
      }

      final title = _stringValue(map['note']) ??
          _stringValue(map['title']) ??
          _stringValue(map['task_title']) ??
          'Task';
      final status = (_stringValue(map['status']) ?? 'pending').toLowerCase();
      final assignee = _stringValue(map['assigned_to_name']) ??
          _stringValue(map['assignee_name']) ??
          _stringValue(map['user_name']) ??
          _stringValue(map['assigned_user_name']) ??
          _displayAssignee(_stringValue(map['assigned_to']));
      final assigneeRole = _stringValue(map['assigned_to_role']) ??
          _stringValue(map['assigned_role']) ??
          _stringValue(map['assignee_role']);
      final isWorkflow = map['is_workflow_task'] == true ||
          map['is_workflow_approval_task'] == true ||
          _stringValue(map['category']) == 'workflow_task';

      final runId = _stringValue(map['workflow_item_run_id']) ??
          _stringValue(map['item_run_id']) ??
          _stringValue(map['workflow_run_id']);
      if (isWorkflow && runId != null) {
        workflowRunMetaById[runId] = {
          'title': title,
          'status': status,
          if (assignee != null) 'assignee': assignee,
          if (assigneeRole != null) 'assignee_role': assigneeRole,
        };
      } else {
        final erpId = _stringValue(map['erp_task_id']) ??
            _stringValue(map['id']);
        if (erpId != null && !erpId.startsWith('-')) {
          final existing = erpTaskMetaById[erpId];
          erpTaskMetaById[erpId] = {
            'title': title,
            'status': status,
            // Prefer newly supplied assignee, else keep any previously cached.
            'assignee': assignee ?? existing?['assignee'] ?? '',
            'assignee_role':
                assigneeRole ?? existing?['assignee_role'] ?? '',
          };
          // Drop empty keys so consumers can treat missing as unset.
          erpTaskMetaById[erpId]!.removeWhere(
            (key, value) =>
                (key == 'assignee' || key == 'assignee_role') && value.isEmpty,
          );
        }
      }
    }

    // If a project is currently selected, refresh its cache from tasks.
    final prefs = await SharedPreferences.getInstance();
    final currentProjectId = prefs.getString('project_id');
    if (currentProjectId != null &&
        _projectSalesSopByErpId.containsKey(currentProjectId)) {
      await _cacheSalesSopId(
        _projectSalesSopByErpId[currentProjectId]!,
        currentProjectId,
      );
    }
  }

  /// Fetch all ERP tasks for [projectId] and merge title/status/assignee into
  /// [erpTaskMetaById] so Chat V1 project-task cards can show Role · Name.
  Future<void> enrichTaskMetaForProject(String projectId) async {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) return;
    try {
      final uri = Uri.parse('https://office.buildahome.in/API/get_tasks')
          .replace(queryParameters: {'project_id': trimmed});
      print('[DataProvider] Enriching chat task meta via $uri');
      final response =
          await ApiHttp.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        print(
          '[DataProvider] get_tasks for project meta failed: '
          '${response.statusCode}',
        );
        return;
      }
      final decoded = jsonDecode(response.body);
      List<dynamic> tasks = const [];
      if (decoded is Map && decoded['tasks'] is List) {
        tasks = decoded['tasks'] as List;
      } else if (decoded is List) {
        tasks = decoded;
      }
      if (tasks.isEmpty) return;
      await cacheSalesSopIdsFromTasks(tasks);
      print(
        '[DataProvider] Cached assignee meta for ${erpTaskMetaById.length} '
        'ERP tasks (project $trimmed)',
      );
    } catch (e) {
      print('[DataProvider] enrichTaskMetaForProject skipped: $e');
    }
  }

  /// Prefer a real display name; ignore bare numeric user ids.
  String? _displayAssignee(String? value) {
    if (value == null || value.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(value)) return null;
    return value;
  }

  String? _salesSopIdFromProjectMap(
    Map<String, dynamic>? project,
    String? erpProjectId,
  ) {
    if (project == null) return null;
    final sopId = _stringValue(project['sales_sop_id']) ??
        _stringValue(project['sales_sop_project_id']) ??
        _stringValue(project['sop_id']);
    if (_isValidSalesSopId(sopId, erpProjectId)) return sopId;
    return null;
  }

  String? _salesSopIdFromProjectsList(String? erpProjectId) {
    if (erpProjectId == null || erpProjectId.isEmpty) {
      // No selected project — use first project that has a sop id.
      for (final p in projects) {
        if (p is! Map) continue;
        final map = Map<String, dynamic>.from(p);
        final sop = _salesSopIdFromProjectMap(map, map['id']?.toString());
        if (sop != null) return sop;
      }
      return null;
    }
    for (final p in projects) {
      if (p is! Map) continue;
      final map = Map<String, dynamic>.from(p);
      final id = _stringValue(map['id']) ?? _stringValue(map['project_id']);
      if (id != erpProjectId) continue;
      return _salesSopIdFromProjectMap(map, erpProjectId);
    }
    return null;
  }

  String? _salesSopIdFromTasks(Iterable<dynamic>? tasks, String? erpProjectId) {
    if (tasks == null) return null;
    for (final task in tasks) {
      if (task is! Map) continue;
      final map = Map<String, dynamic>.from(task);
      final taskProjectId = _stringValue(map['project_id']);
      if (erpProjectId != null &&
          erpProjectId.isNotEmpty &&
          taskProjectId != null &&
          taskProjectId != erpProjectId) {
        continue;
      }
      final sopId = _stringValue(map['sales_sop_id']) ??
          _stringValue(map['sop_id']) ??
          _stringValue(map['sales_sop_project_id']);
      if (_isValidSalesSopId(sopId, erpProjectId ?? taskProjectId)) {
        return sopId;
      }
    }
    return null;
  }

  Future<void> cacheSalesSopIdForProject(
    String salesSopId,
    String erpProjectId,
  ) async {
    if (!_isValidSalesSopId(salesSopId, erpProjectId)) return;
    await _cacheSalesSopId(salesSopId, erpProjectId);
  }

  Future<void> onProjectSelected({
    required String erpProjectId,
    Map<String, dynamic>? project,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken = _normalizeApiToken(prefs.getString('api_token'));
    if (apiToken == null) return;

    String? salesSopId;
    if (project != null) {
      salesSopId = _stringValue(project['sales_sop_id']) ??
          _stringValue(project['sales_sop_project_id']) ??
          _stringValue(project['sop_id']);
    }

    unawaited(ClientGenerationService.instance.refresh(
      projectId: erpProjectId,
      extraPayload: project,
    ));

    if (salesSopId != null && _isValidSalesSopId(salesSopId, erpProjectId)) {
      _projectSalesSopByErpId[erpProjectId] = salesSopId;
      await _cacheSalesSopId(salesSopId, erpProjectId);
      return;
    }

    await resolveSalesSopId(
      projectId: erpProjectId,
      apiToken: apiToken,
      useCache: false,
    );
  }

  Future<void> _cacheSalesSopId(String salesSopId, String? erpProjectId) async {
    clientSalesSopId = salesSopId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sales_sop_id', salesSopId);
    if (erpProjectId != null && erpProjectId.isNotEmpty) {
      await prefs.setString('sales_sop_erp_project_id', erpProjectId);
    }
  }

  Future<void> _cacheSalesSopIdFromPayload(
    Map<String, dynamic> decoded,
    String? erpProjectId,
  ) async {
    final salesSopId = _extractSalesSopId(decoded, null, erpProjectId);
    if (salesSopId != null) {
      await _cacheSalesSopId(salesSopId, erpProjectId);
    }
  }

  void _clearSalesSopIdCacheInMemory() {
    clientSalesSopId = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('sales_sop_id');
      prefs.remove('sales_sop_erp_project_id');
    });
  }

  List<Map<String, dynamic>> _sortTimelineTasks(
    List<Map<String, dynamic>> tasks,
  ) {
    final sorted = List<Map<String, dynamic>>.from(tasks);
    sorted.sort((a, b) {
      final aIdx = int.tryParse(a['order_idx']?.toString() ?? '') ?? 0;
      final bIdx = int.tryParse(b['order_idx']?.toString() ?? '') ?? 0;
      return aIdx.compareTo(bIdx);
    });
    return sorted;
  }

  String? _timelineErrorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return _timelineErrorMessageFromBody(body) ??
          _timelineStatusFallback(response.statusCode);
    } catch (_) {}
    return _timelineStatusFallback(response.statusCode);
  }

  String? _timelineErrorMessageFromBody(dynamic body) {
    if (body is Map && body['message'] != null) {
      return body['message'].toString();
    }
    return null;
  }

  String _timelineStatusFallback(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'Unauthorized. Please log in again.';
      case 404:
        return 'Project not found.';
      case 400:
        return 'Project id is required.';
      default:
        return 'Unable to load timeline ($statusCode)';
    }
  }

  List<Map<String, dynamic>> _parsePendingTaskList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((task) => Map<String, dynamic>.from(task))
        .toList();
  }

  String? _stringValue(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  String? _normalizeApiToken(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  Map<String, String> _apiAuthHeaders(String apiToken) {
    return {
      'X-Api-Token': apiToken,
      'Authorization': 'Bearer $apiToken',
    };
  }

  Future<Map<String, dynamic>?> _fetchSalesSopDetailsContext({
    String? projectId,
    required String apiToken,
  }) async {
    Future<Map<String, dynamic>?> tryUri(Uri uri) async {
      try {
        final response = await ApiHttp.get(
          uri,
          headers: _apiAuthHeaders(apiToken),
        ).timeout(Duration(seconds: 20));
        if (response.statusCode != 200) return null;

        final body = jsonDecode(response.body);
        if (body is! Map) return null;

        final decoded = Map<String, dynamic>.from(body);
        if (decoded['success'] == false) return null;

        final candidate = decoded['api_sales_sop_details'] ??
            decoded['sales_sop_details'] ??
            decoded['data'] ??
            decoded['project'] ??
            decoded;
        final details =
            candidate is Map ? Map<String, dynamic>.from(candidate) : null;

        return {
          'decoded': decoded,
          'details': details,
        };
      } catch (e) {
        print('[DataProvider] SOP details lookup skipped: $e');
        return null;
      }
    }

    final cacheKey = (projectId ?? '').trim();
    final cached = cacheKey.isEmpty
        ? null
        : _workingSopDetailsUriByProject[cacheKey];
    if (cached != null) {
      final hit = await tryUri(cached);
      if (hit != null) return hit;
      _workingSopDetailsUriByProject.remove(cacheKey);
    }

    final queryAttempts = <Map<String, String>>[
      if (projectId != null && projectId.isNotEmpty)
        {'project_id': projectId, 'api_token': apiToken},
      if (projectId != null && projectId.isNotEmpty)
        {'id': projectId, 'api_token': apiToken},
      {'api_token': apiToken},
    ];

    final detailPaths = [
      'https://office.buildahome.in/API/sales_sop_details',
      'https://office.buildahome.in/api/sales_sop_details',
    ];

    for (final basePath in detailPaths) {
      for (final query in queryAttempts) {
        final uri = Uri.parse(basePath).replace(queryParameters: query);
        final hit = await tryUri(uri);
        if (hit != null) {
          if (cacheKey.isNotEmpty) {
            _workingSopDetailsUriByProject[cacheKey] = uri;
          }
          return hit;
        }
      }
    }
    return null;
  }

  String? _extractSalesSopIdFromContext(
    Map<String, dynamic>? context,
    String? erpProjectId,
  ) {
    if (context == null) return null;
    final decoded = context['decoded'] as Map<String, dynamic>?;
    final details = context['details'] as Map<String, dynamic>?;
    return _extractSalesSopId(decoded, details, erpProjectId);
  }

  String? _extractSalesSopId(
    Map<String, dynamic>? decoded,
    Map<String, dynamic>? details,
    String? erpProjectId,
  ) {
    if (decoded != null) {
      final topLevel = _stringValue(decoded['sales_sop_id']);
      if (_isValidSalesSopId(topLevel, erpProjectId)) return topLevel;

      if (decoded['project'] is Map) {
        final project = Map<String, dynamic>.from(decoded['project'] as Map);
        final fromProject = _stringValue(project['sales_sop_id']) ??
            _stringValue(project['id']);
        if (_isValidSalesSopId(fromProject, erpProjectId)) return fromProject;
      }
    }

    if (details != null) {
      final fromDetails = _stringValue(details['sales_sop_id']);
      if (_isValidSalesSopId(fromDetails, erpProjectId)) return fromDetails;

      if (details['project'] is Map) {
        final project = Map<String, dynamic>.from(details['project'] as Map);
        final fromNestedProject = _stringValue(project['sales_sop_id']) ??
            _stringValue(project['id']);
        if (_isValidSalesSopId(fromNestedProject, erpProjectId)) {
          return fromNestedProject;
        }
      }

      final detailsId = _stringValue(details['id']);
      if (_isValidSalesSopId(detailsId, erpProjectId)) return detailsId;
    }

    return null;
  }

  bool _isValidSalesSopId(String? salesSopId, String? erpProjectId) {
    if (salesSopId == null || salesSopId.isEmpty) return false;
    if (erpProjectId != null &&
        erpProjectId.isNotEmpty &&
        salesSopId == erpProjectId) {
      return false;
    }
    return true;
  }

  Future<void> _loadPendingTasksFromEndpoint(
    String salesSopId,
    String apiToken,
    String projectId,
  ) async {
    final endpointAttempts = <Map<String, dynamic>>[
      {
        'uri': Uri.parse(
            'https://office.buildahome.in/API/sales_sop_pending_tasks/$salesSopId'),
        'query': {'api_token': apiToken},
      },
      {
        'uri': Uri.parse(
            'https://office.buildahome.in/API/sales_sop_pending_tasks'),
        'query': {
          'api_token': apiToken,
          'sales_sop_id': salesSopId,
          'project_id': projectId,
        },
      },
    ];

    for (final attempt in endpointAttempts) {
      try {
        final uri = (attempt['uri'] as Uri).replace(
          queryParameters:
              Map<String, String>.from(attempt['query'] as Map<String, String>),
        );
        final response = await ApiHttp.get(
          uri,
          headers: _apiAuthHeaders(apiToken),
        ).timeout(Duration(seconds: 20));
        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body);
        if (body is! Map || body['success'] != true) continue;

        clientPendingTasks = _parsePendingTaskList(body['pending_tasks']);
        if (clientPendingTasks.isEmpty) {
          clientPendingTasks =
              _parsePendingTaskList(body['pending_timeline_tasks']);
        }
        clientPendingTaskCount =
            int.tryParse(body['pending_task_count']?.toString() ?? '') ??
                clientPendingTasks.length;
        final current = body['current_pending_task'];
        clientCurrentPendingTask = current is Map
            ? Map<String, dynamic>.from(current)
            : (clientPendingTasks.isNotEmpty ? clientPendingTasks.first : null);
        break;
      } catch (e) {
        print('[DataProvider] Pending tasks attempt skipped: $e');
      }
    }

    clientPendingTasksLoaded = true;
  }

  // Helper method to load project location
  Future<void> _loadProjectLocation(String projectId) async {
    try {
      var locationUrl =
          'https://office.buildahome.in/API/get_project_location?id=${projectId}';
      var locResponse = await ApiHttp.get(Uri.parse(locationUrl));
      if (locResponse.statusCode == 200 && locResponse.body.trim().isNotEmpty) {
        clientProjectLocation = locResponse.body.trim();
      }
    } catch (e) {
      print('Error loading project location: $e');
    }
  }

  // Helper method to load project completion percentage
  Future<void> _loadProjectPercentage(
      String projectId, SharedPreferences prefs) async {
    try {
      var percUrl =
          'https://office.buildahome.in/API/get_project_percentage?id=${projectId}';
      var percResponse = await ApiHttp.get(Uri.parse(percUrl));
      print('percentage response: ${percResponse.body}');
      if (percResponse.statusCode == 200) {
        clientProjectCompletion = percResponse.body;
        // Only save to SharedPreferences for Client users
        if (currentRole == 'Client') {
          prefs.setString('completed', percResponse.body);
        }
      } else if (currentRole == 'Client' && prefs.containsKey("completed")) {
        // Only fallback to SharedPreferences for Client users
        clientProjectCompletion = prefs.getString('completed');
      } else {
        // For non-Client users or when API fails, return null to indicate data not loaded
        clientProjectCompletion = null;
      }
    } catch (e) {
      print('Error loading project percentage: $e');
      // Fallback to SharedPreferences for Client users on error
      if (currentRole == 'Client' && prefs.containsKey("completed")) {
        clientProjectCompletion = prefs.getString('completed');
      } else {
        clientProjectCompletion = null;
      }
    }
  }

  // Helper method to load latest updates
  Future<void> _loadLatestUpdates(String projectId, SharedPreferences prefs,
      {bool skipIfRecent = false}) async {
    // Skip if already loading updates to prevent duplicate calls
    if (isLoadingUpdates) {
      print(
          '[DataProvider] Skipping latest updates load - already in progress');
      // Wait for the current load to complete
      while (isLoadingUpdates) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return;
    }

    // Skip if updates were loaded recently (within last 2 seconds) to prevent duplicate calls
    if (skipIfRecent &&
        lastUpdatesLoad != null &&
        DateTime.now().difference(lastUpdatesLoad!).inSeconds < 2) {
      print(
          '[DataProvider] Skipping latest updates load - already loaded recently');
      return;
    }

    isLoadingUpdates = true;
    try {
      print('[DataProvider] Loading latest updates for project $projectId');
      var updatesUrl =
          'https://office.buildahome.in/API/latest_update?id=${projectId}';
      var updatesResponse =
          await http.get(Uri.parse(updatesUrl)).timeout(Duration(seconds: 15));

      if (updatesResponse.statusCode == 200 &&
          updatesResponse.body.trim() != "No updates") {
        clientProjectUpdates = jsonDecode(updatesResponse.body);
        lastUpdatesLoad = DateTime.now();
        print(
            '[DataProvider] Successfully loaded ${clientProjectUpdates is List ? clientProjectUpdates.length : 0} updates');
      } else if (updatesResponse.statusCode == 200 &&
          updatesResponse.body.trim() == "No updates") {
        // API returned "No updates" - set to empty list to indicate data was loaded but is empty
        // For non-Client users, use empty list; for Client users, check SharedPreferences
        if ((currentRole ?? '').trim().toLowerCase() != 'client') {
          clientProjectUpdates = [];
        } else {
          // For Client users, check SharedPreferences as fallback
          var savedUpdates = prefs.getString('latest_update');
          if (savedUpdates != null && savedUpdates.isNotEmpty) {
            try {
              clientProjectUpdates = jsonDecode(savedUpdates);
            } catch (e) {
              clientProjectUpdates = [];
            }
          } else {
            clientProjectUpdates = [];
          }
        }
        lastUpdatesLoad = DateTime.now();
        print('[DataProvider] No updates returned from API');
      } else {
        // API call failed - set to null to indicate data not loaded
        print(
            '[DataProvider] Failed to load updates: status ${updatesResponse.statusCode}');
        // For non-Client users, always set to null (never load from SharedPreferences)
        if ((currentRole ?? '').trim().toLowerCase() != 'client') {
          clientProjectUpdates = null;
        } else {
          // Only for Client users, check SharedPreferences as fallback
          var savedUpdates = prefs.getString('latest_update');
          if (savedUpdates != null && savedUpdates.isNotEmpty) {
            try {
              clientProjectUpdates = jsonDecode(savedUpdates);
            } catch (e) {
              clientProjectUpdates = null;
            }
          } else {
            clientProjectUpdates = null;
          }
        }
      }
    } catch (e) {
      print('[DataProvider] Error loading latest updates: $e');
      // On error, handle fallback for Client users
      if ((currentRole ?? '').trim().toLowerCase() != 'client') {
        clientProjectUpdates = null;
      } else {
        var savedUpdates = prefs.getString('latest_update');
        if (savedUpdates != null && savedUpdates.isNotEmpty) {
          try {
            clientProjectUpdates = jsonDecode(savedUpdates);
          } catch (e) {
            clientProjectUpdates = null;
          }
        } else {
          clientProjectUpdates = null;
        }
      }
    } finally {
      isLoadingUpdates = false;
    }
  }

  // Load latest updates independently (for immediate loading when project is selected)
  Future<void> loadLatestUpdatesForProject(String projectId) async {
    if (projectId.isEmpty) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Update currentRole if not set
    if (currentRole == null) {
      currentRole = prefs.getString('role');
    }

    // Load updates independently without blocking on other data
    await _loadLatestUpdates(projectId, prefs);
  }

  // Helper method to load project block status
  Future<void> _loadProjectBlockStatus(String projectId) async {
    try {
      var statusUrl =
          'https://office.buildahome.in/API/get_project_block_status?project_id=${projectId}';
      var statusResponse = await ApiHttp.get(Uri.parse(statusUrl));
      if (statusResponse.statusCode == 200) {
        var statusResponseBody = jsonDecode(statusResponse.body);
        if (statusResponseBody['status'] == 'blocked') {
          clientProjectBlocked = true;
          clientProjectBlockReason = statusResponseBody['reason'];
        } else {
          clientProjectBlocked = false;
          clientProjectBlockReason = null;
        }
      }
    } catch (e) {
      print('Error loading project block status: $e');
    }
  }

  // Initialize data based on user role
  Future<void> initializeData({bool force = false}) => openHome(force: force);

  /// Single Home/boot coordinator. Dedupes overlapping callers (login, Home,
  /// dashboard) and skips a network round-trip when data is still fresh.
  Future<void> openHome({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role') ?? currentRole;
    currentUserId =
        prefs.getString('userId') ?? prefs.getString('user_id') ?? currentUserId;
    currentApiToken = prefs.getString('api_token') ?? currentApiToken;

    if (currentRole == null) return;

    final isClient = currentRole!.trim().toLowerCase() == 'client';
    var projectId = prefs.getString('project_id')?.trim();
    if (isClient && (projectId == null || projectId.isEmpty)) {
      projectId = await ensureClientProjectSelected();
    }

    final key = '${currentRole}|${currentUserId}|${projectId ?? ''}';
    if (_openHomeInFlight != null && _openHomeKey == key && !force) {
      await _openHomeInFlight;
      return;
    }

    final future = _openHomeInternal(
      force: force,
      isClient: isClient,
      projectId: projectId,
    );
    _openHomeInFlight = future;
    _openHomeKey = key;
    try {
      await future;
    } finally {
      if (identical(_openHomeInFlight, future)) {
        _openHomeInFlight = null;
        _openHomeKey = null;
      }
    }
  }

  Future<void> _openHomeInternal({
    required bool force,
    required bool isClient,
    String? projectId,
  }) async {
    unawaited(
      ClientGenerationService.instance.ensureLoaded(projectId: projectId),
    );

    final work = <Future<void>>[];
    if (projectId != null && projectId.isNotEmpty) {
      work.add(loadProjectDataForProject(projectId, force: force));
      work.add(loadProjectTimeline(force: force));
    }
    if (!isClient) {
      work.add(loadProjects(force: force));
    }
    if (work.isEmpty) return;
    await Future.wait(work, eagerError: false);
  }

  /// Ensures a Client has `project_id` in SharedPreferences.
  ///
  /// OTP login often omits project fields for legacy clients. Falls back to:
  /// 1) existing prefs, 2) get_projects_for_user, 3) get_tasks, 4) sales_sop_details.
  Future<String?> ensureClientProjectSelected({
    Map<String, dynamic>? loginPayload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role') ?? currentRole;
    currentUserId =
        prefs.getString('userId') ?? prefs.getString('user_id') ?? currentUserId;
    currentApiToken = prefs.getString('api_token') ?? currentApiToken;

    String? projectId = prefs.getString('project_id')?.trim();
    if (_isValidId(projectId)) {
      print('[DataProvider] Using existing project_id=$projectId');
      return projectId;
    }

    // Prefer ids from the login / verify payload (top-level or nested).
    projectId = _extractProjectIdFromMap(loginPayload) ??
        _extractProjectIdFromMap(
          loginPayload != null && loginPayload['user'] is Map
              ? Map<String, dynamic>.from(loginPayload['user'] as Map)
              : null,
        );
    if (_isValidId(projectId)) {
      await _persistClientProjectContext(
        projectId: projectId!,
        source: loginPayload,
      );
      return projectId;
    }

    projectId = await _resolveProjectIdFromProjectsApi();
    if (_isValidId(projectId)) {
      return projectId;
    }

    projectId = await _resolveProjectIdFromTasksApi();
    if (_isValidId(projectId)) {
      return projectId;
    }

    projectId = await _resolveProjectIdFromSalesSopDetails();
    if (_isValidId(projectId)) {
      return projectId;
    }

    print('[DataProvider] Unable to resolve client project_id');
    return null;
  }

  bool _isValidId(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }

  String? _extractProjectIdFromMap(Map<String, dynamic>? source) {
    if (source == null) return null;
    final direct = _stringValue(source['project_id']) ??
        _stringValue(source['converted_project_id']) ??
        _stringValue(source['erp_project_id']) ??
        _stringValue(source['projectId']) ??
        _stringValue(source['id']);
    if (_isValidId(direct) &&
        (source.containsKey('project_id') ||
            source.containsKey('converted_project_id') ||
            source.containsKey('erp_project_id') ||
            source.containsKey('projectId'))) {
      return direct;
    }

    final project = source['project'];
    if (project is Map) {
      final nested = _stringValue(project['id']) ??
          _stringValue(project['project_id']) ??
          _stringValue(project['converted_project_id']);
      if (_isValidId(nested)) return nested;
    }

    final projects = source['projects'];
    if (projects is List && projects.isNotEmpty) {
      final first = projects.first;
      if (first is Map) {
        final nested = _stringValue(first['id']) ??
            _stringValue(first['project_id']) ??
            _stringValue(first['converted_project_id']);
        if (_isValidId(nested)) return nested;
      }
    }
    return null;
  }

  Future<void> _persistClientProjectContext({
    required String projectId,
    Map<String, dynamic>? source,
    String? projectName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('project_id', projectId);
    clientProjectId = projectId;

    final name = projectName ??
        _stringValue(source?['client_name']) ??
        _stringValue(source?['project_name']) ??
        _stringValue(source?['name']);
    if (name != null && name.trim().isNotEmpty && name.toLowerCase() != 'null') {
      await prefs.setString('client_name', name.trim());
    }

    final value = _stringValue(source?['project_value']) ??
        _stringValue(source?['value']);
    if (value != null && value.isNotEmpty) {
      await prefs.setString('project_value', value);
      clientProjectValue = value;
    }

    final completed = _stringValue(source?['completed_percentage']) ??
        _stringValue(source?['completed']) ??
        _stringValue(source?['percentage']);
    if (completed != null && completed.isNotEmpty) {
      await prefs.setString('completed', completed);
      clientProjectCompletion = completed;
    }

    final location = _stringValue(source?['location']);
    if (location != null && location.isNotEmpty) {
      await prefs.setString('location', location);
      clientProjectLocation = location;
    }

    final sopId = _stringValue(source?['sales_sop_id']) ??
        _stringValue(source?['sop_id']);
    if (sopId != null && sopId.isNotEmpty) {
      await prefs.setString('sales_sop_id', sopId);
      await prefs.setString('sales_sop_erp_project_id', projectId);
      clientSalesSopId = sopId;
    }

    print('[DataProvider] Persisted client project_id=$projectId');
  }

  Future<String?> _resolveProjectIdFromProjectsApi() async {
    final userId = currentUserId?.trim();
    final token = currentApiToken?.trim();
    final role = currentRole?.trim();
    if (userId == null ||
        userId.isEmpty ||
        token == null ||
        token.isEmpty ||
        role == null ||
        role.isEmpty) {
      return null;
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://office1.buildahome.in/API/get_projects_for_user'),
            body: {
              'user_id': userId,
              'role': role,
              'api_token': token,
            },
            headers: {'X-Api-Token': token},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        print(
            '[DataProvider] get_projects_for_user failed: ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(response.body);
      List<dynamic> list = [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['projects'] is List) {
        list = decoded['projects'] as List;
      }
      if (list.isEmpty) return null;

      final first = list.first;
      if (first is! Map) return null;
      final map = Map<String, dynamic>.from(first);
      final projectId = _stringValue(map['id']) ??
          _stringValue(map['project_id']) ??
          _stringValue(map['converted_project_id']);
      if (!_isValidId(projectId)) return null;

      await _persistClientProjectContext(
        projectId: projectId!,
        source: map,
        projectName: _stringValue(map['name']) ??
            _stringValue(map['client_name']) ??
            _stringValue(map['project_name']),
      );
      return projectId;
    } catch (e) {
      print('[DataProvider] get_projects_for_user error: $e');
      return null;
    }
  }

  Future<String?> _resolveProjectIdFromTasksApi() async {
    final userId = currentUserId?.trim();
    final token = currentApiToken?.trim();
    if (userId == null || userId.isEmpty) return null;

    try {
      final query = <String, String>{
        'user_id': userId,
        'assigned_to': userId,
        if (token != null && token.isNotEmpty) 'api_token': token,
      };
      final response = await http
          .get(
            Uri.parse('https://office.buildahome.in/API/get_tasks')
                .replace(queryParameters: query),
            headers: {
              if (token != null && token.isNotEmpty) 'X-Api-Token': token,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      List<dynamic> tasks = [];
      if (decoded is Map && decoded['tasks'] is List) {
        tasks = decoded['tasks'] as List;
      } else if (decoded is List) {
        tasks = decoded;
      }
      for (final task in tasks) {
        if (task is! Map) continue;
        final projectId = _stringValue(task['project_id']) ??
            _stringValue(task['erp_project_id']);
        if (_isValidId(projectId)) {
          await _persistClientProjectContext(
            projectId: projectId!,
            source: Map<String, dynamic>.from(task),
            projectName: _stringValue(task['project_name']) ??
                _stringValue(task['client_name']),
          );
          return projectId;
        }
      }
    } catch (e) {
      print('[DataProvider] get_tasks project resolve error: $e');
    }
    return null;
  }

  Future<String?> _resolveProjectIdFromSalesSopDetails() async {
    final token = currentApiToken?.trim();
    if (token == null || token.isEmpty) return null;

    final urls = [
      'https://office.buildahome.in/API/sales_sop_details',
      'https://office.buildahome.in/api/sales_sop_details',
      'https://office1.buildahome.in/API/sales_sop_details',
      'https://office1.buildahome.in/api/sales_sop_details',
    ];

    for (final base in urls) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: {
          'api_token': token,
        });
        final response = await http
            .get(uri, headers: {'X-Api-Token': token, 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        final projectId = _extractProjectIdFromMap(map) ??
            _extractProjectIdFromMap(
              map['project'] is Map
                  ? Map<String, dynamic>.from(map['project'] as Map)
                  : null,
            ) ??
            _stringValue(map['converted_project_id']);
        if (_isValidId(projectId)) {
          await _persistClientProjectContext(
            projectId: projectId!,
            source: map,
          );
          return projectId;
        }
      } catch (e) {
        print('[DataProvider] sales_sop_details resolve error: $e');
      }
    }
    return null;
  }

  // Load project data for non-Client users (payments, gallery, schedule, notes, documents)
  Future<void> loadProjectDataForNonClient(String projectId) async {
    if (isLoadingProjectData) return;
    if (currentRole == 'Client') return;

    isLoadingProjectData = true;
    try {
      await Future.wait([
        _loadPaymentsData(projectId),
        _loadGalleryData(projectId),
        _loadScheduleData(projectId),
        _loadNotesData(projectId),
        _loadDocumentsData(projectId),
      ], eagerError: false);
    } catch (e) {
      print('[DataProvider] Error loading project data: $e');
    } finally {
      isLoadingProjectData = false;
    }
  }

  Future<void> _loadPaymentsData(String projectId) async {
    try {
      final paymentUrl =
          'https://office.buildahome.in/API/get_payment?project_id=$projectId';
      final paymentResponse =
          await ApiHttp.get(Uri.parse(paymentUrl)).timeout(Duration(seconds: 15));
      if (paymentResponse.statusCode == 200) {
        final data = jsonDecode(paymentResponse.body);
        cachedPayments = (data is List && data.isNotEmpty) ? data[0] : {};
        lastPaymentsLoad = DateTime.now();
      }
    } catch (e) {
      print('[DataProvider] Error loading payments: $e');
    }
  }

  Future<void> _loadGalleryData(String projectId) async {
    try {
      final url =
          'https://office.buildahome.in/API/get_gallery_data?id=$projectId';
      final response =
          await ApiHttp.get(Uri.parse(url)).timeout(Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        cachedGallery = data is List ? data : [];
        lastGalleryLoad = DateTime.now();
      }
    } catch (e) {
      print('[DataProvider] Error loading gallery: $e');
    }
  }

  Future<void> _loadScheduleData(String projectId) async {
    try {
      final url =
          'https://office.buildahome.in/API/get_all_tasks?project_id=$projectId&nt_toggle=0';
      final response =
          await ApiHttp.get(Uri.parse(url)).timeout(Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        cachedSchedule = data is List ? data : [];
        lastScheduleLoad = DateTime.now();
      }
    } catch (e) {
      print('[DataProvider] Error loading schedule: $e');
    }
  }

  Future<void> _loadNotesData(String projectId) async {
    try {
      final url =
          'https://office.buildahome.in/API/get_notes?project_id=$projectId';
      final response =
          await ApiHttp.get(Uri.parse(url)).timeout(Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        cachedNotes = data is List ? data : [];
        lastNotesLoad = DateTime.now();
      }
    } catch (e) {
      print('[DataProvider] Error loading notes: $e');
    }
  }

  Future<void> _loadDocumentsData(String projectId) async {
    try {
      final url =
          'https://office.buildahome.in/API/view_all_documents?id=$projectId';
      final response =
          await ApiHttp.get(Uri.parse(url)).timeout(Duration(seconds: 15));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = jsonDecode(response.body);
        cachedDocuments = data is List ? data : [];
        lastDocumentsLoad = DateTime.now();
      }
    } catch (e) {
      print('[DataProvider] Error loading documents: $e');
    }
  }

  /// Shared get_tasks fetch used by Home, My Tasks, and View All Tasks.
  Future<List<dynamic>> loadUserTasks({
    bool force = false,
    String? projectId,
    bool applyProjectId = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role') ?? currentRole;
    currentUserId =
        prefs.getString('userId') ?? prefs.getString('user_id') ?? currentUserId;
    currentApiToken = prefs.getString('api_token') ?? currentApiToken;
    final resolvedProjectId =
        (projectId ?? prefs.getString('project_id'))?.trim();

    if (currentUserId == null || currentApiToken == null) {
      return cachedUserTasks;
    }

    final isClient = (currentRole ?? '').trim().toLowerCase() == 'client';
    final applyProject =
        applyProjectId || isClient;
    final cacheKey =
        '${currentUserId}|${applyProject ? resolvedProjectId ?? '' : ''}';

    if (!force &&
        lastUserTasksLoad != null &&
        DateTime.now().difference(lastUserTasksLoad!) < _tasksTtl &&
        cachedUserTasks.isNotEmpty &&
        _userTasksInFlightKey == cacheKey) {
      return cachedUserTasks;
    }

    if (_userTasksInFlight != null &&
        _userTasksInFlightKey == cacheKey &&
        !force) {
      await _userTasksInFlight;
      return cachedUserTasks;
    }

    final future = _fetchUserTasks(
      userId: currentUserId!,
      apiToken: currentApiToken!,
      projectId: applyProject ? resolvedProjectId : null,
    );
    _userTasksInFlight = future;
    _userTasksInFlightKey = cacheKey;
    try {
      await future;
    } finally {
      if (identical(_userTasksInFlight, future)) {
        _userTasksInFlight = null;
      }
    }
    return cachedUserTasks;
  }

  Future<void> _fetchUserTasks({
    required String userId,
    required String apiToken,
    String? projectId,
  }) async {
    final queryParams = <String, String>{
      'user_id': userId,
      'assigned_to': userId,
      'api_token': apiToken,
    };
    if (projectId != null && projectId.isNotEmpty) {
      queryParams['project_id'] = projectId;
    }

    final uri = Uri.parse('https://office.buildahome.in/API/get_tasks')
        .replace(queryParameters: queryParams);
    final response =
        await ApiHttp.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return;

    final decoded = jsonDecode(response.body);
    List<dynamic> fetched = [];
    if (decoded is Map && decoded['tasks'] is List) {
      fetched = decoded['tasks'];
    } else if (decoded is List) {
      fetched = decoded;
    }

    final taskMap = <String, dynamic>{};
    for (final task in fetched) {
      if (task is Map && task['id'] != null) {
        final id = task['id'].toString().trim();
        if (id.isNotEmpty && id != '0') taskMap[id] = task;
      }
    }
    cachedUserTasks = taskMap.values.toList();
    lastUserTasksLoad = DateTime.now();
    await cacheSalesSopIdsFromTasks(cachedUserTasks);
  }

  // Reload data (used when navigating to screens)
  Future<void> reloadData({bool force = false}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var role = prefs.getString('role');

    if (role == null) {
      return;
    }

    currentRole = role;
    var projectId = prefs.getString('project_id')?.trim();
    final isClient = role.trim().toLowerCase() == 'client';

    if (projectId != null &&
        projectId.isNotEmpty &&
        (force ||
            lastClientDataLoad == null ||
            DateTime.now().difference(lastClientDataLoad!) > _homeDataTtl)) {
      await loadProjectDataForProject(projectId, force: force);
    } else if (isClient && (projectId == null || projectId.isEmpty)) {
      print('[DataProvider] reloadData: Client missing project_id');
    }
  }

  // Reset project data (for switching projects from AdminDashboard)
  void resetProjectData() {
    clientProjectLocation = null;
    clientSalesSopId = null;
    _clearSalesSopIdCacheInMemory();
    clientProjectCompletion = null;
    clientProjectUpdates = null;
    clientProjectBlocked = null;
    clientProjectBlockReason = null;
    clientProjectValue = null;
    clientWorkflowDashboardSlots = [];
    clientPendingTasks = [];
    clientPendingTaskCount = 0;
    clientCurrentPendingTask = null;
    clientPendingTasksLoaded = false;
    clientTimelineTasks = [];
    clientTimelineTaskCount = 0;
    clientTimelinePendingCount = 0;
    clientTimelineCompletedCount = 0;
    clientTimelineUpcomingCount = 0;
    clientTimelineLoaded = false;
    lastClientDataLoad = null;
    lastUpdatesLoad = null;
    lastUserTasksLoad = null;
    cachedUserTasks = [];
    _workingSopDetailsUriByProject.clear();
    _projectDataInFlight = null;
    _projectDataInFlightId = null;

    // Clear cached project data
    cachedPayments = null;
    cachedGallery = null;
    cachedSchedule = null;
    cachedNotes = null;
    cachedDocuments = null;
    lastPaymentsLoad = null;
    lastGalleryLoad = null;
    lastScheduleLoad = null;
    lastNotesLoad = null;
    lastDocumentsLoad = null;
    MobileDocumentsService.instance.clearMemory();

    print('[DataProvider] Project data reset');
  }

  // Clear all data (for logout)
  void clearData() {
    projects = [];
    clientProjectId = null;
    clientSalesSopId = null;
    _projectSalesSopByErpId.clear();
    _taskSalesSopHints = [];
    erpTaskMetaById.clear();
    workflowRunMetaById.clear();
    _clearSalesSopIdCacheInMemory();
    clientProjectLocation = null;
    clientProjectCompletion = null;
    clientProjectUpdates = null;
    clientProjectBlocked = null;
    clientProjectBlockReason = null;
    clientProjectValue = null;
    clientWorkflowDashboardSlots = [];
    clientPendingTasks = [];
    clientPendingTaskCount = 0;
    clientCurrentPendingTask = null;
    clientPendingTasksLoaded = false;
    clientTimelineTasks = [];
    clientTimelineTaskCount = 0;
    clientTimelinePendingCount = 0;
    clientTimelineCompletedCount = 0;
    clientTimelineUpcomingCount = 0;
    clientTimelineLoaded = false;
    lastProjectsLoad = null;
    lastClientDataLoad = null;
    lastUpdatesLoad = null;
    lastUserTasksLoad = null;
    cachedUserTasks = [];
    _workingSopDetailsUriByProject.clear();
    _openHomeInFlight = null;
    _openHomeKey = null;
    _projectDataInFlight = null;
    _projectDataInFlightId = null;
    _userTasksInFlight = null;
    _userTasksInFlightKey = null;
    currentRole = null;
    currentUserId = null;
    currentApiToken = null;

    // Clear loading flags to prevent stale state
    projectsLoading = false;
    clientDataLoading = false;
    isLoadingUpdates = false;
    isLoadingProjectData = false;

    // Clear cached project data
    cachedPayments = null;
    cachedGallery = null;
    cachedSchedule = null;
    cachedNotes = null;
    cachedDocuments = null;
    lastPaymentsLoad = null;
    lastGalleryLoad = null;
    lastScheduleLoad = null;
    lastNotesLoad = null;
    lastDocumentsLoad = null;
    MobileDocumentsService.instance.clearMemory();

    print('[DataProvider] All data cleared');
    ClientGenerationService.instance.clearMemory();
  }
}
