import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import "Payments.dart";
import 'app_theme.dart';
import 'widgets/skeleton_loader.dart';
import 'Drawings.dart';
import 'Scheduler.dart';
import 'Gallery.dart' hide TimelineGallery;
import 'TimelineGallery.dart';
import 'NotesAndComments.dart';
import 'chat_v1/chat_v1_app.dart';
import 'ProjectFocusScreen.dart';
import 'checklist_categories.dart';
import 'services/api_http.dart';
import 'services/data_provider.dart';
import 'services/notification_service.dart';
import 'services/rbac_service.dart';
import 'services/session_manager.dart';
import 'services/mobile_live_test_access.dart';
import 'AdminDashboard.dart';
import 'RequestDrawing.dart';
import 'InspectionRequest.dart';
import 'SiteVisitReports.dart';
import 'indents_screen.dart';
import 'indent_proof.dart';
import 'approved_pos_screen.dart';
// import 'work_orders_screen.dart';
import 'mobile_live_test_screen.dart';
import 'main.dart';
import 'MyTasksScreen.dart';
import 'task_display_title.dart';
import 'ProjectTimelineScreen.dart';
import 'SalesSopCardsScreen.dart';
import 'SlotsScreen.dart';
import 'ClientPortalScreen.dart';
import 'UploadPaymentProofScreen.dart';
import 'documents_v1/documents_v1_home_screen.dart';
import 'VirtualTour.dart';
import 'NavMenu.dart';
import 'notifcations.dart';
import 'Dpr.dart';
import 'services/client_generation_service.dart';
import 'services/legacy_client_features.dart';
import 'services/mobile_quick_actions.dart';
import 'services/mobile_quick_actions_service.dart';
import 'services/profile_picture_service.dart';
import 'utilities/role_app_bar_color.dart';
import 'widgets/client_home_tour.dart';
import 'widgets/dashboard_chrome.dart';
import 'widgets/modern_task_card.dart';
import 'widgets/profile_picture_dialog.dart';

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
  final GlobalKey _tourHeaderKey = GlobalKey();
  final GlobalKey _tourProgressKey = GlobalKey();
  final GlobalKey _tourChatKey = GlobalKey();
  final GlobalKey _tourActionsKey = GlobalKey();
  final GlobalKey _tourBottomNavKey = GlobalKey();
  String displayName = 'there';
  String? _userRole;
  int _bottomNavIndex = 0;
  bool _tourActive = false;
  bool _tourStartInFlight = false;
  static const Color _navy = Color(0xFF1B254B);
  static const Color _mutedGrey = Color(0xFF8A94A6);
  // Removed local navigatorKey and observer - using global ones from main.dart

  bool get _showBackToDashboard {
    if (!widget.fromAdminDashboard) return false;
    final role = (_userRole ?? '').trim();
    if (role.isEmpty) return true;
    return role.toLowerCase() != 'client';
  }

  @override
  void initState() {
    super.initState();
    ClientGenerationService.instance.generation
        .addListener(_onClientGenerationChanged);
    _loadDisplayName();
    _loadUnreadNotifications();
    ClientGenerationService.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryStartFirstRun();
    });
  }

  @override
  void dispose() {
    ClientGenerationService.instance.generation
        .removeListener(_onClientGenerationChanged);
    super.dispose();
  }

  void _onClientGenerationChanged() {
    if (mounted) {
      setState(() {});
      _tryStartFirstRun();
    }
  }

  bool get _restrictLegacyClientFeatures =>
      ClientGenerationService.instance.restrictsClientFeatures(_userRole);

  Future<void> _tryStartFirstRun() async {
    if (!mounted || _tourActive || _tourStartInFlight) return;
    if (widget.fromAdminDashboard) return;

    _tourStartInFlight = true;
    try {
      await ClientGenerationService.instance.ensureLoaded();
      if (!mounted) return;

      final role = _userRole ??
          (await SharedPreferences.getInstance()).getString('role');
      final isClient = (role ?? '').trim().toLowerCase() == 'client';
      if (!isClient || ClientGenerationService.instance.isLegacy) {
        maybePromptForProfilePicture(context);
        return;
      }
      if (await ClientHomeTour.hasCompleted()) {
        if (mounted) maybePromptForProfilePicture(context);
        return;
      }

      for (var i = 0; i < 16; i++) {
        if (_userDashboardKey.currentState?.isReadyForTour == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 160));
        if (!mounted) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || _tourActive) return;
      if (await ClientHomeTour.hasCompleted()) {
        maybePromptForProfilePicture(context);
        return;
      }
      // Mark done as soon as it opens so login/rebuild/logout cannot replay it.
      await ClientHomeTour.markCompleted();
      if (!mounted || _tourActive) return;
      setState(() => _tourActive = true);
    } finally {
      _tourStartInFlight = false;
    }
  }

  Future<void> _finishTour() async {
    if (mounted) setState(() => _tourActive = false);
    if (mounted) maybePromptForProfilePicture(context);
  }

  Future<void> _revealTourTarget(GlobalKey key) async {
    await _userDashboardKey.currentState?.revealTourTarget(key);
  }

  _loadDisplayName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await ProfilePictureService.getStoredPath();
    String loadedUsername = ' ';
    if (prefs.containsKey("client_name")) {
      loadedUsername = prefs.getString('client_name') ?? ' ';
    } else {
      loadedUsername = prefs.getString('username') ?? ' ';
    }

    String name = _getDisplayName(loadedUsername);
    final role = prefs.getString('role');
    if (mounted) {
      setState(() {
        displayName = name;
        _userRole = role;
      });
      _tryStartFirstRun();
    }
  }

  void _goBackToDashboard() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => AdminDashboard()),
    );
  }

  Future<void> _loadUnreadNotifications({bool force = false}) async {
    final service = NotificationService.instance;
    await service.ensureHydrated();
    await service.sync(force: force);
  }

  String _getDisplayName(String username) {
    if (username.isEmpty || username == ' ') {
      return 'there';
    }
    try {
      String name = username.split('-')[0].trim();
      return name.isNotEmpty ? name : username.trim();
    } catch (e) {
      return username.trim().isNotEmpty ? username.trim() : 'there';
    }
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardChrome.wrap(
          DashboardChromeStyle.user,
          const Notifications(),
        ),
      ),
    );
    _loadUnreadNotifications(force: true);
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

    if (_restrictLegacyClientFeatures && index == 1) {
      await showFeatureComingSoon(
        context,
        featureName: 'My tasks',
      );
      return;
    }

    setState(() => _bottomNavIndex = index);
    final screen = _userDashboardKey.currentState;
    Widget? page;
    switch (index) {
      case 1:
        final tasks = screen?._tasks ?? <dynamic>[];
        page = MyTasksScreen(
          tasks: List<dynamic>.from(tasks),
          onRefresh: screen == null
              ? null
              : () => screen._refreshTasksForMyTasks(),
        );
        break;
      case 2:
        page = const DprScreen(title: 'Updates');
        break;
      case 3:
        if (screen != null) {
          await screen.openChat();
        }
        if (mounted) setState(() => _bottomNavIndex = 0);
        return;
    }

    if (page != null) {
      final chrome = widget.fromAdminDashboard
          ? DashboardChromeStyle.admin
          : DashboardChromeStyle.user;
      final appBarColor = chrome == DashboardChromeStyle.admin
          ? RoleAppBarColor.forRole(_userRole)
          : null;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardChrome.wrap(
            chrome,
            page!,
            appBarColor: appBarColor,
          ),
        ),
      );
      if (mounted) setState(() => _bottomNavIndex = 0);
    }
  }

  Widget _buildUserHeader() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: MediaQuery.of(context).size.width,
      padding: EdgeInsets.only(top: topPad + 8, left: 16, right: 16, bottom: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showBackToDashboard) ...[
            Material(
              color: const Color(0xFFF1F4F8),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: _goBackToDashboard,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, color: _navy, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Back to dashboard',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greetingForNow(),
                      style: const TextStyle(
                        color: _mutedGrey,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${displayName.isNotEmpty ? displayName : 'there'} 👋',
                      style: const TextStyle(
                        color: _navy,
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
          KeyedSubtree(
            key: _tourHeaderKey,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _openNotifications,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE6EAF0)),
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
                                color: _navy,
                                size: 22,
                              ),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 16),
                                  height: 16,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE53935),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    unreadCount > 9
                                        ? '9+'
                                        : '$unreadCount',
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
                ValueListenableBuilder<String?>(
                  valueListenable: ProfilePictureService.picturePathNotifier,
                  builder: (context, picturePath, _) {
                    return ProfileAvatar(
                      displayName: displayName,
                      picturePath: picturePath,
                      size: 40,
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      borderColor: const Color(0xFFE6EAF0),
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    );
                  },
                ),
              ],
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = <_DashNavItem>[
      _DashNavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
      _DashNavItem(
          Icons.pending_actions_rounded, Icons.pending_actions_outlined, 'Tasks'),
      _DashNavItem(
          Icons.description_rounded, Icons.description_outlined, 'Updates'),
      _DashNavItem(
          Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'Chat'),
      _DashNavItem(Icons.menu_rounded, Icons.menu_rounded, 'More'),
    ];

    return Container(
      key: _tourBottomNavKey,
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
              final comingSoon = _restrictLegacyClientFeatures && index == 1;
              final color = comingSoon
                  ? const Color(0xFFB0B7C3)
                  : (selected ? _navy : _mutedGrey);
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
                          comingSoon ? 'Soon' : item.label,
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
    // When opened from AdminDashboard, one system/back press should simply
    // pop this project route and reveal the existing dashboard underneath.
    // Do NOT pushReplacement AdminDashboard — that stacked extra routes and
    // forced users to press back multiple times.
    return PopScope(
      canPop: !widget.fromAdminDashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.fromAdminDashboard) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );
        }
      },
      child: Stack(
        children: [
          Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.white,
            drawer: NavMenuWidget(),
            appBar: (!widget.fromAdminDashboard && Navigator.of(context).canPop())
                ? AppBar(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: _navy,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    title: const Text(
                      'Project',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    iconTheme: const IconThemeData(color: _navy),
                  )
                : null,
            body: Column(
              children: [
                _buildUserHeader(),
                Expanded(
                  child: UserDashboardScreen(
                    key: _userDashboardKey,
                    tourProgressKey: _tourProgressKey,
                    tourChatKey: _tourChatKey,
                    tourActionsKey: _tourActionsKey,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: _buildBottomNav(),
          ),
          if (_tourActive)
            Positioned.fill(
              child: ClientHomeTourOverlay(
                steps: [
                  const ClientTourStep(
                    title: 'Welcome to your home',
                    body:
                        'A quick look at where everything lives. This only shows the first time you sign in.',
                  ),
                  ClientTourStep(
                    title: 'Project progress',
                    body:
                        'This banner shows how far construction has come, and opens the site on the map.',
                    targetKey: _tourProgressKey,
                    holeRadius: 18,
                  ),
                  ClientTourStep(
                    title: 'Chat and latest tasks',
                    body:
                        'Start a conversation with the team, or see the work that needs you next.',
                    targetKey: _tourChatKey,
                    holeRadius: 18,
                  ),
                  ClientTourStep(
                    title: 'Quick actions',
                    body:
                        'Payments, gallery, and more. “For me” opens your Client Portal.',
                    targetKey: _tourActionsKey,
                    holeRadius: 16,
                    holePadding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  ),
                  ClientTourStep(
                    title: 'Tasks, updates, and chat',
                    body:
                        'Use the bar below for your tasks, site updates, chat, and the full menu.',
                    targetKey: _tourBottomNavKey,
                    holeRadius: 16,
                    holePadding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                  ),
                  ClientTourStep(
                    title: 'Alerts and your menu',
                    body:
                        'Notifications land on the bell. Tap your photo for the menu, profile, and more screens.',
                    targetKey: _tourHeaderKey,
                    holeRadius: 22,
                    holePadding: const EdgeInsets.all(6),
                  ),
                ],
                ensureVisible: _revealTourTarget,
                onFinished: _finishTour,
              ),
            ),
        ],
      ),
    );
  }
}

class _DashNavItem {
  final IconData activeIcon;
  final IconData icon;
  final String label;
  const _DashNavItem(this.activeIcon, this.icon, this.label);
}

class UserDashboardScreen extends StatefulWidget {
  final GlobalKey? tourProgressKey;
  final GlobalKey? tourChatKey;
  final GlobalKey? tourActionsKey;

  const UserDashboardScreen({
    Key? key,
    this.tourProgressKey,
    this.tourChatKey,
    this.tourActionsKey,
  }) : super(key: key);

  @override
  UserDashboardScreenState createState() {
    return UserDashboardScreenState();
  }
}

class UserDashboardScreenState extends State<UserDashboardScreen> {
  static const Color _navy = Color(0xFF1B254B);
  static const Color _mutedGrey = Color(0xFF8A94A6);
  static const Color _cardBorder = Color(0xFFE8ECF1);
  static const Color _softShadow = Color(0x14000000);

  List dailyUpdateList = [];
  var username = ' ';
  var updatePostedOnDate = " ";
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
  static const double _recentTaskCardHeight = 118;
  static const double _recentTasksViewportHeight =
      _recentTaskCardHeight * 3 + 16;

  final PageController _recentTasksPageController = PageController(
    viewportFraction: 1 / 3,
  );
  String _quickSearchQuery = '';
  String? _currentRole;
  bool _openingMenu = false;

  // Tasks state
  List<dynamic> _tasks = [];
  bool _isLoadingTasks = false;
  String? _tasksError;

  @override
  void dispose() {
    ClientGenerationService.instance.generation
        .removeListener(_onClientGenerationChanged);
    MobileQuickActionsService.instance.revision
        .removeListener(_onQuickActionsChanged);
    _quickSearchController.dispose();
    _quickSearchFocusNode.dispose();
    _scrollController.dispose();
    _recentTasksPageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ClientGenerationService.instance.generation
        .addListener(_onClientGenerationChanged);
    MobileQuickActionsService.instance.revision
        .addListener(_onQuickActionsChanged);
    // Load role
    _loadRole();
    // Load cached data (if available) without blocking the transition
    loadDataFromProvider();
    // Fetch fresh data asynchronously and preload project data for non-Client users
    _initializeData();
    // Load tasks for the current user
    loadTasks();
    ClientGenerationService.instance.ensureLoaded();
    MobileQuickActionsService.instance
        .ensureSurface(MobileQuickActionSurface.projectHomeNew);

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
    final dynamic nextUpdates = dataProvider.clientProjectUpdates;

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
    if (force) {
      await MobileQuickActionsService.instance.ensureSurface(
        MobileQuickActionSurface.projectHomeNew,
        force: true,
      );
    }
    // Section flags are reset inside loadDataFromProvider once data is applied.
    // Note: loadTasks() is only called once at initState to avoid multiple API calls
  }

  String _tasksDeltaKey(List<dynamic> tasks) {
    return tasks.whereType<Map>().map((task) {
      return [
        task['id'],
        task['status'],
        task['workflow_status'],
        task['note'],
        task['updated_at'],
        task['can_update_workflow_task'],
        task['can_approve_workflow_task'],
        jsonEncode(task['workflow_task_actions'] ?? const []),
        jsonEncode(task['workflow_actions'] ?? const []),
        jsonEncode(task['workflow_delay_gate'] ?? const {}),
      ].join('|');
    }).join('||');
  }

  Future<void> loadTasks({bool silent = false}) async {
    if (!mounted) return;

    // Prevent multiple simultaneous calls
    if (_isLoadingTasks) {
      print(
          '[UserDashboard] loadTasks already in progress, skipping duplicate call');
      return;
    }

    final showLoader = !silent && _tasks.isEmpty;
    if (showLoader) {
      setState(() {
        _isLoadingTasks = true;
        _tasksError = null;
      });
    } else {
      _isLoadingTasks = true;
    }

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
      var response = await ApiHttp.get(uri).timeout(const Duration(seconds: 20));

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

        // Deduplicate by task id (workflow ids may not be integers).
        final taskMap = <String, dynamic>{};
        for (var task in fetchedTasks) {
          if (task is Map && task['id'] != null) {
            final taskId = task['id'].toString().trim();
            if (taskId.isNotEmpty && taskId != '0') {
              taskMap[taskId] = task;
            }
          }
        }

        List<dynamic> allTasks = taskMap.values.toList();

        await DataProvider().cacheSalesSopIdsFromTasks(allTasks);
        String? salesSopId;
        if (projectId != null && projectId.isNotEmpty) {
          salesSopId = await DataProvider().resolveSalesSopId(
            projectId: projectId,
            apiToken: apiToken,
            tasksHint: allTasks,
          );
        }

        // API uses OR logic across filters. Keep this user's tasks for the
        // selected project, including workflow rows keyed by sales_sop_id.
        allTasks = filterTasksForProjectAndAssignee(
          allTasks,
          userId: userId,
          projectId: projectId,
          alsoMatchProjectIds: [
            if (salesSopId != null && salesSopId.isNotEmpty) salesSopId,
          ],
        );

        // Sort by creation date (newest first)
        allTasks.sort((a, b) {
          if (a is! Map || b is! Map) return 0;
          String aDate = (a['created_at'] ?? '').toString();
          String bDate = (b['created_at'] ?? '').toString();
          return bDate.compareTo(aDate);
        });

        if (!mounted) return;
        final changed = _tasksDeltaKey(_tasks) != _tasksDeltaKey(allTasks);
        if (changed || showLoader) {
          setState(() {
            _tasks = allTasks;
            _isLoadingTasks = false;
          });
        } else {
          _isLoadingTasks = false;
        }

        print(
            '[UserDashboard] Loaded ${allTasks.length} tasks for project $projectId');
      } else if (response.statusCode == 404) {
        // No tasks found - this is okay
        if (!mounted) return;
        if (_tasks.isNotEmpty || showLoader) {
          setState(() {
            _tasks = [];
            _isLoadingTasks = false;
          });
        } else {
          _isLoadingTasks = false;
        }
      } else {
        throw Exception('Unable to load tasks (code ${response.statusCode})');
      }
    } catch (e) {
      if (e is SessionInvalidatedException) return;
      if (!mounted) return;
      print('[UserDashboard] Error loading tasks: $e');
      if (silent && _tasks.isNotEmpty) {
        _isLoadingTasks = false;
        return;
      }
      setState(() {
        _isLoadingTasks = false;
        _tasksError = e.toString().replaceAll('Exception: ', '');
        _tasks = [];
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

  bool get _shouldShowInitialPageSkeleton => _shouldShowInitialSummarySkeleton;

  bool get _isAnySectionLoading => _isLoadingSummary || _isLoadingTasks;

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

  bool get _isClientUser =>
      (_currentRole ?? '').trim().toLowerCase() == 'client';

  bool get isReadyForTour => !_shouldShowInitialPageSkeleton;

  Future<void> revealTourTarget(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  bool get _restrictLegacyClientFeatures =>
      ClientGenerationService.instance.restrictsClientFeatures(_currentRole);

  void _onClientGenerationChanged() {
    if (mounted) setState(() {});
  }

  void _onQuickActionsChanged() {
    if (mounted) setState(() {});
  }

  bool _isLegacyFeatureAllowed(String? title) {
    return LegacyClientFeatures.isAllowed(title);
  }

  Widget _buildLegacyUpdatesSection() {
    final updates = dailyUpdateList
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList();
    final dateLabel = updatePostedOnDate.toString().trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToWidget(const DprScreen(title: 'Updates')),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: _dashboardSurfaceDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Latest Updates',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'View all',
                    style: TextStyle(
                      color: AppTheme.accentBlue,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (dateLabel.isNotEmpty && dateLabel != ' ') ...[
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: const TextStyle(
                    color: _mutedGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (updates.isEmpty)
                const Text(
                  'Stay tuned for updates about your home',
                  style: TextStyle(
                    color: _mutedGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                )
              else
                for (var i = 0; i < updates.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF2563EB),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          updates[i],
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
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
    );
  }

  BoxDecoration get _dashboardSurfaceDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: _softShadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      );

  void _openChat() {
    openChat();
  }

  void _openAllProjectTasks() {
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

  void _openProjectTaskDetails(Map<String, dynamic> task) {
    if (isIndentProofReviewTask(task) || isIndentProofDeeplinkTask(task)) {
      if (isIndentProofReviewTask(task)) {
        openIndentProofReviewFromTask(
          context,
          Map<String, dynamic>.from(task),
          onRefresh: _refreshTasksForMyTasks,
        );
      } else {
        openIndentProofFromTask(context, task).then((_) {
          _refreshTasksForMyTasks();
        });
      }
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyTasksScreen(
          tasks: _tasks,
          onRefresh: _refreshTasksForMyTasks,
          focusTaskId: task['id']?.toString(),
        ),
      ),
    );
  }

  String _compactTaskDate(Map<String, dynamic> task) {
    final iso = _firstTaskString(task, [
      'due_date',
      'updated_at',
      'created_at',
      'completed_at',
    ]);
    if (iso == null) return '';
    try {
      return DateFormat('d MMM').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  Map<String, dynamic> _compactTaskStatusMeta(Map<String, dynamic> task) {
    if (_isTaskOverdue(task)) {
      return {
        'label': 'Overdue',
        'color': const Color(0xFFDC2626),
        'bg': const Color(0xFFFEE2E2),
      };
    }

    final status = _normalizedTaskStatus(task);
    switch (status) {
      case 'in_progress':
      case 'ready':
      case 'waiting_approval':
        return {
          'label': status == 'waiting_approval' ? 'In Review' : 'In Progress',
          'color': status == 'waiting_approval'
              ? const Color(0xFF2563EB)
              : const Color(0xFFEA580C),
          'bg': status == 'waiting_approval'
              ? const Color(0xFFDBEAFE)
              : const Color(0xFFFFEDD5),
        };
      case 'scheduled':
        return {
          'label': 'Scheduled',
          'color': const Color(0xFF6366F1),
          'bg': const Color(0xFFEEF2FF),
        };
      default:
        final label = workflowStatusDisplayLabel(task);
        if (label.toLowerCase().contains('progress')) {
          return {
            'label': label,
            'color': const Color(0xFFEA580C),
            'bg': const Color(0xFFFFEDD5),
          };
        }
        return {
          'label': label == 'Pending' ? 'On Track' : label,
          'color': const Color(0xFF16A34A),
          'bg': const Color(0xFFDCFCE7),
        };
    }
  }

  Widget _buildChatAndLatestTasksRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildBahChatCard()),
          const SizedBox(width: 12),
          Expanded(child: _buildProjectLatestTasksCard()),
        ],
      ),
    );
  }

  Widget _buildBahChatCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openChat,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: _dashboardSurfaceDecoration,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'bAh Chat',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFDBEAFE),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 34,
                            color: AppTheme.getPrimaryColor(context),
                          ),
                          Positioned(
                            bottom: 18,
                            child: Icon(
                              Icons.home_work_outlined,
                              size: 16,
                              color: AppTheme.getPrimaryColor(context)
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Start a conversation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _mutedGrey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 0,
                top: 54,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE8ECF1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectLatestTasksCard() {
    final recent = _activeRecentTasks.take(_isClientUser ? 1 : 2).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _dashboardSurfaceDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Latest Tasks',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!_isClientUser)
                TextButton(
                  onPressed: _openAllProjectTasks,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingTasks && recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No pending tasks',
                style: TextStyle(
                  color: _mutedGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            for (var index = 0; index < recent.length; index++) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Color(0xFFEEF2F6)),
                ),
              _buildCompactProjectTaskRow(
                recent[index],
                showAction: !_isClientUser,
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildCompactProjectTaskRow(
    Map<String, dynamic> task, {
    bool showAction = true,
  }) {
    final status = _compactTaskStatusMeta(task);
    final description = _clientTaskTitle(task);
    final dateLabel = _compactTaskDate(task);

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: status['color'] as Color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status['bg'] as Color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status['label'] as String,
                  style: TextStyle(
                    color: status['color'] as Color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: _navy,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (dateLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dateLabel,
              style: const TextStyle(
                color: _mutedGrey,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );

    if (!showAction) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProjectTaskDetails(task),
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }

  bool get _shouldShowMyPendingTasksSection =>
      _activeRecentTasks.isNotEmpty;

  Widget _buildTasksSection() {
    final recent = _activeRecentTasks.take(2).toList();
    if (recent.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'My Pending Tasks',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TextButton(
              onPressed: _openAllTasks,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View all tasks',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            for (var index = 0; index < recent.length; index++)
              _buildModernDashboardTaskCard(recent[index], index),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openAllTasks,
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

  Widget _buildModernDashboardTaskCard(
      Map<String, dynamic> task, int index) {
    final assigneeParts = _taskAssigneeParts(task);
    final dateParts = _taskDateTimeParts(task);
    final assigneeText = assigneeParts.whereType<String>().join(' · ');
    final dateText = dateParts[0] == null
        ? null
        : dateParts[1] == null
            ? dateParts[0]
            : '${dateParts[0]} · ${dateParts[1]}';

    return ModernTaskCard(
      title: _dashboardPendingTaskTitle(task),
      projectName: _isClientUser ? null : task['project_name']?.toString(),
      assigneeName: _isClientUser
          ? null
          : (assigneeText.isEmpty ? null : assigneeText),
      dateLabel: dateText,
      status: isWorkflowDelayGated(task)
          ? 'pending'
          : normalizeTaskStatusValue(task),
      statusLabel: workflowStatusDisplayLabel(task),
      accentIndex: index,
      onTap: () => _openTaskDetails(task),
    );
  }

  String _dashboardPendingTaskTitle(Map<String, dynamic> task) {
    final title = _clientTaskTitle(task);
    if (!_isClientUser) return title;

    final projectName = task['project_name']?.toString().trim() ?? '';
    if (projectName.isEmpty) return title;

    final lowerTitle = title.toLowerCase();
    final lowerProject = projectName.toLowerCase();
    if (lowerTitle == lowerProject) return title;

    for (final separator in [' - ', ' – ', ': ']) {
      final prefix = '$lowerProject$separator';
      if (lowerTitle.startsWith(prefix)) {
        final stripped = title.substring(prefix.length).trim();
        if (stripped.isNotEmpty) return stripped;
      }
    }
    return title;
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
    if (isIndentProofReviewTask(task) || isIndentProofDeeplinkTask(task)) {
      if (isIndentProofReviewTask(task)) {
        openIndentProofReviewFromTask(
          context,
          Map<String, dynamic>.from(task),
          onRefresh: _refreshTasksForMyTasks,
        );
      } else {
        openIndentProofFromTask(context, task).then((_) {
          _refreshTasksForMyTasks();
        });
      }
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyTasksScreen(
          tasks: _tasks,
          onRefresh: _refreshTasksForMyTasks,
          focusTaskId: task['id']?.toString(),
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
    return workflowTaskDisplayTitle(
      task,
      emptyFallback: 'Review your project task',
    );
  }

  String _clientTaskDescription(Map<String, dynamic> task) {
    final description = _firstTaskString(task, [
      'description',
      'client_description',
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
        return isCreateIndentRedirectAction(_primaryWorkflowAction(task))
            ? Icons.request_quote_outlined
            : Icons.open_in_new_rounded;
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
      if (days == 0) return 'Due today';
      if (days == 1) return 'Due tomorrow';
      if (days > 1) return 'Due in $days days';
    }

    if (task['is_workflow_task'] == true) {
      return workflowStatusDisplayLabel(task);
    }

    switch (_normalizedTaskStatus(task)) {
      case 'waiting_approval':
        return 'Waiting for approval';
      case 'ready':
        return 'Ready for review';
      case 'completed':
      case 'done':
      case 'finished':
      case 'approved':
        return 'Approved';
      case 'in_progress':
        return 'In progress';
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
    if (customLabel != null) return toSentenceCaseLabel(customLabel);

    final actionType = action?['type']?.toString() ?? '';
    switch (actionType) {
      case 'upload':
        return 'Upload document';
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
        return 'Book appointment';
      case 'redirect_button':
        return isCreateIndentRedirectAction(_primaryWorkflowAction(task))
            ? 'Create indent'
            : 'Open';
      case 'view_prior_response':
      case 'yes_no_summary':
      case 'user_checklist_summary':
      case 'text_list_summary':
      case 'material_shift_summary':
        return 'View response';
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
        return isCreateIndentRedirectAction(_primaryWorkflowAction(task))
            ? Icons.request_quote_outlined
            : Icons.open_in_new_rounded;
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
    return TaskStatusChipSet(
      currentStatus: currentStatus,
      enabled: !isWorkflowTask,
      onStatusSelected: (newStatus) => updateTaskStatus(taskId, newStatus),
    );
  }

  List<Map<String, dynamic>> getMenuItems() {
    List<Map<String, dynamic>> menuItems = [];
    final rbac = RBACService();

    if (_currentRole != 'Billing') {
      // Client Portal — documents, design, site prep, inspection (clients only)
      if (_currentRole?.toLowerCase() == 'client') {
        menuItems.add({
          'title': 'Client Portal',
          'icon': Icons.dashboard_customize_outlined,
          'route': () => const ClientPortalScreen(),
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
      menuItems.add({
        'title': 'Project Timeline',
        'icon': Icons.timeline_rounded,
        'route': () => const ProjectTimelineScreen(),
      });
      // Clients: shared Client Information card only.
      if (_currentRole?.toLowerCase() == 'client') {
        menuItems.add({
          'title': 'Client Information',
          'icon': Icons.person_outline_rounded,
          'route': () => const SalesSopCardsScreen(
                initialCardKey: 'client_information',
                isClient: true,
              ),
        });
      }
      menuItems.add({
        'title': 'Slots',
        'icon': Icons.event_available_outlined,
        'route': () => const SlotsScreen(),
      });
    }

    // Project Details SOP cards — all PDF card APIs for non-clients.
    if (_currentRole != null &&
        _currentRole!.toLowerCase() != 'client' &&
        _currentRole != 'Billing') {
      menuItems.add({
        'title': 'Project Details',
        'icon': Icons.home_work_outlined,
        'route': () => const SalesSopCardsScreen(
              initialCardKey: 'client_information',
              isClient: false,
            ),
      });
    }

    // Indents - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.indent)) {
      menuItems.add({
        'title': 'Indents',
        'icon': Icons.request_quote,
        'route': () async {
          final prefs = await SharedPreferences.getInstance();
          return IndentsScreenLayout(
            initialProjectId: prefs.getString('project_id'),
            initialProjectName: prefs.getString('client_name'),
          );
        },
      });
      menuItems.add({
        'title': 'Approved POs',
        'icon': Icons.receipt_long_outlined,
        'route': () async {
          final prefs = await SharedPreferences.getInstance();
          final projectId = prefs.getString('project_id');
          final projectName = prefs.getString('client_name');
          return ApprovedPosScreenLayout(
            initialProjectId: projectId,
            initialProjectName: projectName,
          );
        },
      });
    }

    // Work orders — hidden for now.
    // if (_currentRole != null && _currentRole!.toLowerCase() != 'client') {
    //   menuItems.add({
    //     'title': 'Work orders',
    //     'icon': Icons.engineering_outlined,
    //     'route': () async {
    //       final prefs = await SharedPreferences.getInstance();
    //       final salesSopId = prefs.getString('sales_sop_id');
    //       final projectId = prefs.getString('project_id');
    //       final projectName = prefs.getString('client_name');
    //       return WorkOrdersScreenLayout(
    //         salesSopId: salesSopId,
    //         projectId: projectId,
    //         initialProjectName: projectName,
    //       );
    //     },
    //   });
    // }

    // Payments - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.payments)) {
      menuItems.add({
        'title': 'Payments',
        'icon': Icons.payment,
        'route': () => PaymentTaskWidget(),
      });
      if (_isClientUser) {
        menuItems.add({
          'title': 'NT Payments',
          'icon': Icons.receipt_long,
          'route': () => const PaymentTaskWidget(
                initialCategory: PaymentCategory.nonTender,
              ),
        });
      }
    }

    if (_isClientUser) {
      menuItems.add({
        'title': 'Updates',
        'icon': Icons.description_outlined,
        'route': () => const DprScreen(title: 'Updates'),
      });
    }

    // Client-only: upload UPI / bank / cheque screenshots for Finance review.
    if (_currentRole?.toLowerCase() == 'client') {
      menuItems.add({
        'title': 'Upload proof',
        'icon': Icons.cloud_upload_outlined,
        'route': () => const UploadPaymentProofScreen(),
      });
    }

    // Documents — staff only. Clients no longer get Docs V1 on home.
    if (!_isClientUser &&
        rbac.canViewSync(_currentRole, RBACService.documents)) {
      menuItems.add({
        'title': 'Documents',
        'icon': Icons.description,
        'route': () => Documents(),
      });
      menuItems.add({
        'title': 'Documents V1',
        'icon': Icons.folder_copy_outlined,
        'route': () => const DocumentsV1HomeScreen(),
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

    // Gallery - check RBAC. Clients get Timeline Gallery only.
    if (rbac.canViewSync(_currentRole, RBACService.gallery)) {
      if (!_isClientUser) {
        menuItems.add({
          'title': 'Gallery',
          'icon': Icons.photo_library,
          'route': () => Gallery(),
        });
      }
      menuItems.add({
        'title': 'Timeline Gallery',
        'icon': Icons.auto_awesome_motion,
        'route': () => TimelineGallery(),
      });
    }

    menuItems.add({
      'title': 'Virtual Tour',
      'icon': Icons.view_in_ar_rounded,
      'route': () => const VirtualTourScreen(),
    });

    // ChatBox - check RBAC
    if (rbac.canViewSync(_currentRole, RBACService.tasksAndNotes)) {
      menuItems.add({
        'title': 'ChatBox',
        'icon': Icons.note_add,
        'route': () => NotesAndComments(),
      });
    }
    // Chat V1 — Client always allowed (General channel + DOC approve).
    if (_currentRole == 'Client' ||
        rbac.canViewSync(_currentRole, RBACService.tasksAndNotes)) {
      menuItems.add({
        'title': 'Chat V1',
        'icon': Icons.forum_outlined,
        'route': () => ChatV1App.openQuick(),
      });
    }

    // Project Status — staff only (hidden for clients)
    if (!_isClientUser &&
        rbac.canViewSync(_currentRole, RBACService.tasksAndNotes)) {
      menuItems.add({
        'title': 'Project Status',
        'icon': Icons.flag_outlined,
        'route': () => ProjectFocusScreen.openQuick(),
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

    // Site Visit Reports — staff only (hidden for clients)
    if (!_isClientUser) {
      menuItems.add({
        'title': 'Site Visit Reports',
        'icon': Icons.assignment,
        'route': () async {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          final projectId = prefs.getString('project_id');
          return SiteVisitReportsScreen(
            fixedProjectId: projectId,
            projectFixed: true,
          );
        },
      });
    }

    if (MobileLiveTestAccess.canEnable(_currentRole)) {
      menuItems.add({
        'title': MobileLiveTestAccess.menuTitle,
        'icon': Icons.phonelink_setup_outlined,
        'route': () => const MobileLiveTestScreen(),
      });
    }

    return menuItems;
  }

  /// Pinned quick actions for clients on the project dashboard.
  static const List<String> _clientPinnedQuickActionTitles = [
    'Client Portal',
    'Slots',
    'Project Timeline',
    'Timeline Gallery',
    'Payments',
    'Upload proof',
  ];

  /// Working tiles from commit 440e62a, then newer tiles marked coming soon.
  static const List<String> _legacyClientPinnedQuickActionTitles = [
    'Payments',
    'NT Payments',
    'Gallery',
    'Updates',
    'Scheduler',
    'ChatBox',
    'Checklist',
    'Request Drawings',
    'Client Portal',
    'My tasks',
    'Project Timeline',
    'Client Information',
    'Upload payment proofs',
    'Timeline Gallery',
    'Virtual Tour',
    'Chat V1',
    'Project Status',
  ];

  /// Pinned quick actions for staff / other roles on the project dashboard.
  static const List<String> _staffPinnedQuickActionTitles = [
    'My tasks',
    'Project Timeline',
    'Project Status',
    'Timeline Gallery',
    'Indents',
    'Approved POs',
    'Work orders',
    'Documents V1',
    'Payments',
    'Slots',
  ];

  List<Map<String, dynamic>> _hardcodedPinnedQuickActions(
      List<Map<String, dynamic>> items) {
    final byTitle = <String, Map<String, dynamic>>{};
    for (final item in items) {
      byTitle[item['title'].toString()] = item;
    }

    final titles = _isClientUser
        ? (_restrictLegacyClientFeatures
            ? _legacyClientPinnedQuickActionTitles
            : _clientPinnedQuickActionTitles)
        : _staffPinnedQuickActionTitles;

    final pinned = <Map<String, dynamic>>[];
    for (final title in titles) {
      final item = byTitle[title];
      if (item != null) pinned.add(item);
    }
    return pinned;
  }

  List<Map<String, dynamic>> _pinnedQuickActions(
      List<Map<String, dynamic>> items) {
    return resolveMobileQuickActions(
      surface: MobileQuickActionSurface.projectHomeNew,
      catalog: items,
      fallback: _hardcodedPinnedQuickActions(items),
      snapshot: MobileQuickActionsService.instance
          .snapshot(MobileQuickActionSurface.projectHomeNew),
    );
  }

  Widget build(BuildContext context) {
    final menuItems = _orderedMenuItems(getMenuItems());
    final pinnedActions = _pinnedQuickActions(menuItems);

    final dashboardContent = Container(
      color: Colors.white,
      child: RefreshIndicator(
        color: _navy,
        onRefresh: () => reloadData(force: true),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: <Widget>[
            if (blocked == true) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Project blocked',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reason : ${bolckReason.toString()}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            KeyedSubtree(
              key: widget.tourProgressKey,
              child: _buildHeroBanner(),
            ),
            if (_restrictLegacyClientFeatures) ...[
              const SizedBox(height: 16),
              _buildLegacyUpdatesSection(),
            ],
            if (!_restrictLegacyClientFeatures &&
                _shouldShowMyPendingTasksSection) ...[
              const SizedBox(height: 16),
              _buildTasksSection(),
            ],
            if (!_restrictLegacyClientFeatures) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: widget.tourChatKey,
                child: _buildChatAndLatestTasksRow(),
              ),
            ],
            const SizedBox(height: 22),
            KeyedSubtree(
              key: widget.tourActionsKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _restrictLegacyClientFeatures ? 3 : 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
                childAspectRatio: _restrictLegacyClientFeatures ? 0.72 : 0.78,
              ),
              itemCount: pinnedActions.length,
              itemBuilder: (BuildContext context, int index) {
                final item = pinnedActions[index];
                final title = item['title'].toString();
                final colors = _quickActionColors(title);
                final comingSoon = _restrictLegacyClientFeatures &&
                    !_isLegacyFeatureAllowed(title);
                return InkWell(
                  onTap: () => _handleMenuTap(item),
                  borderRadius: BorderRadius.circular(16),
                  child: Opacity(
                    opacity: comingSoon ? 0.62 : 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
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
                            if (!comingSoon &&
                                _quickActionBadgeCount(title) != null)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: Colors.white, width: 1.2),
                                  ),
                                  child: Text(
                                    _quickActionBadgeCount(title).toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            if (comingSoon)
                              Positioned(
                                right: -8,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1B254B),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Soon',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _restrictLegacyClientFeatures && title == 'ChatBox'
                              ? 'Notes & Comments'
                              : _quickActionLabel(title),
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
                        if (comingSoon) ...[
                          const SizedBox(height: 2),
                          const Text(
                            'Coming soon',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8A94A6),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
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

    if (_shouldShowInitialPageSkeleton) {
      return _buildLoadingState();
    }

    return dashboardContent;
  }

  Widget _buildHeroBanner() {
    final progress = ((double.tryParse(completed ?? '') ?? 0.0) / 100)
        .clamp(0.0, 1.0)
        .toDouble();
    final percentLabel = completed == null || completed!.isEmpty
        ? '--'
        : '${completed!.replaceAll('%', '')}%';

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
            Positioned(
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          height: 76,
                          child: CircularPercentIndicator(
                            radius: 34,
                            lineWidth: 7,
                            percent: progress,
                            animation: true,
                            animationDuration: 1000,
                            circularStrokeCap: CircularStrokeCap.round,
                            progressColor: const Color(0xFF60A5FA),
                            backgroundColor: Colors.white.withValues(alpha: 0.18),
                            center: Text(
                              percentLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Project Completion',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: location.isEmpty
                                    ? null
                                    : () async {
                                        await launchUrl(
                                          Uri.parse(location),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      },
                                borderRadius: BorderRadius.circular(6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'View on Map',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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
          keywords: title == 'Upload proof'
              ? [
                  title,
                  'proof',
                  'payment proof',
                  'screenshot',
                  'upi',
                  'receipt',
                  'cheque',
                ]
              : title == 'Work orders'
                  ? [title, 'WO', 'work order', 'contractor']
                  : title == 'Timeline Gallery'
                      ? [title, 'gallery', 'photos', 'images']
                      : title == 'Slots'
                          ? [
                              title,
                              'site inspection',
                              'times',
                              'schedule',
                              'visit',
                            ]
                          : [title],
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
    final title = item['title']?.toString() ?? '';
    if (_restrictLegacyClientFeatures && !_isLegacyFeatureAllowed(title)) {
      await showFeatureComingSoon(context, featureName: title);
      return;
    }
    if (_openingMenu) return;
    _openingMenu = true;
    try {
      final routeResult = item['route']();
      final widget = routeResult is Future ? await routeResult : routeResult;
      await _navigateToWidget(widget);
    } finally {
      _openingMenu = false;
    }
  }

  Future<void> openChat() async {
    if (_restrictLegacyClientFeatures) {
      await showFeatureComingSoon(context, featureName: 'Chat');
      return;
    }
    await _navigateToWidget(
      ChatV1App.openQuick(tasksHint: _tasks),
    );
  }

  Future<void> openDocuments() async {
    await _navigateToWidget(
      _isClientUser
          ? const DocumentsV1HomeScreen(clientMode: true)
          : Documents(),
    );
  }

  Map<String, Color> _quickActionColors(String title) {
    switch (title.toLowerCase()) {
      case 'gallery':
      case 'timeline gallery':
        return {
          'bg': const Color(0xFFF3E8FF),
          'fg': const Color(0xFF7C3AED),
        };
      case 'project timeline':
      case 'timeline':
        return {
          'bg': const Color(0xFFDCFCE7),
          'fg': const Color(0xFF16A34A),
        };
      case 'project status':
      case 'status':
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
      case 'payments':
      case 'nt payments':
      case 'non tender payments':
        return {
          'bg': const Color(0xFFFFE4E6),
          'fg': const Color(0xFFE11D48),
        };
      case 'upload proof':
        return {
          'bg': const Color(0xFFE0F2FE),
          'fg': const Color(0xFF0369A1),
        };
      case 'scheduler':
      case 'schedule':
        return {
          'bg': const Color(0xFFDBEAFE),
          'fg': const Color(0xFF2563EB),
        };
      case 'documents':
      case 'updates':
        return {
          'bg': const Color(0xFFCCFBF1),
          'fg': const Color(0xFF0D9488),
        };
      case 'chatbox':
      case 'chat':
      case 'chat v1':
        return {
          'bg': const Color(0xFFE0E7FF),
          'fg': const Color(0xFF4F46E5),
        };
      case 'checklist':
        return {
          'bg': const Color(0xFFF5E6D3),
          'fg': const Color(0xFFB45309),
        };
      case 'indents':
        return {
          'bg': const Color(0xFFFFEDD5),
          'fg': const Color(0xFFEA580C),
        };
      case 'approved pos':
        return {
          'bg': const Color(0xFFE0E7FF),
          'fg': const Color(0xFF4338CA),
        };
      case 'work orders':
        return {
          'bg': const Color(0xFFEDE9FE),
          'fg': const Color(0xFF6D28D9),
        };
      case 'documents v1':
        return {
          'bg': const Color(0xFFCCFBF1),
          'fg': const Color(0xFF0D9488),
        };
      case 'site visit reports':
      case 'upcoming visits':
        return {
          'bg': const Color(0xFFE0F2FE),
          'fg': const Color(0xFF0284C7),
        };
      case 'virtual tour':
        return {
          'bg': const Color(0xFFE0E7FF),
          'fg': const Color(0xFF4338CA),
        };
      case 'client portal':
        return {
          'bg': const Color(0xFFE0E7FF),
          'fg': const Color(0xFF1B254B),
        };
      case 'slots':
        return {
          'bg': const Color(0xFFEEF2FF),
          'fg': const Color(0xFF4F46E5),
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
        return 'My tasks';
      case 'Project Timeline':
        return 'Timeline';
      case 'Indents':
        return 'Indents';
      case 'Approved POs':
        return 'POs';
      case 'Work orders':
        return 'Work orders';
      case 'Documents V1':
        return 'Docs V1';
      case 'Scheduler':
        return 'Schedule';
      case 'ChatBox':
        return 'Chat';
      case 'Chat V1':
        return 'Chat V1';
      case 'Project Status':
        return 'Status';
      case 'Site Visit Reports':
        return 'Upcoming visits';
      case 'Timeline Gallery':
        return 'Timeline Gallery';
      case 'Virtual Tour':
        return '3D Tour';
      case 'Client Portal':
        return 'For me';
      case 'NT Payments':
        return 'NT Payments';
      case 'Updates':
        return 'Updates';
      default:
        return title;
    }
  }

  int? _quickActionBadgeCount(String title) {
    if (title == 'Site Visit Reports') return 6;
    return null;
  }

  IconData _quickActionIcon(String title, IconData fallback) {
    switch (title) {
      case 'Client Portal':
        return Icons.dashboard_customize_outlined;
      case 'Site Visit Reports':
        return Icons.event_available_outlined;
      case 'Gallery':
        return Icons.photo_library_rounded;
      case 'Project Timeline':
        return Icons.view_timeline_rounded;
      case 'My tasks':
        return Icons.assignment_outlined;
      case 'Timeline Gallery':
        return Icons.auto_awesome_motion;
      case 'Indents':
        return Icons.request_quote_outlined;
      case 'Approved POs':
        return Icons.receipt_long_outlined;
      case 'Work orders':
        return Icons.engineering_outlined;
      case 'Documents V1':
        return Icons.folder_copy_outlined;
      case 'Payments':
        return Icons.account_balance_wallet_outlined;
      case 'NT Payments':
      case 'Non Tender Payments':
        return Icons.receipt_long_outlined;
      case 'Updates':
        return Icons.campaign_outlined;
      case 'Upload payment proofs':
      case 'Upload proof':
        return Icons.cloud_upload_outlined;
      case 'Scheduler':
        return Icons.calendar_month_rounded;
      case 'Documents':
        return Icons.description_outlined;
      case 'ChatBox':
        return Icons.chat_bubble_outline_rounded;
      case 'Chat V1':
        return Icons.forum_outlined;
      case 'Project Status':
        return Icons.flag_outlined;
      case 'Checklist':
        return Icons.checklist_rtl_rounded;
      case 'Virtual Tour':
        return Icons.view_in_ar_rounded;
      case 'Slots':
        return Icons.event_available_outlined;
      default:
        return fallback;
    }
  }

  List<Map<String, dynamic>> _orderedMenuItems(
      List<Map<String, dynamic>> items) {
    const clientPreferred = [
      'Client Portal',
      'Slots',
      'Project Timeline',
      'Timeline Gallery',
      'Payments',
      'Upload proof',
      'Virtual Tour',
      'My tasks',
      'Scheduler',
      'ChatBox',
      'Chat V1',
      'Checklist',
    ];
    const staffPreferred = [
      'My tasks',
      'Project Timeline',
      'Timeline Gallery',
      'Indents',
      'Approved POs',
      'Work orders',
      'Documents V1',
      'Payments',
      'Project Details',
      'Slots',
      'Documents',
      'Scheduler',
      'Gallery',
      'Virtual Tour',
      'ChatBox',
      'Chat V1',
      'Project Status',
      'Checklist',
      'Request Drawings',
      'Inspection Requests',
      'Site Visit Reports',
    ];
    final preferred = _isClientUser
        ? (_restrictLegacyClientFeatures
            ? _legacyClientPinnedQuickActionTitles
            : clientPreferred)
        : staffPreferred;
    final byTitle = <String, Map<String, dynamic>>{};
    for (final item in items) {
      byTitle[item['title'].toString()] = item;
    }
    final ordered = <Map<String, dynamic>>[];
    for (final title in preferred) {
      final item = byTitle.remove(title);
      if (item != null) ordered.add(item);
    }
    ordered.addAll(byTitle.values);
    return ordered;
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
      pageBuilder: (context, animation, secondaryAnimation) =>
          DashboardChrome.wrap(DashboardChromeStyle.user, widget),
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

  Widget _buildLoadingState() {
    final baseColor = const Color(0xFFE8ECF1);
    final highlightColor = const Color(0xFFF8FAFC);

    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildSkeletonCard(baseColor, highlightColor,
              height: 148, margin: const EdgeInsets.only(bottom: 16)),
          _buildSkeletonCard(baseColor, highlightColor,
              height: 190, margin: const EdgeInsets.only(bottom: 16)),
          _buildSkeletonCard(baseColor, highlightColor,
              height: 170, margin: const EdgeInsets.only(bottom: 20)),
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
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: 8,
      itemBuilder: (_, __) {
        return Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 10,
                width: 48,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
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

// Logout for clients is handled by `NavMenuWidget` (drawer) to match other roles.
