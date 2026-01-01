import 'dart:async';
import 'dart:convert';

import 'package:buildAhome/AddDailyUpdate.dart';
import 'package:buildAhome/UserHome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'SiteVisitReports.dart';
import 'TestReportsScreen.dart';
import 'app_theme.dart';
import 'checklist_categories.dart';
import 'indents_screen.dart';
import 'notifcations.dart';
import 'project_picker.dart';
import 'user_picker.dart';
import 'services/data_provider.dart';
import 'services/rbac_service.dart';
import 'stock_report.dart';
import 'ViewAllTasksScreen.dart';
import 'TasksScreen.dart';
import 'Skin2/loginPage.dart';
import 'widgets/dark_mode_toggle.dart';
import 'NavMenu.dart';
import 'NotesAndComments.dart';

class AdminDashboard extends StatefulWidget {
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AdminHomeState> _adminHomeKey = GlobalKey<AdminHomeState>();
  int _rebuildTrigger = 0;
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    // Periodically check if AdminHomeState is ready and rebuild if needed
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted && _adminHomeKey.currentState != null) {
        setState(() {
          _rebuildTrigger++;
        });
      }
    });
    // Listen to search query changes to rebuild search results
    _searchQueryNotifier.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if state is available after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _adminHomeKey.currentState != null && _rebuildTrigger == 0) {
        setState(() {
          _rebuildTrigger++;
        });
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      drawer: NavMenuWidget(),
      appBar: null,
      body: Stack(
        children: [
          // Background image with opacity
          Positioned.fill(
            child: Opacity(
              opacity: 0.3,
              child: Image.asset(
                'assets/images/See details.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: AppTheme.getBackgroundPrimary(context));
                },
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.7,
              child: Container(color: AppTheme.getBackgroundPrimary(context)),
            ),
          ),
          // Content on top
          GestureDetector(
            onTap: () {
              // Hide search results when tapping outside
              if (_adminHomeKey.currentState != null) {
                _adminHomeKey.currentState!._quickSearchFocusNode.unfocus();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                // User avatar header
                if (_adminHomeKey.currentState != null)
                  _adminHomeKey.currentState!._buildUserHeader(),
                // Search field
                if (_adminHomeKey.currentState != null)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                    
                  ),
                  child: _adminHomeKey.currentState!._buildSearchField(),
                ),
                // Main content
                Expanded(
                  child: AdminHome(
                    key: _adminHomeKey,
                    searchQueryNotifier: _searchQueryNotifier,
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

class _LogoutButton extends StatelessWidget {
  Future<void> _handleLogout(BuildContext context) async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Logout',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontWeight: FontWeight.normal,
            ),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Logout',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      // Clear data immediately (synchronous)
      DataProvider().clearData();
      
      // Navigate immediately without waiting for SharedPreferences.clear()
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginScreenNew()),
          (route) => false,
        );
      }
      
      // Clear SharedPreferences in background (don't wait for it)
      SharedPreferences.getInstance().then((preferences) {
        preferences.clear();
      }).catchError((e) {
        print('Error clearing SharedPreferences: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _handleLogout(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.getPrimaryColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.logout,
              color: AppTheme.backgroundPrimaryLight,
              size: 14,
            ),
            
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  final ValueNotifier<String>? searchQueryNotifier;
  
  const AdminHome({Key? key, this.searchQueryNotifier}) : super(key: key);

  @override
  AdminHomeState createState() {
    return AdminHomeState();
  }
}

class AdminHomeState extends State<AdminHome> {
  var currentWidgetContext;
  var currentDate;
  var showTopSection = true;
  var showProjects = false;
  bool _isLoadingProjects = false;
  bool _isRefreshingProjects = false;
  String? _projectsError;
  var searchProjectfocusNode = FocusNode();
  var searchProjectTextController = new TextEditingController();
  var currentUserRole = '';
  var currentUserName = '';
  var projects = [];
  var projectsToShow = [];
  bool readOnly = true;
  final TextEditingController _quickSearchController = TextEditingController();
  final FocusNode _quickSearchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _projectsRefreshTimer;
  Timer? _searchDebounceTimer;
  String _cachedFilterQuery = '';
  ValueNotifier<String>? _searchQueryNotifier;
  
  // Tasks state
  List<dynamic> _tasks = [];
  bool _isLoadingTasks = false;
  bool _hasLoadedTasksOnce = false;
  String? _tasksError;
  Map<int, Map<String, dynamic>> _previousTasksMap = {}; // Track previous tasks for comparison
  
  // Navigation state to prevent double-taps
  bool _isNavigating = false;

  @override
  void dispose() {
    searchProjectfocusNode.dispose();
    searchProjectTextController.dispose();
    _quickSearchController.dispose();
    _quickSearchFocusNode.dispose();
    _scrollController.dispose();
    _projectsRefreshTimer?.cancel();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  setDate() {
    var now = new DateTime.now();
    var formatter = new DateFormat('d, MMMM');
    currentDate = formatter.format(now);
  }

  setRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserRole = prefs.getString('role') ?? '';
      currentUserName = prefs.getString('username') ?? '';
    });
  }

  Future<void> loadProjects({bool force = false, bool showLoader = false}) async {
    if (!mounted) return;

    if (showLoader || !showLoader) {
      setState(() {
        if (showLoader) {
          _isLoadingProjects = true;
        } else {
          _isRefreshingProjects = true;
        }
        _projectsError = null;
      });
    }

    try {
      // Directly call loadProjects() instead of reloadData() to ensure projects are actually loaded
      // reloadData() doesn't call loadProjects() anymore (removed to prevent loading in UserDashboard)
      print('[AdminDashboard] Loading projects with force=$force');
      await DataProvider().loadProjects(force: force);
      if (!mounted) return;
      final provider = DataProvider();
      final newProjects = provider.projects;
      
      print('[AdminDashboard] Loaded ${newProjects.length} projects');
      
      setState(() {
        projects = newProjects;
        projectsToShow = projects;
        // Reset search if projects changed
        if (_cachedFilterQuery.isNotEmpty) {
          final query = _cachedFilterQuery.toLowerCase();
          projectsToShow = projects.where((project) {
            final name = project['name']?.toString().toLowerCase() ?? '';
            final id = project['id']?.toString().toLowerCase() ?? '';
            final clientName = project['client_name']?.toString().toLowerCase() ?? '';
            return name.contains(query) || 
                   id.contains(query) || 
                   clientName.contains(query);
          }).toList();
        }
      });
      
      // Reload tasks after projects are loaded to filter by project IDs
      // Always load tasks, even if projects list is empty (tasks can be assigned directly to users)
      loadTasks();
    } catch (e) {
      print('[AdminDashboard] Error loading projects: $e');
      if (!mounted) return;
      setState(() {
        _projectsError = 'Unable to refresh projects. Please pull down to retry.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingProjects = false;
        _isRefreshingProjects = false;
      });
    }
  }


  @override
  void initState() {
    super.initState();
    _searchQueryNotifier = widget.searchQueryNotifier;
    setDate();
    setRole();
    // Load projects from data provider (it should already be loaded on app init)
    final initialProjects = DataProvider().projects;
    setState(() {
      projects = initialProjects;
      projectsToShow = projects;
    });
    // Force reload on first load to ensure fresh data, especially after login
    loadProjects(force: true, showLoader: true);
    _startProjectsAutoRefresh();
    // Note: loadTasks() will be called by loadProjects() after projects are loaded
  }

  void _startProjectsAutoRefresh() {
    _projectsRefreshTimer?.cancel();
    _projectsRefreshTimer = Timer.periodic(Duration(minutes: 1), (_) {
      if (!mounted) return;
      loadProjects();
    });
  }

  Future<void> loadTasks() async {
    if (!mounted) return;
    
    // Prevent multiple simultaneous calls
    if (_isLoadingTasks) {
      print('[AdminDashboard] loadTasks already in progress, skipping duplicate call');
      return;
    }
    
    setState(() {
      _isLoadingTasks = true;
      _tasksError = null;
    });

    try {
      print('Loading tasks');
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');
      print('UserId: $userId');
      print('Api Token: $apiToken');  
      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      // Build query parameters for GET request
      // API uses OR logic - tasks matching ANY filter will be returned
      Map<String, String> queryParams = {
        'user_id': userId,
        'assigned_to': userId,
      };
      
      List<dynamic> allTasks = [];
      
      // Fetch tasks for user_id and assigned_to
      Uri uri = Uri.parse("https://office1.buildahome.in/API/get_tasks").replace(
        queryParameters: queryParams,
      );
      
      print('Uri ${uri.toString()}');
      var response = await http.get(uri).timeout(const Duration(seconds: 20));
      print('Response ${response.body}');
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> fetchedTasks = [];
        
        if (decoded is Map && decoded['success'] == true && decoded['tasks'] != null) {
          fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
        } else if (decoded is Map && decoded['tasks'] != null) {
          fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
        } else if (decoded is List) {
          fetchedTasks = decoded;
        }
        
        // Add tasks to our list (deduplicate by task id)
        Map<int, dynamic> taskMap = {};
        for (var task in fetchedTasks) {
          if (task is Map && task['id'] != null) {
            int taskId = int.tryParse(task['id'].toString()) ?? 0;
            if (taskId > 0) {
              taskMap[taskId] = task;
            }
          }
        }
        allTasks = taskMap.values.toList();
        
        // Check if tasks have changed
        Map<int, Map<String, dynamic>> currentTasksMap = {};
        for (var task in allTasks) {
          if (task is Map && task['id'] != null) {
            int taskId = int.tryParse(task['id'].toString()) ?? 0;
            if (taskId > 0) {
              currentTasksMap[taskId] = Map<String, dynamic>.from(task);
            }
          }
        }
        
        // Compare with previous tasks to detect changes
        bool hasChanges = false;
        if (_previousTasksMap.length != currentTasksMap.length) {
          hasChanges = true;
        } else {
          for (var entry in currentTasksMap.entries) {
            final taskId = entry.key;
            final task = entry.value;
            if (!_previousTasksMap.containsKey(taskId)) {
              hasChanges = true;
              break;
            }
            // Check if task data has changed
            final prevTask = _previousTasksMap[taskId];
            if (prevTask != null) {
              final prevStatus = prevTask['status']?.toString() ?? '';
              final currStatus = task['status']?.toString() ?? '';
              final prevNote = prevTask['note']?.toString() ?? '';
              final currNote = task['note']?.toString() ?? '';
              if (prevStatus != currStatus || prevNote != currNote) {
                hasChanges = true;
                break;
              }
            }
          }
        }
        
        // Update UI only if there are changes
        if (hasChanges || !_hasLoadedTasksOnce) {
          allTasks.sort((a, b) {
            if (a is! Map || b is! Map) return 0;
            String aDate = (a['created_at'] ?? '').toString();
            String bDate = (b['created_at'] ?? '').toString();
            return bDate.compareTo(aDate);
          });
          
          setState(() {
            _tasks = allTasks;
            _isLoadingTasks = false;
            _hasLoadedTasksOnce = true;
            _previousTasksMap = currentTasksMap;
          });
        } else {
          // Don't call setState if there are no changes to prevent flickering
          // Only update loading state if it was true
          if (_isLoadingTasks) {
            setState(() {
              _isLoadingTasks = false;
            });
          }
        }
      } else if (response.statusCode == 404) {
        // No tasks found - this is okay
        setState(() {
          _tasks = [];
          _isLoadingTasks = false;
          _hasLoadedTasksOnce = true;
        });
      } else {
        throw Exception('Unable to load tasks (code ${response.body})');
      }
    } catch (e) {
      if (!mounted) return;
      print('[AdminDashboard] Error loading tasks: $e');
      setState(() {
        _tasksError = e.toString().replaceAll('Exception: ', '');
        _isLoadingTasks = false;
        _hasLoadedTasksOnce = true;
        // Set empty list on error to show empty state
        _tasks = [];
      });
    }
  }

  Future<void> updateTaskStatus(int taskId, String newStatus) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? apiToken = prefs.getString('api_token');

      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/update_task_status");
      final response = await http.post(
        uri,
        body: {
          'task_id': taskId.toString(),
          'status': newStatus,
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          // Reload tasks to get updated data
          await loadTasks();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Task status updated successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to update task status');
        }
      } else {
        throw Exception('Unable to update task status (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> createTask({
    required int projectId,
    required int assignedTo,
    String? note,
    String status = 'pending',
  }) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');

      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/create_task");
      final response = await http.post(
        uri,
        body: {
          'user_id': userId,
          'project_id': projectId.toString(),
          'assigned_to': assignedTo.toString(),
          'status': status,
          'note': note ?? '',
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));
      print(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          // Reload tasks to get updated data
          await loadTasks();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Task created successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to create task');
        }
      } else {
        throw Exception('Unable to create task (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(e.toString().replaceAll('Exception: ', '')),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _showCreateTaskDialog() {
    // Prevent double-tap navigation
    if (_isNavigating) {
      return;
    }

    setState(() {
      _isNavigating = true;
    });

    _navigateWithAnimation(
      context,
      TasksLayout(
        initialTasks: _tasks,
        onTaskUpdated: () {
          loadTasks();
        },
        loadTasksCallback: () async {
          await loadTasks();
          return _tasks;
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    });
  }

  List<Map<String, dynamic>> getMenuItems() {
    List<Map<String, dynamic>> menuItems = [];
    final rbac = RBACService();

     // My Projects (non-Client)
    if (currentUserRole != 'Client') {
      menuItems.add({
        'title': 'Projects',
        'icon': Icons.list,
        'route': () async {
          await ProjectPickerScreen.show(context);
          if (mounted) {
            loadProjects();
          }
        },
      });
    }

    // Add Daily Update - check RBAC
    if (rbac.canViewSync(currentUserRole, RBACService.dailyUpdate)) {
      menuItems.add({
        'title': 'Daily Update',
        'icon': Icons.update,
        'route': () => AddDailyUpdate(returnToAdminDashboard: true),
      });
    }

    // Indents - check RBAC
    if (rbac.canViewSync(currentUserRole, RBACService.indent)) {
      menuItems.add({
        'title': 'Indents',
        'icon': Icons.request_quote,
        'route': () => IndentsScreenLayout(),
      });
    }

    // Stock report (not in RBAC table, but keep for non-Client)
    if (currentUserRole != 'Client') {
      menuItems.add({
        'title': 'Stock Report',
        'icon': Icons.inventory,
        'route': () => StockReportLayout(),
      });

      menuItems.add({
        'title': 'Site Visits',
        'icon': Icons.assignment_outlined,
        'route': () => SiteVisitReportsScreen(),
      });
    }

    // Test Reports / QC Reports - only for Admin or QC roles
    if (currentUserRole == 'Admin' || 
        currentUserRole == 'QC' || 
        currentUserRole == 'Quality Engineer') {
      menuItems.add({
        'title': 'Test Reports',
        'icon': Icons.science,
        'route': () => TestReportsScreen(),
      });
    }

    // Checklist - check RBAC
    if (rbac.canViewSync(currentUserRole, RBACService.checklist)) {
      menuItems.add({
        'title': 'Checklist',
        'icon': Icons.list,
        'route': () => ChecklistCategoriesLayout(),
      });
    }

    // ChatBox - check RBAC but exclude site engineer
    if (rbac.canViewSync(currentUserRole, RBACService.tasksAndNotes) && 
        currentUserRole != 'Site Engineer') {
      menuItems.add({
        'title': 'ChatBox',
        'icon': Icons.note_add,
        'route': () => NotesAndComments(),
      });
    }

    // My Notifications
    menuItems.add({
      'title': 'My Notifications',
      'icon': Icons.notifications_on,
      'route': () => Notifications(),
    });

    // // Log out
    // menuItems.add({
    //   'title': 'Log out',
    //   'icon': Icons.logout,
    //   'route': () async {
    //     SharedPreferences preferences = await SharedPreferences.getInstance();
    //     preferences.clear();
    //     Navigator.pushAndRemoveUntil(
    //       context,
    //       MaterialPageRoute(builder: (context) => App()),
    //       (route) => false,
    //     );
    //   },
    // });

    return menuItems;
  }

  Widget build(BuildContext context) {
    currentWidgetContext = context;
    List<Map<String, dynamic>> menuItems = getMenuItems();
    int totalProjects = projects.length;
    
    return RefreshIndicator(
      onRefresh: () => loadProjects(force: true),
      color: AppTheme.getPrimaryColor(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
        ),
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(20),
          children: [
            if (_projectsError != null)
              Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _projectsError!,
                        style: TextStyle(
                          color: Colors.red[800],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Statistics Cards - Total Projects and Total Pending Tasks
            if (currentUserRole != 'Client')
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      'Total Projects',
                      totalProjects.toString(),
                      Icons.folder_special_outlined,
                      AppTheme.getPrimaryColor(context),
                      index: 0,
                      onTap: () async {
                        // Navigate to ProjectPickerScreen (same as Projects tab)
                        if (_isNavigating) return;
                        
                        setState(() {
                          _isNavigating = true;
                        });
                        
                        try {
                          await ProjectPickerScreen.show(context);
                          if (mounted) {
                            loadProjects();
                          }
                          // Add delay to prevent tap that closes modal from retriggering
                          await Future.delayed(Duration(milliseconds: 300));
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isNavigating = false;
                            });
                          }
                        }
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      'Pending Tasks',
                      _tasks.where((task) {
                        if (task is Map) {
                          final status = task['status']?.toString().toLowerCase() ?? '';
                          return status == 'pending';
                        }
                        return false;
                      }).length.toString(),
                      Icons.pending_actions_outlined,
                      AppTheme.getPrimaryColor(context),
                      index: 1,
                      onTap: () {
                        // Navigate to view all tasks screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TasksLayout(
                              initialTasks: _tasks,
                              initialTabIndex: 1,
                              onTaskUpdated: () => loadTasks(),
                              loadTasksCallback: () async {
                                await loadTasks();
                                return _tasks;
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

            SizedBox(height: 20),

            // Tasks Section - hidden for Client and Billing roles
            if (currentUserRole != 'Client' && currentUserRole != 'Billing') _buildTasksSection(),

            SizedBox(height: 20),
            Row(
              children: [
                
           Icon(Icons.task_alt_outlined, color: AppTheme.getPrimaryColor(context), size: 24),
            SizedBox(width: 8),
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            Spacer(),
              ]
            ),

            // GridView for menu items
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: menuItems.length,
              itemBuilder: (BuildContext context, int index) {
                final item = menuItems[index];
                return Material(
                  color: AppTheme.getBackgroundSecondary(context),
                  child: InkWell(
                    onTap: _isNavigating ? null : () async {
                      await _handleMenuTap(context, item);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: item['title'] == 'Log out' 
                                ? Colors.red.withOpacity(0.15) 
                                : AppTheme.getPrimaryColor(context).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            item['icon'],
                            size: 20,
                            color: item['title'] == 'Log out' ? Colors.red : AppTheme.getPrimaryColor(context),
                          ),
                        ),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            item['title'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }



  Widget _buildUserHeader() {
    return Container(
      width: MediaQuery.of(context).size.width,
      padding: EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Builder(
            builder: (context) => InkWell(
              onTap: () {
                Scaffold.of(context).openDrawer();
              },
              borderRadius: BorderRadius.circular(30),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.getPrimaryColor(context),
                      child: Text(
                        currentUserName.isNotEmpty 
                            ? currentUserName[0].toUpperCase() 
                            : 'U',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    currentUserName.isNotEmpty ? currentUserName : 'User',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              DarkModeToggle(showLabel: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 18),
      child: Opacity(
        opacity: _isNavigating ? 0.6 : 1.0,
        child: InkWell(
          onTap: _isNavigating ? null : () async {
            // Prevent double-tap opening picker twice
            if (_isNavigating) return;
            
            setState(() {
              _isNavigating = true;
            });
            
            try {
              await ProjectPickerScreen.show(context);
              if (mounted) {
                loadProjects();
              }
              // Add delay to prevent tap that closes modal from retriggering
              await Future.delayed(Duration(milliseconds: 300));
            } finally {
              if (mounted) {
                setState(() {
                  _isNavigating = false;
                });
              }
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                if (_isNavigating)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
                    ),
                  )
                else
                  Icon(
                    Icons.folder_special,
                    color: AppTheme.getPrimaryColor(context),
                    size: 20,
                  ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select a project',
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppTheme.getTextSecondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildSearchResultsSection([String? queryValue]) {
    // Use the provided query value or fall back to controller text
    final query = (queryValue ?? _quickSearchController.text).trim();
    if (query.isEmpty) {
      return SizedBox.shrink();
    }

    // Filter projects based on current query
    final queryLower = query.toLowerCase();
    final filteredProjects = projects.where((project) {
      final name = project['name']?.toString().toLowerCase() ?? '';
      final id = project['id']?.toString().toLowerCase() ?? '';
      final clientName = project['client_name']?.toString().toLowerCase() ?? '';
      return name.contains(queryLower) || 
             id.contains(queryLower) || 
             clientName.contains(queryLower);
    }).toList();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.getPrimaryColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Search Results (${filteredProjects.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: AppTheme.getTextPrimary(context),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Projects list
          if (filteredProjects.isEmpty)
            Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: AppTheme.getTextSecondary(context),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No projects found',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Try a different search term',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                physics: AlwaysScrollableScrollPhysics(),
                itemCount: filteredProjects.length,
                itemBuilder: (context, index) {
                  final project = filteredProjects[index];
                  final projectName = project['name']?.toString() ?? 'Unnamed Project';
                  final projectId = project['id']?.toString() ?? '';
                  final clientName = project['client_name']?.toString() ?? '';
                  
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundPrimaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          // Prevent double-tap navigation
                          if (_isNavigating) {
                            return;
                          }

                          final projectIdStr = project['id']?.toString();
                          final projectNameStr = project['name']?.toString() ?? 'Project';
                          
                          if (projectIdStr == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Unable to open this project.')),
                            );
                            return;
                          }
                          
                          setState(() {
                            _isNavigating = true;
                          });

                          try {
                            SharedPreferences prefs = await SharedPreferences.getInstance();
                            await prefs.setString("project_id", projectIdStr);
                            await prefs.setString("client_name", projectNameStr);
                            
                            // Preload project data for non-Client users
                            final role = prefs.getString('role');
                            if (role != null && role != 'Client') {
                              DataProvider().resetProjectData();
                              DataProvider().loadProjectDataForNonClient(projectIdStr).catchError((e) {
                                print('[AdminDashboard] Error preloading project data: $e');
                              });
                            }
                            
                            if (!mounted) return;
                            
                            await _navigateWithAnimation(
                              context,
                              Home(fromAdminDashboard: true),
                            ).then((_) {
                              if (mounted) {
                                loadProjects();
                              }
                            });
                            _clearQuickSearch();
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isNavigating = false;
                              });
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.folder_special,
                                  color: AppTheme.getPrimaryColor(context),
                                  size: 24,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      projectName,
                                      style: TextStyle(
                                        color: AppTheme.getTextPrimary(context),
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (clientName.isNotEmpty) ...[
                                      SizedBox(height: 4),
                                      Text(
                                        'Client: $clientName',
                                        style: TextStyle(
                                          color: AppTheme.getTextSecondary(context),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    if (projectId.isNotEmpty) ...[
                                      SizedBox(height: 2),
                                      Text(
                                        'ID: $projectId',
                                        style: TextStyle(
                                          color: AppTheme.getTextSecondary(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: AppTheme.getTextSecondary(context),
                                size: 20,
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
  }

  void _clearQuickSearch() {
    _searchDebounceTimer?.cancel();
    _quickSearchController.clear();
    _quickSearchFocusNode.unfocus();
    _searchQueryNotifier?.value = '';
    setState(() {
      _cachedFilterQuery = '';
      projectsToShow = projects;
    });
  }


  // Helper method for smooth animated navigation
  Future<T?> _navigateWithAnimation<T extends Object?>(
    BuildContext context,
    Widget destination, {
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeInOutCubic,
    Offset beginOffset = const Offset(0.3, 0.0),
  }) async {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Combine fade and slide for smooth animation
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Interval(0.0, 0.6, curve: curve),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: beginOffset,
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: curve,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: duration,
        reverseTransitionDuration: duration,
      ),
    );
  }

  Future<void> _handleMenuTap(BuildContext context, Map<String, dynamic> item) async {
    // Prevent double-tap navigation
    if (_isNavigating) {
      return;
    }

    if (item['title'] == 'Log out') {
      DataProvider().clearData();
      await item['route']();
      return;
    }

    setState(() {
      _isNavigating = true;
    });

    try {
      final routeResult = item['route']();
      final widget = routeResult is Future ? await routeResult : routeResult;

      if (!mounted) return;

      if (item['title'] == 'Projects') {
        await ProjectPickerScreen.show(context);
        if (mounted) {
          loadProjects();
        }
        // Add delay to prevent tap that closes modal from retriggering
        await Future.delayed(Duration(milliseconds: 300));
        return;
      }

      await _navigateWithAnimation(context, widget).then((_) {
        if (mounted) {
          loadProjects();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color, {int index = 0, VoidCallback? onTap}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, animationValue, child) {
        final isDisabled = _isNavigating && onTap != null;
        return Transform.translate(
          offset: Offset(0, 30 * (1 - animationValue)),
          child: Opacity(
            opacity: animationValue * (isDisabled ? 0.6 : 1.0),
            child: Material(
              child: InkWell(
                onTap: isDisabled ? null : onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundSecondary(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icon,
                          size: 24,
                          color: color,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              value,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getTextPrimary(context),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.getTextSecondary(context),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - minimal
        Row(
          children: [
            Icon(Icons.task_alt_outlined, color: AppTheme.getPrimaryColor(context), size: 24),
            SizedBox(width: 8),
            Text(
              'Recent Tasks',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            Spacer(),
            // Create Task Button - compact with green
            Container(
              decoration: BoxDecoration(
                color: Color(0xFF10B981),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showCreateTaskDialog(),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Create',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 6),
            // Refresh Button - compact
            Container(
              decoration: BoxDecoration(
                color: AppTheme.getPrimaryColor(context),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: loadTasks,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.refresh, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        
        // Error message - compact
        if (_tasksError != null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.95 + (0.05 * value),
                  child: Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _tasksError!,
                            style: TextStyle(
                              color: Colors.red[800],
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

        // Fixed height container to prevent layout shifts
        SizedBox(
          height: 210,
          child: _isLoadingTasks
              ? // Loading state - skeleton loader (show whenever loading)
                ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    itemCount: 5,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < 4 ? 12 : 0,
                        ),
                        child: _buildTaskCardSkeleton(),
                      );
                    },
                  )
              : _tasks.isEmpty && _tasksError == null
                  ? // Empty state - compact with animation
                    Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.scale(
                                scale: 0.9 + (0.1 * value),
                                child: Container(
                                  padding: EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: AppTheme.getBackgroundSecondary(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.task_alt,
                                          size: 32,
                                          color: AppTheme.getPrimaryColor(context),
                                        ),
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'No tasks found',
                                        style: TextStyle(
                                          color: AppTheme.getTextPrimary(context),
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Create your first task',
                                        style: TextStyle(
                                          color: AppTheme.getTextSecondary(context),
                                          fontSize: 12,
                                        ),
                                      ),
                                      SizedBox(height: 12),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Color(0xFF10B981),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () => _showCreateTaskDialog(),
                                            borderRadius: BorderRadius.circular(6),
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.add, color: Colors.white, size: 14),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Create Task',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                  : // Tasks list with horizontal scroll view
                    ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(vertical: 8),
                        itemCount: _tasks.length > 5 ? 5 : _tasks.length,
                        itemBuilder: (context, index) {
                          final task = _tasks[index];
                          if (task is Map<String, dynamic>) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 400 + (index * 100)),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.scale(
                                    scale: 0.9 + (0.1 * value),
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: index < (_tasks.length > 5 ? 5 : _tasks.length) - 1 ? 12 : 0,
                                      ),
                                      child: _buildTaskCard(task, index),
                                    ),
                                  ),
                                );
                              },
                            );
                          } else {
                            return SizedBox.shrink();
                          }
                        },
                      ),
        ),

        // View All Tasks button - styled like Create Task button

      ],
    );
  }

  // Helper function to convert text to sentence case
  String _toSentenceCase(String text) {
    if (text.isEmpty) return text;
    // Convert first character to uppercase and rest to lowercase
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  // Helper function to generate darker color from name
  Color _getColorFromName(String name) {
    if (name.isEmpty) return Colors.grey.shade700;
    final colors = [
      Color(0xFF1565C0), // Darker Blue
      Color(0xFF0D7A4A), // Darker Green
      Color(0xFFC62828), // Darker Red
      Color(0xFFB8860B), // Darker Amber
      Color(0xFF6A1B9A), // Darker Purple
      Color(0xFF00838F), // Darker Cyan
      Color(0xFFE65100), // Darker Orange
      Color(0xFF5D4037), // Darker Brown
    ];
    final codeUnits = name.codeUnits;
    final sum = codeUnits.fold<int>(0, (a, b) => a + b);
    final index = sum % colors.length;
    return colors[index];
  }

  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final taskId = task['id']?.toString() ?? '';
    final projectId = task['project_id']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final assignedTo = task['assigned_to']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final userName = task['user_name']?.toString() ?? '';
    final userId = task['user_id']?.toString() ?? task['created_by']?.toString() ?? '';
    final status = task['status']?.toString() ?? 'pending';
    final note = task['note']?.toString() ?? '';
    final createdAt = task['created_at']?.toString() ?? '';

    // Get status color - using theme colors where appropriate
    Color statusColor;
    IconData statusIcon;
    
    switch (status.toLowerCase()) {
      case 'completed':
        statusColor = Color(0xFF10B981); // Green
        statusIcon = Icons.check_circle;
        break;
      case 'in_progress':
        statusColor = Color(0xFF2196F3); // Blue
        statusIcon = Icons.work;
        break;
      case 'cancelled':
        statusColor = Color(0xFFEF4444); // Red
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Color(0xFFD97706); // Darker amber/yellow
        statusIcon = Icons.pending;
    }

    // Build avatar stack - smaller avatars
    Widget avatarWidget;
    if (userName.isNotEmpty || assignedToName.isNotEmpty) {
      List<Widget> avatarList = [];
      if (userName.isNotEmpty) {
        avatarList.add(
          CircleAvatar(
            radius: 10,
            backgroundColor: _getColorFromName(userName),
            child: Text(
              userName[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        );
      }
      if (assignedToName.isNotEmpty && assignedToName != userName) {
        avatarList.add(
          Positioned(
            left: 14,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: _getColorFromName(assignedToName),
              child: Text(
                assignedToName[0].toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }
      if (avatarList.length == 1) {
        avatarWidget = avatarList[0];
      } else {
        avatarWidget = Stack(
          clipBehavior: Clip.none,
          children: avatarList,
        );
      }
    } else {
      avatarWidget = CircleAvatar(
        radius: 10,
        backgroundColor: statusColor,
        child: Icon(statusIcon, color: Colors.white, size: 12),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ViewAllTasksScreen(
                tasks: [task],
                onTaskUpdated: () => loadTasks(),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Container(
              width: 140,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundSecondary(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            // Left border with dynamic color
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
            ),
            // Content
            Container(
              width: 140,
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top section with avatar and status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar stack on top
                      Row(
                        children: [
                          avatarWidget,
                          Spacer(),
                          // Status indicator
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              statusIcon,
                              size: 12,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      // Note
                      if (note.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            _toSentenceCase(note),
                            style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  // Bottom section with project and assigned info
                  if (projectName.isNotEmpty || assignedToName.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 12),
                        if (projectName.isNotEmpty)
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              projectName,
                              style: TextStyle(
                                color: AppTheme.getTextSecondary(context),
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (assignedToName.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: Text(
                                assignedToName,
                                style: TextStyle(
                                  color: AppTheme.getTextSecondary(context),
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCardSkeleton() {
    final baseColor = AppTheme.getBackgroundSecondary(context).withOpacity(0.4);
    final highlightColor = Colors.white.withOpacity(0.35);
    
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Stack(
        children: [
          Container(
            width: 140,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          // Left border skeleton
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
          ),
          // Content skeleton
          Container(
            width: 140,
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar and status skeleton
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: baseColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Spacer(),
                        Container(
                          width: 24,
                          height: 16,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    // Note skeleton - 3 lines
                    Container(
                      width: double.infinity,
                      height: 12,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 12,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                // Bottom section skeleton
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 12),
                    Container(
                      width: 100,
                      height: 10,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      width: 70,
                      height: 10,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    final statuses = [
      {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706), 'icon': Icons.pending},
      {'value': 'in_progress', 'label': 'In Progress', 'color': AppTheme.getPrimaryColor(context), 'icon': Icons.work},
      {'value': 'completed', 'label': 'Completed', 'color': Color(0xFF10B981), 'icon': Icons.check_circle},
      {'value': 'cancelled', 'label': 'Cancelled', 'color': Color(0xFFEF4444), 'icon': Icons.cancel},
    ];

    final currentStatusData = statuses.firstWhere(
      (s) => s['value'] == currentStatus,
      orElse: () => statuses[0],
    );
    final currentColor = currentStatusData['color'] as Color;
    final currentIcon = currentStatusData['icon'] as IconData;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        value: currentStatus,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.getTextSecondary(context)),
        dropdownColor: AppTheme.backgroundPrimaryLight,
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 14,
        ),
        items: statuses.map((statusData) {
          final status = statusData['value'] as String;
          final label = statusData['label'] as String;
          final color = statusData['color'] as Color;
          final icon = statusData['icon'] as IconData;
          
          return DropdownMenuItem<String>(
            value: status,
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (String? newStatus) {
          if (newStatus != null && newStatus != currentStatus) {
            updateTaskStatus(taskId, newStatus);
          }
        },
        selectedItemBuilder: (BuildContext context) {
          return statuses.map((statusData) {
            final label = statusData['label'] as String;
            return Row(
              children: [
                Icon(currentIcon, size: 16, color: currentColor),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final formatter = DateFormat('MMM d, y • h:mm a');
      return formatter.format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }
}

// Create Task Screen
class CreateTaskScreen extends StatefulWidget {
  final VoidCallback? onTaskCreated;

  const CreateTaskScreen({Key? key, this.onTaskCreated}) : super(key: key);

  @override
  _CreateTaskScreenState createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final noteController = TextEditingController();
  final _searchController = TextEditingController();
  String selectedStatus = 'pending';
  bool isLoading = false;
  int? selectedProjectId;
  String? selectedProjectName;
  int? selectedUserId;
  String? selectedUserName;
  List<dynamic> _projects = [];
  List<dynamic> _filteredProjects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _searchController.addListener(_filterProjects);
  }

  @override
  void dispose() {
    noteController.dispose();
    _searchController.removeListener(_filterProjects);
    _searchController.dispose();
    super.dispose();
  }

  void _filterProjects() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredProjects = List<dynamic>.from(_projects);
      } else {
        _filteredProjects = _projects.where((project) {
          final name = project['name']?.toString().toLowerCase() ?? '';
          final id = project['id']?.toString() ?? '';
          final client = project['client_name']?.toString().toLowerCase() ?? '';
          return name.contains(query) || id.contains(query) || client.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadProjects() async {
    try {
      await DataProvider().reloadData(force: false);
      if (mounted) {
        setState(() {
          _projects = List<dynamic>.from(DataProvider().projects);
          _filteredProjects = List<dynamic>.from(_projects);
        });
      }
    } catch (e) {
      print('[CreateTaskScreen] Error loading projects: $e');
    }
  }

  Future<void> _createTask() async {
    if (selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a project'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task note cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');

      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      // Use selected user or current user as assigned_to
      final assignedToInt = selectedUserId ?? int.tryParse(userId);
      if (assignedToInt == null) {
        throw Exception('Invalid user ID');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/create_task");
      final response = await http.post(
        uri,
        body: {
          'user_id': userId,
          'project_id': selectedProjectId.toString(),
          'assigned_to': assignedToInt.toString(),
          'status': selectedStatus,
          'note': noteController.text.trim().isEmpty ? '' : noteController.text.trim(),
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));
      print(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Task created successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            widget.onTaskCreated?.call();
            Navigator.of(context).pop();
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to create task');
        }
      } else {
        throw Exception('Unable to create task (code ${response.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(e.toString().replaceAll('Exception: ', '')),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showProjectPicker() {
    // Reset search when opening picker
    _searchController.clear();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            // Re-filter based on current search query
            final query = _searchController.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? _projects
                : _projects.where((project) {
                    final name = project['name']?.toString().toLowerCase() ?? '';
                    final id = project['id']?.toString() ?? '';
                    final client = project['client_name']?.toString().toLowerCase() ?? '';
                    return name.contains(query) || id.contains(query) || client.contains(query);
                  }).toList();

            return Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select Project',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
                        onPressed: () {
                          _searchController.clear();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                // Search Field
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {});
                      _filterProjects();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search projects by name, ID, or client...',
                      hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search, color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppTheme.getTextSecondary(context), size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setModalState(() {});
                                _filterProjects();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context),
                          width: 2,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                // Projects List
                Expanded(
                  child: _projects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, size: 48, color: AppTheme.getTextSecondary(context)),
                              SizedBox(height: 16),
                              Text(
                                'No projects available',
                                style: TextStyle(
                                  color: AppTheme.getTextSecondary(context),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 48, color: AppTheme.getTextSecondary(context)),
                                  SizedBox(height: 16),
                                  Text(
                                    'No projects match your search',
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final project = filtered[index];
                        final projectId = project['id']?.toString();
                        final projectName = project['name']?.toString() ?? 'Unnamed Project';
                        final clientName = project['client_name']?.toString();
                        final isSelected = selectedProjectId?.toString() == projectId;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.getPrimaryColor(context).withOpacity(0.1)
                                : Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColorConst
                                  : AppTheme.getPrimaryColor(context).withOpacity(0.2),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  selectedProjectId = int.tryParse(projectId ?? '');
                                  selectedProjectName = projectName;
                                });
                                _searchController.clear();
                                Navigator.pop(context);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        Icons.folder_special,
                                        color: AppTheme.getPrimaryColor(context),
                                        size: 16,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            projectName,
                                            style: TextStyle(
                                              color: AppTheme.getTextPrimary(context),
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                          if (clientName != null && clientName.isNotEmpty) ...[
                                            SizedBox(height: 2),
                                            Text(
                                              clientName,
                                              style: TextStyle(
                                                color: AppTheme.getTextSecondary(context),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                          if (projectId != null) ...[
                                            SizedBox(height: 2),
                                            Text(
                                              'ID: $projectId',
                                              style: TextStyle(
                                                color: AppTheme.getTextSecondary(context),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: AppTheme.getPrimaryColor(context),
                                        size: 20,
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
            );
          },
        ),
      ),
    );
  }

  void _showUserPicker() async {
    if (selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a project first')),
      );
      return;
    }
    
    final result = await UserPickerScreen.show(
      context,
      projectId: selectedProjectId,
    );

    if (result != null && mounted) {
      print('[AdminDashboard] User picker result: $result');
      print('[AdminDashboard] Result keys: ${result.keys.toList()}');
      
      setState(() {
        // Try different possible ID field names
        final userIdStr = result['user_id']?.toString() ?? 
                         result['id']?.toString() ?? 
                         result['userId']?.toString() ?? '';
        selectedUserId = userIdStr.isNotEmpty ? int.tryParse(userIdStr) : null;
        
        // Try different possible name field names
        selectedUserName = result['user_name']?.toString() ?? 
                          result['name']?.toString() ?? 
                          result['username']?.toString();
        
        print('[AdminDashboard] Set selectedUserId: $selectedUserId');
        print('[AdminDashboard] Set selectedUserName: $selectedUserName');
      });
    }
  }

  Widget _buildStatusDropdownForForm() {
    final statuses = [
      {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706), 'icon': Icons.pending},
      {'value': 'in_progress', 'label': 'In Progress', 'color': AppTheme.getPrimaryColor(context), 'icon': Icons.work},
      {'value': 'completed', 'label': 'Completed', 'color': Color(0xFF10B981), 'icon': Icons.check_circle},
      {'value': 'cancelled', 'label': 'Cancelled', 'color': Color(0xFFEF4444), 'icon': Icons.cancel},
    ];

    final currentStatusData = statuses.firstWhere(
      (s) => s['value'] == selectedStatus,
      orElse: () => statuses[0],
    );
    final currentColor = currentStatusData['color'] as Color;
    final currentIcon = currentStatusData['icon'] as IconData;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        value: selectedStatus,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.getTextSecondary(context)),
        dropdownColor: AppTheme.backgroundPrimaryLight,
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 14,
        ),
        items: statuses.map((statusData) {
          final status = statusData['value'] as String;
          final label = statusData['label'] as String;
          final color = statusData['color'] as Color;
          final icon = statusData['icon'] as IconData;
          
          return DropdownMenuItem<String>(
            value: status,
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (String? newStatus) {
          if (newStatus != null) {
            setState(() {
              selectedStatus = newStatus;
            });
          }
        },
        selectedItemBuilder: (BuildContext context) {
          return statuses.map((statusData) {
            final label = statusData['label'] as String;
            return Row(
              children: [
                Icon(currentIcon, size: 16, color: currentColor),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.getTextPrimary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Create New Task',
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(20),
          children: [
            // Project Picker
            Text(
              'Project *',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
            SizedBox(height: 8),
            InkWell(
              onTap: () => _showProjectPicker(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedProjectId == null 
                        ? AppTheme.getPrimaryColor(context).withOpacity(0.3)
                        : AppTheme.getPrimaryColor(context).withOpacity(0.5),
                    width: selectedProjectId == null ? 1 : 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_special,
                      color: AppTheme.getPrimaryColor(context),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: selectedProjectId == null
                          ? Text(
                              'Select a project',
                              style: TextStyle(
                                color: AppTheme.getTextSecondary(context),
                                fontSize: 14,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedProjectName ?? 'Project',
                                  style: TextStyle(
                                    color: AppTheme.getTextPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                if (selectedProjectId != null)
                                  Text(
                                    'ID: $selectedProjectId',
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
            if (selectedProjectId == null)
              Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Please select a project',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 11,
                  ),
                ),
              ),
            SizedBox(height: 20),
            
            // User Picker (Assign To)
            Text(
              'Assign To',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
            SizedBox(height: 8),
            InkWell(
              onTap: () => _showUserPicker(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedUserId == null 
                        ? AppTheme.getPrimaryColor(context).withOpacity(0.3)
                        : AppTheme.getPrimaryColor(context).withOpacity(0.5),
                    width: selectedUserId == null ? 1 : 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: AppTheme.getPrimaryColor(context),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: selectedUserId == null
                          ? Text(
                              'Select a user (optional)',
                              style: TextStyle(
                                color: AppTheme.getTextSecondary(context),
                                fontSize: 14,
                              ),
                            )
                          : Text(
                              selectedUserName ?? 'User',
                              style: TextStyle(
                                color: AppTheme.getTextPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            
            // Status Dropdown
            Text(
              'Status',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
            SizedBox(height: 8),
            _buildStatusDropdownForForm(),
            SizedBox(height: 20),
            
            // Note
            Text(
              'Note / Description',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
            SizedBox(height: 8),
            TextFormField(
              controller: noteController,
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Task note cannot be empty';
                }
                return null;
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.backgroundPrimaryLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.getPrimaryColor(context), width: 2),
                ),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.note, color: AppTheme.getPrimaryColor(context)),
                ),
                hintText: 'Enter task description...',
                labelText: 'Note / Description *',
              ),
            ),
            SizedBox(height: 30),
            
            // Submit Button - Green
            Container(
              decoration: BoxDecoration(
                color: Color(0xFF10B981),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLoading ? null : _createTask,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Create Task',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                    ),
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



class Dashboard extends StatefulWidget {
  @override
  DashboardState createState() {
    return DashboardState();
  }
}

class DashboardState extends State<Dashboard> {
  var update = "";
  var username = "";
  var date = "";
  var role = "";
  var userId;
  var data;
  var searchData;
  bool _isLoading = false;
  String? _errorMessage;
  final _searchController = TextEditingController();
  List<dynamic> _projects = [];

  @override
  void initState() {
    super.initState();
    call();
    _loadProjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      await DataProvider().reloadData(force: false);
      if (mounted) {
        setState(() {
          _projects = List<dynamic>.from(DataProvider().projects);
        });
      }
    } catch (e) {
      print('[Dashboard] Error loading projects: $e');
    }
  }

  void _showProjectPicker() {
    _searchController.clear();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final query = _searchController.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? _projects
                : _projects.where((project) {
                    final name = project['name']?.toString().toLowerCase() ?? '';
                    final id = project['id']?.toString() ?? '';
                    final client = project['client_name']?.toString().toLowerCase() ?? '';
                    return name.contains(query) || id.contains(query) || client.contains(query);
                  }).toList();

            return Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select Project',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
                        onPressed: () {
                          _searchController.clear();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.black.withOpacity(0.3)
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Search projects by name, ID, or client...',
                      hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search, color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppTheme.getTextSecondary(context), size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.getBackgroundSecondary(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context),
                          width: 2,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: _projects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, size: 48, color: AppTheme.getTextSecondary(context)),
                              SizedBox(height: 16),
                              Text(
                                'No projects available',
                                style: TextStyle(
                                  color: AppTheme.getTextSecondary(context),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 48, color: AppTheme.getTextSecondary(context)),
                                  SizedBox(height: 16),
                                  Text(
                                    'No projects match your search',
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final project = filtered[index];
                                final projectId = project['id']?.toString();
                                final projectName = project['name']?.toString() ?? 'Unnamed Project';
                                final clientName = project['client_name']?.toString();

                                return Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.getBackgroundPrimary(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        SharedPreferences prefs = await SharedPreferences.getInstance();
                                        await prefs.setString("project_id", projectId ?? '');
                                        await prefs.setString("client_name", projectName);

                                        // Preload project data for non-Client users
                                        final role = prefs.getString('role');
                                        if (role != null && role != 'Client') {
                                          DataProvider().loadProjectDataForNonClient(projectId ?? '').catchError((e) {
                                            print('[Dashboard] Error preloading project data: $e');
                                          });
                                        }
                                        _searchController.clear();
                                        Navigator.pop(context);
                                        Navigator.pushReplacement(
                                          context,
                                          PageRouteBuilder(
                                            pageBuilder: (context, animation, secondaryAnimation) => Home(fromAdminDashboard: true),
                                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                              return FadeTransition(
                                                opacity: animation,
                                                child: SlideTransition(
                                                  position: Tween<Offset>(
                                                    begin: const Offset(0.3, 0.0),
                                                    end: Offset.zero,
                                                  ).animate(CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOutCubic,
                                                  )),
                                                  child: child,
                                                ),
                                              );
                                            },
                                            transitionDuration: Duration(milliseconds: 300),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Icon(
                                                Icons.folder_special,
                                                color: AppTheme.getPrimaryColor(context),
                                                size: 16,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    projectName,
                                                    style: TextStyle(
                                                      color: AppTheme.getTextPrimary(context),
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (clientName != null && clientName.isNotEmpty) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      clientName,
                                                      style: TextStyle(
                                                        color: AppTheme.getTextSecondary(context),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                  if (projectId != null) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'ID: $projectId',
                                                      style: TextStyle(
                                                        color: AppTheme.getTextSecondary(context),
                                                        fontSize: 10,
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
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> call({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      role = prefs.getString('role') ?? '';
      userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');

      if (userId == null || apiToken == null || role.isEmpty) {
        throw Exception('Missing credentials to load your projects. Please log in again.');
      }

      final payload = {"user_id": userId, "role": role, "api_token": apiToken};
      print('user_id: $userId'); 
      final uri = Uri.parse("https://office1.buildahome.in/API/get_projects_for_user");
      print('[Dashboard] Loading projects with $payload');
      final response = await http.post(uri, body: payload).timeout(const Duration(seconds: 20));
      print('response: ${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Unable to load projects right now (code ${response.statusCode}). Pull to refresh to retry.');
      }

      final decoded = jsonDecode(response.body);

      setState(() {
        data = decoded;
        searchData = data;
        username = prefs.getString('username') ?? '';
      });
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Request timed out while loading projects. Pull down to retry.';
      });
    } catch (e) {
      print('[Dashboard] Error loading projects: $e');
      setState(() {
        _errorMessage = 'Something went wrong while loading your projects. Pull down to retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => call(force: true),
      color: AppTheme.getPrimaryColor(context),
      child: Container(
          child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(25),
        children: <Widget>[
          Container(
            padding: EdgeInsets.only(bottom: 10),
            margin: EdgeInsets.only(bottom: 10, right: 100),
            child: Text("Projects handled by you", style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal)),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 3))),
          ),
          if (_errorMessage != null)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[800], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            margin: EdgeInsets.only(bottom: 10, top: 10),
            child: InkWell(
              onTap: () => _showProjectPicker(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundPrimaryLight(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_special,
                      color: AppTheme.getPrimaryColor(context),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Select a project',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }
}

class HomeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
