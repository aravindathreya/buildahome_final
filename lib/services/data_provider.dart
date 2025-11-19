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
  Future<void> loadProjects() async {
    if (projectsLoading) return;
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role');
    currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');
    currentApiToken = prefs.getString('api_token');

    if (currentRole == null || currentUserId == null || currentApiToken == null) {
      return;
    }

    if (currentRole == 'Client') {
      return; // Don't load projects for clients
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
        Uri.parse("https://office.buildahome.in/API/get_projects_for_user"),
        body: payload,
      );

      if (response.statusCode == 200) {
        projects = jsonDecode(response.body);
        lastProjectsLoad = DateTime.now();
        print('[DataProvider] Loaded ${projects.length} projects');
      } else {
        print('[DataProvider] Failed to load projects: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading projects: $e');
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
    if (clientDataLoading) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // Update currentRole if not set
    if (currentRole == null) {
      currentRole = prefs.getString('role');
    }

    clientProjectId = projectId;
    clientDataLoading = true;

    print('loading project data for project $projectId');
    print('prefs: $prefs');
    print('clientProjectId: $clientProjectId');
    print('currentRole: $currentRole');

    try {
      // Load project location
      var locationUrl = 'https://office.buildahome.in/API/get_project_location?id=${projectId}';
      var locResponse = await http.get(Uri.parse(locationUrl));
      if (locResponse.statusCode == 200 && locResponse.body.trim().isNotEmpty) {
        clientProjectLocation = locResponse.body.trim();
      }

      // Load project completion percentage
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

      // Load project value
      // Only load from SharedPreferences for Client users
      if (currentRole == 'Client') {
        var value = prefs.getString('project_value');
        if (value != null) {
          clientProjectValue = value;
        }
      } else {
        // For non-Client users, try to load from API or set empty
        clientProjectValue = '';
      }

      // Load latest updates - always from API, no SharedPreferences fallback
      // For non-Client users, explicitly set to null at start to ensure skeleton loader shows
      if (currentRole != 'Client') {
        clientProjectUpdates = null;
      }
      
      var updatesUrl = 'https://office.buildahome.in/API/latest_update?id=${projectId}';
      var updatesResponse = await http.get(Uri.parse(updatesUrl));
      if (updatesResponse.statusCode == 200 && updatesResponse.body.trim() != "No updates") {
        clientProjectUpdates = jsonDecode(updatesResponse.body);
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
      } else {
        // API call failed - set to null to indicate data not loaded
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

      // Load project block status
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

      lastClientDataLoad = DateTime.now();
    } catch (e) {
      print('Error loading client project data: $e');
    } finally {
      clientDataLoading = false;
    }
  }

  // Initialize data based on user role
  Future<void> initializeData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var role = prefs.getString('role');

    if (role == null) {
      return;
    }

    if (role == 'Client') {
      await loadClientProjectData();
    } else {
      await loadProjects();
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

      // Force reload projects if forced or if data is stale (older than 5 minutes)
      if (force || lastProjectsLoad == null || 
          DateTime.now().difference(lastProjectsLoad!).inMinutes > 5) {
        await loadProjects();
      }

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
    currentRole = null;
    currentUserId = null;
    currentApiToken = null;
    
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
  }
}

