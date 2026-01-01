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
import 'Gallery.dart';
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
import 'ViewAllTasksScreen.dart';
import 'Skin2/loginPage.dart';
import 'widgets/dark_mode_toggle.dart';

class UserDashboardLayout extends StatefulWidget {
  final bool fromAdminDashboard;

  UserDashboardLayout({this.fromAdminDashboard = false});

  @override
  UserDashboardLayoutState createState() => UserDashboardLayoutState();
}

// Custom route that intercepts back button presses
class _BackButtonInterceptingRoute<T> extends PageRoute<T> {
  final Widget Function(BuildContext, Animation<double>, Animation<double>) pageBuilder;
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
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
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
    print('[BackButtonInterceptingRoute] Android/system back button - willPop!');
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
    print('[BackButtonInterceptingRoute] Android/system back button was pressed!');
    print('[BackButtonInterceptingRoute] Calling super.didPop()...');
    final result2 = super.didPop(result);
    print('[BackButtonInterceptingRoute] didPop returned: $result2');
    print('[BackButtonInterceptingRoute] ===================================');
    return result2;
  }

  @override
  void didComplete(T? result) {
    print('[BackButtonInterceptingRoute] ========== didComplete called ==========');
    print('[BackButtonInterceptingRoute] Route name: $routeName');
    print('[BackButtonInterceptingRoute] Result: $result');
    print('[BackButtonInterceptingRoute] ===================================');
    super.didComplete(result);
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    print('[BackButtonInterceptingRoute] didChangeNext - nextRoute: ${nextRoute?.settings.name ?? "null"}');
    super.didChangeNext(nextRoute);
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    print('[BackButtonInterceptingRoute] didChangePrevious - previousRoute: ${previousRoute?.settings.name ?? "null"}');
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
      print('[NavigatorObserver] Previous route: ${previousRoute.settings.name ?? previousRoute.runtimeType}');
    }
    
    // Check if this is the Payments route
    final routeName = route.settings.name ?? '';
    final routeType = route.runtimeType.toString();
    if (routeName.contains('Payment') || routeType.contains('Payment')) {
      print('[NavigatorObserver] *** This is a Payments route! ***');
      print('[NavigatorObserver] Android back button was pressed on Payments page!');
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
  final GlobalKey<UserDashboardScreenState> _userDashboardKey = GlobalKey<UserDashboardScreenState>();
  String displayName = 'My Home';
  // Removed local navigatorKey and observer - using global ones from main.dart

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
  }

  _loadDisplayName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadedUsername = ' ';
    if (prefs.containsKey("client_name")) {
      loadedUsername = prefs.getString('client_name') ?? ' ';
    } else {
      loadedUsername = prefs.getString('username') ?? ' ';
    }

    String name = _getDisplayName(loadedUsername);
    if (mounted) {
      setState(() {
        displayName = name;
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
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
              Container(
                margin: EdgeInsets.only(top: 12),
                width: MediaQuery.of(context).size.width * 0.6,
                child: Text(
                  displayName.isNotEmpty ? displayName + "\'s Dashboard" : 'User\'s Dashboard',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
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
        backgroundColor: AppTheme.getBackgroundPrimary(context),
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
            Column(
              children: [
                // User avatar header
                if (_userDashboardKey.currentState != null)
                  _buildUserHeader(),
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
  var expanded = false;
  bool _isLoadingSummary = true;
  bool _isLoadingUpdates = true;
  bool _hasLoadedSummary = false;
  bool _hasLoadedUpdates = false;
  final TextEditingController _quickSearchController = TextEditingController();
  final FocusNode _quickSearchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
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
          if (_scrollController.hasClients) {
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

    List<String> nextDailyUpdates = [];
    String nextUpdateDate = DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();

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
      print('[UserDashboard] loadTasks already in progress, skipping duplicate call');
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

      if (projectId == null || projectId.isEmpty) {
        // No project selected - set empty tasks
        setState(() {
          _tasks = [];
          _isLoadingTasks = false;
        });
        return;
      }

      // Fetch all tasks for the project (irrespective of assigned_to)
      Map<String, String> queryParams = {
        'project_id': projectId,
      };
      
      Uri uri = Uri.parse("https://office.buildahome.in/API/get_tasks").replace(
        queryParameters: queryParams,
      );
      
      print('[UserDashboard] Fetching tasks for project_id: $projectId');
      var response = await http.get(uri).timeout(const Duration(seconds: 20));
      
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
        
        List<dynamic> allTasks = taskMap.values.toList();
        
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
        
        print('[UserDashboard] Loaded ${allTasks.length} tasks for project $projectId');
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

  Future<void> updateTaskStatus(int taskId, String newStatus) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');

      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/update_task_status");
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

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  bool get _shouldShowInitialSummarySkeleton => _isLoadingSummary && !_hasLoadedSummary;

  bool get _shouldShowInitialUpdatesSkeleton => _isLoadingUpdates && !_hasLoadedUpdates;

  bool get _shouldShowInitialPageSkeleton => _shouldShowInitialSummarySkeleton && _shouldShowInitialUpdatesSkeleton;

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

  Widget _buildTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - minimal (matching admin dashboard)
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
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
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

        // Tasks list with horizontal scroll view (matching admin dashboard)
        if (!_isLoadingTasks && _tasks.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.builder(
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
        
        if (!_isLoadingTasks && _tasks.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(0xFF10B981), // Same green as Create Task button
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ViewAllTasksScreen(
                                tasks: _tasks,
                                onTaskUpdated: () => loadTasks(),
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.view_list, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'View All Tasks',
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
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final projectName = task['project_name']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final userName = task['user_name']?.toString() ?? '';
    final status = task['status']?.toString() ?? 'pending';
    final note = task['note']?.toString() ?? task['s_note']?.toString() ?? '';

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

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    final statuses = [
      {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706), 'icon': Icons.pending},
      {'value': 'in_progress', 'label': 'In Progress', 'color': AppTheme.primaryColorConst, 'icon': Icons.work},
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
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.getTextSecondary(context)),
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

  List<Map<String, dynamic>> getMenuItems() {
    List<Map<String, dynamic>> menuItems = [];
    final rbac = RBACService();

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
              direction: SlideDirection.topToBottom, // Specify the slide direction
              duration: Duration(milliseconds: 300), // Adjust the duration as needed
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
                      Container(alignment: Alignment.centerLeft, child: Text("Project blocked", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                      Container(
                          alignment: Alignment.centerLeft,
                          margin: EdgeInsets.only(bottom: 15),
                          child: Text("Reason : " + bolckReason.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                    ],
                  ),
                // Progress Card with enhanced design
                _buildSummarySection(),
                SizedBox(height: 10),
                // Hide tasks section for Billing role
                if (_currentRole != 'Billing') _buildTasksSection(),
                SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.only(bottom: 16, top: 8),
                  child: Row(
                    children: [
                     Icon(Icons.update_rounded, color: AppTheme.getPrimaryColor(context), size: 24),
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
                    direction: SlideDirection.bottomToTop, // Specify the slide direction
                    duration: Duration(milliseconds: 300), // Adjust the duration as needed
                    child: Column(
                      children: [
                        Container(
                          margin: EdgeInsets.only(bottom: 20),
                          child: GridView.builder(
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
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          item['icon'],
                                          size: 20,
                                          color: AppTheme.getPrimaryColor(context),
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
                                            fontWeight: FontWeight.w600,
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
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
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
          prefixIcon: Icon(Icons.search, color: AppTheme.getTextSecondary(context), size: 20),
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
          hintStyle: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 14),
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
    final filteredItems = hasQuery ? searchItems.where((item) => item.matches(query)).toList() : <_DashboardSearchItem>[];

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
            border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.1)),
          ),
          child: TextField(
            controller: _quickSearchController,
            focusNode: _quickSearchFocusNode,
            onTap: () async {
              // Scroll to top when search field is tapped
              // Use a small delay to ensure the scroll controller is ready
              await Future.delayed(Duration(milliseconds: 50));
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
                  if (_scrollController.hasClients && mounted) {
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
              prefixIcon: Icon(Icons.search, color: AppTheme.getTextSecondary(context)),
              suffixIcon: _quickSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
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
                    color: AppTheme.getBackgroundSecondary(context).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.12)),
                  ),
                  child: filteredItems.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            'No shortcuts match "$query".',
                            style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 13),
                          ),
                        )
                      : Column(
                          children: filteredItems
                              .map(
                                (item) => ListTile(
                                  dense: true,
                                  leading: Icon(item.icon, color: AppTheme.primaryColorConst),
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
                                          style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 12),
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
    _quickSearchController.clear();
    _quickSearchFocusNode.unfocus();
    setState(() {
      _quickSearchQuery = '';
    });
  }

  List<_DashboardSearchItem> _buildSearchItems(List<Map<String, dynamic>> menuItems) {
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
                        child: _buildCardSkeleton(width: 150, height: 16, borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                    SizedBox(width: 8),
                    if (location.isNotEmpty)
                      InkWell(
                        onTap: () async {
                          await launchUrl(Uri.parse(location), mode: LaunchMode.externalApplication);
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
                ] else ...[
                ],
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
                      backgroundColor: AppTheme.getBackgroundPrimaryLight(context),
                      clipLinearGradient: true,
                      linearGradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColorConst,
                          AppTheme.primaryColorConst.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                ],
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
            if (updateResponseBody != null && updateResponseBody is List && updateResponseBody.length > 0 && updateResponseBody[0] != null && updateResponseBody[0]['tradesmenMap'] != null)
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
                        parsedUpdateTradesmen(updateResponseBody[0]['tradesmenMap']),
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
                          padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
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
    return _buildCardSkeleton(height: 170, borderRadius: BorderRadius.circular(20));
  }

  Widget _buildUpdatesSkeleton() {
    return _buildCardSkeleton(height: 220, borderRadius: BorderRadius.circular(16));
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
                  color: AppTheme.getBackgroundPrimary(context).withOpacity(0.65),
                  child: Center(
                    child: _buildSkeleton(80, MediaQuery.of(context).size.width - 32),
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

  Widget _buildCardSkeleton({required double height, required BorderRadius borderRadius, double? width}) {
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
          _buildSkeletonCard(baseColor, highlightColor, height: 60, margin: EdgeInsets.only(bottom: 16)),
          _buildSkeletonCard(baseColor, highlightColor, height: 170, margin: EdgeInsets.only(bottom: 20)),
          _buildSkeletonCard(baseColor, highlightColor, height: 200, margin: EdgeInsets.only(bottom: 20)),
          _buildSkeletonGrid(baseColor, highlightColor),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(Color base, Color highlight, {double height = 120, EdgeInsets? margin}) {
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
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
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
    if (subtitle != null && subtitle!.toLowerCase().contains(lower)) return true;
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

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide> with SingleTickerProviderStateMixin {
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
      final List<String> parsed = jsonMap.substring(1, jsonMap.length - 1).split(',');
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
    return tradesmenMap.toString().trim() == 'null' ? '' : tradesmenMap.toString().trim();
  }
}

class _UserLogoutButton extends StatelessWidget {
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
              fontWeight: FontWeight.bold,
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
                  fontWeight: FontWeight.w600,
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
          color: AppTheme.primaryColorConstDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.getBackgroundPrimary(context).withOpacity(0.3),
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

