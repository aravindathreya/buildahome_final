import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  String? clientProjectLocation;
  String? clientProjectCompletion;
  dynamic clientProjectUpdates;
  bool? clientProjectBlocked;
  String? clientProjectBlockReason;
  String? clientProjectValue;
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

    if (currentRole == null || currentUserId == null || currentApiToken == null) {
      print('[DataProvider] Cannot load projects: missing credentials');
      return;
    }

    if (currentRole == 'Client') {
      return; // Don't load projects for clients
    }

    // If forcing reload, clear existing projects first
    if (force) {
      projects = [];
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
      var response = await http.post(
        Uri.parse("https://office1.buildahome.in/API/get_projects_for_user"),
        body: payload,
      ).timeout(Duration(seconds: 15));

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
        print('[DataProvider] Loaded ${projects.length} projects for user $currentUserId (role: $currentRole)');
      } else {
        print('[DataProvider] Failed to load projects: ${response.statusCode}');
        projects = []; // Clear projects on error
      }
    } catch (e) {
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
      ], eagerError: false);

      lastClientDataLoad = DateTime.now();
      print('[DataProvider] Successfully loaded project data for $projectId');
    } catch (e) {
      print('[DataProvider] Error loading client project data: $e');
    } finally {
      clientDataLoading = false;
    }
  }

  // Helper method to load project location
  Future<void> _loadProjectLocation(String projectId) async {
    try {
      var locationUrl = 'https://office.buildahome.in/API/get_project_location?id=${projectId}';
      var locResponse = await http.get(Uri.parse(locationUrl));
      if (locResponse.statusCode == 200 && locResponse.body.trim().isNotEmpty) {
        clientProjectLocation = locResponse.body.trim();
      }
    } catch (e) {
      print('Error loading project location: $e');
    }
  }

  // Helper method to load project completion percentage
  Future<void> _loadProjectPercentage(String projectId, SharedPreferences prefs) async {
    try {
      var percUrl = 'https://office.buildahome.in/API/get_project_percentage?id=${projectId}';
      var percResponse = await http.get(Uri.parse(percUrl));
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
  Future<void> _loadLatestUpdates(String projectId, SharedPreferences prefs, {bool skipIfRecent = false}) async {
    // Skip if already loading updates to prevent duplicate calls
    if (isLoadingUpdates) {
      print('[DataProvider] Skipping latest updates load - already in progress');
      // Wait for the current load to complete
      while (isLoadingUpdates) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return;
    }

    // Skip if updates were loaded recently (within last 2 seconds) to prevent duplicate calls
    if (skipIfRecent && lastUpdatesLoad != null && 
        DateTime.now().difference(lastUpdatesLoad!).inSeconds < 2) {
      print('[DataProvider] Skipping latest updates load - already loaded recently');
      return;
    }

    isLoadingUpdates = true;
    try {
      print('[DataProvider] Loading latest updates for project $projectId');
      var updatesUrl = 'https://office.buildahome.in/API/latest_update?id=${projectId}';
      var updatesResponse = await http.get(Uri.parse(updatesUrl)).timeout(Duration(seconds: 15));
      
      if (updatesResponse.statusCode == 200 && updatesResponse.body.trim() != "No updates") {
        clientProjectUpdates = jsonDecode(updatesResponse.body);
        lastUpdatesLoad = DateTime.now();
        print('[DataProvider] Successfully loaded ${clientProjectUpdates is List ? clientProjectUpdates.length : 0} updates');
      } else if (updatesResponse.statusCode == 200 && updatesResponse.body.trim() == "No updates") {
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
        print('[DataProvider] Failed to load updates: status ${updatesResponse.statusCode}');
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
      var statusUrl = 'https://office.buildahome.in/API/get_project_block_status?project_id=${projectId}';
      var statusResponse = await http.get(Uri.parse(statusUrl));
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
      final paymentUrl = 'https://office.buildahome.in/API/get_payment?project_id=$projectId';
      final paymentResponse = await http.get(Uri.parse(paymentUrl)).timeout(Duration(seconds: 15));
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
      final url = 'https://office.buildahome.in/API/get_gallery_data?id=$projectId';
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 15));
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
      final url = 'https://office.buildahome.in/API/get_all_tasks?project_id=$projectId&nt_toggle=0';
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 15));
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
      final url = 'https://office.buildahome.in/API/get_notes?project_id=$projectId';
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 15));
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
      final url = 'https://office.buildahome.in/API/view_all_documents?id=$projectId';
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 15));
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
      if (force || lastClientDataLoad == null || 
          DateTime.now().difference(lastClientDataLoad!).inMinutes > 5) {
        await loadClientProjectData();
      }
    } else {
      // Load project data (including updates) first - this is critical for showing updates immediately
      if (projectId != null && (force || lastClientDataLoad == null || 
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
            print('[DataProvider] Error loading project data in background: $e');
          });
        }
      }
    }
  }

  // Reset project data (for switching projects from AdminDashboard)
  void resetProjectData() {
    clientProjectLocation = null;
    clientProjectCompletion = null;
    clientProjectUpdates = null;
    clientProjectBlocked = null;
    clientProjectBlockReason = null;
    clientProjectValue = null;
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
    clientProjectLocation = null;
    clientProjectCompletion = null;
    clientProjectUpdates = null;
    clientProjectBlocked = null;
    clientProjectBlockReason = null;
    clientProjectValue = null;
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

