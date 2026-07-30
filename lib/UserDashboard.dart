import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import "Payments.dart";
import 'app_theme.dart';
import 'Drawings.dart';
import 'Scheduler.dart';
import 'Gallery.dart' hide TimelineGallery;
import 'TimelineGallery.dart';
import 'NotesAndComments.dart';
import 'checklist_categories.dart';
import 'services/data_provider.dart';
import 'services/rbac_service.dart';
import 'AdminDashboard.dart';
import 'RequestDrawing.dart';
import 'InspectionRequest.dart';
import 'SiteVisitReports.dart';
import 'indents_screen.dart';
import 'main.dart';
import 'MyTasksScreen.dart';
import 'ProjectTimelineScreen.dart';
import 'NavMenu.dart';
import 'widgets/dark_mode_toggle.dart';

class UserDashboardLayout extends StatefulWidget {
  final bool fromAdminDashboard;

  UserDashboardLayout({this.fromAdminDashboard = false});

  @override
  UserDashboardLayoutState createState() => UserDashboardLayoutState();
}

// Custom route that intercepts back button presses
class _BackButtonInterceptingRoute<T> extends PageRoute<T> {
  final Widget Function(BuildContext, Animation<double>, Animation<double>)
      pageBuilder;
  final String routeName;

  _BackButtonInterceptingRoute({
    required this.pageBuilder,
    required this.routeName,
  }) : super(settings: RouteSettings(name: routeName)) {
    print('[BackButtonInterceptingRoute] Route created: $routeName');
  }

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration(milliseconds: 300);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return pageBuilder(context, animation, secondaryAnimation);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
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
  }

  @override
  Future<RoutePopDisposition> willPop() async {
    print('[BackButtonInterceptingRoute] ========== willPop called ==========');
    print('[BackButtonInterceptingRoute] Route name: $routeName');
    print(
        '[BackButtonInterceptingRoute] Android/system back button - willPop!');
    print('[BackButtonInterceptingRoute] Calling super.willPop()...');
    final disposition = await super.willPop();
    print('[BackButtonInterceptingRoute] willPop returned: $disposition');
    print('[BackButtonInterceptingRoute] ===================================');
    return disposition;
  }

  @override
  bool didPop(T? result) {
    print('[BackButtonInterceptingRoute] ========== didPop called ==========');
    print('[BackButtonInterceptingRoute] Route name: $routeName');
    print('[BackButtonInterceptingRoute] Route type: ${runtimeType}');
    print('[BackButtonInterceptingRoute] Result: $result');
    print(
        '[BackButtonInterceptingRoute] Android/system back button was pressed!');
    print('[BackButtonInterceptingRoute] Calling super.didPop()...');
    final result2 = super.didPop(result);
    print('[BackButtonInterceptingRoute] didPop returned: $result2');
    print('[BackButtonInterceptingRoute] ===================================');
    return result2;
  }

  @override
  void didComplete(T? result) {
    print(
        '[BackButtonInterceptingRoute] ========== didComplete called ==========');
    print('[BackButtonInterceptingRoute] Route name: $routeName');
    print('[BackButtonInterceptingRoute] Result: $result');
    print('[BackButtonInterceptingRoute] ===================================');
    super.didComplete(result);
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    print(
        '[BackButtonInterceptingRoute] didChangeNext - nextRoute: ${nextRoute?.settings.name ?? "null"}');
    super.didChangeNext(nextRoute);
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    print(
        '[BackButtonInterceptingRoute] didChangePrevious - previousRoute: ${previousRoute?.settings.name ?? "null"}');
    super.didChangePrevious(previousRoute);
  }

  @override
  void dispose() {
    print('\n');
    print('╔════════════════════════════════════════════════════════════════╗');
    print('║  🔙 ANDROID BACK BUTTON PRESSED - ROUTE DISPOSED              ║');
    print('╠════════════════════════════════════════════════════════════════╣');
    print('║  Route Name: $routeName');
    print('║  Route Type: ${runtimeType}');
    print('║  Status: Route was removed (likely by Android back button)    ║');
    print('║  NOTE: willPop()/didPop() were NOT called (bypassed pop flow) ║');
    print('╚════════════════════════════════════════════════════════════════╝');
    print('\n');
    super.dispose();
  }
}

class UserDashboardNavigatorObserver extends NavigatorObserver {
  int routeCount = 1; // Start with 1 for the home route
  bool _shouldDecrementOnNextPop = false; // Flag to control manual decrement

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routeCount++;
    print('[NavigatorObserver] Route pushed, count: $routeCount');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Don't decrement here - let onPopInvoked check first, then manually decrement
    // This ensures routeCount is accurate when onPopInvoked checks it
    print('[NavigatorObserver] ========== Route popped (didPop) ==========');
    print('[NavigatorObserver] Route type: ${route.runtimeType}');
    print('[NavigatorObserver] Route name: ${route.settings.name ?? "null"}');
    print('[NavigatorObserver] Route settings: ${route.settings}');
    print('[NavigatorObserver] Count before decrement: $routeCount');
    if (previousRoute != null) {
      print(
          '[NavigatorObserver] Previous route: ${previousRoute.settings.name ?? previousRoute.runtimeType}');
    }

    // Check if this is the Payments route
    final routeName = route.settings.name ?? '';
    final routeType = route.runtimeType.toString();
    if (routeName.contains('Payment') || routeType.contains('Payment')) {
      print('[NavigatorObserver] *** This is a Payments route! ***');
      print(
          '[NavigatorObserver] Android back button was pressed on Payments page!');
    }

    print('[NavigatorObserver] ===================================');
    _shouldDecrementOnNextPop = true;
  }

  void performDecrement() {
    if (_shouldDecrementOnNextPop && routeCount > 1) {
      routeCount--;
      _shouldDecrementOnNextPop = false;
      print('[NavigatorObserver] Route count decremented to: $routeCount');
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (routeCount > 1) {
      routeCount--;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // Route count stays the same for replacements
  }

  bool get hasChildRoutes => routeCount > 1;
  int get currentRouteCount => routeCount;
}

class UserDashboardLayoutState extends State<UserDashboardLayout> {
  final GlobalKey<UserDashboardScreenState> _userDashboardKey =
      GlobalKey<UserDashboardScreenState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String displayName = 'My Home';
  String _userRole = '';
  // Removed local navigatorKey and observer - using global ones from main.dart

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
  }

  _loadDisplayName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadedUsername = ' ';
    final loadedRole = prefs.getString('role') ?? '';
    if (prefs.containsKey("client_name")) {
      loadedUsername = prefs.getString('client_name') ?? ' ';
    } else {
      loadedUsername = prefs.getString('username') ?? ' ';
    }

    String name = _getDisplayName(loadedUsername);
    if (mounted) {
      setState(() {
        displayName = name;
        _userRole = loadedRole;
      });
    }
  }

  String _getDisplayName(String username) {
    if (username.isEmpty || username == ' ') {
      return 'Your';
    }
    try {
      String name = username.split('-')[0].trim();
      return name.isNotEmpty ? name : username.trim();
    } catch (e) {
      return username.trim().isNotEmpty ? username.trim() : 'Your';
    }
  }

  Widget _buildUserHeader() {
    return Container(
      width: MediaQuery.of(context).size.width,
      padding: EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (widget.fromAdminDashboard && Navigator.of(context).canPop())
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                if (_userRole == 'Client')
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              AppTheme.getPrimaryColor(context).withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.getPrimaryColor(context),
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.getPrimaryColor(context),
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
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
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName + "\'s Dashboard"
                          : 'User\'s Dashboard',
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          DarkModeToggle(showLabel: false),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // Always allow popping so child routes can pop normally
      onPopInvoked: (didPop) {
        if (!widget.fromAdminDashboard) return;

        if (!didPop) {
          // Pop was prevented - we're on the root route
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );
          return;
        }

        // Use global navigator observer from main.dart
        // A pop occurred - check the route count BEFORE it was decremented
        // The observer's didPop may be called before or after onPopInvoked
        // So we check synchronously to get the accurate count
        final routeCountBeforePop = globalNavigatorObserver.currentRouteCount;

        // Now perform the decrement that didPop requested
        globalNavigatorObserver.performDecrement();

        // Use a microtask to check AFTER the pop completes
        Future.microtask(() {
          if (!mounted) return;

          // If routeCount was > 1 before the pop, we just popped a child route
          // So stay on UserDashboard (do nothing)
          if (routeCountBeforePop > 1) {
            return;
          }

          // Route count was 1, meaning we pressed back on UserDashboard itself
          // Navigate to AdminDashboard
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );
        });
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        drawer: NavMenuWidget(),
        appBar: (!widget.fromAdminDashboard && Navigator.of(context).canPop())
            ? AppBar(
                backgroundColor: AppTheme.getBackgroundSecondary(context),
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back),
                  color: AppTheme.getTextPrimary(context),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  'Project',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                iconTheme:
                    IconThemeData(color: AppTheme.getTextPrimary(context)),
              )
            : null,
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
                    return Container(
                        color: AppTheme.getBackgroundPrimary(context));
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
            Column(
              children: [
                // User avatar header
                if (_userDashboardKey.currentState != null) _buildUserHeader(),
                // Main content
                Expanded(
                  child: UserDashboardScreen(key: _userDashboardKey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({Key? key}) : super(key: key);

  @override
  UserDashboardScreenState createState() {
    return UserDashboardScreenState();
  }
}

class UserDashboardScreenState extends State<UserDashboardScreen> {
  List dailyUpdateList = [];
  var username = ' ';
  var updatePostedOnDate = " ";
  var value = " ";
  String? completed;
  dynamic updateResponseBody;
  var blocked = false;
  var bolckReason = '';
  var location = '';
  List<dynamic> workflowDashboardSlots = [];
  var expanded = false;
  bool _isLoadingSummary = true;
  bool _isLoadingUpdates = true;
  bool _hasLoadedSummary = false;
  bool _hasLoadedUpdates = false;
  final TextEditingController _quickSearchController = TextEditingController();
  final FocusNode _quickSearchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  static const double _recentTaskCardHeight = 118;
  static const double _recentTasksViewportHeight =
      _recentTaskCardHeight * 3 + 16;

  final PageController _recentTasksPageController = PageController(
    viewportFraction: 1 / 3,
  );
  String _quickSearchQuery = '';
  String? _currentRole;

  // Tasks state
  List<dynamic> _tasks = [];
  bool _isLoadingTasks = false;
  String? _tasksError;

  @override
  void dispose() {
    _quickSearchController.dispose();
    _quickSearchFocusNode.dispose();
    _scrollController.dispose();
    _recentTasksPageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Load role
    _loadRole();
    // Load cached data (if available) without blocking the transition
    loadDataFromProvider();
    // Fetch fresh data asynchronously and preload project data for non-Client users
    _initializeData();
    // Load tasks for the project
    loadTasks();

    // Add listener to scroll to top when search field is focused
    _quickSearchFocusNode.addListener(() {
      if (_quickSearchFocusNode.hasFocus) {
        // Wait for the next frame to ensure the scroll controller is attached
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              0.0,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  Future<void> _loadRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        final role = prefs.getString('role');
        // Normalize the role to ensure proper mapping (e.g., "PH" -> "Project Head")
        final rbac = RBACService();
        _currentRole = rbac.normalizeRole(role) ?? role;
      });
    }
  }

  Future<void> _initializeData() async {
    // Load updates immediately and independently - this is critical for showing updates right away
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final projectId = prefs.getString('project_id');

    final dataProvider = DataProvider();

    if (projectId != null && projectId.isNotEmpty) {
      // First priority: Load latest updates independently and immediately
      // This ensures updates show without waiting for other data to load
      dataProvider.loadLatestUpdatesForProject(projectId).then((_) {
        // Refresh UI after updates load
        if (mounted) {
          loadDataFromProvider();
        }
      }).catchError((e) {
        print('[UserDashboard] Error loading latest updates: $e');
      });

      // Load other project data (location, completion, etc.) in parallel
      if (role == 'Client') {
        // For Client users, load client project data which includes all project info
        dataProvider.loadClientProjectData().catchError((e) {
          print('[UserDashboard] Error loading client project data: $e');
        });
      } else {
        // For non-Client users, load project data (location, completion, etc.)
        // Updates are already loading above, but this also includes them (for consistency)
        dataProvider.loadProjectDataForProject(projectId).catchError((e) {
          print('[UserDashboard] Error loading project data: $e');
        });

        // Preload other project data (payments, gallery, etc.) in background
        // This doesn't block updates from loading
        dataProvider.loadProjectDataForNonClient(projectId).catchError((e) {
          print('[UserDashboard] Error preloading project data: $e');
        });
      }

      DataProvider().loadProjectTimeline().then((_) {
        if (mounted) setState(() {});
      }).catchError((e) {
        print('[UserDashboard] Error preloading project timeline: $e');
      });

      // Refresh UI periodically to pick up loaded data
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          loadDataFromProvider();
        }
      });

      Future.delayed(Duration(milliseconds: 1000), () {
        if (mounted) {
          loadDataFromProvider();
        }
      });
    }

    // Also run the standard reloadData for other data dependencies
    await reloadData(force: true);
  }

  loadDataFromProvider() async {
    final dataProvider = DataProvider();

    // Load username first
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadedUsername = ' ';
    if (prefs.containsKey("client_name")) {
      loadedUsername = prefs.getString('client_name') ?? ' ';
    } else {
      loadedUsername = prefs.getString('username') ?? ' ';
    }

    if (!mounted) return;

    final String nextLocation = dataProvider.clientProjectLocation ?? '';
    final String? nextCompletion = dataProvider.clientProjectCompletion;
    final bool nextBlocked = dataProvider.clientProjectBlocked ?? false;
    final String nextBlockReason = dataProvider.clientProjectBlockReason ?? '';
    final String nextValue = dataProvider.clientProjectValue ?? '';
    final dynamic nextUpdates = dataProvider.clientProjectUpdates;
    final List<dynamic> nextWorkflowSlots =
        List<dynamic>.from(dataProvider.clientWorkflowDashboardSlots);

    List<String> nextDailyUpdates = [];
    String nextUpdateDate =
        DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();

    // Only process updates if data is loaded (not null)
    if (nextUpdates != null && nextUpdates is List && nextUpdates.isNotEmpty) {
      nextUpdateDate = nextUpdates[0]['date']?.toString() ?? nextUpdateDate;
      for (final update in nextUpdates) {
        final title = update['update_title']?.toString();
        if (title == null || title.isEmpty) continue;
        if (!nextDailyUpdates.contains(title)) {
          nextDailyUpdates.add(title);
        }
      }
      if (nextDailyUpdates.isEmpty) {
        nextDailyUpdates.add('Stay tuned for updates about your home');
      }
    } else if (nextUpdates == null) {
      // Data not loaded yet - keep empty list to show skeleton
      nextDailyUpdates = [];
    } else {
      // Data loaded but empty - show empty state message
      nextDailyUpdates.add('Stay tuned for updates about your home');
    }

    if (!mounted) return;

    setState(() {
      // Load client project data from provider
      location = nextLocation;
      completed = nextCompletion;
      blocked = nextBlocked;
      bolckReason = nextBlockReason;
      value = nextValue;
      workflowDashboardSlots = nextWorkflowSlots;
      username = loadedUsername;
      _isLoadingSummary = false;
      _hasLoadedSummary = true;
    });

    setState(() {
      updateResponseBody = nextUpdates;
      dailyUpdateList = nextDailyUpdates;
      updatePostedOnDate = nextUpdateDate;
      _isLoadingUpdates = false;
      // Only mark as loaded if we have actual data OR if we got empty data (not null)
      // If nextUpdates is null, data hasn't loaded yet, so keep hasLoadedUpdates false to show skeleton
      _hasLoadedUpdates = nextUpdates != null;
    });
  }

  Future<void> reloadData({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingSummary = true;
      _isLoadingUpdates = true;
    });
    await DataProvider().reloadData(force: force);
    await loadDataFromProvider();
    // Section flags are reset inside loadDataFromProvider once data is applied.
    // Note: loadTasks() is only called once at initState to avoid multiple API calls
  }

  Future<void> loadTasks() async {
    if (!mounted) return;

    // Prevent multiple simultaneous calls
    if (_isLoadingTasks) {
      print(
          '[UserDashboard] loadTasks already in progress, skipping duplicate call');
      return;
    }

    setState(() {
      _isLoadingTasks = true;
      _tasksError = null;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');
      String? projectId = prefs.getString('project_id');

      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      // Fetch tasks for the current client/user and project. Some workflow
      // tasks are assigned directly to the user, so project_id alone can miss
      // client-assigned work.
      Map<String, String> queryParams = {
        'user_id': userId,
        'assigned_to': userId,
      };
      if (projectId != null && projectId.isNotEmpty) {
        queryParams['project_id'] = projectId;
      }

      Uri uri = Uri.parse("https://office.buildahome.in/API/get_tasks").replace(
        queryParameters: queryParams,
      );

      print('[UserDashboard] Fetching tasks with filters: $queryParams');
      var response = await http.get(uri).timeout(const Duration(seconds: 20));

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

        List<dynamic> allTasks = taskMap.values.toList();

        // API uses OR logic across filters; keep assignee tasks and workflow
        // reviewer approval tasks for the current project.
        allTasks = filterTasksForProjectAndAssignee(
          allTasks,
          userId: userId,
          projectId: projectId,
        );

        // Sort by creation date (newest first)
        allTasks.sort((a, b) {
          if (a is! Map || b is! Map) return 0;
          String aDate = (a['created_at'] ?? '').toString();
          String bDate = (b['created_at'] ?? '').toString();
          return bDate.compareTo(aDate);
        });

        if (!mounted) return;
        setState(() {
          _tasks = allTasks;
          _isLoadingTasks = false;
        });

        print(
            '[UserDashboard] Loaded ${allTasks.length} tasks for project $projectId');
      } else if (response.statusCode == 404) {
        // No tasks found - this is okay
        if (!mounted) return;
        setState(() {
          _tasks = [];
          _isLoadingTasks = false;
        });
      } else {
        throw Exception('Unable to load tasks (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      print('[UserDashboard] Error loading tasks: $e');
      setState(() {
        _isLoadingTasks = false;
        _tasksError = e.toString().replaceAll('Exception: ', '');
        _tasks = [];
      });
    }
  }

  Future<List<dynamic>> _refreshTasksForMyTasks() async {
    await loadTasks();
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
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');

      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri =
          Uri.parse("https://office.buildahome.in/API/update_task_status");
      final response = await http.post(
        uri,
        body: {
          'user_id': userId,
          'api_token': apiToken,
          'task_id': taskId.toString(),
          'status': newStatus,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
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

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  bool get _shouldShowInitialSummarySkeleton =>
      _isLoadingSummary && !_hasLoadedSummary;

  bool get _shouldShowInitialUpdatesSkeleton =>
      _isLoadingUpdates && !_hasLoadedUpdates;

  bool get _shouldShowInitialPageSkeleton =>
      _shouldShowInitialSummarySkeleton && _shouldShowInitialUpdatesSkeleton;

  bool get _isAnySectionLoading => _isLoadingSummary || _isLoadingUpdates;

  Widget _buildSkeleton(double height, double width) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context).withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  List<Map<String, dynamic>> get _activeRecentTasks =>
      filterActiveRecentTasks(_tasks);

  Widget _buildTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - minimal (matching admin dashboard)
        Row(
          children: [
            Text(
              'Pending Tasks',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.getTextPrimary(context),
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            if (!_isLoadingTasks && _tasks.isNotEmpty)
              TextButton(
                onPressed: _openAllTasks,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View All',
                  style: TextStyle(
                    color: AppTheme.getPrimaryColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Refresh tasks',
                onPressed: _isLoadingTasks ? null : loadTasks,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.getPrimaryColor(context),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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

        // Loading state - compact (only show on first load)
        if (_isLoadingTasks && _tasks.isEmpty)
          Container(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SpinKitRing(
                color: AppTheme.getPrimaryColor(context),
                size: 32,
                lineWidth: 2.5,
              ),
            ),
          ),

        // Empty state - compact with animation
        if (!_isLoadingTasks && _tasks.isEmpty && _tasksError == null)
          TweenAnimationBuilder<double>(
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
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.getPrimaryColor(context)
                                .withOpacity(0.15),
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
                          'Tasks for this project will appear here',
                          style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

        // Premium client task carousel
        if (!_isLoadingTasks && _activeRecentTasks.isNotEmpty)
          _buildRecentTasksCarousel(_activeRecentTasks),
      ],
    );
  }

  Widget _buildRecentTasksCarousel(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) return SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: _recentTasksViewportHeight,
          child: PageView.builder(
            controller: _recentTasksPageController,
            scrollDirection: Axis.vertical,
            itemCount: tasks.length,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildTaskCard(tasks[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final accentColor = _recentTaskAccentColor(task);
    final title = _clientTaskTitle(task);
    final assigneeParts = _taskAssigneeParts(task);
    final dateParts = _taskDateTimeParts(task);
    final assigneeText =
        assigneeParts.whereType<String>().join(' · ');
    final dateText = dateParts[0] == null
        ? null
        : dateParts[1] == null
            ? dateParts[0]
            : '${dateParts[0]} · ${dateParts[1]}';

    return SizedBox(
      height: _recentTaskCardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8ECF1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _taskStatusIcon(task),
                            color: accentColor,
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isWorkflowDelayGated(task)) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 13,
                                        color: accentColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: WorkflowDelayCountdownText(
                                          gateData:
                                              workflowDelayGate(task) ??
                                                  const {},
                                          style: TextStyle(
                                            color: accentColor,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildTaskStatusBadge(task, accentColor),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (assigneeText.isNotEmpty)
                      _buildRecentTaskMetaRow(
                        icon: Icons.person_outline_rounded,
                        text: assigneeText,
                      ),
                    if (dateText != null) ...[
                      const SizedBox(height: 4),
                      _buildRecentTaskMetaRow(
                        icon: Icons.calendar_today_outlined,
                        text: dateText,
                      ),
                    ],
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () => _openTaskDetails(task),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Details',
                                style: TextStyle(
                                  color: AppTheme.getPrimaryColor(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: AppTheme.getPrimaryColor(context),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTaskMetaRow({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _recentTaskAccentColor(Map<String, dynamic> task) {
    if (isWorkflowDelayGated(task)) return const Color(0xFF6366F1);
    if (_isTaskOverdue(task)) return const Color(0xFFEF4444);

    final actionType = _primaryWorkflowAction(task)?['type']?.toString() ?? '';
    switch (actionType) {
      case 'upload':
        return const Color(0xFFEF4444);
      case 'yes_no':
      case 'complete_button':
      case 'checklist':
      case 'user_checklist':
      case 'text_list':
      case 'picture_choice_list':
      case 'picture_choice_pick':
        return const Color(0xFF3B82F6);
      case 'slot_selection':
        return const Color(0xFF8B5CF6);
      default:
        return _taskStatusColor(task);
    }
  }

  Widget _buildTaskStatusBadge(Map<String, dynamic> task, Color color) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        _taskStatusBadgeLabel(task),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildNoFilesState() {
    return Center(
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.folder_off_outlined,
          color: AppTheme.getPrimaryColor(context),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildFileRow(Map<String, dynamic> file) {
    final name = _firstTaskString(file, [
          'filename',
          'file_name',
          'name',
          'document_name',
          'label',
          'title',
        ]) ??
        'Project file';
    final type = _taskFileType(file, name);
    final size = _taskFileSize(file);
    final badge = _firstTaskString(file, ['status', 'state']) ?? 'Ready';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openTaskFile(file, fallbackName: name),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(_taskFileIcon(type),
                    color: Color(0xFF2563EB), size: 21),
              ),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 3),
                    Text(
                      size.isEmpty ? type : '$type • $size',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _toSentenceCase(badge),
                  style: TextStyle(
                    color: Color(0xFF15803D),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.open_in_new_rounded,
                  color: Color(0xFF9CA3AF), size: 15),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshTaskAfterInlineAction() async {
    await loadTasks();
  }

  Future<void> _openTaskFile(
    Map<String, dynamic> file, {
    required String fallbackName,
  }) async {
    final rawUrl = _taskFileUrl(file, fallbackName: fallbackName);
    if (rawUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open this file. File link is missing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final url = _absoluteTaskFileUrl(rawUrl);
    if (_looksLikeTaskImage(rawUrl)) {
      _showTaskImagePreview(url, fallbackName);
      return;
    }

    final uri = Uri.tryParse(url);
    final opened = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open this file.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String? _taskFileUrl(
    Map<String, dynamic> file, {
    required String fallbackName,
  }) {
    final url = _firstTaskString(file, ['url', 'file_url', 'path']);
    if (url != null) return url;
    if (_looksLikeTaskFile(fallbackName)) return fallbackName;
    return null;
  }

  String _absoluteTaskFileUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('file://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return 'https://office.buildahome.in$trimmed';
    }
    return 'https://office.buildahome.in/$trimmed';
  }

  bool _looksLikeTaskImage(String value) {
    final lower = value.toLowerCase().split('?').first;
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.gif');
  }

  void _showTaskImagePreview(String url, String title) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 34),
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Color(0xFF111827)),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                child: Container(
                  color: Colors.white,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.68,
                  ),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Padding(
                        padding: EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 42,
                              color: Color(0xFF9CA3AF),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Unable to preview this image.',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w700,
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
        );
      },
    );
  }

  Widget _buildTaskActionButton({
    required String label,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback onTap,
    Color? color,
  }) {
    final buttonColor = color ?? Color(0xFF111827);
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            decoration: BoxDecoration(
              color: isPrimary ? buttonColor : Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: isPrimary ? buttonColor : Color(0xFFE5E7EB),
              ),
              boxShadow: isPrimary
                  ? [
                      BoxShadow(
                        color: buttonColor.withValues(alpha: 0.22),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isPrimary ? Colors.white : Color(0xFF111827),
                  size: 18,
                ),
                SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isPrimary ? Colors.white : Color(0xFF111827),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAllTasks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyTasksScreen(
          tasks: _tasks,
          onRefresh: _refreshTasksForMyTasks,
          initialTabIndex: 0,
        ),
      ),
    );
  }

  void _openTaskDetails(Map<String, dynamic> task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyTasksScreen(
          tasks: _tasks,
          onRefresh: _refreshTasksForMyTasks,
          initialTabIndex: 0,
        ),
      ),
    );
  }

  List<String?> _taskAssigneeParts(Map<String, dynamic> task) {
    final name = _firstTaskString(task, [
      'assigned_to_name',
      'assignee_name',
      'assigned_to',
      'user_name',
      'assigned_user_name',
    ]);
    final role = _firstTaskString(task, [
      'assigned_to_role',
      'assigned_role',
      'role',
      'assignee_role',
    ]);
    return [name, role];
  }

  List<String?> _taskDateTimeParts(Map<String, dynamic> task) {
    final display = _firstTaskString(task, [
      'completed_at_display',
      'due_at_display',
      'updated_at_display',
      'created_at_display',
    ]);
    if (display != null) {
      final parts = display.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        return [
          '${parts[0]} ${parts[1]} ${parts[2]}',
          parts.sublist(3).join(' '),
        ];
      }
      return [display, null];
    }

    final iso = _firstTaskString(task, [
      'updated_at',
      'created_at',
      'due_date',
      'completed_at',
    ]);
    if (iso == null) return [null, null];

    try {
      final parsed = DateTime.parse(iso);
      return [
        DateFormat('dd MMM yyyy').format(parsed),
        DateFormat('hh:mm a').format(parsed),
      ];
    } catch (_) {
      return [iso, null];
    }
  }

  String _taskAssigneeLine(Map<String, dynamic> task) {
    final name = _firstTaskString(task, [
      'assigned_to_name',
      'assignee_name',
      'assigned_to',
      'user_name',
      'assigned_user_name',
    ]);
    final role = _firstTaskString(task, [
      'assigned_to_role',
      'assigned_role',
      'role',
      'assignee_role',
    ]);
    if (name != null && role != null) return '$name · $role';
    if (name != null) return name;
    if (role != null) return role;
    return '';
  }

  String? _taskSubtitleDate(Map<String, dynamic> task) {
    final display = _firstTaskString(task, [
      'completed_at_display',
      'due_at_display',
      'updated_at_display',
      'created_at_display',
    ]);
    if (display != null) return display;

    final iso = _firstTaskString(task, [
      'updated_at',
      'created_at',
      'due_date',
      'completed_at',
    ]);
    if (iso == null) return null;

    try {
      return DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _clientTaskTitle(Map<String, dynamic> task) {
    final title = _firstTaskString(task, [
      'title',
      'task_name',
      'name',
      'subject',
      'note',
      's_note',
    ]);
    if (title != null) return _toSentenceCase(title);

    final taskId = task['id']?.toString() ?? '';
    return taskId.isEmpty ? 'Review your project task' : 'Task #$taskId';
  }

  String _clientTaskDescription(Map<String, dynamic> task) {
    final description = _firstTaskString(task, [
      'description',
      'client_description',
      'message',
      'remarks',
      'note',
      's_note',
    ]);
    if (description != null && description.length > 8) {
      return _toSentenceCase(description);
    }

    final actionLabel = _primaryTaskActionLabel(task).toLowerCase();
    if (actionLabel.contains('upload')) {
      return 'Please upload the requested document so our team can continue the next step.';
    }
    if (actionLabel.contains('payment')) {
      return 'Please review the payment details and complete the pending payment.';
    }
    if (actionLabel.contains('appointment') || actionLabel.contains('book')) {
      return 'Please choose a convenient appointment slot for your project update.';
    }
    if (actionLabel.contains('download')) {
      return 'Your project file is ready. Open the details to download it.';
    }
    if (actionLabel.contains('approve')) {
      return 'Please review the shared information and approve it if everything looks correct.';
    }
    return 'Please review this task and complete the required action from the details screen.';
  }

  Color _taskStatusColor(Map<String, dynamic> task) {
    if (_isTaskOverdue(task)) return Color(0xFFEF4444);

    switch (_normalizedTaskStatus(task)) {
      case 'completed':
      case 'done':
      case 'finished':
      case 'approved':
      case 'skipped':
        return Color(0xFF10B981);
      case 'in_progress':
      case 'ready':
      case 'information':
      case 'info':
      case 'waiting_approval':
        return Color(0xFF2563EB);
      case 'cancelled':
      case 'rejected':
        return Color(0xFFEF4444);
      default:
        return Color(0xFFF59E0B);
    }
  }

  IconData _taskStatusIcon(Map<String, dynamic> task) {
    if (isWorkflowDelayGated(task)) return Icons.schedule_rounded;

    final actionType = _primaryWorkflowAction(task)?['type']?.toString() ?? '';
    switch (actionType) {
      case 'upload':
        return Icons.cloud_upload_outlined;
      case 'slot_selection':
        return Icons.event_available_outlined;
      case 'redirect_button':
        return Icons.open_in_new_rounded;
      case 'checklist':
      case 'user_checklist':
      case 'text_list':
      case 'picture_choice_list':
      case 'picture_choice_pick':
        return Icons.fact_check_outlined;
      case 'yes_no':
      case 'complete_button':
        return Icons.verified_outlined;
    }

    if (_isTaskOverdue(task)) return Icons.warning_amber_rounded;
    switch (_normalizedTaskStatus(task)) {
      case 'completed':
      case 'done':
      case 'finished':
      case 'approved':
        return Icons.check_circle_outline_rounded;
      case 'in_progress':
      case 'ready':
      case 'information':
      case 'info':
      case 'waiting_approval':
        return Icons.info_outline_rounded;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.pending_actions_rounded;
    }
  }

  String _taskStatusBadgeLabel(Map<String, dynamic> task) {
    if (_isTaskOverdue(task)) return 'Overdue';

    final dueDate = _taskDueDate(task);
    if (dueDate != null) {
      final today = DateTime.now();
      final normalizedToday = DateTime(today.year, today.month, today.day);
      final normalizedDue = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final days = normalizedDue.difference(normalizedToday).inDays;
      if (days == 0) return 'Due Today';
      if (days == 1) return 'Due Tomorrow';
      if (days > 1) return 'Due in $days Days';
    }

    if (task['is_workflow_task'] == true) {
      return workflowStatusDisplayLabel(task);
    }

    switch (_normalizedTaskStatus(task)) {
      case 'waiting_approval':
        return 'Waiting for Approval';
      case 'ready':
        return 'Ready for Review';
      case 'completed':
      case 'done':
      case 'finished':
      case 'approved':
        return 'Approved';
      case 'in_progress':
        return 'In Progress';
      case 'information':
      case 'info':
        return 'Information';
      default:
        return 'Pending';
    }
  }

  String _primaryTaskActionLabel(Map<String, dynamic> task) {
    final action = _primaryWorkflowAction(task);
    final customLabel = action == null
        ? null
        : _firstTaskString(action, ['label', 'button_label', 'title']);
    if (customLabel != null) return customLabel;

    final actionType = action?['type']?.toString() ?? '';
    switch (actionType) {
      case 'upload':
        return 'Upload Document';
      case 'complete_button':
        return 'Confirm';
      case 'update_status':
        return 'Review';
      case 'yes_no':
        return 'Confirm';
      case 'checklist':
      case 'user_checklist':
      case 'text_list':
        return 'Review';
      case 'picture_choice_list':
        return 'Send options';
      case 'picture_choice_pick':
        return 'Choose option';
      case 'slot_selection':
        return 'Book Appointment';
      case 'redirect_button':
        return 'Open';
      case 'view_prior_response':
      case 'yes_no_summary':
      case 'user_checklist_summary':
      case 'text_list_summary':
      case 'material_shift_summary':
        return 'View Response';
    }

    switch (_normalizedTaskStatus(task)) {
      case 'completed':
      case 'done':
      case 'finished':
      case 'approved':
        return 'Download';
      case 'waiting_approval':
      case 'ready':
        return 'Approve';
      default:
        return 'Review';
    }
  }

  IconData _primaryTaskActionIcon(Map<String, dynamic> task) {
    final actionType = _primaryWorkflowAction(task)?['type']?.toString() ?? '';
    switch (actionType) {
      case 'upload':
        return Icons.upload_file_rounded;
      case 'slot_selection':
        return Icons.calendar_month_outlined;
      case 'redirect_button':
        return Icons.open_in_new_rounded;
      case 'view_prior_response':
      case 'yes_no_summary':
      case 'user_checklist_summary':
      case 'text_list_summary':
      case 'material_shift_summary':
        return Icons.visibility_outlined;
      case 'checklist':
      case 'user_checklist':
      case 'text_list':
      case 'picture_choice_list':
        return Icons.palette_outlined;
      case 'picture_choice_pick':
        return Icons.color_lens_outlined;
      default:
        return Icons.arrow_forward_rounded;
    }
  }

  Map<String, dynamic>? _primaryWorkflowAction(Map<String, dynamic> task) {
    final actions = [
      ..._mapTaskListFlexible(task['workflow_task_actions']),
      ..._mapTaskListFlexible(task['workflow_actions']),
    ];
    if (actions.isEmpty) return null;

    for (final action in actions) {
      final type = action['type']?.toString() ?? '';
      if (type == 'delay_timer') continue;
      if (!type.contains('summary') && type != 'view_prior_response') {
        return action;
      }
    }
    for (final action in actions) {
      if (action['type']?.toString() != 'delay_timer') return action;
    }
    return actions.first;
  }

  List<Map<String, dynamic>> _recentTaskFiles(Map<String, dynamic> task) {
    final files = <Map<String, dynamic>>[];
    _collectRecentTaskFiles(task, files);

    final seen = <String>{};
    return files.where((file) {
      final key = (_firstTaskString(file, [
                'url',
                'file_url',
                'path',
                'filename',
                'file_name',
                'name',
              ]) ??
              file.toString())
          .toLowerCase();
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }

  void _collectRecentTaskFiles(
      dynamic value, List<Map<String, dynamic>> files) {
    if (value == null) return;

    if (value is String) {
      if (_looksLikeTaskFile(value)) {
        files.add({'name': value.split('/').last, 'url': value});
      }
      return;
    }

    if (value is List) {
      for (final item in value) {
        _collectRecentTaskFiles(item, files);
      }
      return;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final fileName = _firstTaskString(map, [
        'filename',
        'file_name',
        'document_name',
        'name',
        'label',
        'title',
      ]);
      final fileUrl = _firstTaskString(map, ['url', 'file_url', 'path']);
      if ((fileName != null && _looksLikeTaskFile(fileName)) ||
          (fileUrl != null && _looksLikeTaskFile(fileUrl))) {
        files.add(map);
      }

      for (final entry in map.entries) {
        _collectRecentTaskFiles(entry.value, files);
      }
    }
  }

  bool _looksLikeTaskFile(String value) {
    if (value.trim().isEmpty) return false;
    final lower = value.toLowerCase().split('?').first;
    return lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.dwg') ||
        lower.endsWith('.dxf') ||
        lower.endsWith('.zip');
  }

  String _taskFileType(Map<String, dynamic> file, String name) {
    final explicitType = _firstTaskString(file, [
      'type',
      'file_type',
      'content_type',
      'mime_type',
    ]);
    if (explicitType != null) return explicitType.toUpperCase();

    final cleanName = name.split('?').first;
    final dotIndex = cleanName.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < cleanName.length - 1) {
      return cleanName.substring(dotIndex + 1).toUpperCase();
    }
    return 'FILE';
  }

  String _taskFileSize(Map<String, dynamic> file) {
    final rawSize = file['size'] ?? file['file_size'] ?? file['bytes'];
    if (rawSize == null) return '';
    if (rawSize is num) {
      if (rawSize >= 1024 * 1024) {
        return '${(rawSize / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      if (rawSize >= 1024) {
        return '${(rawSize / 1024).toStringAsFixed(1)} KB';
      }
      return '${rawSize.toStringAsFixed(0)} B';
    }
    final text = rawSize.toString().trim();
    return text == 'null' ? '' : text;
  }

  IconData _taskFileIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('image') ||
        lower == 'jpg' ||
        lower == 'jpeg' ||
        lower == 'png' ||
        lower == 'webp') {
      return Icons.image_outlined;
    }
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.contains('dwg') || lower.contains('dxf')) {
      return Icons.architecture_outlined;
    }
    if (lower.contains('sheet') || lower.contains('xls')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _normalizedTaskStatus(Map<String, dynamic> task) {
    return normalizeTaskStatusValue(task);
  }

  bool _isTaskOverdue(Map<String, dynamic> task) {
    final status = _normalizedTaskStatus(task);
    if (status == 'completed' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'approved') {
      return false;
    }

    final dueDate = _taskDueDate(task);
    if (dueDate == null) return false;
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedDue = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return normalizedDue.isBefore(normalizedToday);
  }

  DateTime? _taskDueDate(Map<String, dynamic> task) {
    final dueText = _firstTaskString(task, [
      'due_date',
      'deadline',
      'end_date',
      'target_date',
      'scheduled_at',
    ]);
    if (dueText == null) return null;
    return DateTime.tryParse(dueText);
  }

  List<Map<String, dynamic>> _mapTaskListFlexible(dynamic value) {
    dynamic normalized = value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        normalized = jsonDecode(value);
      } catch (_) {
        normalized = value;
      }
    }
    if (normalized is! List) return <Map<String, dynamic>>[];
    return normalized
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String? _firstTaskString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return null;
  }

  // Helper function to convert text to sentence case
  String _toSentenceCase(String text) {
    if (text.isEmpty) return text;
    // Convert first character to uppercase and rest to lowercase
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    final isWorkflowTask = taskId < 0;
    final statuses = [
      {
        'value': 'pending',
        'label': 'Pending',
        'color': Color(0xFFD97706),
        'icon': Icons.pending
      },
      {
        'value': 'in_progress',
        'label': 'In Progress',
        'color': AppTheme.primaryColorConst,
        'icon': Icons.work
      },
      {
        'value': 'completed',
        'label': 'Completed',
        'color': Color(0xFF10B981),
        'icon': Icons.check_circle
      },
      {
        'value': 'cancelled',
        'label': 'Cancelled',
        'color': Color(0xFFEF4444),
        'icon': Icons.cancel
      },
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
          color: AppTheme.primaryColorConst.withOpacity(0.2),
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
        icon: Icon(Icons.arrow_drop_down,
            color: AppTheme.getTextSecondary(context)),
        dropdownColor: AppTheme.getBackgroundPrimaryLight(context),
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
        onChanged: isWorkflowTask
            ? null
            : (String? newStatus) {
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

  List<Map<String, dynamic>> getMenuItems() {
    List<Map<String, dynamic>> menuItems = [];
    final rbac = RBACService();

    if (_currentRole != 'Billing') {
      menuItems.add({
        'title': 'My tasks',
        'icon': Icons.pending_actions,
        'route': () => MyTasksScreen(
              tasks: _tasks,
              onRefresh: _refreshTasksForMyTasks,
            ),
      });
      menuItems.add({
        'title': 'Project Timeline',
        'icon': Icons.timeline_rounded,
        'route': () => const ProjectTimelineScreen(),
      });
    }

    // Indents - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.indent)) {
      menuItems.add({
        'title': 'Indents',
        'icon': Icons.request_quote,
        'route': () => IndentsScreenLayout(),
      });
    }

    // Payments - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.payments)) {
      menuItems.add({
        'title': 'Payments',
        'icon': Icons.payment,
        'route': () => PaymentTaskWidget(),
      });
    }

    // Documents - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.documents)) {
      menuItems.add({
        'title': 'Documents',
        'icon': Icons.description,
        'route': () => Documents(),
      });
    }

    // Scheduler - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.scheduler)) {
      menuItems.add({
        'title': 'Scheduler',
        'icon': Icons.calendar_today,
        'route': () => const TaskWidget(),
      });
    }

    // Gallery - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.gallery)) {
      menuItems.add({
        'title': 'Gallery',
        'icon': Icons.photo_library,
        'route': () => Gallery(),
      });
      menuItems.add({
        'title': 'Timeline Gallery',
        'icon': Icons.auto_awesome_motion,
        'route': () => TimelineGallery(),
      });
    }

    // ChatBox - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.tasksAndNotes)) {
      menuItems.add({
        'title': 'ChatBox',
        'icon': Icons.note_add,
        'route': () => NotesAndComments(),
      });
    }

    // Checklist - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.checklist)) {
      menuItems.add({
        'title': 'Checklist',
        'icon': Icons.checklist,
        'route': () => ChecklistCategoriesLayout(),
      });
    }

    // Request Drawings - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.requestDrawing)) {
      menuItems.add({
        'title': 'Request Drawings',
        'icon': Icons.architecture,
        'route': () => RequestDrawingLayout(),
      });
    }

    // Inspection Requests - not shown to clients
    if (_currentRole != null && _currentRole!.toLowerCase() != 'client') {
      menuItems.add({
        'title': 'Inspection Requests',
        'icon': Icons.fact_check_outlined,
        'route': () async {
          // Get current project ID from SharedPreferences
          SharedPreferences prefs = await SharedPreferences.getInstance();
          final projectId = prefs.getString('project_id');
          // Open InspectionRequest with fixed project ID
          return InspectionRequestLayout(
            fixedProjectId: projectId,
            projectFixed: true,
          );
        },
      });
    }

    // Site Visit Reports (not in RBAC table, but keep for now)
    menuItems.add({
      'title': 'Site Visit Reports',
      'icon': Icons.assignment,
      'route': () async {
        // Get current project ID from SharedPreferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        final projectId = prefs.getString('project_id');
        // Open SiteVisitReports with fixed project ID
        return SiteVisitReportsScreen(
          fixedProjectId: projectId,
          projectFixed: true,
        );
      },
    });

    return menuItems;
  }

  Widget build(BuildContext context) {
    List<Map<String, dynamic>> menuItems = getMenuItems();

    final dashboardContent = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: ListView(
        controller: _scrollController,
        children: <Widget>[
          AnimatedWidgetSlide(
              direction:
                  SlideDirection.topToBottom, // Specify the slide direction
              duration:
                  Duration(milliseconds: 300), // Adjust the duration as needed
              child: Column(
                children: [
                  // Welcome section with better styling
                ],
              )),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (blocked == true)
                  Column(
                    children: [
                      Container(
                          alignment: Alignment.centerLeft,
                          child: Text("Project blocked",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red))),
                      Container(
                          alignment: Alignment.centerLeft,
                          margin: EdgeInsets.only(bottom: 15),
                          child: Text("Reason : " + bolckReason.toString(),
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red))),
                    ],
                  ),
                // Progress Card with enhanced design
                _buildSummarySection(),
                if (workflowDashboardSlots.isNotEmpty) ...[
                  _buildWorkflowSlotsSection(),
                  SizedBox(height: 10),
                ],
                SizedBox(height: 10),
                // Hide tasks section for Billing roles
                if (_currentRole != 'Billing') _buildTasksSection(),
                SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.only(bottom: 16, top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.update_rounded,
                          color: AppTheme.getPrimaryColor(context), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Latest Updates',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                      Spacer(),
                    ],
                  ),
                ),
                _buildUpdatesSection(),
                SizedBox(height: 20),
                // Section header for Quick Actions
                Padding(
                  padding: EdgeInsets.only(bottom: 16, top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColorConst,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTextPrimary(context),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedWidgetSlide(
                    direction: SlideDirection
                        .bottomToTop, // Specify the slide direction
                    duration: Duration(
                        milliseconds: 300), // Adjust the duration as needed
                    child: Column(
                      children: [
                        Container(
                          margin: EdgeInsets.only(bottom: 20),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
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
                                  onTap: () async {
                                    await _handleMenuTap(item);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              AppTheme.getPrimaryColor(context)
                                                  .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          item['icon'],
                                          size: 20,
                                          color:
                                              AppTheme.getPrimaryColor(context),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 8),
                                        child: Column(
                                          children: [
                                            Text(
                                              item['title'],
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: AppTheme.getTextPrimary(
                                                    context),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (item['subtitle'] != null &&
                                                item['subtitle']
                                                    .toString()
                                                    .isNotEmpty) ...[
                                              SizedBox(height: 4),
                                              Text(
                                                item['subtitle'].toString(),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: AppTheme
                                                      .getTextSecondary(
                                                          context),
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    )),
                // Latest Updates Section
              ],
            ),
          ),
        ],
      ),
    );

    if (_shouldShowInitialPageSkeleton) {
      return _buildLoadingState();
    }

    return Stack(
      children: [
        dashboardContent,
        // if (_isAnySectionLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
      ),
      child: TextField(
        controller: _quickSearchController,
        focusNode: _quickSearchFocusNode,
        onChanged: (value) {
          setState(() {
            _quickSearchQuery = value;
          });
        },
        style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)),
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          prefixIcon: Icon(Icons.search,
              color: AppTheme.getTextSecondary(context), size: 20),
          suffixIcon: _quickSearchFocusNode.hasFocus
              ? IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppTheme.getTextSecondary(context),
                    size: 18,
                  ),
                  onPressed: _clearQuickSearch,
                  padding: EdgeInsets.all(8),
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Clear search',
                )
              : null,
          hintText: 'Search payments, gallery, scheduler…',
          hintStyle: TextStyle(
              color: AppTheme.getTextSecondary(context), fontSize: 14),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildQuickSearchSection(List<Map<String, dynamic>> menuItems) {
    final searchItems = _buildSearchItems(menuItems);
    final query = _quickSearchQuery.trim();
    final hasQuery = query.isNotEmpty;
    final filteredItems = hasQuery
        ? searchItems.where((item) => item.matches(query)).toList()
        : <_DashboardSearchItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Find what you need',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
        SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppTheme.primaryColorConst.withOpacity(0.1)),
          ),
          child: TextField(
            controller: _quickSearchController,
            focusNode: _quickSearchFocusNode,
            onTap: () async {
              // Scroll to top when search field is tapped
              // Use a small delay to ensure the scroll controller is ready
              await Future.delayed(Duration(milliseconds: 50));
              if (!mounted) return;
              if (_scrollController.hasClients) {
                print("scrolling to bottom");
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent + 110,
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              } else {
                // If controller not attached yet, wait for next frame
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent + 110,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
            },
            onChanged: (value) {
              setState(() {
                _quickSearchQuery = value;
              });
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              prefixIcon:
                  Icon(Icons.search, color: AppTheme.getTextSecondary(context)),
              suffixIcon: _quickSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close,
                          color: AppTheme.getTextSecondary(context)),
                      onPressed: _clearQuickSearch,
                    )
                  : null,
              hintText: 'Search payments, gallery, scheduler…',
              border: InputBorder.none,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 200),
          child: hasQuery
              ? Container(
                  key: ValueKey(query),
                  width: double.infinity,
                  margin: EdgeInsets.only(top: 12),
                  padding: EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundSecondary(context)
                        .withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.primaryColorConst.withOpacity(0.12)),
                  ),
                  child: filteredItems.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            'No shortcuts match "$query".',
                            style: TextStyle(
                                color: AppTheme.getTextSecondary(context),
                                fontSize: 13),
                          ),
                        )
                      : Column(
                          children: filteredItems
                              .map(
                                (item) => ListTile(
                                  dense: true,
                                  leading: Icon(item.icon,
                                      color: AppTheme.primaryColorConst),
                                  title: Text(
                                    item.title,
                                    style: TextStyle(
                                      color: AppTheme.getTextPrimary(context),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: item.subtitle != null
                                      ? Text(
                                          item.subtitle!,
                                          style: TextStyle(
                                              color: AppTheme.getTextSecondary(
                                                  context),
                                              fontSize: 12),
                                        )
                                      : null,
                                  onTap: () async {
                                    await item.onSelected();
                                    _clearQuickSearch();
                                  },
                                ),
                              )
                              .toList(),
                        ),
                )
              : SizedBox.shrink(),
        ),
      ],
    );
  }

  void _clearQuickSearch() {
    if (!mounted) return;
    _quickSearchController.clear();
    _quickSearchFocusNode.unfocus();
    setState(() {
      _quickSearchQuery = '';
    });
  }

  List<_DashboardSearchItem> _buildSearchItems(
      List<Map<String, dynamic>> menuItems) {
    final List<_DashboardSearchItem> items = [];

    for (final item in menuItems) {
      final title = item['title']?.toString() ?? '';
      if (title.isEmpty) continue;
      items.add(
        _DashboardSearchItem(
          title: title,
          icon: item['icon'] as IconData? ?? Icons.circle,
          keywords: [title],
          onSelected: () => _handleMenuTap(item),
        ),
      );
    }

    items.add(
      _DashboardSearchItem(
        title: 'Payments • Project',
        subtitle: 'Track tender milestones',
        icon: Icons.payments_rounded,
        keywords: ['payment', 'tender', 'project'],
        onSelected: () => _openPaymentCategory(PaymentCategory.tender),
      ),
    );

    items.add(
      _DashboardSearchItem(
        title: 'Payments • Non Tender',
        subtitle: 'Monitor custom expenses',
        icon: Icons.receipt_long,
        keywords: ['payment', 'non tender', 'expenses'],
        onSelected: () => _openPaymentCategory(PaymentCategory.nonTender),
      ),
    );

    return items;
  }

  Future<void> _handleMenuTap(Map<String, dynamic> item) async {
    final routeResult = item['route']();
    final widget = routeResult is Future ? await routeResult : routeResult;
    await _navigateToWidget(widget);
  }

  Future<void> _openPaymentCategory(PaymentCategory category) async {
    await _navigateToWidget(PaymentTaskWidget(initialCategory: category));
  }

  Future<void> _navigateToWidget(Widget widget) async {
    await DataProvider().reloadData();
    if (!mounted) return;

    // Create a custom route that intercepts back button presses
    final routeName = widget.runtimeType.toString();
    final route = _BackButtonInterceptingRoute(
      routeName: routeName,
      pageBuilder: (context, animation, secondaryAnimation) => widget,
    );

    print('[UserDashboard] Pushing route: $routeName');
    print('[UserDashboard] Route type: ${route.runtimeType}');
    print('[UserDashboard] Route settings: ${route.settings}');

    await Navigator.push(context, route);

    if (!mounted) return;
    print('[UserDashboard] ========== Navigator.push completed ==========');
    print('[UserDashboard] Route popped - returned from: $routeName');
    print('[UserDashboard] ===============================================');
    reloadData();
  }

  Widget _buildSummarySection() {
    final summaryCard = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: _buildSummaryCardBody(),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
    );

    return _wrapSectionWithLoader(
      isLoading: _isLoadingSummary,
      hasLoaded: _hasLoadedSummary,
      skeleton: _buildSummarySkeleton(),
      borderRadius: BorderRadius.circular(20),
      margin: const EdgeInsets.only(bottom: 20),
      child: summaryCard,
    );
  }

  Widget _buildSummaryCardBody() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColorConst.withOpacity(0.08),
            AppTheme.primaryColorConst.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.primaryColorConst.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColorConst.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header section with icon and label
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColorConst.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.trending_up_rounded,
                        color: AppTheme.primaryColorConst,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 10),
                    if (completed != null) ...[
                      Flexible(
                        child: Text(
                          "Construction Progress",
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.getTextSecondary(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else ...[
                      Flexible(
                        child: _buildCardSkeleton(
                            width: 150,
                            height: 16,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                    SizedBox(width: 8),
                    if (location.isNotEmpty)
                      InkWell(
                        onTap: () async {
                          await launchUrl(Uri.parse(location),
                              mode: LaunchMode.externalApplication);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.getBackgroundSecondary(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.directions_outlined,
                            color: AppTheme.primaryColorConst,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 16),
                // Percentage display - large and prominent
                if (completed != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              completed!,
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getTextPrimary(context),
                                height: 1.0,
                                letterSpacing: -1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(bottom: 6, left: 4),
                            child: Text(
                              "%",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.getTextSecondary(context),
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          "Complete",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.getTextSecondary(context),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else
                  ...[],
                // Progress bar
                if (completed != null) ...[
                  Container(
                    child: LinearPercentIndicator(
                      barRadius: Radius.circular(10),
                      padding: EdgeInsets.all(0),
                      lineHeight: 6.0,
                      percent: (double.tryParse(completed!) ?? 0.0) / 100,
                      animation: true,
                      animationDuration: 1200,
                      backgroundColor:
                          AppTheme.getBackgroundPrimaryLight(context),
                      clipLinearGradient: true,
                      linearGradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColorConst,
                          AppTheme.primaryColorConst.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ] else
                  ...[],
              ],
            ),
          ),
          SizedBox(width: 12),
          // Good going.jpg banner on the right - better positioned
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 110,
              height: 130,
              constraints: BoxConstraints(
                maxWidth: 110,
                maxHeight: 130,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/Good going.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: AppTheme.getBackgroundSecondary(context),
                    child: Icon(
                      Icons.image_not_supported,
                      color: AppTheme.getTextSecondary(context),
                      size: 32,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowSlotsSection() {
    final slotRecords = workflowDashboardSlots
        .whereType<Map>()
        .map((slot) => Map<String, dynamic>.from(slot))
        .toList();
    if (slotRecords.isEmpty) return SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
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
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.event_available_outlined,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Workflow Slots',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          ...slotRecords.map((record) => _buildWorkflowSlotRecord(record)),
        ],
      ),
    );
  }

  Widget _buildWorkflowSlotRecord(Map<String, dynamic> record) {
    final taskName = _firstTaskString(record, [
          'task_name',
          'source_task_name',
          'name',
          'title',
        ]) ??
        'Workflow slot';
    final slots = _mapTaskListFlexible(record['slots']);
    final acceptedSlot = _configMapFromDynamic(
      record['accepted_slot'] ?? record['confirmed_slot'],
    );
    final acceptedIndex =
        int.tryParse(record['accepted_slot_index']?.toString() ?? '') ??
            int.tryParse(acceptedSlot?['index']?.toString() ?? '');
    final clientComment = _firstTaskString(record, [
      'client_comment',
      'note',
      'comment',
    ]);
    final confirmationComment = _firstTaskString(record, [
      'confirmation_comment',
      'confirmed_comment',
      'confirm_note',
    ]);
    final confirmedBy =
        _firstTaskString(record, ['confirmed_by', 'accepted_by']);
    final confirmedAt =
        _firstTaskString(record, ['confirmed_at', 'accepted_at']);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            taskName,
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (slots.isNotEmpty) ...[
            SizedBox(height: 10),
            ...slots.asMap().entries.map((entry) {
              final slot = entry.value;
              final slotIndex = int.tryParse(slot['index']?.toString() ?? '') ??
                  entry.key + 1;
              final accepted =
                  acceptedIndex != null && acceptedIndex == slotIndex;
              return _buildWorkflowSlotPill(slot, slotIndex, accepted);
            }),
          ],
          if (clientComment != null)
            _buildWorkflowSlotNote('Client comment', clientComment),
          if (confirmationComment != null)
            _buildWorkflowSlotNote('Confirmation comment', confirmationComment),
          if (confirmedBy != null || confirmedAt != null) ...[
            SizedBox(height: 8),
            Text(
              [
                if (confirmedBy != null) 'Confirmed by $confirmedBy',
                if (confirmedAt != null) confirmedAt,
              ].join(' • '),
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkflowSlotPill(
    Map<String, dynamic> slot,
    int slotIndex,
    bool accepted,
  ) {
    final display = _firstTaskString(slot, ['display', 'datetime', 'value']) ??
        'Slot $slotIndex';
    final timeLabel = _firstTaskString(slot, ['time_label']);
    final time = _firstTaskString(slot, ['time']);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accepted ? Color(0xFFDCFCE7) : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: accepted ? Color(0xFF10B981) : Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Icon(
            accepted ? Icons.check_circle : Icons.schedule_outlined,
            color: accepted ? Color(0xFF10B981) : Color(0xFF6B7280),
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                display,
                if (timeLabel != null) timeLabel,
                if (time != null) time,
              ].join(' • '),
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 12.5,
                fontWeight: accepted ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowSlotNote(String label, String text) {
    return Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        '$label: $text',
        style: TextStyle(
          color: AppTheme.getTextSecondary(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  Map<String, dynamic>? _configMapFromDynamic(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  Widget _buildUpdatesSection() {
    final updatesCard = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 700),
      curve: Curves.easeOut,
      child: _buildUpdatesCardBody(context),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
    );

    return _wrapSectionWithLoader(
      isLoading: _isLoadingUpdates,
      hasLoaded: _hasLoadedUpdates,
      skeleton: Container(),
      borderRadius: BorderRadius.circular(16),
      margin: const EdgeInsets.only(bottom: 20),
      child: updatesCard,
    );
  }

  Widget _buildUpdatesCardBody(BuildContext context) {
    // Show skeleton if data not loaded yet
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.getBackgroundSecondary(context),
        border: Border.all(
          color: AppTheme.primaryColorConst.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColorConst.withOpacity(0.08),
            blurRadius: 10,
            offset: Offset(0, 3),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: Offset(0, 2),
            spreadRadius: -1,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Accent colored side border
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: AppTheme.primaryColorConst,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
          ),
          // Main content
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon and date
                Row(
                  children: [
                    Icon(
                      Icons.update_rounded,
                      color: AppTheme.primaryColorConst,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      updatePostedOnDate,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.getTextSecondary(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // Tradesmen info - no box, just text
                if (updateResponseBody != null &&
                    updateResponseBody is List &&
                    updateResponseBody.length > 0 &&
                    updateResponseBody[0] != null &&
                    updateResponseBody[0]['tradesmenMap'] != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.people_outline,
                          color: AppTheme.primaryColorConst,
                          size: 14,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            parsedUpdateTradesmen(
                                updateResponseBody[0]['tradesmenMap']),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.getTextPrimary(context),
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Daily updates list with simple bullet points
                if (dailyUpdateList.isNotEmpty) ...[
                  SizedBox(height: 12),
                  ...dailyUpdateList.asMap().entries.map((entry) {
                    final index = entry.key;
                    final update = entry.value.toString();
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 400 + (index * 100)),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 8 * (1 - value)),
                            child: Padding(
                              padding:
                                  EdgeInsets.only(top: index == 0 ? 0 : 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      update,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.getTextPrimary(context),
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySkeleton() {
    return _buildCardSkeleton(
        height: 170, borderRadius: BorderRadius.circular(20));
  }

  Widget _buildUpdatesSkeleton() {
    return _buildCardSkeleton(
        height: 220, borderRadius: BorderRadius.circular(16));
  }

  Widget _wrapSectionWithLoader({
    required bool isLoading,
    required bool hasLoaded,
    required Widget child,
    required Widget skeleton,
    required BorderRadius borderRadius,
    EdgeInsetsGeometry? margin,
  }) {
    Widget withMargin(Widget widget) {
      final padding = margin;
      if (padding == null) return widget;
      return Padding(
        padding: padding,
        child: widget,
      );
    }

    if (isLoading && !hasLoaded) {
      return withMargin(skeleton);
    }

    Widget content = child;

    if (isLoading && hasLoaded) {
      content = Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: borderRadius,
                child: Container(
                  color:
                      AppTheme.getBackgroundPrimary(context).withOpacity(0.65),
                  child: Center(
                    child: _buildSkeleton(
                        80, MediaQuery.of(context).size.width - 32),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return withMargin(content);
  }

  Widget _buildCardSkeleton(
      {required double height,
      required BorderRadius borderRadius,
      double? width}) {
    return Shimmer.fromColors(
      baseColor: AppTheme.getBackgroundSecondary(context).withOpacity(0.4),
      highlightColor: Colors.white.withOpacity(0.35),
      child: Container(
        height: height,
        width: width,
        constraints: width != null ? BoxConstraints(maxWidth: width) : null,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context).withOpacity(0.4),
          borderRadius: borderRadius,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final baseColor = AppTheme.getTextPrimary(context).withOpacity(0.6);
    final highlightColor = Colors.white.withOpacity(0.35);

    return Container(
      color: AppTheme.getBackgroundPrimary(context),
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          _buildSkeletonCard(baseColor, highlightColor,
              height: 60, margin: EdgeInsets.only(bottom: 16)),
          _buildSkeletonCard(baseColor, highlightColor,
              height: 170, margin: EdgeInsets.only(bottom: 20)),
          _buildSkeletonCard(baseColor, highlightColor,
              height: 200, margin: EdgeInsets.only(bottom: 20)),
          _buildSkeletonGrid(baseColor, highlightColor),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(Color base, Color highlight,
      {double height = 120, EdgeInsets? margin}) {
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        height: height,
        margin: margin ?? EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context).withOpacity(0.4),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid(Color base, Color highlight) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: 6,
      itemBuilder: (_, __) {
        return Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context).withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingOverlay() {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          opacity: _isAnySectionLoading ? 1.0 : 0.0,
          duration: Duration(milliseconds: 200),
          child: Container(
            margin: EdgeInsets.only(top: 12),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context).withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.primaryColorConst.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColorConst),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Loading project data...',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 12,
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

class _DashboardSearchItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<String> keywords;
  final Future<void> Function() onSelected;

  _DashboardSearchItem({
    required this.title,
    required this.icon,
    required this.onSelected,
    this.subtitle,
    List<String>? keywords,
  }) : keywords = keywords ?? [title];

  bool matches(String query) {
    final lower = query.toLowerCase();
    if (title.toLowerCase().contains(lower)) return true;
    if (subtitle != null && subtitle!.toLowerCase().contains(lower))
      return true;
    return keywords.any((keyword) => keyword.toLowerCase().contains(lower));
  }
}

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  AnimatedWidgetSlide({
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  _AnimatedWidgetSlideState createState() => _AnimatedWidgetSlideState();
}

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    switch (widget.direction) {
      case SlideDirection.leftToRight:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInSine,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, -1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
    }

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

String parsedUpdateTradesmen(dynamic tradesmenMap) {
  try {
    // Try parsing as JSON Map<String,int>
    final jsonMap = tradesmenMap.toString().trim();
    if (jsonMap == 'null' || jsonMap.isEmpty) {
      return '';
    }
    print("jsonMap: $jsonMap");
    // Try decode as JSON
    if (jsonMap.startsWith('{') && jsonMap.endsWith('}')) {
      final List<String> parsed =
          jsonMap.substring(1, jsonMap.length - 1).split(',');
      String result = '';
      int index = 0;
      for (final item in parsed) {
        final key = item.split(':')[0].trim();
        final value = item.split(':')[1].trim();
        if (index == parsed.length - 1) {
          result += '$value ${key}s';
        } else if (parsed.length > 2 && index == parsed.length - 2) {
          result += '$value ${key}s and ';
        } else {
          result += '$value ${key}s, ';
        }
        index++;
      }
      return 'Resources: $result';
    }
    return '';
  } catch (e) {
    return tradesmenMap.toString().trim() == 'null'
        ? ''
        : tradesmenMap.toString().trim();
  }
}

// Logout for clients is handled by `NavMenuWidget` (drawer) to match other roles.
