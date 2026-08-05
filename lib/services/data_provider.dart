import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_http.dart';
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
        projects = []; // Clear projects on error
      }
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print('[DataProvider] Error loading projects: $e');
      projects = []; // Clear projects on error
    } finally {
      projectsLoading = false;
    }
  }

  // Load project data for Client users
  Future<void> loadClientProjectData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role');

    if (currentRole != 'Client') {
      return; // Don't load client data for non-clients
    }

    var projectId = prefs.getString('project_id');
    if (projectId == null) {
      return;
    }

    await _loadProjectData(projectId);
  }

  Future<void> loadProjectDataForProject(String projectId) async {
    await _loadProjectData(projectId);
  }

  Future<void> _loadProjectData(String projectId) async {
    // Allow concurrent loads for updates - they're lightweight and should load independently
    // Only prevent concurrent loads if we're loading the same project
    if (clientDataLoading && clientProjectId == projectId) {
      // If already loading the same project, wait for it to complete
      while (clientDataLoading && clientProjectId == projectId) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Update currentRole if not set
    if (currentRole == null) {
      currentRole = prefs.getString('role');
    }

    clientProjectId = projectId;
    clientDataLoading = true;

    print('[DataProvider] Loading project data for project $projectId');
    print('[DataProvider] Current role: $currentRole');
    print('[DataProvider] Current user id: $currentUserId');

    // For non-Client users, explicitly set to null at start to ensure skeleton loader shows
    if (currentRole != 'Client') {
      clientProjectUpdates = null;
    }

    // Load project value from SharedPreferences (synchronous, no API call needed)
    if (currentRole == 'Client') {
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
      await Future.wait([
        _loadLatestUpdates(projectId, prefs, skipIfRecent: true),
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
          if (response.statusCode == 401) {
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

    clientTimelineLoaded = true;
    if (lastStatusCode == 401) {
      throw Exception(
        'Unauthorized. Your API token is missing or expired. Please log out and log in again.',
      );
    }
    if (salesSopId == null && !isClient) {
      throw Exception(
        'Could not resolve sales SOP id for this project. '
        'Try selecting the project again or contact support.',
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final erpProjectId = projectId ?? prefs.getString('project_id');

    if (useCache) {
      final cachedSopId = prefs.getString('sales_sop_id');
      final cachedErpId = prefs.getString('sales_sop_erp_project_id');
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

    final sopContext = await _fetchSalesSopDetailsContext(
      projectId: erpProjectId,
      apiToken: apiToken,
    );
    final salesSopId = _extractSalesSopIdFromContext(sopContext, erpProjectId);
    if (salesSopId != null) {
      await _cacheSalesSopId(salesSopId, erpProjectId);
      return salesSopId;
    }

    print(
      '[DataProvider] Could not resolve sales_sop_id for ERP project $erpProjectId',
    );
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

    if (salesSopId != null && _isValidSalesSopId(salesSopId, erpProjectId)) {
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
        try {
          final uri = Uri.parse(basePath).replace(queryParameters: query);
          final response = await ApiHttp.get(
            uri,
            headers: _apiAuthHeaders(apiToken),
          ).timeout(Duration(seconds: 20));
          if (response.statusCode != 200) continue;

          final body = jsonDecode(response.body);
          if (body is! Map) continue;

          final decoded = Map<String, dynamic>.from(body);
          if (decoded['success'] == false) continue;

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
          await ApiHttp.get(Uri.parse(updatesUrl)).timeout(Duration(seconds: 15));

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
        if (currentRole != 'Client') {
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
        if (currentRole != 'Client') {
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
      if (currentRole != 'Client') {
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
  Future<void> initializeData({bool force = false}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var role = prefs.getString('role');

    if (role == null) {
      return;
    }

    // Ensure we have fresh credentials
    currentRole = role;
    currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');
    currentApiToken = prefs.getString('api_token');

    if (role == 'Client') {
      await loadClientProjectData();
    } else {
      // Force reload projects after login to ensure fresh data
      await loadProjects(force: force);
    }
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

  // Reload data (used when navigating to screens)
  Future<void> reloadData({bool force = false}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var role = prefs.getString('role');

    if (role == null) {
      return;
    }

    var projectId = prefs.getString('project_id');

    if (role == 'Client') {
      // Force reload client data if forced or if data is stale (older than 5 minutes)
      if (force ||
          lastClientDataLoad == null ||
          DateTime.now().difference(lastClientDataLoad!).inMinutes > 5) {
        await loadClientProjectData();
      }
    } else {
      // Load project data (including updates) first - this is critical for showing updates immediately
      if (projectId != null &&
          (force ||
              lastClientDataLoad == null ||
              DateTime.now().difference(lastClientDataLoad!).inMinutes > 5)) {
        await loadProjectDataForProject(projectId);
      }

      // Note: loadProjects() should only be called from AdminDashboard, not from UserDashboard
      // Removed from here to prevent unnecessary loading in UserDashboard

      // Load project data for non-Client users (payments, gallery, etc.) in background
      // This should not block the updates from showing
      if (projectId != null) {
        final shouldLoad = force ||
            lastPaymentsLoad == null ||
            lastGalleryLoad == null ||
            lastScheduleLoad == null ||
            lastNotesLoad == null ||
            lastDocumentsLoad == null ||
            DateTime.now().difference(lastPaymentsLoad!).inMinutes > 5;

        if (shouldLoad) {
          // Don't await - let this run in background so updates can show immediately
          loadProjectDataForNonClient(projectId).catchError((e) {
            print(
                '[DataProvider] Error loading project data in background: $e');
          });
        }
      }
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

    print('[DataProvider] Project data reset');
  }

  // Clear all data (for logout)
  void clearData() {
    projects = [];
    clientProjectId = null;
    clientSalesSopId = null;
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

    print('[DataProvider] All data cleared');
  }
}
