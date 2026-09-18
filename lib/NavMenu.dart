import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'AddDailyUpdate.dart';
import 'Dpr.dart';
import 'Drawings.dart';
import 'Gallery.dart';
import 'documents_v1/documents_v1_home_screen.dart';
import 'InspectionRequest.dart';
import 'MyTasksScreen.dart';
import 'chat_v1/chat_v1_app.dart';
import 'ProjectFocusScreen.dart';
import 'Payments.dart';
import 'ProjectTimelineScreen.dart';
import 'Scheduler.dart';
import 'SiteVisitReports.dart';
import 'SlotsScreen.dart';
import 'TestReportsScreen.dart';
import 'mobile_live_test_screen.dart';
import 'services/mobile_live_test_access.dart';
import 'UserHome.dart';
import 'VirtualTour.dart';
import 'ClientPortalScreen.dart';
import 'UploadPaymentProofScreen.dart';
import 'app_theme.dart';
import 'app_navigator.dart';
import 'indents_screen.dart';
import 'notifcations.dart';
import 'project_picker.dart';
import 'services/app_logout.dart';
import 'services/client_generation_service.dart';
import 'services/data_provider.dart';
import 'services/legacy_client_features.dart';
import 'services/mobile_more_menu.dart';
import 'services/mobile_more_menu_service.dart';
import 'services/notification_service.dart';
import 'services/profile_picture_service.dart';
import 'services/rbac_service.dart';
import 'stock_report.dart';
import 'AttendanceScreen.dart';
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

class _NavSection {
  final String title;
  final List<_NavEntry> entries;

  const _NavSection(this.title, this.entries);
}

class _NavEntry {
  final String actionKey;
  final String title;
  final IconData icon;
  final NavRouteBuilder? route;
  final Future<void> Function(BuildContext context)? action;
  final bool isHome;
  final bool isLogout;
  final bool comingSoon;

  const _NavEntry({
    required this.actionKey,
    required this.title,
    required this.icon,
    this.route,
    this.action,
    this.isHome = false,
    this.isLogout = false,
    this.comingSoon = false,
  });
}

/// Apply backend visibility/order while keeping each row in its original
/// section so the drawer chrome (headers, cards, profile) does not change.
List<_NavSection> _applyBackendMoreMenu(
  List<_NavSection> catalog,
  MobileMoreMenuSurface surface,
  MobileMoreMenuSnapshot? snapshot,
) {
  if (snapshot == null || !snapshot.configured) return catalog;

  final catalogKeys = <String>{};
  final fallbackKeys = <String>[];
  final byKey = <String, _NavEntry>{};
  final sectionByKey = <String, String>{};
  for (final section in catalog) {
    for (final entry in section.entries) {
      catalogKeys.add(entry.actionKey);
      fallbackKeys.add(entry.actionKey);
      byKey.putIfAbsent(entry.actionKey, () => entry);
      sectionByKey.putIfAbsent(entry.actionKey, () => section.title);
    }
  }

  final orderedKeys = resolveMobileMoreMenuActionKeys(
    surface: surface,
    catalogKeys: catalogKeys,
    fallbackKeys: fallbackKeys,
    snapshot: snapshot,
  );

  final bySection = <String, List<_NavEntry>>{};
  for (final key in orderedKeys) {
    final entry = byKey[key];
    if (entry == null) continue;
    final sectionTitle = sectionByKey[key];
    if (sectionTitle == null) continue;
    bySection.putIfAbsent(sectionTitle, () => []).add(entry);
  }

  final rebuilt = <_NavSection>[];
  for (final section in catalog) {
    final entries = bySection[section.title];
    if (entries != null && entries.isNotEmpty) {
      rebuilt.add(_NavSection(section.title, entries));
    }
  }
  return rebuilt;
}

class NavMenuItem extends StatelessWidget {
  final _NavEntry entry;

  const NavMenuItem(this.entry, {Key? key}) : super(key: key);

  Future<void> _handleTap(BuildContext context) async {
    if (entry.isLogout) {
      // Use root navigator via AppLogout — drawer context is disposed after pop
      // and must not drive navigation (that caused a second/wrong login screen).
      await AppLogout.logoutAndGoToLogin(context: context);
      return;
    }

    // Capture the host navigator before closing the drawer — the menu
    // item's context can be disposed once the drawer route pops.
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;

    if (entry.comingSoon) {
      navigator.pop();
      if (!hostContext.mounted) return;
      await showFeatureComingSoon(hostContext, featureName: entry.title);
      return;
    }

    if (entry.action != null) {
      navigator.pop();
      if (!hostContext.mounted) return;
      await entry.action!(hostContext);
      return;
    }

    if (entry.route == null) return;

    // Lock before closing the drawer so triple-taps cannot queue pushes.
    final goHome = entry.isHome;
    if (!goHome && !NavigationDebounce.tryAcquire()) return;

    final built = await entry.route!();
    if (!hostContext.mounted || built == null) return;

    navigator.pop();
    if (!hostContext.mounted) return;

    if (goHome) {
      Navigator.pushAndRemoveUntil(
        hostContext,
        _navFadeRoute(built),
        (route) => false,
      );
    } else {
      NavigationDebounce.beginPush();
      try {
        await Navigator.push(hostContext, _navFadeRoute(built));
      } finally {
        NavigationDebounce.endPush();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogout = entry.isLogout;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, isLogout ? 10 : 8, 16, isLogout ? 10 : 8),
          child: Row(
            children: [
              Icon(
                entry.icon,
                color: isLogout ? const Color(0xFFDC2626) : AppTheme.navy,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  entry.comingSoon && entry.title == 'ChatBox'
                      ? 'Notes & Comments'
                      : entry.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isLogout
                        ? const Color(0xFFB91C1C)
                        : entry.comingSoon
                            ? const Color(0xFF8A94A6)
                            : AppTheme.getTextPrimary(context),
                  ),
                ),
              ),
              if (entry.comingSoon)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Soon',
                    style: TextStyle(
                      color: Color(0xFF5B6578),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
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
    ClientGenerationService.instance.generation
        .addListener(_onClientGenerationChanged);
    MobileMoreMenuService.instance.revision.addListener(_onMoreMenuChanged);
    _loadProfile();
    unawaited(_primeMoreMenu());
  }

  @override
  void dispose() {
    ClientGenerationService.instance.generation
        .removeListener(_onClientGenerationChanged);
    MobileMoreMenuService.instance.revision.removeListener(_onMoreMenuChanged);
    super.dispose();
  }

  void _onClientGenerationChanged() {
    if (mounted) setState(() {});
    unawaited(_primeMoreMenu());
  }

  void _onMoreMenuChanged() {
    if (mounted) setState(() {});
  }

  MobileMoreMenuSurface get _moreMenuSurface => moreMenuSurfaceFor(
        role: role,
        useLegacyProjectUi:
            ClientGenerationService.instance.shouldUseLegacyProjectUi,
      );

  /// Cache-first, then background refresh. Never called from build().
  Future<void> _primeMoreMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final storedRole = prefs.getString('role') ?? role;
    final surface = moreMenuSurfaceFor(
      role: storedRole,
      useLegacyProjectUi:
          ClientGenerationService.instance.shouldUseLegacyProjectUi,
    );
    await MobileMoreMenuService.instance.ensureSurface(surface);
  }

  bool get _restrictLegacyClientFeatures =>
      ClientGenerationService.instance.restrictsClientFeatures(role);

  List<_NavSection> _applyLegacyComingSoon(List<_NavSection> sections) {
    if (!_restrictLegacyClientFeatures) return sections;
    return sections
        .map((section) => _NavSection(
              section.title,
              section.entries.map((entry) {
                if (entry.isHome ||
                    entry.isLogout ||
                    entry.title == 'Notifications' ||
                    entry.title == 'Updates') {
                  return entry;
                }
                if (LegacyClientFeatures.isAllowed(entry.title)) return entry;
                return _NavEntry(
                  actionKey: entry.actionKey,
                  title: entry.title,
                  icon: entry.icon,
                  route: entry.route,
                  action: entry.action,
                  isHome: entry.isHome,
                  isLogout: entry.isLogout,
                  comingSoon: true,
                );
              }).toList(),
            ))
        .toList();
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
        actionKey: 'home',
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
        actionKey: 'my_tasks',
        title: 'My Tasks',
        icon: Icons.pending_actions_rounded,
        route: () {
          final cached = DataProvider().cachedUserTasks;
          return MyTasksScreen(
            tasks: cached.isNotEmpty ? cached : const [],
            onRefresh: fetchTasksForCurrentUser,
          );
        },
      ),
      _NavEntry(
        actionKey: 'notifications',
        title: 'Notifications',
        icon: Icons.notifications_rounded,
        route: () => const Notifications(),
      ),
    ];

    if (!isClient) {
      homeEntries.insert(
        1,
        _NavEntry(
          actionKey: 'projects',
          title: 'Projects',
          icon: Icons.folder_special_rounded,
          action: (context) => ProjectPickerScreen.show(context),
        ),
      );
      homeEntries.insert(
        3,
        _NavEntry(
          actionKey: 'attendance',
          title: 'Attendance',
          icon: Icons.fingerprint_rounded,
          route: () => const AttendanceScreen(),
        ),
      );
    } else {
      homeEntries.insert(
        1,
        _NavEntry(
          actionKey: 'client_portal',
          title: 'Client Portal',
          icon: Icons.dashboard_customize_outlined,
          route: () => const ClientPortalScreen(),
        ),
      );
      homeEntries.insert(
        2,
        _NavEntry(
          actionKey: 'project_timeline',
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
          actionKey: 'updates',
          title: 'Daily Update',
          icon: Icons.update_rounded,
          route: () => AddDailyUpdate(returnToAdminDashboard: true),
        ));
      }
      if (isClient) {
        projectEntries.add(_NavEntry(
          actionKey: 'updates',
          title: 'Updates',
          icon: Icons.description_rounded,
          route: () => const DprScreen(title: 'Updates'),
        ));
      }
    }

    if (rbac.canViewSync(currentRole, RBACService.scheduler)) {
      projectEntries.add(_NavEntry(
        actionKey: 'scheduler',
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
      if (!isClient) {
        projectEntries.add(_NavEntry(
          actionKey: 'documents',
          title: 'Documents',
          icon: Icons.description_rounded,
          action: _openAfterProjectPick(() => Documents()),
        ));
        projectEntries.add(_NavEntry(
          actionKey: 'documents_v1',
          title: 'Documents V1',
          icon: Icons.folder_copy_outlined,
          action: _openAfterProjectPick(() => const DocumentsV1HomeScreen()),
        ));
      }
    }

    if (rbac.canViewSync(currentRole, RBACService.gallery)) {
      if (!isClient) {
        projectEntries.add(_NavEntry(
          actionKey: 'gallery',
          title: 'Gallery',
          icon: Icons.photo_library_rounded,
          action: _openAfterProjectPick(() => Gallery()),
        ));
      }
      projectEntries.add(_NavEntry(
        actionKey: 'timeline_gallery',
        title: 'Timeline Gallery',
        icon: Icons.auto_awesome_motion_rounded,
        route: isClient ? () => TimelineGallery() : null,
        action:
            isClient ? null : _openAfterProjectPick(() => TimelineGallery()),
      ));
    }

    // Virtual Tour is available to clients (and staff after project pick)
    projectEntries.add(_NavEntry(
      actionKey: 'virtual_tour',
      title: 'Virtual Tour',
      icon: Icons.view_in_ar_rounded,
      route: isClient ? () => const VirtualTourScreen() : null,
      action: isClient
          ? null
          : _openAfterProjectPick(() => const VirtualTourScreen()),
    ));
    projectEntries.add(_NavEntry(
      actionKey: 'slots',
      title: 'Slots',
      icon: Icons.event_available_outlined,
      route: isClient ? () => const SlotsScreen() : null,
      action: isClient ? null : _openAfterProjectPick(() => const SlotsScreen()),
    ));

    if (rbac.canViewSync(currentRole, RBACService.payments)) {
      projectEntries.add(_NavEntry(
        actionKey: 'payments',
        title: 'Payments',
        icon: Icons.payment_rounded,
        route: isClient ? () => PaymentTaskWidget() : null,
        action:
            isClient ? null : _openAfterProjectPick(() => PaymentTaskWidget()),
      ));
      if (isClient) {
        projectEntries.add(_NavEntry(
          actionKey: 'nt_payments',
          title: 'NT Payments',
          icon: Icons.receipt_long_rounded,
          route: () => const PaymentTaskWidget(
            initialCategory: PaymentCategory.nonTender,
          ),
        ));
      }
    }

    if (isClient) {
      projectEntries.add(_NavEntry(
        actionKey: 'upload_payment_proof',
        title: 'Upload proof',
        icon: Icons.cloud_upload_outlined,
        route: () => const UploadPaymentProofScreen(),
      ));
    }

    if (projectEntries.isNotEmpty) {
      sections.add(_NavSection('Project', projectEntries));
    }

    // Operations
    final opsEntries = <_NavEntry>[];

    if (rbac.canViewSync(currentRole, RBACService.indent)) {
      opsEntries.add(_NavEntry(
        actionKey: 'indents',
        title: 'Indents',
        icon: Icons.request_quote_rounded,
        route: () => IndentsScreenLayout(),
      ));
    }

    if (!isClient) {
      opsEntries.add(_NavEntry(
        actionKey: 'stock_report',
        title: 'Stock Report',
        icon: Icons.inventory_2_rounded,
        route: () => StockReportLayout(),
      ));
      opsEntries.add(_NavEntry(
        actionKey: 'site_visit_reports',
        title: 'Site Visits',
        icon: Icons.location_on_rounded,
        route: () => SiteVisitReportsScreen(),
      ));
    }

    // Checklist and Request Drawings hidden from side drawer.

    if (currentRole == 'Admin' ||
        currentRole == 'QC' ||
        currentRole == 'Quality Engineer') {
      opsEntries.add(_NavEntry(
        actionKey: 'test_reports',
        title: 'Test Reports',
        icon: Icons.science_rounded,
        route: () => TestReportsScreen(),
      ));
    }

    if (!isClient) {
      opsEntries.add(_NavEntry(
        actionKey: 'inspection_requests',
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
    // ChatBox hidden from side drawer.
    final collabEntries = <_NavEntry>[];
    final canChatV1 = currentRole == 'Client' ||
        (rbac.canViewSync(currentRole, RBACService.tasksAndNotes) &&
            currentRole != 'Site Engineer');
    if (canChatV1) {
      collabEntries.add(_NavEntry(
        actionKey: 'chatbox',
        title: 'Chat V1',
        icon: Icons.forum_rounded,
        route: () => ChatV1App.openQuick(),
      ));
      if (!isClient) {
        collabEntries.add(_NavEntry(
          actionKey: 'project_status',
          title: 'Project Status',
          icon: Icons.flag_rounded,
          route: () => ProjectFocusScreen.openQuick(),
        ));
      }
    }
    if (collabEntries.isNotEmpty) {
      sections.add(_NavSection('Collaboration', collabEntries));
    }

    if (MobileLiveTestAccess.canEnable(currentRole)) {
      sections.add(
        _NavSection(
          'Testing',
          [
            _NavEntry(
              actionKey: 'mobile_live_test',
              title: MobileLiveTestAccess.menuTitle,
              icon: Icons.phonelink_setup_outlined,
              route: () => const MobileLiveTestScreen(),
            ),
          ],
        ),
      );
    }

    sections.add(
      _NavSection(
        'Account',
        [
          const _NavEntry(
            actionKey: 'logout',
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
    final catalog = _sectionsForRole(role);
    final surface = _moreMenuSurface;
    // Until the stored role is loaded, keep the existing hardcoded catalog.
    // Applying another surface's cache here would flash the wrong drawer.
    final snapshot = role == null
        ? null
        : MobileMoreMenuService.instance.snapshot(surface);
    final sections = _applyLegacyComingSoon(
      _applyBackendMoreMenu(catalog, surface, snapshot),
    );

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
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
