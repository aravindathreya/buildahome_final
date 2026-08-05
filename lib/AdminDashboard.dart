import 'dart:async';
import 'dart:convert';

import 'package:buildAhome/AddDailyUpdate.dart';
import 'package:buildAhome/UserHome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/notification_service.dart';
import 'services/profile_picture_service.dart';
import 'services/rbac_service.dart';
import 'services/api_http.dart';
import 'services/session_manager.dart';
import 'stock_report.dart';
import 'TasksScreen.dart';
import 'MyTasksScreen.dart';
import 'Skin2/loginPage.dart';
import 'NavMenu.dart';
import 'NotesAndComments.dart';
import 'utilities/role_app_bar_color.dart';
import 'widgets/dashboard_chrome.dart';
import 'widgets/modern_task_card.dart';
import 'widgets/opening_project_splash.dart';
import 'widgets/profile_picture_dialog.dart';

class AdminDashboard extends StatefulWidget {
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const Color _navy = Color(0xFF1B254B);
  static const Color _mutedGrey = Color(0xFF8A94A6);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AdminHomeState> _adminHomeKey = GlobalKey<AdminHomeState>();
  int _rebuildTrigger = 0;
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
  int _bottomNavIndex = 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptForProfilePicture(context);
    });
  }

  @override
  void dispose() {
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  Future<void> _onBottomNavTap(int index) async {
    if (index == 0) {
      setState(() => _bottomNavIndex = 0);
      return;
    }
    if (index == 4) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }

    setState(() => _bottomNavIndex = index);
    final home = _adminHomeKey.currentState;
    if (home == null) {
      setState(() => _bottomNavIndex = 0);
      return;
    }

    switch (index) {
      case 1:
        await home.openTasksScreen();
        break;
      case 2:
        await home.openProjectsPicker();
        break;
      case 3:
        await home.openSiteVisits();
        break;
    }
    if (mounted) setState(() => _bottomNavIndex = 0);
  }

  Widget _buildBottomNav() {
    final items = <_AdminDashNavItem>[
      _AdminDashNavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
      _AdminDashNavItem(
          Icons.pending_actions_rounded, Icons.pending_actions_outlined, 'Tasks'),
      _AdminDashNavItem(
          Icons.folder_special_rounded, Icons.folder_special_outlined, 'Projects'),
      _AdminDashNavItem(
          Icons.location_on_rounded, Icons.location_on_outlined, 'Site Visits'),
      _AdminDashNavItem(Icons.menu_rounded, Icons.menu_rounded, 'More'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF1F5))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = _bottomNavIndex == index;
              final color = selected ? _navy : _mutedGrey;
              return Expanded(
                child: InkWell(
                  onTap: () => _onBottomNavTap(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? item.activeIcon : item.icon,
                          color: color,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 10.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: NavMenuWidget(),
      appBar: null,
      body: GestureDetector(
        onTap: () {
          // Hide search results when tapping outside
          if (_adminHomeKey.currentState != null) {
            _adminHomeKey.currentState!._quickSearchFocusNode.unfocus();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: AdminHome(
          key: _adminHomeKey,
          searchQueryNotifier: _searchQueryNotifier,
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}

class _AdminDashNavItem {
  final IconData activeIcon;
  final IconData icon;
  final String label;
  const _AdminDashNavItem(this.activeIcon, this.icon, this.label);
}

class _AdminHeroStat extends StatelessWidget {
  final String value;
  final String label;
  const _AdminHeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFC7D0E0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
      NotificationService.instance.clear();
      ProfilePictureService.promptShownThisSession = false;

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
  static const Color _navy = Color(0xFF1B254B);
  static const Color _mutedGrey = Color(0xFF8A94A6);
  static const Color _cardBorder = Color(0xFFE8ECF1);
  static const Color _softShadow = Color(0x14000000);

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
  Map<int, Map<String, dynamic>> _previousTasksMap =
      {}; // Track previous tasks for comparison

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
    await ProfilePictureService.getStoredPath();
    if (!mounted) return;
    setState(() {
      currentUserRole = prefs.getString('role') ?? '';
      currentUserName = prefs.getString('username') ?? '';
    });
  }

  Color get _roleAppBarColor => RoleAppBarColor.forRole(currentUserRole);

  String _projectsDeltaKey(List<dynamic> list) {
    return list
        .whereType<Map>()
        .map((p) => '${p['id']}|${p['name']}|${p['client_name']}')
        .join('||');
  }

  Future<void> loadProjects({
    bool force = false,
    bool showLoader = false,
    bool refreshTasks = true,
    bool silentTasks = false,
  }) async {
    if (!mounted) return;

    if (showLoader) {
      setState(() {
        _isLoadingProjects = true;
        _projectsError = null;
      });
    } else {
      _isRefreshingProjects = true;
      _projectsError = null;
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

      final previousKey = _projectsDeltaKey(projects);
      final nextKey = _projectsDeltaKey(newProjects);
      final projectsChanged = previousKey != nextKey;

      if (projectsChanged || showLoader) {
        setState(() {
          projects = newProjects;
          projectsToShow = projects;
          if (_cachedFilterQuery.isNotEmpty) {
            final query = _cachedFilterQuery.toLowerCase();
            projectsToShow = projects.where((project) {
              final name = project['name']?.toString().toLowerCase() ?? '';
              final id = project['id']?.toString().toLowerCase() ?? '';
              final clientName =
                  project['client_name']?.toString().toLowerCase() ?? '';
              return name.contains(query) ||
                  id.contains(query) ||
                  clientName.contains(query);
            }).toList();
          }
          _isLoadingProjects = false;
          _isRefreshingProjects = false;
        });
      } else {
        _isLoadingProjects = false;
        _isRefreshingProjects = false;
      }

      // Reload tasks after projects are loaded to filter by project IDs
      if (refreshTasks) {
        await loadTasks(silent: silentTasks || !showLoader);
      }
    } catch (e) {
      print('[AdminDashboard] Error loading projects: $e');
      if (!mounted) return;
      setState(() {
        _projectsError =
            'Unable to refresh projects. Please pull down to retry.';
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
    _loadUnreadNotifications();
    // Use projects already loaded at app/login startup so the UI opens immediately.
    final initialProjects = DataProvider().projects;
    setState(() {
      projects = initialProjects;
      projectsToShow = projects;
    });
    // Refresh in background; only show a loader if nothing is cached yet.
    loadProjects(
      force: initialProjects.isEmpty,
      showLoader: initialProjects.isEmpty,
    );
    _startProjectsAutoRefresh();
    // Note: loadTasks() will be called by loadProjects() after projects are loaded
  }

  Future<void> _loadUnreadNotifications({bool force = false}) async {
    final service = NotificationService.instance;
    await service.ensureHydrated();
    await service.sync(force: force);
  }

  String _displayName() {
    final raw = currentUserName.trim();
    if (raw.isEmpty) return 'there';
    final first = raw.split('-').first.trim();
    return first.isNotEmpty ? first : raw;
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Future<void> openTasksScreen() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      await _navigateWithAnimation(
        context,
        MyTasksScreen(
          tasks: _tasks,
          onRefresh: _refreshTasksForMyTasks,
        ),
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> openProjectsPicker() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      await ProjectPickerScreen.show(context);
      if (mounted) loadProjects();
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> openSiteVisits() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      await _navigateWithAnimation(context, SiteVisitReportsScreen());
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _startProjectsAutoRefresh() {
    _projectsRefreshTimer?.cancel();
    _projectsRefreshTimer = Timer.periodic(Duration(minutes: 1), (_) {
      if (!mounted) return;
      // Silent background refresh — UI updates only when data changes.
      loadProjects(
        force: false,
        showLoader: false,
        refreshTasks: true,
        silentTasks: true,
      );
    });
  }

  String _taskDeltaKey(Map task) {
    return [
      task['id'],
      task['status'],
      task['workflow_status'],
      task['note'],
      task['s_note'],
      task['updated_at'],
      task['created_at'],
      task['assigned_to'],
      task['assigned_to_name'],
      task['project_id'],
      task['project_name'],
      task['can_update_workflow_task'],
      task['can_approve_workflow_task'],
      task['pending_manager_approval'],
      jsonEncode(task['workflow_task_actions'] ?? const []),
      jsonEncode(task['workflow_actions'] ?? const []),
      jsonEncode(task['workflow_delay_gate'] ?? const {}),
    ].join('|');
  }

  Future<void> loadTasks({bool silent = false}) async {
    if (!mounted) return;

    // Prevent multiple simultaneous calls
    if (_isLoadingTasks) {
      print(
          '[AdminDashboard] loadTasks already in progress, skipping duplicate call');
      return;
    }

    final showLoader = !silent && !_hasLoadedTasksOnce;
    if (showLoader) {
      setState(() {
        _isLoadingTasks = true;
        _tasksError = null;
      });
    } else {
      _isLoadingTasks = true;
      _tasksError = null;
    }

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
      Uri uri = Uri.parse("https://office.buildahome.in/API/get_tasks").replace(
        queryParameters: queryParams,
      );

      print('Uri ${uri.toString()}');
      var response = await ApiHttp.get(uri).timeout(const Duration(seconds: 20));
      print('Response ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> fetchedTasks = [];

        if (decoded is Map &&
            decoded['success'] == true &&
            decoded['tasks'] != null) {
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
            if (taskId != 0) {
              taskMap[taskId] = task;
            }
          }
        }
        allTasks = taskMap.values.toList();

        // API uses OR logic across filters, so keep only tasks assigned to user.
        allTasks = filterTasksForProjectAndAssignee(
          allTasks,
          userId: userId,
        );

        // Check if tasks have changed
        Map<int, Map<String, dynamic>> currentTasksMap = {};
        for (var task in allTasks) {
          if (task is Map && task['id'] != null) {
            int taskId = int.tryParse(task['id'].toString()) ?? 0;
            if (taskId != 0) {
              currentTasksMap[taskId] = Map<String, dynamic>.from(task);
            }
          }
        }

        // Compare with previous tasks to detect meaningful deltas
        bool hasChanges = false;
        if (!_hasLoadedTasksOnce ||
            _previousTasksMap.length != currentTasksMap.length) {
          hasChanges = true;
        } else {
          for (var entry in currentTasksMap.entries) {
            final prevTask = _previousTasksMap[entry.key];
            if (prevTask == null ||
                _taskDeltaKey(prevTask) != _taskDeltaKey(entry.value)) {
              hasChanges = true;
              break;
            }
          }
        }

        allTasks.sort((a, b) {
          if (a is! Map || b is! Map) return 0;
          String aDate = (a['created_at'] ?? '').toString();
          String bDate = (b['created_at'] ?? '').toString();
          return bDate.compareTo(aDate);
        });

        // Update UI only if there are changes — avoid reload flicker.
        if (!mounted) return;
        if (hasChanges) {
          setState(() {
            _tasks = allTasks;
            _isLoadingTasks = false;
            _hasLoadedTasksOnce = true;
            _previousTasksMap = currentTasksMap;
          });
        } else {
          _isLoadingTasks = false;
          _hasLoadedTasksOnce = true;
        }
      } else if (response.statusCode == 404) {
        // No tasks found - this is okay
        if (!mounted) return;
        if (_tasks.isNotEmpty || _isLoadingTasks || !_hasLoadedTasksOnce) {
          setState(() {
            _tasks = [];
            _isLoadingTasks = false;
            _hasLoadedTasksOnce = true;
            _previousTasksMap = {};
          });
        } else {
          _isLoadingTasks = false;
          _hasLoadedTasksOnce = true;
        }
      } else {
        throw Exception('Unable to load tasks (code ${response.body})');
      }
    } catch (e) {
      if (e is SessionInvalidatedException) return;
      if (!mounted) return;
      print('[AdminDashboard] Error loading tasks: $e');
      // Keep existing tasks on background refresh errors to avoid wipe/flicker.
      if (silent && _hasLoadedTasksOnce) {
        _isLoadingTasks = false;
        return;
      }
      setState(() {
        _tasksError = e.toString().replaceAll('Exception: ', '');
        _isLoadingTasks = false;
        _hasLoadedTasksOnce = true;
        _tasks = [];
        _previousTasksMap = {};
      });
    }
  }

  Future<List<dynamic>> _refreshTasksForMyTasks() async {
    await loadTasks(silent: true);
    return List<dynamic>.from(_tasks);
  }

  Future<void> updateTaskStatus(int taskId, String newStatus) async {
    if (taskId < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Workflow tasks cannot be updated from this screen yet.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? apiToken = prefs.getString('api_token');

      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri =
          Uri.parse("https://office.buildahome.in/API/update_task_status");
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
        throw Exception(
            'Unable to update task status (code ${response.statusCode})');
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

    menuItems.add({
      'title': 'My tasks',
      'icon': Icons.pending_actions,
      'route': () => MyTasksScreen(
            tasks: _tasks,
            onRefresh: _refreshTasksForMyTasks,
          ),
    });

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
    final menuItems = getMenuItems();
    final visibleActions = menuItems.take(8).toList();
    final totalProjects = projects.length;
    final pendingCount = _tasks.where((task) {
      if (task is Map) {
        final status = task['status']?.toString().toLowerCase() ?? '';
        return status == 'pending';
      }
      return false;
    }).length;

    return RefreshIndicator(
      onRefresh: () async {
        await loadProjects(force: true);
        await loadTasks();
        await _loadUnreadNotifications(force: true);
      },
      color: _navy,
      child: Container(
        color: Colors.white,
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _buildUserHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _buildHeroBanner(),
                  const SizedBox(height: 16),
                  _buildSearchField(),
                  const SizedBox(height: 16),
                  if (_projectsError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _projectsError!,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (currentUserRole != 'Client')
                    _buildOverviewCard(totalProjects, pendingCount),
                  const SizedBox(height: 18),
                  if (currentUserRole != 'Billing') _buildTasksSection(),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showAllQuickActions(menuItems),
                        child: const Text(
                          'View all',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: visibleActions.length,
                    itemBuilder: (BuildContext context, int index) {
                      final item = visibleActions[index];
                      final title = item['title'].toString();
                      final colors = _quickActionColors(title);
                      return InkWell(
                        onTap: _isNavigating
                            ? null
                            : () async {
                                await _handleMenuTap(context, item);
                              },
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: colors['bg'],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _quickActionIcon(
                                    title, item['icon'] as IconData),
                                size: 24,
                                color: colors['fg'],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _quickActionLabel(title),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    final topPad = MediaQuery.of(context).padding.top;
    final name = _displayName();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        width: MediaQuery.of(context).size.width,
        padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, 8),
        color: _roleAppBarColor,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greetingForNow(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$name 👋',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardChrome.wrap(
                      DashboardChromeStyle.admin,
                      const Notifications(),
                      appBarColor: _roleAppBarColor,
                    ),
                  ),
                );
                _loadUnreadNotifications(force: true);
              },
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable:
                      NotificationService.instance.unreadCountNotifier,
                  builder: (context, unreadCount, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Center(
                          child: Icon(
                            Icons.notifications_none_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 16),
                              height: 16,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Builder(
              builder: (context) => ValueListenableBuilder<String?>(
                valueListenable: ProfilePictureService.picturePathNotifier,
                builder: (context, picturePath, _) {
                  return ProfileAvatar(
                    displayName: name,
                    picturePath: picturePath,
                    size: 40,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    borderColor: Colors.white.withValues(alpha: 0.35),
                    onTap: () => Scaffold.of(context).openDrawer(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 128,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B254B), Color(0xFF243463)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              right: -10,
              bottom: -20,
              child: Opacity(
                opacity: 0.12,
                child: Icon(
                  Icons.home_work_outlined,
                  size: 160,
                  color: Colors.white,
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 16, 8, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _AdminHeroStat(value: '1700+', label: 'Projects'),
                        _AdminHeroStat(value: '18+', label: 'Cities'),
                        _AdminHeroStat(
                            value: '5M+', label: 'Sq. Ft of Build Area'),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 132,
                  height: double.infinity,
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.transparent, Colors.white, Colors.white],
                        stops: [0.0, 0.22, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: Image.asset(
                      'assets/images/Good going.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.35),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(int totalProjects, int pendingCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: _softShadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/home1.jpg',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFFEEF2FF),
                    child: const Icon(Icons.apartment_rounded, color: _navy),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WORKSPACE',
                      style: TextStyle(
                        color: _mutedGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      currentUserRole.isNotEmpty
                          ? currentUserRole
                          : 'Team Dashboard',
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pendingCount > 0
                          ? '$pendingCount pending task${pendingCount == 1 ? '' : 's'} need attention'
                          : 'All caught up — no pending tasks',
                      style: const TextStyle(
                        color: _mutedGrey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  label: 'Projects',
                  value: '$totalProjects',
                  color: const Color(0xFF2563EB),
                  bg: const Color(0xFFDBEAFE),
                  icon: Icons.folder_special_rounded,
                  onTap: openProjectsPicker,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMiniStat(
                  label: 'Pending',
                  value: '$pendingCount',
                  color: const Color(0xFFEAB308),
                  bg: const Color(0xFFFFF1D6),
                  icon: Icons.pending_actions_rounded,
                  onTap: openTasksScreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    required Color bg,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isNavigating ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _mutedGrey,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Opacity(
      opacity: _isNavigating ? 0.6 : 1.0,
      child: InkWell(
        onTap: _isNavigating ? null : openProjectsPicker,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
            boxShadow: const [
              BoxShadow(
                color: _softShadow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              if (_isNavigating)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_navy),
                  ),
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.folder_special_rounded,
                    color: _navy,
                    size: 18,
                  ),
                ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select a project',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Open a project to manage work',
                      style: TextStyle(
                        color: _mutedGrey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: _mutedGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, Color> _quickActionColors(String title) {
    switch (title.toLowerCase()) {
      case 'projects':
        return {
          'bg': const Color(0xFFDBEAFE),
          'fg': const Color(0xFF2563EB),
        };
      case 'my tasks':
      case 'tasks':
        return {
          'bg': const Color(0xFFFFF1D6),
          'fg': const Color(0xFFEAB308),
        };
      case 'daily update':
        return {
          'bg': const Color(0xFFE0E7FF),
          'fg': const Color(0xFF4F46E5),
        };
      case 'indents':
        return {
          'bg': const Color(0xFFFFEDD5),
          'fg': const Color(0xFFEA580C),
        };
      case 'stock report':
        return {
          'bg': const Color(0xFFCCFBF1),
          'fg': const Color(0xFF0D9488),
        };
      case 'site visits':
        return {
          'bg': const Color(0xFFE0F2FE),
          'fg': const Color(0xFF0284C7),
        };
      case 'test reports':
        return {
          'bg': const Color(0xFFF3E8FF),
          'fg': const Color(0xFF7C3AED),
        };
      case 'checklist':
        return {
          'bg': const Color(0xFFF5E6D3),
          'fg': const Color(0xFFB45309),
        };
      case 'chatbox':
      case 'chat':
        return {
          'bg': const Color(0xFFE0E7FF),
          'fg': const Color(0xFF4F46E5),
        };
      case 'my notifications':
        return {
          'bg': const Color(0xFFFFE4E6),
          'fg': const Color(0xFFE11D48),
        };
      default:
        return {
          'bg': const Color(0xFFEEF2FF),
          'fg': _navy,
        };
    }
  }

  String _quickActionLabel(String title) {
    switch (title) {
      case 'My tasks':
        return 'Tasks';
      case 'Daily Update':
        return 'Updates';
      case 'Stock Report':
        return 'Stock';
      case 'Site Visits':
        return 'Visits';
      case 'Test Reports':
        return 'Tests';
      case 'ChatBox':
        return 'Chat';
      case 'My Notifications':
        return 'Alerts';
      default:
        return title;
    }
  }

  IconData _quickActionIcon(String title, IconData fallback) {
    switch (title) {
      case 'Projects':
        return Icons.folder_special_rounded;
      case 'My tasks':
        return Icons.assignment_outlined;
      case 'Daily Update':
        return Icons.campaign_rounded;
      case 'Indents':
        return Icons.request_quote_outlined;
      case 'Stock Report':
        return Icons.inventory_2_outlined;
      case 'Site Visits':
        return Icons.location_on_outlined;
      case 'Test Reports':
        return Icons.science_outlined;
      case 'Checklist':
        return Icons.checklist_rtl_rounded;
      case 'ChatBox':
        return Icons.chat_bubble_outline_rounded;
      case 'My Notifications':
        return Icons.notifications_none_rounded;
      default:
        return fallback;
    }
  }

  Future<void> _showAllQuickActions(List<Map<String, dynamic>> items) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All Actions',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final title = item['title'].toString();
                      final colors = _quickActionColors(title);
                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _handleMenuTap(context, item);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: colors['bg'],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _quickActionIcon(
                                    title, item['icon'] as IconData),
                                size: 24,
                                color: colors['fg'],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _quickActionLabel(title),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                  final projectName =
                      project['name']?.toString() ?? 'Unnamed project';
                  final projectId = project['id']?.toString() ?? '';
                  final clientName = project['client_name']?.toString() ?? '';

                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundPrimaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            AppTheme.getPrimaryColor(context).withOpacity(0.2),
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
                          final projectNameStr =
                              project['name']?.toString() ?? 'Project';

                          if (projectIdStr == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('Unable to open this project.')),
                            );
                            return;
                          }

                          setState(() {
                            _isNavigating = true;
                          });
                          _clearQuickSearch();

                          try {
                            // Show splash immediately; do prefs/API work while it displays.
                            await OpeningProjectGate.push(
                              context,
                              projectName: projectNameStr,
                              destination: Home(fromAdminDashboard: true),
                              prepare: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString(
                                    "project_id", projectIdStr);
                                await prefs.setString(
                                    "client_name", projectNameStr);

                                await DataProvider().onProjectSelected(
                                  erpProjectId: projectIdStr,
                                  project:
                                      Map<String, dynamic>.from(project),
                                );

                                final role = prefs.getString('role');
                                if (role != null && role != 'Client') {
                                  DataProvider().resetProjectData();
                                  DataProvider()
                                      .loadProjectDataForNonClient(
                                          projectIdStr)
                                      .catchError((e) {
                                    print(
                                        '[AdminDashboard] Error preloading project data: $e');
                                  });
                                }
                              },
                            );
                            if (mounted) {
                              loadProjects();
                            }
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
                                  color: AppTheme.getPrimaryColor(context)
                                      .withOpacity(0.15),
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
                                          color: AppTheme.getTextSecondary(
                                              context),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    if (projectId.isNotEmpty) ...[
                                      SizedBox(height: 2),
                                      Text(
                                        'ID: $projectId',
                                        style: TextStyle(
                                          color: AppTheme.getTextSecondary(
                                              context),
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
    if (!mounted) return;
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
        pageBuilder: (context, animation, secondaryAnimation) =>
            DashboardChrome.wrap(
              DashboardChromeStyle.admin,
              destination,
              appBarColor: _roleAppBarColor,
            ),
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

  Future<void> _handleMenuTap(
      BuildContext context, Map<String, dynamic> item) async {
    // Prevent double-tap navigation
    if (_isNavigating) {
      return;
    }

    if (item['title'] == 'Log out') {
      DataProvider().clearData();
      await NotificationService.instance.clear();
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

  Widget _buildStatCard(BuildContext context, String title, String value,
      IconData icon, Color color,
      {int index = 0, VoidCallback? onTap}) {
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

  List<Map<String, dynamic>> get _activeRecentTasks =>
      filterActiveRecentTasks(_tasks);

  Widget _buildTasksSection() {
    final recent = _activeRecentTasks.take(4).toList();
    final pendingCount = _tasks.where((task) {
      if (task is! Map) return false;
      final status = task['status']?.toString().toLowerCase() ?? '';
      return status == 'pending' ||
          status == 'in_progress' ||
          status == 'ready' ||
          status == 'scheduled';
    }).length;
    final completedCount = _tasks.where((task) {
      if (task is! Map) return false;
      return kCompletedTaskStatuses
          .contains(task['status']?.toString().toLowerCase() ?? '');
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TaskSummaryStatCard(
                value: '$pendingCount',
                label: 'Pending tasks',
                icon: Icons.assignment_outlined,
                iconColor: const Color(0xFFEAB308),
                iconBg: const Color(0xFFFFF1D6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TaskSummaryStatCard(
                value: '$completedCount',
                label: 'Completed tasks',
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF16A34A),
                iconBg: const Color(0xFFDCFCE7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent tasks',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardChrome.wrap(
                      DashboardChromeStyle.admin,
                      MyTasksScreen(
                        tasks: _tasks,
                        onRefresh: _refreshTasksForMyTasks,
                      ),
                      appBarColor: _roleAppBarColor,
                    ),
                  ),
                );
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View all',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: _navy,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _showCreateTaskDialog(),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 15),
                      SizedBox(width: 4),
                      Text(
                        'New task',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_tasksError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFDC2626), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tasksError!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_isLoadingTasks)
          Column(
            children: List.generate(
              3,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildTaskCardSkeleton(),
              ),
            ),
          )
        else if (recent.isEmpty && _tasksError == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.task_alt, size: 28, color: _navy),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No tasks found',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Create your first task',
                  style: TextStyle(
                    color: _mutedGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: _navy,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => _showCreateTaskDialog(),
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        'New task',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < recent.length; index++)
                if (recent[index] is Map)
                  _buildModernRecentTaskCard(
                    Map<String, dynamic>.from(recent[index] as Map),
                    index,
                  ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DashboardChrome.wrap(
                          DashboardChromeStyle.admin,
                          MyTasksScreen(
                            tasks: _tasks,
                            onRefresh: _refreshTasksForMyTasks,
                          ),
                          appBarColor: _roleAppBarColor,
                        ),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all tasks',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildModernRecentTaskCard(Map<String, dynamic> task, int index) {
    final taskId = task['id']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final status = task['status']?.toString() ?? 'pending';
    final note = task['note']?.toString() ?? '';
    final createdAt = task['created_at']?.toString() ?? '';
    final title = note.trim().isNotEmpty
        ? _toSentenceCase(note.trim())
        : 'Task #$taskId';

    String? dateLabel;
    if (createdAt.isNotEmpty) {
      try {
        dateLabel =
            DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(createdAt));
      } catch (_) {
        dateLabel = createdAt;
      }
    }

    return ModernTaskCard(
      title: title,
      projectName: projectName,
      assigneeName: assignedToName,
      dateLabel: dateLabel,
      status: status,
      accentIndex: index,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardChrome.wrap(
              DashboardChromeStyle.admin,
              MyTasksScreen(
                tasks: _tasks,
                onRefresh: _refreshTasksForMyTasks,
                focusTaskId: taskId,
              ),
              appBarColor: _roleAppBarColor,
            ),
          ),
        );
      },
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

  Widget _buildTaskAvatar({
    required String userName,
    required String assignedToName,
    required Color fallbackColor,
    required IconData fallbackIcon,
  }) {
    Widget avatarFor(String name) {
      return CircleAvatar(
        radius: 10,
        backgroundColor: _getColorFromName(name),
        child: Text(
          name[0].toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.normal,
          ),
        ),
      );
    }

    if (userName.isNotEmpty &&
        assignedToName.isNotEmpty &&
        assignedToName != userName) {
      return SizedBox(
        width: 34,
        height: 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatarFor(userName),
            Positioned(
              left: 14,
              child: avatarFor(assignedToName),
            ),
          ],
        ),
      );
    }

    if (userName.isNotEmpty) return avatarFor(userName);
    if (assignedToName.isNotEmpty) return avatarFor(assignedToName);

    return CircleAvatar(
      radius: 10,
      backgroundColor: fallbackColor,
      child: Icon(fallbackIcon, color: Colors.white, size: 12),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final taskId = task['id']?.toString() ?? '';
    final projectId = task['project_id']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final assignedTo = task['assigned_to']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final userName = task['user_name']?.toString() ?? '';
    final userId =
        task['user_id']?.toString() ?? task['created_by']?.toString() ?? '';
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

    final avatarWidget = _buildTaskAvatar(
      userName: userName,
      assignedToName: assignedToName,
      fallbackColor: statusColor,
      fallbackIcon: statusIcon,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardChrome.wrap(
                DashboardChromeStyle.admin,
                MyTasksScreen(
                  tasks: _tasks,
                  onRefresh: _refreshTasksForMyTasks,
                  focusTaskId: taskId,
                ),
                appBarColor: _roleAppBarColor,
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
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
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
    final baseColor = const Color(0xFFE8ECF1);
    final highlightColor = const Color(0xFFF8FAFC);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    final isWorkflowTask = taskId < 0;
    return TaskStatusChipSet(
      currentStatus: currentStatus,
      enabled: !isWorkflowTask,
      onStatusSelected: (newStatus) => updateTaskStatus(taskId, newStatus),
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
          return name.contains(query) ||
              id.contains(query) ||
              client.contains(query);
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
          'note': noteController.text.trim().isEmpty
              ? ''
              : noteController.text.trim(),
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
                    final name =
                        project['name']?.toString().toLowerCase() ?? '';
                    final id = project['id']?.toString() ?? '';
                    final client =
                        project['client_name']?.toString().toLowerCase() ?? '';
                    return name.contains(query) ||
                        id.contains(query) ||
                        client.contains(query);
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
                          'Select project',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: AppTheme.getTextSecondary(context)),
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
                    style: TextStyle(
                        color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {});
                      _filterProjects();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search projects by name, ID, or client...',
                      hintStyle:
                          TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search,
                          color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: AppTheme.getTextSecondary(context),
                                  size: 20),
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
                          color: AppTheme.getPrimaryColor(context)
                              .withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context)
                              .withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context),
                          width: 2,
                        ),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                              Icon(Icons.folder_open,
                                  size: 48,
                                  color: AppTheme.getTextSecondary(context)),
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
                                  Icon(Icons.search_off,
                                      size: 48,
                                      color:
                                          AppTheme.getTextSecondary(context)),
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
                                final projectName =
                                    project['name']?.toString() ??
                                        'Unnamed project';
                                final clientName =
                                    project['client_name']?.toString();
                                final isSelected =
                                    selectedProjectId?.toString() == projectId;

                                return Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.getPrimaryColor(context)
                                            .withOpacity(0.1)
                                        : Theme.of(context)
                                            .scaffoldBackgroundColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primaryColorConst
                                          : AppTheme.getPrimaryColor(context)
                                              .withOpacity(0.2),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          selectedProjectId =
                                              int.tryParse(projectId ?? '');
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
                                                color: AppTheme.getPrimaryColor(
                                                        context)
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Icon(
                                                Icons.folder_special,
                                                color: AppTheme.getPrimaryColor(
                                                    context),
                                                size: 16,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    projectName,
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .getTextPrimary(
                                                              context),
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.normal,
                                                    ),
                                                  ),
                                                  if (clientName != null &&
                                                      clientName
                                                          .isNotEmpty) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      clientName,
                                                      style: TextStyle(
                                                        color: AppTheme
                                                            .getTextSecondary(
                                                                context),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                  if (projectId != null) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'ID: $projectId',
                                                      style: TextStyle(
                                                        color: AppTheme
                                                            .getTextSecondary(
                                                                context),
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
                                                color: AppTheme.getPrimaryColor(
                                                    context),
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
            result['userId']?.toString() ??
            '';
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
    return TaskStatusChipSet(
      currentStatus: selectedStatus,
      onStatusSelected: (newStatus) {
        setState(() {
          selectedStatus = newStatus;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.getTextPrimary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Create new task',
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
              'Assign to',
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
                  borderSide: BorderSide(
                      color:
                          AppTheme.getPrimaryColor(context).withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color:
                          AppTheme.getPrimaryColor(context).withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppTheme.getPrimaryColor(context), width: 2),
                ),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.note,
                      color: AppTheme.getPrimaryColor(context)),
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
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Create task',
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
    final parentContext = context;
    var isClosing = false;
    _searchController.clear();

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.8,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(sheetContext),
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
                    final name =
                        project['name']?.toString().toLowerCase() ?? '';
                    final id = project['id']?.toString() ?? '';
                    final client =
                        project['client_name']?.toString().toLowerCase() ?? '';
                    return name.contains(query) ||
                        id.contains(query) ||
                        client.contains(query);
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
                          'Select project',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: AppTheme.getTextSecondary(context)),
                        onPressed: () {
                          isClosing = true;
                          FocusManager.instance.primaryFocus?.unfocus();
                          _searchController.clear();
                          Navigator.pop(sheetContext);
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
                    style: TextStyle(
                        color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      if (isClosing) return;
                      setModalState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Search projects by name, ID, or client...',
                      hintStyle:
                          TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search,
                          color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: AppTheme.getTextSecondary(context),
                                  size: 20),
                              onPressed: () {
                                if (isClosing) return;
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
                          color: AppTheme.getPrimaryColor(context)
                              .withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context)
                              .withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context),
                          width: 2,
                        ),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: _projects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open,
                                  size: 48,
                                  color: AppTheme.getTextSecondary(context)),
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
                                  Icon(Icons.search_off,
                                      size: 48,
                                      color:
                                          AppTheme.getTextSecondary(context)),
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
                                final projectName =
                                    project['name']?.toString() ??
                                        'Unnamed project';
                                final clientName =
                                    project['client_name']?.toString();

                                return Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.getBackgroundPrimary(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppTheme.getPrimaryColor(context)
                                          .withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        isClosing = true;
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        _searchController.clear();
                                        Navigator.pop(sheetContext);
                                        if (!mounted) return;
                                        // Splash first; prepare project while it shows.
                                        await OpeningProjectGate.push(
                                          parentContext,
                                          projectName: projectName,
                                          destination:
                                              Home(fromAdminDashboard: true),
                                          prepare: () async {
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            await prefs.setString(
                                                "project_id", projectId ?? '');
                                            await prefs.setString(
                                                "client_name", projectName);

                                            final role =
                                                prefs.getString('role');
                                            if (role != null &&
                                                role != 'Client') {
                                              DataProvider()
                                                  .loadProjectDataForNonClient(
                                                      projectId ?? '')
                                                  .catchError((e) {
                                                print(
                                                    '[Dashboard] Error preloading project data: $e');
                                              });
                                            }

                                            if (projectId != null &&
                                                projectId.isNotEmpty) {
                                              await DataProvider()
                                                  .onProjectSelected(
                                                erpProjectId: projectId,
                                                project: Map<String,
                                                    dynamic>.from(project),
                                              );
                                            }
                                          },
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
                                                color: AppTheme.getPrimaryColor(
                                                        context)
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Icon(
                                                Icons.folder_special,
                                                color: AppTheme.getPrimaryColor(
                                                    context),
                                                size: 16,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    projectName,
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .getTextPrimary(
                                                              context),
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (clientName != null &&
                                                      clientName
                                                          .isNotEmpty) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      clientName,
                                                      style: TextStyle(
                                                        color: AppTheme
                                                            .getTextSecondary(
                                                                context),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                  if (projectId != null) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'ID: $projectId',
                                                      style: TextStyle(
                                                        color: AppTheme
                                                            .getTextSecondary(
                                                                context),
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
        throw Exception(
            'Missing credentials to load your projects. Please log in again.');
      }

      final payload = {"user_id": userId, "role": role, "api_token": apiToken};
      print('user_id: $userId');
      final uri =
          Uri.parse("https://office1.buildahome.in/API/get_projects_for_user");
      print('[Dashboard] Loading projects with $payload');
      final response = await http
          .post(uri, body: payload)
          .timeout(const Duration(seconds: 20));
      print('response: ${response.body}');
      if (response.statusCode != 200) {
        throw Exception(
            'Unable to load projects right now (code ${response.statusCode}). Pull to refresh to retry.');
      }

      final decoded = jsonDecode(response.body);

      setState(() {
        data = decoded;
        searchData = data;
        username = prefs.getString('username') ?? '';
      });
    } on TimeoutException {
      setState(() {
        _errorMessage =
            'Request timed out while loading projects. Pull down to retry.';
      });
    } catch (e) {
      print('[Dashboard] Error loading projects: $e');
      setState(() {
        _errorMessage =
            'Something went wrong while loading your projects. Pull down to retry.';
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
            child: Text("Projects handled by you",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal)),
            decoration:
                BoxDecoration(border: Border(bottom: BorderSide(width: 3))),
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
