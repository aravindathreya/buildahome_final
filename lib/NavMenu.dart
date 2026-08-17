import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'AddDailyUpdate.dart';
import 'Dpr.dart';
import 'Drawings.dart';
import 'Gallery.dart';
import 'InspectionRequest.dart';
import 'MyTasksScreen.dart';
import 'NotesAndComments.dart';
import 'chat_v1/chat_v1_app.dart';
import 'chat_v1/chat_v1_socket.dart';
import 'ProjectStatusScreen.dart';
import 'Payments.dart';
import 'ProjectTimelineScreen.dart';
import 'RequestDrawing.dart';
import 'Scheduler.dart';
import 'SiteVisitReports.dart';
import 'Skin2/loginPage.dart';
import 'TestReportsScreen.dart';
import 'UserHome.dart';
import 'VirtualTour.dart';
import 'ClientPortalScreen.dart';
import 'app_theme.dart';
import 'checklist_categories.dart';
import 'indents_screen.dart';
import 'notifcations.dart';
import 'project_picker.dart';
import 'services/client_portal_service.dart';
import 'services/data_provider.dart';
import 'services/notification_service.dart';
import 'services/profile_picture_service.dart';
import 'services/rbac_service.dart';
import 'stock_report.dart';
import 'widgets/profile_picture_dialog.dart';

typedef NavRouteBuilder = FutureOr<Widget?> Function();

PageRouteBuilder<T> _navFadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
  );
}

/// Project-scoped screens from the nav menu must pick a project first
/// (non-clients). Clients already have a fixed project context.
Future<void> Function(BuildContext) _openAfterProjectPick(
  NavRouteBuilder routeBuilder,
) {
  return (context) async {
    final picked = await ProjectPickerScreen.pick(context);
    if (!picked || !context.mounted) return;
    final page = await routeBuilder();
    if (!context.mounted || page == null) return;
    await Navigator.push(context, _navFadeRoute(page));
  };
}

Future<List<dynamic>> _fetchTasksForCurrentUser() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('userId') ?? prefs.getString('user_id');
  final apiToken = prefs.getString('api_token');
  final role = prefs.getString('role');
  final projectId = prefs.getString('project_id');
  if (userId == null || apiToken == null) return <dynamic>[];

  final queryParams = <String, String>{
    'user_id': userId,
    'assigned_to': userId,
  };
  if (role == 'Client' && projectId != null && projectId.isNotEmpty) {
    queryParams['project_id'] = projectId;
  }

  final uri = Uri.parse('https://office.buildahome.in/API/get_tasks').replace(
    queryParameters: queryParams,
  );
  final response = await http.get(uri).timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) return <dynamic>[];

  final decoded = jsonDecode(response.body);
  List<dynamic> fetched = [];
  if (decoded is Map && decoded['tasks'] is List) {
    fetched = decoded['tasks'];
  } else if (decoded is List) {
    fetched = decoded;
  }

  final taskMap = <int, dynamic>{};
  for (final task in fetched) {
    if (task is Map && task['id'] != null) {
      final id = int.tryParse(task['id'].toString()) ?? 0;
      if (id != 0) taskMap[id] = task;
    }
  }

  return filterTasksForProjectAndAssignee(
    taskMap.values.toList(),
    userId: userId,
    projectId: role == 'Client' ? projectId : null,
  );
}

class _NavSection {
  final String title;
  final List<_NavEntry> entries;

  const _NavSection(this.title, this.entries);
}

class _NavEntry {
  final String title;
  final IconData icon;
  final NavRouteBuilder? route;
  final Future<void> Function(BuildContext context)? action;
  final bool isHome;
  final bool isLogout;

  const _NavEntry({
    required this.title,
    required this.icon,
    this.route,
    this.action,
    this.isHome = false,
    this.isLogout = false,
  });
}

class NavMenuItem extends StatelessWidget {
  final _NavEntry entry;

  const NavMenuItem(this.entry, {Key? key}) : super(key: key);

  Future<void> _logout() async {
    ChatV1Socket.instance.disconnect();
    DataProvider().clearData();
    await ClientPortalService().clearSession();
    await NotificationService.instance.clear();
    ProfilePictureService.promptShownThisSession = false;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.clear();
    } catch (e) {
      print('Error clearing SharedPreferences: $e');
    }
  }

  Future<void> _handleTap(BuildContext context) async {
    if (entry.isLogout) {
      await _logout();
      if (!context.mounted) return;
      Navigator.pop(context);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LoginScreenNew()),
        (route) => false,
      );
      return;
    }

    // Capture the host navigator before closing the drawer — the menu
    // item's context can be disposed once the drawer route pops.
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;

    if (entry.action != null) {
      navigator.pop();
      if (!hostContext.mounted) return;
      await entry.action!(hostContext);
      return;
    }

    if (entry.route == null) return;

    final built = await entry.route!();
    if (!hostContext.mounted || built == null) return;

    navigator.pop();
    if (!hostContext.mounted) return;

    if (entry.isHome) {
      Navigator.pushAndRemoveUntil(
        hostContext,
        _navFadeRoute(built),
        (route) => false,
      );
    } else {
      Navigator.push(hostContext, _navFadeRoute(built));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogout = entry.isLogout;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isLogout
                ? const Color(0xFFFFF1F2)
                : AppTheme.getBackgroundPrimaryLight(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLogout
                  ? const Color(0xFFFECACA)
                  : AppTheme.getBorderColor(context),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isLogout
                      ? const Color(0xFFFEE2E2)
                      : AppTheme.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  entry.icon,
                  color: isLogout ? const Color(0xFFDC2626) : AppTheme.navy,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isLogout
                        ? const Color(0xFFB91C1C)
                        : AppTheme.getTextPrimary(context),
                  ),
                ),
              ),
              if (entry.title == 'Notifications')
                ValueListenableBuilder<int>(
                  valueListenable:
                      NotificationService.instance.unreadCountNotifier,
                  builder: (context, unreadCount, _) {
                    if (unreadCount <= 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isLogout
                    ? const Color(0xFFDC2626)
                    : AppTheme.getTextSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavMenuWidget extends StatefulWidget {
  @override
  NavMenuWidgetState createState() => NavMenuWidgetState();
}

class NavMenuWidgetState extends State<NavMenuWidget> {
  String? username;
  String? role;
  String? clientName;
  String? email;
  String? profilePicture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final picture = await ProfilePictureService.getStoredPath();
    // Hydrate cached unread count for the nav badge; sync in background.
    final notifications = NotificationService.instance;
    await notifications.ensureHydrated();
    unawaited(notifications.sync());
    if (!mounted) return;
    setState(() {
      username = prefs.getString('username');
      role = prefs.getString('role');
      email = username;
      profilePicture = picture;

      final storedClient = prefs.getString('client_name');
      if (storedClient != null && storedClient.trim().isNotEmpty) {
        clientName = storedClient;
      } else {
        final raw = (username ?? '').trim();
        clientName = raw.contains('-') ? raw.split('-').first.trim() : raw;
      }
    });
  }

  Future<void> _changeProfilePicture() async {
    final path = await showProfilePictureDialog(
      context,
      currentPicturePath: profilePicture,
    );
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      // Keep header avatars in sync immediately.
      ProfilePictureService.picturePathNotifier.value = path;
      setState(() => profilePicture = path);
    } else {
      // Refresh in case it was saved but dialog returned null.
      final stored = await ProfilePictureService.getStoredPath();
      if (!mounted) return;
      if (stored != profilePicture) {
        setState(() => profilePicture = stored);
      }
    }
  }

  Future<String?> _projectId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('project_id');
  }

  List<_NavSection> _sectionsForRole(String? currentRole) {
    final rbac = RBACService();
    final isClient = currentRole == 'Client';
    final sections = <_NavSection>[];

    // Home / workspace
    final homeEntries = <_NavEntry>[
      _NavEntry(
        title: 'Home',
        icon: Icons.home_rounded,
        isHome: true,
        action: (context) async {
          if (isClient) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => Home()),
              (route) => false,
            );
          } else {
            // Return to the admin root without importing AdminDashboard
            // (avoids a circular import with the dashboard shell).
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
      ),
      _NavEntry(
        title: 'My Tasks',
        icon: Icons.pending_actions_rounded,
        route: () async {
          final tasks = await _fetchTasksForCurrentUser();
          return MyTasksScreen(
            tasks: tasks,
            onRefresh: _fetchTasksForCurrentUser,
          );
        },
      ),
      _NavEntry(
        title: 'Notifications',
        icon: Icons.notifications_rounded,
        route: () => const Notifications(),
      ),
    ];

    if (!isClient) {
      homeEntries.insert(
        1,
        _NavEntry(
          title: 'Projects',
          icon: Icons.folder_special_rounded,
          action: (context) => ProjectPickerScreen.show(context),
        ),
      );
    } else {
      homeEntries.insert(
        1,
        _NavEntry(
          title: 'Client Portal',
          icon: Icons.dashboard_customize_outlined,
          route: () => const ClientPortalScreen(),
        ),
      );
      homeEntries.insert(
        2,
        _NavEntry(
          title: 'Project Timeline',
          icon: Icons.timeline_rounded,
          route: () => const ProjectTimelineScreen(),
        ),
      );
    }

    sections.add(_NavSection('Workspace', homeEntries));

    // Project screens
    final projectEntries = <_NavEntry>[];

    if (isClient || rbac.canViewSync(currentRole, RBACService.dailyUpdate)) {
      if (!isClient &&
          rbac.canViewSync(currentRole, RBACService.dailyUpdate)) {
        projectEntries.add(_NavEntry(
          title: 'Daily Update',
          icon: Icons.update_rounded,
          route: () => AddDailyUpdate(returnToAdminDashboard: true),
        ));
      }
      if (isClient) {
        projectEntries.add(_NavEntry(
          title: 'Updates',
          icon: Icons.description_rounded,
          route: () => const DprScreen(title: 'Updates'),
        ));
      }
    }

    if (rbac.canViewSync(currentRole, RBACService.scheduler)) {
      projectEntries.add(_NavEntry(
        title: 'Scheduler',
        icon: Icons.calendar_today_rounded,
        // Project-scoped: pick a project from nav before opening.
        route: isClient ? () => const TaskWidget() : null,
        action: isClient
            ? null
            : _openAfterProjectPick(() => const TaskWidget()),
      ));
    }

    if (rbac.canViewSync(currentRole, RBACService.documents)) {
      projectEntries.add(_NavEntry(
        title: 'Documents',
        icon: Icons.description_rounded,
        route: isClient ? () => Documents() : null,
        action: isClient ? null : _openAfterProjectPick(() => Documents()),
      ));
    }

    if (rbac.canViewSync(currentRole, RBACService.gallery)) {
      projectEntries.add(_NavEntry(
        title: 'Gallery',
        icon: Icons.photo_library_rounded,
        route: isClient ? () => Gallery() : null,
        action: isClient ? null : _openAfterProjectPick(() => Gallery()),
      ));
      projectEntries.add(_NavEntry(
        title: 'Timeline Gallery',
        icon: Icons.auto_awesome_motion_rounded,
        route: isClient ? () => TimelineGallery() : null,
        action:
            isClient ? null : _openAfterProjectPick(() => TimelineGallery()),
      ));
    }

    // Virtual Tour is available to clients (and staff after project pick)
    projectEntries.add(_NavEntry(
      title: 'Virtual Tour',
      icon: Icons.view_in_ar_rounded,
      route: isClient ? () => const VirtualTourScreen() : null,
      action: isClient
          ? null
          : _openAfterProjectPick(() => const VirtualTourScreen()),
    ));

    if (rbac.canViewSync(currentRole, RBACService.payments)) {
      projectEntries.add(_NavEntry(
        title: 'Payments',
        icon: Icons.payment_rounded,
        route: isClient ? () => PaymentTaskWidget() : null,
        action:
            isClient ? null : _openAfterProjectPick(() => PaymentTaskWidget()),
      ));
    }

    if (projectEntries.isNotEmpty) {
      sections.add(_NavSection('Project', projectEntries));
    }

    // Operations
    final opsEntries = <_NavEntry>[];

    if (rbac.canViewSync(currentRole, RBACService.indent)) {
      opsEntries.add(_NavEntry(
        title: 'Indents',
        icon: Icons.request_quote_rounded,
        route: () => IndentsScreenLayout(),
      ));
    }

    if (!isClient) {
      opsEntries.add(_NavEntry(
        title: 'Stock Report',
        icon: Icons.inventory_2_rounded,
        route: () => StockReportLayout(),
      ));
      opsEntries.add(_NavEntry(
        title: 'Site Visits',
        icon: Icons.location_on_rounded,
        route: () => SiteVisitReportsScreen(),
      ));
    } else {
      opsEntries.add(_NavEntry(
        title: 'Site Visit Reports',
        icon: Icons.assignment_rounded,
        route: () async {
          final projectId = await _projectId();
          return SiteVisitReportsScreen(
            fixedProjectId: projectId,
            projectFixed: true,
          );
        },
      ));
    }

    if (rbac.canViewSync(currentRole, RBACService.checklist)) {
      opsEntries.add(_NavEntry(
        title: 'Checklist',
        icon: Icons.checklist_rounded,
        route: isClient ? () => ChecklistCategoriesLayout() : null,
        action: isClient
            ? null
            : _openAfterProjectPick(() => ChecklistCategoriesLayout()),
      ));
    }

    if (currentRole == 'Admin' ||
        currentRole == 'QC' ||
        currentRole == 'Quality Engineer') {
      opsEntries.add(_NavEntry(
        title: 'Test Reports',
        icon: Icons.science_rounded,
        route: () => TestReportsScreen(),
      ));
    }

    if (rbac.canViewSync(currentRole, RBACService.requestDrawing)) {
      opsEntries.add(_NavEntry(
        title: 'Request Drawings',
        icon: Icons.architecture_rounded,
        route: isClient ? () => RequestDrawingLayout() : null,
        action: isClient
            ? null
            : _openAfterProjectPick(() => RequestDrawingLayout()),
      ));
    }

    if (!isClient) {
      opsEntries.add(_NavEntry(
        title: 'Inspection Requests',
        icon: Icons.fact_check_outlined,
        action: _openAfterProjectPick(() async {
          final projectId = await _projectId();
          return InspectionRequestLayout(
            fixedProjectId: projectId,
            projectFixed: projectId != null,
          );
        }),
      ));
    }

    if (opsEntries.isNotEmpty) {
      sections.add(_NavSection('Operations', opsEntries));
    }

    // Collaboration — Chat V1 must allow Client (General + DOC approve).
    final collabEntries = <_NavEntry>[];
    final canChatBox = rbac.canViewSync(currentRole, RBACService.tasksAndNotes) &&
        currentRole != 'Site Engineer';
    final canChatV1 = currentRole == 'Client' ||
        (rbac.canViewSync(currentRole, RBACService.tasksAndNotes) &&
            currentRole != 'Site Engineer');
    if (canChatBox) {
      collabEntries.add(_NavEntry(
        title: 'ChatBox',
        icon: Icons.chat_rounded,
        route: () => NotesAndComments(),
      ));
    }
    if (canChatV1) {
      collabEntries.add(_NavEntry(
        title: 'Chat V1',
        icon: Icons.forum_rounded,
        route: () => ChatV1App.openQuick(),
      ));
      collabEntries.add(_NavEntry(
        title: 'Project Status',
        icon: Icons.flag_rounded,
        route: () => ProjectStatusScreen.openQuick(),
      ));
    }
    if (collabEntries.isNotEmpty) {
      sections.add(_NavSection('Collaboration', collabEntries));
    }

    sections.add(
      _NavSection(
        'Account',
        [
          const _NavEntry(
            title: 'Log out',
            icon: Icons.logout_rounded,
            isLogout: true,
          ),
        ],
      ),
    );

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        ((role == 'Client' ? clientName : username) ?? 'User').toString();
    final subtitle =
        role == 'Client' ? (email ?? '').toString() : (role ?? '').toString();
    final sections = _sectionsForRole(role);

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.navy, AppTheme.navySoft],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  ProfileAvatar(
                    displayName: displayName,
                    picturePath: profilePicture,
                    size: 52,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    borderColor: Colors.white.withValues(alpha: 0.2),
                    showEditBadge: true,
                    onTap: _changeProfilePicture,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _changeProfilePicture,
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle.isEmpty ? 'buildAhome' : subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFC7D0E0),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profilePicture == null || profilePicture!.isEmpty
                                ? 'Tap to add photo'
                                : 'Tap to change photo',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                dragStartBehavior: DragStartBehavior.start,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                      child: Text(
                        section.title.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.mutedGrey,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    for (final entry in section.entries) NavMenuItem(entry),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
