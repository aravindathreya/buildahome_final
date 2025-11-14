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
      var response = await http.post(
        Uri.parse("https://office.buildahome.in/API/get_projects_for_user"),
        body: {
          "user_id": currentUserId!,
          "role": currentRole!,
          "api_token": currentApiToken!,
        },
      );

      if (response.statusCode == 200) {
        projects = jsonDecode(response.body);
        lastProjectsLoad = DateTime.now();
      }
    } catch (e) {
      print('Error loading projects: $e');
      projects = [];
    } finally {
      projectsLoading = false;
    }
  }

  // Load project data for Client users
  Future<void> loadClientProjectData() async {
    if (clientDataLoading) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    currentRole = prefs.getString('role');

    if (currentRole != 'Client') {
      return; // Don't load client data for non-clients
    }

    var projectId = prefs.getString('project_id');
    if (projectId == null) {
      return;
    }

    clientProjectId = projectId;
    clientDataLoading = true;

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
        prefs.setString('completed', percResponse.body);
      } else if (prefs.containsKey("completed")) {
        clientProjectCompletion = prefs.getString('completed');
      }

      // Load project value
      var value = prefs.getString('project_value');
      if (value != null) {
        clientProjectValue = value;
      }

      // Load latest updates
      var updatesUrl = 'https://office.buildahome.in/API/latest_update?id=${projectId}';
      var updatesResponse = await http.get(Uri.parse(updatesUrl));
      if (updatesResponse.statusCode == 200 && updatesResponse.body.trim() != "No updates") {
        clientProjectUpdates = jsonDecode(updatesResponse.body);
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

  // Reload data (used when navigating to screens)
  Future<void> reloadData({bool force = false}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var role = prefs.getString('role');

    if (role == null) {
      return;
    }

    if (role == 'Client') {
      // Force reload client data if forced or if data is stale (older than 5 minutes)
      if (force || lastClientDataLoad == null || 
          DateTime.now().difference(lastClientDataLoad!).inMinutes > 5) {
        await loadClientProjectData();
      }
    } else {
      // Force reload projects if forced or if data is stale (older than 5 minutes)
      if (force || lastProjectsLoad == null || 
          DateTime.now().difference(lastProjectsLoad!).inMinutes > 5) {
        await loadProjects();
      }
    }
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
  }
}

